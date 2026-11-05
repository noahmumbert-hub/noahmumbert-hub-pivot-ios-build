import Foundation
import CryptoKit
import ImageIO
import Combine

enum RideArtworkVariant: String, Sendable { case thumbnail, detail }

struct RideArtworkAsset: Hashable, Sendable {
    let artworkID: String
    let variant: RideArtworkVariant
    let filename: String
    let sha256: String
    let byteCount: Int
    let width: Int
    let height: Int
    let sourceCommit: String

    var isValid: Bool {
        let ids = artworkID.split(separator: "-")
        return ids.count == 2 && ids.allSatisfy({ part in
                Int(part).map { $0 > 0 && String($0) == String(part) } == true
            })
            && filename == artworkID + "-" + variant.rawValue + ".jpg"
            && sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
            && sourceCommit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
            && byteCount > 0 && byteCount <= (variant == .detail ? 350_000 : 50_000)
            && width > 0 && width <= (variant == .detail ? 768 : 256)
            && height > 0 && height <= (variant == .detail ? 960 : 320)
            && abs(Double(width) / Double(height) - 0.8) < 0.01
    }

    var remoteURL: URL? {
        guard isValid else { return nil }
        return URL(string: "https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/\(sourceCommit)/PIVOT/Resources/RideIllustrations/\(filename)")
    }
}

struct RideArtworkStoragePolicy: Sendable {
    // Valid originals are never automatically evicted. Future catalogues reuse
    // the same content hashes; reaching the quota pauses additions, not reuse.
    var maximumStoredBytes: Int64 = 384 * 1_024 * 1_024
    var freeSpaceReserveBytes: Int64 = 512 * 1_024 * 1_024
    var maximumConcurrentTransfers = 2
}

enum RideArtworkDownloadError: Error, Equatable, Sendable {
    case invalidAsset, verificationFailed, networkUnavailable, httpStatus(Int)
    case insufficientSpace, storageLimit, storageUnavailable, cancelled

    var message: String {
        switch self {
        case .insufficientSpace: return "More free space is needed. Saved artwork stays available."
        case .storageLimit: return "Artwork storage is full. Saved artwork stays available."
        case .storageUnavailable: return "Artwork couldn’t be saved or storage checked. Retry when storage is available."
        case .verificationFailed, .invalidAsset: return "The illustration couldn’t be verified. Retry to download the original."
        case .cancelled: return "Download paused. Saved artwork stays available."
        case .networkUnavailable, .httpStatus: return "The illustration is unavailable. Connect to the internet and retry."
        }
    }
}

/// A redirect may not turn this public, commit-pinned image request into a
/// request to another provider, branch, file identity, or authenticated endpoint.
private final class RideArtworkRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let expected: URL
    init(_ expected: URL) { self.expected = expected }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url == expected ? request : nil)
    }
}

enum RideArtworkHTTP {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: configuration)
    }()

    static func fetch(_ asset: RideArtworkAsset) async throws -> Data {
        try await fetch(asset, session: session)
    }

    static func fetch(_ asset: RideArtworkAsset, session: URLSession) async throws -> Data {
        guard let url = asset.remoteURL else { throw RideArtworkDownloadError.invalidAsset }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (bytes, response) = try await session.bytes(for: request, delegate: RideArtworkRedirectGuard(url))
        guard let http = response as? HTTPURLResponse, response.url == url, http.statusCode == 200 else {
            bytes.task.cancel()
            throw RideArtworkDownloadError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard response.expectedContentLength < 0 || response.expectedContentLength == Int64(asset.byteCount) else {
            bytes.task.cancel()
            throw RideArtworkDownloadError.verificationFailed
        }
        return try await withTaskCancellationHandler {
            var data = Data()
            data.reserveCapacity(asset.byteCount)
            for try await byte in bytes {
                guard data.count < asset.byteCount else {
                    bytes.task.cancel()
                    throw RideArtworkDownloadError.verificationFailed
                }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard data.count == asset.byteCount else { throw RideArtworkDownloadError.verificationFailed }
            return data
        } onCancel: { bytes.task.cancel() }
    }
}

private actor RideArtworkTransferGate {
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = max(1, limit) }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
}

