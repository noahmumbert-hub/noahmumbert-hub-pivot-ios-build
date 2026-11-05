import SwiftUI

struct ArtworkDownloadSettingsView: View {
    @ObservedObject private var downloads = RideArtworkDownloads.shared
    private var originalBytes: Int64 {
        downloads.records.reduce(0) { $0 + Int64($1.thumbnailBytes + $1.detailBytes) }
    }
    var body: some View {
        Form {
            Section {
                Text("\(downloads.completedIllustrations) of \(downloads.records.count) illustrations saved")
                    .accessibilityIdentifier("artwork-download-count")
                Text("Saved originals: \(ByteCountFormatter.string(fromByteCount: downloads.storedBytes, countStyle: .file))")
                    .accessibilityIdentifier("artwork-storage-used")
                Text("All originals: \(ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file))")
                if downloads.isCheckingInventory { ProgressView("Checking saved artwork…") }
                if downloads.isDownloadingAll {
                    ProgressView(value: Double(downloads.completedIllustrations), total: Double(max(1, downloads.records.count)))
                        .accessibilityLabel("Artwork download progress")
                    Button("Pause downloads") { Task { await downloads.pause() } }
                        .frame(minHeight: 44).accessibilityIdentifier("pause-artwork-downloads")
                } else {
                    Button(downloads.completedIllustrations == 0 ? "Download all illustrations" : "Download remaining illustrations") {
                        downloads.downloadAll()
                    }
                    .frame(minHeight: 44).accessibilityIdentifier("download-all-artwork")
                    .disabled(downloads.completedIllustrations == downloads.records.count || downloads.isPausing || downloads.isCheckingInventory)
                }
                if let message = downloads.statusMessage {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("artwork-download-message")
                }
            } header: {
                Text("Offline illustrations")
            } footer: {
                Text("Internet is needed once, including after upgrading from 1.18.4. Saved illustrations remain available offline across ordinary app updates. Photos or placeholders appear until an illustration is saved. Downloads run while PIVOT is open; resume here after an interruption.")
            }
            Section("Room for future updates") {
                Text("Artwork can use up to 384 MiB. New downloads pause to leave a 512 MiB space reserve for updates and other data. Some system or SideStore updates may need more space.")
                Text("Valid saved originals are reused and are never automatically removed. Reaching the artwork limit pauses new downloads.")
            }
        }
        .navigationTitle("Artwork downloads")
        .navigationBarTitleDisplayMode(.inline)
        .task { await downloads.refreshInventory() }
    }
}
