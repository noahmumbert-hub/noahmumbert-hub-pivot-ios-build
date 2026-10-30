import SwiftUI
import MapKit

// A bundled, source-attributed catalog keeps locations independent of live-feed failures.
struct ParkMapCatalog: Decodable {
    let generatedAt: String
    let parks: [String: ParkMapPark]

    static func load() throws -> ParkMapCatalog {
        guard let url = Bundle.main.url(forResource: "park-map-catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
struct ParkMapPark: Decodable {
    let name: String
    let points: [ParkMapPoint]
    let missing: [ParkMapMissingPoint]
}
struct ParkMapMissingPoint: Decodable {
    let name: String
}
enum ParkMapCategory: String, Decodable, CaseIterable, Identifiable {
    case ride = "RIDE", restaurant = "RESTAURANT", show = "SHOW"
    var id: String { rawValue }
    var title: String {
        switch self { case .ride: "Rides"; case .restaurant: "Food"; case .show: "Shows" }
    }
    var symbol: String {
        switch self { case .ride: "tram.fill"; case .restaurant: "fork.knife"; case .show: "sparkles" }
    }
    var color: Color {
        switch self { case .ride: .pivotMint; case .restaurant: .orange; case .show: .purple }
    }
}
struct ParkMapPoint: Decodable, Identifiable {
    let id: String
    let name: String
    let category: ParkMapCategory
    let latitude: Double
    let longitude: Double
    let rideId: Int?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct ParkMapView: View {
    @Environment(\.pivotAccent) private var accent
    let park: FloridaPark?
    let snapshot: LiveParkSnapshot?
    let onChoosePark: () -> Void
    @State private var catalog: ParkMapCatalog?
    @State private var loadFailed = false
    @State private var category: ParkMapCategory?
    @State private var query = ""
    @State private var openOnly = false
    @State private var selectedID: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var showPlaces = false
    @State private var selectedRide: LiveRide?

    private var parkData: ParkMapPark? { park.flatMap { catalog?.parks[String($0.id)] } }
    private var freshSnapshot: LiveParkSnapshot? {
        guard let snapshot, snapshot.parkId == park?.id else { return nil }
        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        return age >= -60 && age <= 15 * 60 ? snapshot : nil
    }
    private var rides: [LiveRide] { freshSnapshot?.feedHealthy == true ? freshSnapshot?.rides ?? [] : [] }
    private var allPoints: [ParkMapPoint] {
        guard let park else { return [] }
        return (parkData?.points ?? []).filter {
            !NativeRetiredAttractions.excludes(parkID: park.id, rideID: $0.rideId ?? -1, name: $0.name, entityID: $0.id)
        }
    }
    private var points: [ParkMapPoint] {
        allPoints.filter { point in
            (category == nil || point.category == category)
                && (query.isEmpty || point.name.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespaces)))
                && (!openOnly || rides.contains { $0.id == point.rideId && $0.status == .open })
        }
    }
    private var selected: ParkMapPoint? { points.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if park == nil {
                ContentUnavailableView {
                    Label("Explore the park", systemImage: "map")
                } description: {
                    Text("Choose a park to see rides, food, and shows.")
                } actions: {
                    Button("Choose park", action: onChoosePark).buttonStyle(.borderedProminent)
                }
            } else if loadFailed || (catalog != nil && parkData == nil) {
                ContentUnavailableView {
                    Label("Locations unavailable", systemImage: "map")
                } description: {
                    Text("The park catalog could not load.")
                } actions: { Button("Try again", action: loadCatalog) }
            } else if parkData == nil {
                ProgressView("Loading park locations…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                searchField
                filters
                if category == .ride {
                    Toggle("Open rides only", isOn: $openOnly)
                        .font(.caption)
                        .tint(accent)
                        .accessibilityIdentifier("Map open rides only")
                }
                ZStack(alignment: .topTrailing) {
                    Map(position: $position, selection: $selectedID) {
                        ForEach(points) { point in
                            Marker(point.name, systemImage: point.category.symbol, coordinate: point.coordinate)
                                .tint(point.category.color)
                                .tag(point.id)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControls { MapCompass(); MapScaleView() }
                    .accessibilityIdentifier("Park map")
                    Button {
                        recenter()
                    } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                    .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(10)
                    .accessibilityLabel("Show whole park")
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(minHeight: 180, maxHeight: .infinity)
                if let point = selected {
                    selectedPlace(point)
                } else if points.isEmpty {
                    HStack {
                        Text(query.isEmpty ? "No locations match these filters." : "No matching places.").font(.caption)
                        Spacer()
                        Button("Reset") { category = nil; query = ""; openOnly = false }
                    }.padding(8)
                }
                Button { showPlaces = true } label: {
                    HStack {
                        Label("Browse \(points.count) places", systemImage: "list.bullet")
                        Spacer()
                        Image(systemName: "chevron.up")
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .accessibilityIdentifier("Browse map places")
            }
        }
        .task(id: park?.id) { loadCatalog(); recenter() }
        .onChange(of: category) { _, _ in openOnly = false; selectedID = nil }
        .sheet(isPresented: $showPlaces) { placesSheet }
        .sheet(item: $selectedRide) { ride in
            RideDetailScreenView(initialRide: ride, timeZone: park?.timeZone ?? .current)
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.pivotMuted)
            TextField("Search rides, food, shows", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("Search park places")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .frame(minWidth: 36, minHeight: 44).accessibilityLabel("Clear place search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var filters: some View {
        HStack(spacing: 6) {
            categoryButton(nil, title: "All places")
            ForEach(ParkMapCategory.allCases) { value in categoryButton(value, title: value.title) }
        }
    }
    private func categoryButton(_ value: ParkMapCategory?, title: String) -> some View {
        let count = allPoints.filter { value == nil || $0.category == value }.count
        return Button { category = value } label: {
            VStack(spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text("\(count)").font(.caption2).foregroundStyle(Color.pivotMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(category == value ? accent : Color.white)
            .background(category == value ? accent.opacity(0.12) : Color.pivotSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(category == value ? accent : Color.pivotBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) places")
        .accessibilityAddTraits(category == value ? .isSelected : [])
        .accessibilityIdentifier("map-category-\(value?.rawValue ?? "ALL")")
    }
    private func isTodayAtPark(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = park?.timeZone ?? .current
        return calendar.isDate(date, inSameDayAs: Date())
    }
    private func status(_ point: ParkMapPoint) -> String {
        if point.category == .restaurant { return "Dining location · hours unavailable" }
        if point.category == .show {
            if let current = freshSnapshot, !current.showScheduleIsStale,
               let next = current.showList.first(where: { $0.id == point.id })?.nextShowAt,
               next >= Date(), isTodayAtPark(next) {
                return "Next at \(ParkTimeFormatter.time(next, timeZone: park?.timeZone))"
            }
            return "Check Shows for today’s schedule"
        }
        guard let ride = rides.first(where: { $0.id == point.rideId }) else { return "Live status unavailable" }
        switch ride.status {
        case .open: return ride.waitTime.map { $0 == 0 ? "Open · walk-on" : "Open · \($0) min wait" } ?? "Open · wait not posted"
        case .down: return "Temporarily closed"
        case .scheduled: return "Not operating now"
        case .parkInactive: return "Park inactive"
        case .stale, .unknown: return "Live status unavailable"
        }
    }
    private func selectedPlace(_ point: ParkMapPoint) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: point.category.symbol).foregroundStyle(point.category.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(point.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(status(point)).font(.caption).foregroundStyle(Color.pivotMuted)
                if let ride = rides.first(where: { $0.id == point.rideId }) {
                    Button("Ride details") { selectedRide = ride }.font(.caption.weight(.semibold)).frame(minHeight: 32)
                }
            }
            Spacer(minLength: 0)
            Button { selectedID = nil } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                .accessibilityLabel("Close place details")
        }
        .pivotCard(padding: 12)
    }
    private var placesSheet: some View {
        NavigationStack {
            List {
                Section("\(points.count) places shown") {
                    if points.isEmpty { Text("No locations match these filters.").foregroundStyle(Color.pivotMuted) }
                    ForEach(points) { point in
                        Button {
                            selectedID = point.id
                            position = .region(MKCoordinateRegion(center: point.coordinate, latitudinalMeters: 500, longitudinalMeters: 500))
                            showPlaces = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: point.category.symbol).foregroundStyle(point.category.color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(point.name).foregroundStyle(.white)
                                    Text(status(point)).font(.caption).foregroundStyle(Color.pivotMuted)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                Section("Map coverage & sources") {
                    Link("Locations by ThemeParks.wiki", destination: URL(string: "https://www.themeparks.wiki/")!)
                    Text("Catalog checked \(String(catalog?.generatedAt.prefix(10) ?? "Unknown")). \(parkData?.missing.count ?? 0) places omitted because coordinates are unavailable or outside the park area.")
                    Text("Provider listings may be incomplete, seasonal, or closed. A pin does not confirm operation. Restaurant hours and menus are unavailable. Check Shows for today’s performances. Follow posted paths; this map is for orientation.")
                }.font(.caption).foregroundStyle(Color.pivotMuted)
            }
            .navigationTitle(park?.name ?? "Park places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPlaces = false } } }
        }
        .preferredColorScheme(.dark)
    }
    private func loadCatalog() {
        do { catalog = try ParkMapCatalog.load(); loadFailed = false }
        catch { loadFailed = true }
    }
    private func recenter() {
        guard let park else { return }
        let all = allPoints
        if let minLat = all.map(\.latitude).min(), let maxLat = all.map(\.latitude).max(),
           let minLon = all.map(\.longitude).min(), let maxLon = all.map(\.longitude).max() {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                span: MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat-minLat)*1.25), longitudeDelta: max(0.004, (maxLon-minLon)*1.25))))
        } else if let center = ParkLocationDetector.coordinates[park] {
            position = .region(MKCoordinateRegion(center: center, latitudinalMeters: 1400, longitudinalMeters: 1400))
        }
    }
}
