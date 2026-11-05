import XCTest
import Foundation
import UIKit
@testable import PIVOT

final class RideArtworkDownloadTests: XCTestCase {
    private func fixture(detail: Bool = false, id: String = "5-10916") throws -> (RideArtworkAsset, Data) {
        let record = try XCTUnwrap(RideIllustrationCatalog.records.first { $0.id == id })
        let asset = try XCTUnwrap(record.downloadAsset(detail: detail))
        let url = try XCTUnwrap(Bundle.main.url(forResource: asset.filename, withExtension: nil,
            subdirectory: "PIVOTArtworkTestOriginals"))
        return (asset, try Data(contentsOf: url))
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("artwork-tests-" + UUID().uuidString, isDirectory: true)
    }
    private let ample: RideArtworkFileStore.Capacity = { _ in Int64.max / 4 }
    private func assertFailure(_ expected: RideArtworkDownloadError, store: RideArtworkFileStore,
                               asset: RideArtworkAsset, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await store.load(asset); XCTFail("Invalid download accepted", file: file, line: line) }
        catch { XCTAssertEqual(error as? RideArtworkDownloadError, expected, file: file, line: line) }
    }

    func testCompleteCatalogueIsImmutableExactAndFitsBoundedStorage() throws {
        let records = RideIllustrationCatalog.records
        XCTAssertEqual(records.count, 1082)
        XCTAssertEqual(Set(records.map(\.id)).count, 1082)
        let assets = records.flatMap { [$0.downloadAsset(detail: false), $0.downloadAsset(detail: true)] }
        XCTAssertEqual(assets.compactMap { $0 }.count, 2164)
        XCTAssertEqual(assets.compactMap { $0 }.reduce(0) { $0 + $1.byteCount }, 218_526_843)
        for asset in assets.compactMap({ $0 }) {
            XCTAssertTrue(asset.isValid)
            XCTAssertEqual(asset.remoteURL?.host, "raw.githubusercontent.com")
            XCTAssertTrue(asset.remoteURL!.path.hasPrefix("/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/77191e42fb6dde600e6bc9a3ab948c7ce09ed4c2/"))
        }
        let policy = RideArtworkStoragePolicy()
        XCTAssertEqual(policy.maximumStoredBytes, 402_653_184)
        XCTAssertEqual(policy.freeSpaceReserveBytes, 536_870_912)
        XCTAssertGreaterThan(policy.maximumStoredBytes - 218_526_843, 175 * 1024 * 1024)
        XCTAssertEqual(policy.maximumConcurrentTransfers, 2)
    }

    func testFreshDownloadKeepsOriginalBytesAndSurvivesNewStoreAndSkippedVersions() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: ample)
        let saved = try await first.load(asset)
        XCTAssertEqual(try Data(contentsOf: saved), data)
        XCTAssertEqual(saved.lastPathComponent, asset.sha256 + ".jpg")
        let counter = ArtworkTransferCounter()
        let updated = RideArtworkFileStore(directory: folder, fetch: { _ in
            await counter.enter(); throw URLError(.notConnectedToInternet)
        }, capacity: { _ in 0 })
        let laterManifest = RideArtworkAsset(artworkID: asset.artworkID, variant: asset.variant,
            filename: asset.filename, sha256: asset.sha256, byteCount: asset.byteCount,
            width: asset.width, height: asset.height, sourceCommit: String(repeating: "a", count: 40))
        let reused = try await updated.load(laterManifest)
        XCTAssertEqual(reused, saved, "Content hash reuse does not depend on installed intermediate versions or old source URL")
        XCTAssertEqual(try Data(contentsOf: reused), data)
        let calls = await counter.total
        XCTAssertEqual(calls, 0, "Offline reuse must not perform a request or require new free space")
    }

    func testDirectUpgradeWithoutInternetHasNoOldBundleAndKeepsFallbackState() async throws {
        let (asset, _) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(RideIllustrationCatalog.records.first { $0.id == asset.artworkID }?.fileURL(detail: false))
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in throw URLError(.notConnectedToInternet) }, capacity: ample)
        await assertFailure(.networkUnavailable, store: store, asset: asset)
        let cached = try await store.cachedURL(for: asset)
        XCTAssertNil(cached)
        XCTAssertNotNil(ParkArtworkCatalog.ride(parkID: 5, rideID: 10916))
    }

    func testWrongOriginalAndTruncatedBytesAreNotPersisted() async throws {
        let (asset, data) = try fixture()
        for wrong in [Data(data.dropLast()), Data(repeating: 0, count: data.count)] {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let store = RideArtworkFileStore(directory: folder, fetch: { _ in wrong }, capacity: ample)
            await assertFailure(.verificationFailed, store: store, asset: asset)
            let cached = try await store.cachedURL(for: asset)
            XCTAssertNil(cached)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(asset.sha256 + ".jpg").path))
        }
    }

    func testAnotherRideAndAnotherVariantCannotReplaceTheExpectedImage() async throws {
        let (asset, _) = try fixture()
        let (_, otherRide) = try fixture(id: "6-126")
        let (_, otherVariant) = try fixture(detail: true)
        XCTAssertFalse(RideArtworkFileStore.validate(otherRide, asset: asset))
        XCTAssertFalse(RideArtworkFileStore.validate(otherVariant, asset: asset))
        let wrongIdentity = RideArtworkAsset(artworkID: "6-10916", variant: asset.variant,
            filename: asset.filename, sha256: asset.sha256, byteCount: asset.byteCount,
            width: asset.width, height: asset.height, sourceCommit: asset.sourceCommit)
        XCTAssertFalse(wrongIdentity.isValid)
        XCTAssertNil(wrongIdentity.remoteURL)
        XCTAssertNil(RideIllustrationCatalog.ride(parkID: 6, rideID: 10916))
    }

    func testCorruptPersistentFileIsRejectedAndCanBeReplacedByVerifiedOriginal() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(asset.sha256 + ".jpg")
        try Data(repeating: 1, count: data.count).write(to: file)
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: ample)
        let cached = try await store.cachedURL(for: asset)
        XCTAssertNil(cached, "Corrupt data must never be reported as offline artwork")
        let repaired = try await store.load(asset)
        XCTAssertEqual(try Data(contentsOf: repaired), data)
    }

    func testLaterMetadataMismatchNeverDeletesAValidSavedOriginal() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(asset.sha256 + ".jpg")
        try data.write(to: file)
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in throw URLError(.notConnectedToInternet) }, capacity: ample)
        let bad = RideArtworkAsset(artworkID: asset.artworkID, variant: asset.variant,
            filename: asset.filename, sha256: asset.sha256, byteCount: asset.byteCount - 1,
            width: asset.width, height: asset.height, sourceCommit: asset.sourceCommit)
        await assertFailure(.invalidAsset, store: store, asset: bad)
        XCTAssertEqual(try Data(contentsOf: file), data)
        let correct = try await store.load(asset)
        XCTAssertEqual(correct, file)
    }

    func testInterruptedDownloadIsNotCommittedAndLaterLaunchCanContinue() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let started = expectation(description: "transfer started")
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in
            started.fulfill(); try await Task.sleep(nanoseconds: 5_000_000_000); return data
        }, capacity: ample)
        let task = Task { try await store.load(asset) }
        await fulfillment(of: [started], timeout: 2)
        await store.cancelAll()
        do { _ = try await task.value; XCTFail("Interrupted transfer was accepted") }
        catch { XCTAssertEqual(error as? RideArtworkDownloadError, .cancelled) }
        let cached = try await store.cachedURL(for: asset)
        XCTAssertNil(cached)
        let next = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: ample)
        let saved = try await next.load(asset)
        XCTAssertEqual(try Data(contentsOf: saved), data)
    }

    func testCrashPartialIsCleanedWithoutDeletingValidSavedOriginals() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let final = folder.appendingPathComponent(asset.sha256 + ".jpg")
        let partial = folder.appendingPathComponent(".pending-interrupted")
        try data.write(to: final); try Data([1, 2, 3]).write(to: partial)
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in throw URLError(.notConnectedToInternet) }, capacity: ample)
        let saved = try await store.load(asset)
        XCTAssertEqual(saved, final)
        XCTAssertEqual(try Data(contentsOf: final), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        let bytes = try await store.storedBytes()
        XCTAssertEqual(bytes, Int64(data.count))
    }

    func testLowSpaceAndUnknownCapacityDoNotStartNetworkTransfers() async throws {
        let (asset, data) = try fixture()
        for unknown in [false, true] {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let count = ArtworkTransferCounter()
            let store = RideArtworkFileStore(directory: folder, fetch: { _ in await count.enter(); return data },
                capacity: { _ in unknown ? nil : 536_870_912 + Int64(asset.byteCount) - 1 })
            await assertFailure(unknown ? .storageUnavailable : .insufficientSpace, store: store, asset: asset)
            let requests = await count.total
            XCTAssertEqual(requests, 0)
        }
    }

    func testSpaceIsRecheckedBeforeAtomicCommit() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let capacity = ArtworkCapacitySequence()
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: { _ in capacity.next() })
        await assertFailure(.insufficientSpace, store: store, asset: asset)
        let cached = try await store.cachedURL(for: asset)
        XCTAssertNil(cached)
    }

    func testWriteFailureDoesNotPublishPartialOrRemoveExistingArtwork() async throws {
        let (asset, data) = try fixture()
        let (savedAsset, savedData) = try fixture(id: "6-126")
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = folder.appendingPathComponent(savedAsset.sha256 + ".jpg")
        try savedData.write(to: existing)
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: ample,
            writer: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await assertFailure(.insufficientSpace, store: store, asset: asset)
        XCTAssertEqual(try Data(contentsOf: existing), savedData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [existing.lastPathComponent])
    }

    func testQuotaCountsOldAssetsWithoutEvictingThem() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appendingPathComponent(String(repeating: "b", count: 64) + ".jpg")
        try data.write(to: old)
        var policy = RideArtworkStoragePolicy(); policy.maximumStoredBytes = Int64(data.count)
        let store = RideArtworkFileStore(directory: folder, policy: policy, fetch: { _ in data }, capacity: ample)
        await assertFailure(.storageLimit, store: store, asset: asset)
        XCTAssertEqual(try Data(contentsOf: old), data, "A later catalogue must not delete valid older originals to make room")
    }

    func testIncompleteDiskWriteIsRejectedBeforeAtomicRename() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: ample,
            writer: { bytes, url in try Data(bytes.dropLast()).write(to: url) })
        await assertFailure(.verificationFailed, store: store, asset: asset)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testConcurrentRequestsAreDeduplicatedAndBounded() async throws {
        let values = [try fixture(), try fixture(detail: true), try fixture(id: "6-126")]
        let data = Dictionary(uniqueKeysWithValues: values.map { ($0.0.sha256, $0.1) })
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let count = ArtworkTransferCounter()
        let store = RideArtworkFileStore(directory: folder, fetch: { asset in
            await count.enter()
            do { try await Task.sleep(nanoseconds: 30_000_000) }
            catch { await count.leave(); throw error }
            await count.leave()
            return data[asset.sha256]!
        }, capacity: ample)
        try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<3 { for pair in values { group.addTask { try await store.load(pair.0) } } }
            var completed = 0
            for try await _ in group { completed += 1 }
            XCTAssertEqual(completed, 9)
        }
        let requests = await count.total, maximum = await count.maximum
        XCTAssertEqual(requests, 3)
        XCTAssertLessThanOrEqual(maximum, 2)
    }

    func testApplicationSupportDownloadsAreExcludedFromBackup() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in data }, capacity: ample)
        _ = try await store.load(asset)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    @MainActor
    func testRetryStateNeverCallsAValidCacheEntryAgain() async throws {
        let (asset, data) = try fixture()
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let count = ArtworkTransferCounter()
        let store = RideArtworkFileStore(directory: folder, fetch: { _ in
            let number = await count.enter()
            return number == 1 ? Data(repeating: 0, count: data.count) : data
        }, capacity: ample)
        let model = RideArtworkDownloads(store: store, records: [])
        let first = await model.request(asset)
        XCTAssertFalse(first)
        XCTAssertEqual(model.failures[asset.sha256], .verificationFailed)
        let unrequestedRetry = await model.request(asset)
        XCTAssertFalse(unrequestedRetry)
        let retried = await model.request(asset, retry: true)
        XCTAssertTrue(retried)
        XCTAssertNil(model.failures[asset.sha256])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.localURL(for: asset))), data)
        let reused = await model.request(asset, retry: true)
        XCTAssertTrue(reused)
        let requests = await count.total
        XCTAssertEqual(requests, 2)
    }

    func testHTTPStreamingAcceptsOnlyExpectedPublicOriginal() async throws {
        let (asset, data) = try fixture()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkHTTPTestProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        ArtworkHTTPTestProtocol.configure(status: 200, data: data, headerLength: data.count)
        let received = try await RideArtworkHTTP.fetch(asset, session: session)
        XCTAssertEqual(received, data)
        for mode in 0..<4 {
            switch mode {
            case 0: ArtworkHTTPTestProtocol.configure(status: 403, data: Data(), headerLength: 0)
            case 1: ArtworkHTTPTestProtocol.configure(status: 200, data: data + Data([0]), headerLength: nil)
            case 2: ArtworkHTTPTestProtocol.configure(status: 200, data: Data(data.dropLast()), headerLength: nil)
            default: ArtworkHTTPTestProtocol.configure(status: 200, data: data, headerLength: data.count, wrongURL: true)
            }
            do { _ = try await RideArtworkHTTP.fetch(asset, session: session); XCTFail("Unexpected response accepted: \(mode)") }
            catch { XCTAssertNotNil(error) }
        }
    }
}

private actor ArtworkTransferCounter {
    private(set) var total = 0
    private(set) var maximum = 0
    private var active = 0
    @discardableResult func enter() -> Int { total += 1; active += 1; maximum = max(maximum, active); return total }
    func leave() { active -= 1 }
}

private final class ArtworkCapacitySequence: @unchecked Sendable {
    private let lock = NSLock(); private var first = true
    func next() -> Int64 { lock.lock(); defer { lock.unlock() }; defer { first = false }; return first ? Int64.max / 4 : 0 }
}

private final class ArtworkHTTPTestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var state: (Int, Data, Int?, Bool) = (200, Data(), nil, false)
    static func configure(status: Int, data: Data, headerLength: Int?, wrongURL: Bool = false) {
        lock.lock(); state = (status, data, headerLength, wrongURL); lock.unlock()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let state = Self.state; Self.lock.unlock()
        let url = state.3 ? URL(string: "https://example.invalid/wrong.jpg")! : request.url!
        var headers = ["Content-Type": "image/jpeg"]
        if let length = state.2 { headers["Content-Length"] = String(length) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: state.0,
            httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: state.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
