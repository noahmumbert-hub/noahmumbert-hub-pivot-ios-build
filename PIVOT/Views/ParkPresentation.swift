import SwiftUI

/// Media stays keyed to stable park and ride IDs. A missing image never borrows
/// another park's photo, and artwork has no influence on live operational data.
struct ParkArtwork: Decodable {
    let parkId: Int
    let rideId: Int
    let assetName: String
    let url: URL
    let sourceURL: URL
    let credit: String
    let license: String
    let licenseURL: URL
    let alt: String

    var photo: RidePhoto {
        RidePhoto(url: url, sourceURL: sourceURL, credit: credit,
                  license: license, licenseURL: licenseURL, alt: alt)
    }
}

enum ParkArtworkCatalog {
    private struct Catalog: Decodable { let records: [ParkArtwork] }
    static let records: [ParkArtwork] = {
        guard let url = Bundle.main.url(forResource: "park-artwork", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return catalog.records
    }()

    static func ride(parkID: Int?, rideID: Int) -> ParkArtwork? {
        records.first { $0.parkId == parkID && $0.rideId == rideID }
    }

    static func hero(for park: FloridaPark) -> ParkArtwork? {
        let preferred = [5: 159, 6: 129, 7: 123]
        return records.first { $0.parkId == park.id && $0.rideId == preferred[park.id] }
            ?? records.first { $0.parkId == park.id }
    }

    static func symbol(for park: FloridaPark?) -> String {
        guard let park else { return "mappin.and.ellipse" }
        switch park {
        case .epcot: return "globe.americas.fill"
        case .magicKingdom: return "sparkles"
        case .hollywoodStudios, .universalStudiosFlorida: return "film.fill"
        case .animalKingdom, .buschGardensTampaBay, .sixFlagsDiscoveryKingdom: return "leaf.fill"
        case .seaWorldOrlando, .volcanoBay, .hurricaneHarborLosAngeles,
             .hurricaneHarborNewJersey, .hurricaneHarborPhoenix, .schlitterbahnNewBraunfels: return "water.waves"
        case .epicUniverse: return "sparkle"
        default: return "ticket.fill"
        }
    }
}

struct ParkBannerView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: FloridaPark?
    let hours: ParkHoursSnapshot?
    let isLocating: Bool
    let onChoosePark: () -> Void
    @State private var showPhotoCredit = false

