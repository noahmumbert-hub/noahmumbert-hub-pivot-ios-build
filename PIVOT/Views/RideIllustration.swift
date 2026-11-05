import SwiftUI
import UIKit

/// Generated artwork never supplies ride identity, status, waits or locations.
/// An exact park + ride match is required; photos remain the fallback.
struct RideIllustration: Decodable, Identifiable, Sendable {
    struct Reference: Decodable, Sendable {
        let sourceURL: URL
        let credit: String
        let license: String
        let licenseURL: URL
    }

    let parkId: Int
    let rideId: Int
    let rideName: String
    let thumbnailFile: String
    let detailFile: String
    let thumbnailSHA256: String
    let thumbnailBytes: Int
    let thumbnailPixels: [Int]
    let detailSHA256: String
    let detailBytes: Int
    let detailPixels: [Int]
    let downloadSourceCommit: String?
    let alt: String
    let references: [Reference]
    let license: String?
    let licenseURL: URL?

    var id: String { "\(parkId)-\(rideId)" }

    func fileURL(detail: Bool) -> URL? {
        // Only the current bundle is addressable. An updated app cannot recover
        // JPEGs from the replaced 1.18.4 bundle; Release contains no such folder.
        Bundle.main.url(forResource: detail ? detailFile : thumbnailFile,
                        withExtension: nil, subdirectory: "RideIllustrations")
    }

    func downloadAsset(detail: Bool) -> RideArtworkAsset? {
        guard let downloadSourceCommit else { return nil }
        let pixels = detail ? detailPixels : thumbnailPixels
        guard pixels.count == 2 else { return nil }
        let asset = RideArtworkAsset(artworkID: id, variant: detail ? .detail : .thumbnail,
            filename: detail ? detailFile : thumbnailFile,
            sha256: detail ? detailSHA256 : thumbnailSHA256,
            byteCount: detail ? detailBytes : thumbnailBytes,
            width: pixels[0], height: pixels[1], sourceCommit: downloadSourceCommit)
        return asset.isValid ? asset : nil
    }
}

enum RideIllustrationCatalog {
    private struct Catalog: Decodable { let schemaVersion: Int; let records: [RideIllustration] }
    static let records: [RideIllustration] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "RideIllustrationMetadata"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.schemaVersion == 1,
              Set(catalog.records.map(\.id)).count == catalog.records.count,
              catalog.records.allSatisfy({ $0.downloadAsset(detail: false) != nil && $0.downloadAsset(detail: true) != nil }) else { return [] }
        return catalog.records
    }()
    /// Every release contains all accepted metadata, not an additive patch.
    /// The replaced 1.18.4 bundle cannot be read to migrate its old JPEGs.
    static var downloadableRecords: [RideIllustration] { records }
    private static let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func ride(parkID: Int?, rideID: Int) -> RideIllustration? {
        guard let parkID, let artwork = byID["\(parkID)-\(rideID)"],
              artwork.downloadAsset(detail: false) != nil, artwork.downloadAsset(detail: true) != nil else { return nil }
        return artwork
    }
}

/// Verified originals have bounded pixel dimensions before display.
/// NSCache is thread safe, evicts on memory pressure, and never retains the
/// complete park catalog. Decode happens away from the scrolling main thread.
final class RideIllustrationImageCache: @unchecked Sendable {
    static let shared = RideIllustrationImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.totalCostLimit = 20 * 1_024 * 1_024
        cache.countLimit = 80
    }

    func image(at url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        return await Task.detached(priority: .utility) { [self] in
            guard let original = UIImage(contentsOfFile: url.path),
                  let image = original.preparingForDisplay() else { return nil }
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: url as NSURL, cost: cost)
            return image
        }.value
    }
}

struct RideIllustrationImage: View {
    let artwork: RideIllustration
    var detail = false
    var contentMode: ContentMode = .fill
    @State private var loadedURL: URL?
    @State private var image: UIImage?
    @State private var decodeFailed = false
    @State private var decodeAttempt = 0
    @ObservedObject private var downloads = RideArtworkDownloads.shared
    private var url: URL? {
        artwork.fileURL(detail: detail) ?? artwork.downloadAsset(detail: detail).flatMap { downloads.localURL(for: $0) }
    }
    private var decodeTaskID: String { (url?.absoluteString ?? "none") + ":\(decodeAttempt)" }

    var body: some View {
        Group {
            if loadedURL == url, let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color.pivotSurfaceRaised)
                    .overlay {
                        if decodeFailed && detail {
                            Button("Retry illustration") { decodeAttempt += 1 }.frame(minHeight: 44)
                        } else { Image(systemName: "photo").foregroundStyle(Color.pivotMuted) }
                    }
            }
        }
        .accessibilityLabel("AI illustration: \(artwork.alt)")
        .accessibilityValue(loadedURL == url && image != nil ? "Loaded" : (decodeFailed ? "Unavailable" : "Loading"))
        .task(id: decodeTaskID) {
            image = nil
            loadedURL = nil
            decodeFailed = false
            guard let requestedURL = url else { return }
            let result = await RideIllustrationImageCache.shared.image(at: requestedURL)
            guard !Task.isCancelled else { return }
            image = result
            decodeFailed = result == nil
            loadedURL = requestedURL
        }
    }
}

struct RideIllustrationCredit: View {
    let artwork: RideIllustration
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AI-generated illustration", systemImage: "paintbrush.pointed")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("ride-illustration-credit")
            Text("Inspired by real ride photography. Composition and lighting are illustrated.")
            ForEach(Array(artwork.references.enumerated()), id: \.offset) { _, reference in
                Link("Reference photo: \(reference.credit)", destination: reference.sourceURL)
                Link("Reference rights: \(reference.license)", destination: reference.licenseURL)
            }
            if let license = artwork.license, let url = artwork.licenseURL {
                Link("Illustration adaptation: \(license)", destination: url)
            }
        }
        .font(.caption).foregroundStyle(Color.pivotMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct RideArtworkDownloadStatus: View {
    let artwork: RideIllustration
    @Environment(\.pivotAccent) private var accent
    @ObservedObject private var downloads = RideArtworkDownloads.shared
    private var asset: RideArtworkAsset? { artwork.downloadAsset(detail: true) }
    var body: some View {
        if let asset {
            VStack(alignment: .leading, spacing: 8) {
                if downloads.downloading.contains(asset.sha256) {
                    ProgressView("Downloading illustration…")
                } else {
                    Text(downloads.failures[asset.sha256]?.message ?? "This illustration needs a one-time download before it is available offline.")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ride-artwork-download-status-\(artwork.id)")
                    Button {
                        Task { await downloads.request(asset, retry: true) }
                    } label: {
                        Text(downloads.failures[asset.sha256] == nil ? "Download illustration" : "Retry artwork download")
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .foregroundStyle(accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("retry-artwork-\(artwork.id)")
                    .disabled(downloads.isPausing)
                }
            }
            .font(.subheadline).foregroundStyle(Color.pivotMuted)
        }
    }
}
