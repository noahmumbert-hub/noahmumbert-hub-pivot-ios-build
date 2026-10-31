import SwiftUI
import UIKit

/// Generated artwork never supplies ride identity, status, waits or locations.
/// An exact park + ride match is required; photos remain the fallback.
struct RideIllustration: Decodable, Identifiable {
    struct Reference: Decodable {
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
    let alt: String
    let references: [Reference]
    let license: String
    let licenseURL: URL

    var id: String { "\(parkId)-\(rideId)" }

    func fileURL(detail: Bool) -> URL? {
        Bundle.main.url(forResource: detail ? detailFile : thumbnailFile,
                        withExtension: nil, subdirectory: "RideIllustrations")
    }
}

enum RideIllustrationCatalog {
    private struct Catalog: Decodable { let records: [RideIllustration] }
    static let records: [RideIllustration] = {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "RideIllustrations"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return catalog.records
    }()
    private static let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func ride(parkID: Int?, rideID: Int) -> RideIllustration? {
        guard let parkID, let artwork = byID["\(parkID)-\(rideID)"],
              artwork.fileURL(detail: false) != nil, artwork.fileURL(detail: true) != nil else { return nil }
        return artwork
    }
}

/// Files have bounded pixel dimensions before they enter the app bundle.
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
    private var url: URL? { artwork.fileURL(detail: detail) }

    var body: some View {
        Group {
            if loadedURL == url, let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color.pivotSurfaceRaised)
                    .overlay { Image(systemName: "photo").foregroundStyle(Color.pivotMuted) }
            }
        }
        .accessibilityLabel("AI illustration: \(artwork.alt)")
        .accessibilityValue(loadedURL == url && image != nil ? "Loaded" : "Loading")
        .task(id: url) {
            image = nil
            loadedURL = nil
            guard let requestedURL = url else { return }
            let result = await RideIllustrationImageCache.shared.image(at: requestedURL)
            guard !Task.isCancelled else { return }
            image = result
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
                Link("Reference license: \(reference.license)", destination: reference.licenseURL)
            }
            Link("Illustration adaptation: \(artwork.license)", destination: artwork.licenseURL)
        }
        .font(.caption).foregroundStyle(Color.pivotMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
}