    private var artwork: ParkArtwork? { park.flatMap(ParkArtworkCatalog.hero) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onChoosePark) {
                HStack(spacing: 10) {
                    Image(systemName: ParkArtworkCatalog.symbol(for: park))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.74, green: 0.76, blue: 1))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.11), in: Circle())
                    Text(park?.name ?? "Choose your park")
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change park. Current park: \(park?.name ?? "none")")

            if let park {
                Rectangle().fill(.white.opacity(0.18)).frame(width: 164, height: 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    scheduleLine("Park hours", value: hours?.regular.map { timeRange($0, park: park) } ?? "Updating", icon: "clock")
                    scheduleLine(hours?.earlyEntry?.label ?? "Early entry",
                                 value: hours?.earlyEntry.map { timeRange($0, park: park) } ?? (hours == nil ? "Updating" : "Not posted"),
                                 icon: "ticket")
                }.padding(.trailing, artwork == nil ? 0 : 28)
                if hours?.stale == true {
                    Label("Saved schedule · refresh pending", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.52))
                }
            } else {
                Text("Wait times, shows, and a plan for your day.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.82))
            }
            if isLocating {
                Label("Finding nearby supported park…", systemImage: "location")
                    .font(.caption).foregroundStyle(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    LinearGradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.30),
                                            Color(red: 0.20, green: 0.18, blue: 0.38)],
                                   startPoint: .bottomLeading, endPoint: .topTrailing)
                    if let artwork {
                        Image(artwork.assetName).resizable().scaledToFill()
                            .frame(width: geometry.size.width * 0.78, height: geometry.size.height)
                            .clipped()
                            .mask {
                                LinearGradient(stops: [.init(color: .clear, location: 0),
                                                       .init(color: .white, location: 0.3),
                                                       .init(color: .white, location: 1)],
                                               startPoint: .leading, endPoint: .trailing)
                            }
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            Image(systemName: ParkArtworkCatalog.symbol(for: park)).font(.system(size: 100, weight: .ultraLight))
                            Text(park?.monogram ?? "").font(.system(size: 42, weight: .black, design: .rounded))
                        }.foregroundStyle(.white.opacity(0.11)).padding(.trailing, 16)
                    }
                    LinearGradient(stops: [
                        .init(color: Color(red: 0.05, green: 0.09, blue: 0.18).opacity(0.97), location: 0),
                        .init(color: Color(red: 0.05, green: 0.09, blue: 0.18).opacity(typeSize.isAccessibilitySize ? 0.86 : 0.82), location: 0.49),
                        .init(color: .black.opacity(typeSize.isAccessibilitySize ? 0.72 : 0.60), location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                }.frame(width: geometry.size.width, height: geometry.size.height).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if artwork != nil {
                Button { showPhotoCredit = true } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Photo credit")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1).allowsHitTesting(false)
        }
        .accessibilityIdentifier("park-banner-\(park?.id ?? -1)")
        .sheet(isPresented: $showPhotoCredit) {
            if let artwork { ParkPhotoCreditView(artwork: artwork) }
        }
    }

    private func timeRange(_ period: ParkHoursPeriod, park: FloridaPark) -> String {
        ParkTimeFormatter.time(period.openingTime, timeZone: park.timeZone) + " – "
            + ParkTimeFormatter.time(period.closingTime, timeZone: park.timeZone)
    }

    private func scheduleLine(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.body).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.white.opacity(0.85))
                Text(value)
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ParkPhotoCreditView: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: ParkArtwork
    var body: some View {
        NavigationStack {
            List {
                Text(artwork.alt).font(.headline)
                Text("Photo: \(artwork.credit)")
                Link("Original photo", destination: artwork.sourceURL)
                Link(artwork.license, destination: artwork.licenseURL)
                Text("Displayed with a crop and a dark overlay for readability.").foregroundStyle(.secondary)
            }.navigationTitle("Photo credit").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RideThumbnailView: View {
    let ride: LiveRide
    let parkID: Int?
    var body: some View {
        Group {
            if let artwork = ParkArtworkCatalog.ride(parkID: parkID, rideID: ride.id) {
                Image(artwork.assetName).resizable().scaledToFill()
            } else if let photo = ride.details?.photo {
                AsyncImage(url: photo.url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { placeholder }
                }
            } else { placeholder }
        }
        .frame(width: 64, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.pivotBorder, lineWidth: 1) }
        .accessibilityHidden(true)
    }
    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.pivotSurfaceRaised, Color.pivotBlue.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "ticket.fill").font(.title2).foregroundStyle(Color.pivotMuted)
        }
    }
}

#if DEBUG
/// Synthetic observations only. Real park/ride IDs exercise the shared layout
/// without depending on a park being open or the provider responding in CI.
enum ReferenceParkUITestFixture {
    static func snapshot(for park: FloridaPark) -> LiveParkSnapshot {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        var payload = try! JSONSerialization.jsonObject(with: encoder.encode(NativeParkMapUITestScreen.rootSnapshot())) as! [String: Any]
        payload["parkId"] = park.id
        payload["park"] = ["name": park.name, "destination": park.destination, "operator": park.operatorName,
                           "country": park.country, "timezone": park.timeZoneIdentifier]
        var hours = payload["parkHours"] as! [String: Any]
        hours["parkId"] = park.id; hours["parkName"] = park.name; hours["timezone"] = park.timeZoneIdentifier
        hours["date"] = ParkHoursSnapshot.localDate(for: park, at: Date())
        payload["parkHours"] = hours
        let points = try! ParkMapCatalog.load().parks[String(park.id)]!.points.filter { $0.rideId != nil }
        let featuredIDs = park == .epcot ? [10916, 10914, 159] : []
        let selected = featuredIDs.isEmpty ? Array(points.prefix(3)) : featuredIDs.compactMap { id in points.first { $0.rideId == id } }
        let base = (payload["rides"] as! [[String: Any]])[0]
        payload["rides"] = selected.enumerated().map { index, point -> [String: Any] in
            var ride = base
            ride["id"] = point.rideId!; ride["name"] = point.name
            ride["land"] = park == .epcot ? (index == 1 ? "World Showcase" : "World Discovery") : "Test observations"
            ride["status"] = index == 2 ? "DOWN" : "OPEN"; ride["isOpen"] = index != 2
            if index == 2 { ride["waitTime"] = NSNull() }
            else { ride["waitTime"] = index == 0 ? 45 : 30 }
            ride["location"] = ["latitude": point.latitude, "longitude": point.longitude]
            ride["waitHistory"] = [["observedAt": Date().timeIntervalSince1970, "waitTime": index == 0 ? 45 : 30]]
            return ride
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try! decoder.decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
#endif