/// Application Support survives ordinary updates under the same app identity;
/// Caches/ and URLCache cannot promise persistent offline artwork. Only trusted
/// catalogue assets enter this directory. No app version is part of the key.
actor RideArtworkFileStore {
    typealias Fetcher = @Sendable (RideArtworkAsset) async throws -> Data
    typealias Capacity = @Sendable (URL) throws -> Int64?
    typealias Writer = @Sendable (Data, URL) throws -> Void
    private let directory: URL
    private let policy: RideArtworkStoragePolicy
    private let fetch: Fetcher
    private let capacity: Capacity
    private let writer: Writer
    private let manager = FileManager.default
    private let gate: RideArtworkTransferGate
    private var prepared = false
    private var usedBytes: Int64 = 0
    private var reservedBytes: Int64 = 0
    private var verified: [RideArtworkAsset: URL] = [:]
    private var pending: [String: (token: UUID, task: Task<URL, Error>)] = [:]

    init(directory: URL? = nil, policy: RideArtworkStoragePolicy = .init(),
         fetch: @escaping Fetcher = { try await RideArtworkHTTP.fetch($0) },
         capacity: @escaping Capacity = { try $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage },
         writer: @escaping Writer = { try $0.write(to: $1, options: .withoutOverwriting) }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PIVOTArtwork/originals-v1", isDirectory: true)
        self.policy = policy; self.fetch = fetch; self.capacity = capacity; self.writer = writer
        gate = RideArtworkTransferGate(limit: policy.maximumConcurrentTransfers)
    }

    func cachedURL(for asset: RideArtworkAsset) throws -> URL? {
        guard asset.isValid else { throw RideArtworkDownloadError.invalidAsset }
        try prepareDirectory()
        if let cached = verified[asset] { return cached }
        let url = directory.appendingPathComponent(asset.sha256 + ".jpg")
        guard manager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RideArtworkDownloadError.storageUnavailable }
        guard (values.fileSize ?? Int.max) <= 350_000, let data = try? Data(contentsOf: url) else {
            throw RideArtworkDownloadError.verificationFailed
        }
        let actualDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if actualDigest == asset.sha256 {
            // A bad later catalogue must not delete a valid older original.
            guard Self.validate(data, asset: asset) else { throw RideArtworkDownloadError.invalidAsset }
            verified[asset] = url
            return url
        }
        // Invalid bytes are not accepted artwork. Discard only this corrupt file,
        // never a verified original, a bundled resource, or an unknown old asset.
        try manager.removeItem(at: url)
        usedBytes = max(0, usedBytes - Int64(values.fileSize ?? 0))
        return nil
    }

    func load(_ asset: RideArtworkAsset) async throws -> URL {
        do { if let local = try cachedURL(for: asset) { return local } }
        catch let error as RideArtworkDownloadError { throw error }
        catch { throw RideArtworkDownloadError.storageUnavailable }
        if let existing = pending[asset.sha256] {
            _ = try await existing.task.value
            guard let local = try cachedURL(for: asset) else { throw RideArtworkDownloadError.verificationFailed }
            return local
        }
        let token = UUID()
        let task = Task { try await self.download(asset) }
        pending[asset.sha256] = (token, task)
        defer { if pending[asset.sha256]?.token == token { pending[asset.sha256] = nil } }
        return try await task.value
    }

    func cancelAll() async {
        let tasks = pending.values.map { $0.task }
        tasks.forEach { $0.cancel() }
        for task in tasks { _ = await task.result }
    }

    func storedBytes() throws -> Int64 { try prepareDirectory(); return usedBytes }

    private func prepareDirectory() throws {
        guard !prepared else { return }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory
            var exclusion = URLResourceValues(); exclusion.isExcludedFromBackup = true
            try url.setResourceValues(exclusion)
            let entries = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            var scannedBytes: Int64 = 0
            for file in entries {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw RideArtworkDownloadError.storageUnavailable }
                if file.lastPathComponent.hasPrefix(".pending-") {
                    try manager.removeItem(at: file)
                } else if values.isRegularFile == true {
                    guard let size = values.fileSize, size >= 0 else { throw RideArtworkDownloadError.storageUnavailable }
                    scannedBytes += Int64(size)
                } else {
                    throw RideArtworkDownloadError.storageUnavailable
                }
            }
            usedBytes = scannedBytes
            prepared = true
        } catch { throw RideArtworkDownloadError.storageUnavailable }
    }

    private func checkSpace(for asset: RideArtworkAsset, includesReservation: Bool) throws {
        let length = Int64(asset.byteCount)
        let otherReservations = reservedBytes - (includesReservation ? length : 0)
        guard usedBytes + otherReservations + length <= policy.maximumStoredBytes else { throw RideArtworkDownloadError.storageLimit }
        let available: Int64
        do {
            guard let value = try capacity(directory) else { throw RideArtworkDownloadError.storageUnavailable }
            available = value
        } catch { throw RideArtworkDownloadError.storageUnavailable }
        guard available >= policy.freeSpaceReserveBytes + 2 * (otherReservations + length) else {
            throw RideArtworkDownloadError.insufficientSpace
        }
    }

    private func download(_ asset: RideArtworkAsset) async throws -> URL {
        await gate.acquire()
        defer { Task { await gate.release() } }
        guard !Task.isCancelled else { throw RideArtworkDownloadError.cancelled }
        if let local = try cachedURL(for: asset) { return local }
        try checkSpace(for: asset, includesReservation: false)
        reservedBytes += Int64(asset.byteCount)
        defer { reservedBytes -= Int64(asset.byteCount) }
        do {
            let data = try await fetch(asset)
            try Task.checkCancellation()
            guard Self.validate(data, asset: asset) else { throw RideArtworkDownloadError.verificationFailed }
            try checkSpace(for: asset, includesReservation: true)
            let temporary = directory.appendingPathComponent(".pending-" + UUID().uuidString)
            defer { try? manager.removeItem(at: temporary) }
            try writer(data, temporary)
            guard let written = try? Data(contentsOf: temporary), Self.validate(written, asset: asset) else {
                throw RideArtworkDownloadError.verificationFailed
            }
            let final = directory.appendingPathComponent(asset.sha256 + ".jpg")
            try manager.moveItem(at: temporary, to: final)
            usedBytes += Int64(data.count)
            verified[asset] = final
            return final
        } catch is CancellationError {
            throw RideArtworkDownloadError.cancelled
        } catch let error as RideArtworkDownloadError {
            throw error
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            throw RideArtworkDownloadError.insufficientSpace
        } catch let error as NSError where error.domain == NSCocoaErrorDomain {
            throw RideArtworkDownloadError.storageUnavailable
        } catch {
            throw Task.isCancelled ? RideArtworkDownloadError.cancelled : RideArtworkDownloadError.networkUnavailable
        }
    }

    nonisolated static func validate(_ data: Data, asset: RideArtworkAsset) -> Bool {
        guard asset.isValid, data.count == asset.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == asset.sha256,
              data.starts(with: [0xff, 0xd8]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width == asset.width && height == asset.height
    }
}

