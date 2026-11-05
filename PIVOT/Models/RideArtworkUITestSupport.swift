#if DEBUG
import Foundation

/// Native tests exercise the real HTTP streaming/hash/persistence path with
/// accepted original bytes. This file and these resources are absent in Release.
enum RideArtworkUITestFixture {
    @MainActor
    static func make() -> RideArtworkDownloads? {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = environment["PIVOT_ARTWORK_FIXTURE"],
              let token = environment["PIVOT_ARTWORK_DIRECTORY"], UUID(uuidString: token) != nil else { return nil }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PIVOTArtworkUITests/" + token, isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RideArtworkOriginalURLProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        let store = RideArtworkFileStore(directory: directory,
            fetch: { try await RideArtworkHTTP.fetch($0, session: session) },
            capacity: { _ in mode == "low-storage" ? 0 : Int64.max / 4 },
            writer: { data, url in
                if mode == "storage-failure" { throw CocoaError(.fileWriteOutOfSpace) }
                try data.write(to: url, options: .withoutOverwriting)
            })
        let records = environment["PIVOT_ARTWORK_SMALL_BATCH"] == "1"
            ? RideIllustrationCatalog.records.filter { ["6-126", "5-10916"].contains($0.id) }
            : RideIllustrationCatalog.records
        return RideArtworkDownloads(store: store, records: records)
    }
}

private final class RideArtworkOriginalURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var seenDetails: Set<String> = []
    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "raw.githubusercontent.com"
            && request.url?.path.hasPrefix("/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = ProcessInfo.processInfo.environment["PIVOT_ARTWORK_FIXTURE"] ?? "originals"
        let delay = mode == "slow" ? 3.0 : 0
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); let stopped = self.stopped; self.stateLock.unlock()
            guard !stopped else { return }
            guard mode != "offline" else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            guard let url = self.request.url,
                  let original = Bundle.main.url(forResource: url.lastPathComponent, withExtension: nil,
                        subdirectory: "PIVOTArtworkTestOriginals"),
                  var data = try? Data(contentsOf: original) else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return
            }
            if mode == "corrupt-once", url.lastPathComponent.hasSuffix("-detail.jpg") {
                Self.lock.lock()
                let first = Self.seenDetails.insert(url.lastPathComponent).inserted
                Self.lock.unlock()
                if first, !data.isEmpty { data[data.count - 1] ^= 0xff }
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/jpeg", "Content-Length": String(data.count)])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}
#endif