@MainActor
final class RideArtworkDownloads: ObservableObject {
    static let shared: RideArtworkDownloads = {
#if DEBUG
        if let fixture = RideArtworkUITestFixture.make() { return fixture }
#endif
        return RideArtworkDownloads()
    }()
    @Published private(set) var localURLs: [String: URL] = [:]
    @Published private(set) var failures: [String: RideArtworkDownloadError] = [:]
    @Published private(set) var downloading: Set<String> = []
    @Published private(set) var storedBytes: Int64 = 0
    @Published private(set) var isDownloadingAll = false
    @Published private(set) var isPausing = false
    @Published private(set) var isCheckingInventory = false
    @Published private(set) var statusMessage: String?
    private let store: RideArtworkFileStore
    let records: [RideIllustration]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var batch: Task<Void, Never>?

    init(store: RideArtworkFileStore = .init(), records: [RideIllustration] = RideIllustrationCatalog.records) {
        self.store = store; self.records = records
    }
    func localURL(for asset: RideArtworkAsset) -> URL? { localURLs[asset.sha256] }
    var completedIllustrations: Int {
        records.filter { record in
            [false, true].allSatisfy { detail in record.downloadAsset(detail: detail).flatMap { localURLs[$0.sha256] } != nil }
        }.count
    }

    @discardableResult
    func request(_ asset: RideArtworkAsset, retry: Bool = false) async -> Bool {
        guard !isPausing else { return false }
        if localURLs[asset.sha256] != nil { return true }
        if !retry && failures[asset.sha256] != nil { return false }
        if tasks[asset.sha256] == nil {
            failures[asset.sha256] = nil
            downloading.insert(asset.sha256)
            tasks[asset.sha256] = Task { [weak self, store] in
                guard let self else { return }
                do { self.localURLs[asset.sha256] = try await store.load(asset) }
                catch { self.failures[asset.sha256] = (error as? RideArtworkDownloadError) ?? .networkUnavailable }
                self.storedBytes = (try? await store.storedBytes()) ?? self.storedBytes
                self.downloading.remove(asset.sha256)
                self.tasks[asset.sha256] = nil
            }
        }
        await tasks[asset.sha256]?.value
        return localURLs[asset.sha256] != nil
    }

    func refreshInventory() async {
        guard !isCheckingInventory else { return }
        isCheckingInventory = true
        defer { isCheckingInventory = false }
        var found: [String: URL] = [:]
        for record in records {
            for detail in [false, true] {
                guard !Task.isCancelled else { return }
                if let asset = record.downloadAsset(detail: detail), let local = try? await store.cachedURL(for: asset) {
                    found[asset.sha256] = local
                }
            }
        }
        localURLs.merge(found, uniquingKeysWith: { _, new in new })
        storedBytes = (try? await store.storedBytes()) ?? storedBytes
    }

    func downloadAll() {
        guard batch == nil, !isPausing else { return }
        isDownloadingAll = true
        statusMessage = nil
        batch = Task { [weak self] in
            guard let self else { return }
            defer { self.isDownloadingAll = false; self.batch = nil }
            for record in self.records {
                for detail in [false, true] {
                    guard !Task.isCancelled, let asset = record.downloadAsset(detail: detail) else { return }
                    guard await self.request(asset, retry: true) else {
                        self.statusMessage = self.failures[asset.sha256]?.message ?? RideArtworkDownloadError.cancelled.message
                        return
                    }
                }
            }
            self.statusMessage = "All illustrations are saved for offline use."
        }
    }

    func pause() async {
        guard !isPausing, batch != nil || !tasks.isEmpty else { return }
        isPausing = true
        let active = Array(tasks.values)
        let activeBatch = batch
        batch?.cancel()
        await store.cancelAll()
        for task in active { await task.value }
        await activeBatch?.value
        statusMessage = RideArtworkDownloadError.cancelled.message
        isPausing = false
    }
}
