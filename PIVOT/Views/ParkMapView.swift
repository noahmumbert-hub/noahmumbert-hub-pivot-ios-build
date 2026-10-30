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

/// Keep current waits separate from saved values and from operating status.
struct ParkMapRidePresentation: Equatable {
    let title: String
    let detail: String
    let waitMinutes: Int?

    static func resolve(point: ParkMapPoint, parkID: Int?, snapshot: LiveParkSnapshot?,
                        refreshFailed: Bool, at now: Date) -> Self {
        func unavailable(_ detail: String) -> Self {
            Self(title: "Wait unavailable", detail: detail, waitMinutes: nil)
        }
        guard point.category == .ride, let rideID = point.rideId,
              let snapshot, snapshot.parkId == parkID else {
            return unavailable("No current ride update")
        }
        guard !refreshFailed else { return unavailable("Refresh failed · waiting for a current update") }
        let health = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot,
            isLoading: false, refreshFailed: false, at: now)
        guard health.isLive else { return unavailable("Saved or unavailable feed · waiting for a current update") }
        guard let ride = snapshot.rides.first(where: { $0.id == rideID }) else {
            return unavailable("No current update for this ride")
        }
        switch ride.status {
        case .open:
            guard let observed = ride.themeParksWikiStatus?.sourceUpdatedAt ?? ride.lastUpdated else {
                return Self(title: "Open · wait unavailable", detail: "Wait update time unavailable", waitMinutes: nil)
            }
            let age = now.timeIntervalSince(observed)
            guard age.isFinite, age >= -120, age < DashboardFeedHealth.maximumAge else {
                return Self(title: "Open · wait unavailable", detail: "Wait update is too old to call current", waitMinutes: nil)
            }
            guard let wait = ride.waitTime, wait >= 0 else {
                return Self(title: "Open · wait not posted", detail: "No current wait published for this ride", waitMinutes: nil)
            }
            return Self(title: wait == 0 ? "0 min · walk-on" : "\(wait) min",
                detail: "Open · updated \(ParkTimeFormatter.age(observed, relativeTo: now))", waitMinutes: wait)
        case .down: return Self(title: "Temporarily closed", detail: "No current wait while this ride is closed", waitMinutes: nil)
        case .scheduled: return Self(title: "Not operating now", detail: "No current wait outside operation", waitMinutes: nil)
        case .parkInactive: return Self(title: "Park inactive", detail: "No current wait available", waitMinutes: nil)
        case .stale: return unavailable("Ride update is stale")
        case .unknown: return unavailable("Current ride status is unknown")
        }
    }
}

struct ParkMapView: View {
    @Environment(\.pivotAccent) private var accent
    let park: FloridaPark?
    let snapshot: LiveParkSnapshot?
    let onChoosePark: () -> Void
    var refreshFailed = false
    var catalogOverride: ParkMapCatalog? = nil
    @State private var catalog: ParkMapCatalog?
    @State private var loadFailed = false
    @State private var category: ParkMapCategory?
    @State private var query = ""
    @State private var openOnly = false
    @State private var selectedID: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var lastCamera: MapCamera?
    @State private var showPlaces = false
    @State private var selectedRide: LiveRide?
    @State private var isFullScreen = false
    @State private var now = Date()
    @FocusState private var searchFocused: Bool

    private var parkData: ParkMapPark? { park.flatMap { catalog?.parks[String($0.id)] } }
    private var freshSnapshot: LiveParkSnapshot? {
        guard let snapshot, snapshot.parkId == park?.id,
              DashboardFeedHealth.presentation(parkSelected: park != nil, snapshot: snapshot,
                isLoading: false, refreshFailed: refreshFailed, at: now).isLive else { return nil }
        return snapshot
    }
    private var rides: [LiveRide] { freshSnapshot?.rides ?? [] }
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
        Group {
            if isFullScreen { Color.clear } else { mapContent }
        }
        .task(id: park?.id) { loadCatalog(); recenter() }
        .task {
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { break }
            }
        }
        .onChange(of: category) { _, _ in openOnly = false; selectedID = nil }
        .fullScreenCover(isPresented: $isFullScreen, onDismiss: {
            searchFocused = false
            if let lastCamera { position = .camera(lastCamera) }
        }) {
            NavigationStack {
                mapContent
                    .padding(12)
                    .background(Color.pivotBackground)
                    .navigationTitle(park?.name ?? "Park map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { setFullScreen(false) }
                                .accessibilityIdentifier("Close full screen map")
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var mapContent: some View {
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
                    Map(position: $position) {
                        ForEach(points) { point in
                            Annotation(point.name, coordinate: point.coordinate) {
                                Button {
                                    searchFocused = false
                                    selectedID = point.id
                                } label: {
                                    Image(systemName: point.category.symbol)
                                        .font(.headline)
                                        .foregroundStyle(Color.pivotBackground)
                                        .frame(width: 44, height: 44)
                                        .background(point.category.color, in: Circle())
                                        .overlay { Circle().stroke(selectedID == point.id ? Color.white : .clear, lineWidth: 3) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(point.name)
                                .accessibilityIdentifier("map-pin-\(point.id)")
                            }
                        }
                    }
                    .onMapCameraChange(frequency: .onEnd) { lastCamera = $0.camera }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControls { MapCompass(); MapScaleView() }
                    HStack(spacing: 8) {
                        if !isFullScreen {
                            Button { setFullScreen(true) } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Full screen map")
                            .accessibilityIdentifier("Full screen map")
                        }
                        Button { searchFocused = false; recenter() } label: {
                            Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Show whole park")
                    }
                    .background(Color.pivotSurface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(10)
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
        .sheet(isPresented: $showPlaces) { placesSheet }
        .sheet(item: $selectedRide) { ride in
            RideDetailScreenView(initialRide: ride, timeZone: park?.timeZone ?? .current,
                                 mapPoint: allPoints.first { $0.rideId == ride.id })
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.pivotMuted)
            TextField("Search rides, food, shows", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
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
        let value = ridePresentation(point)
        return "\(value.title) · \(value.detail)"
    }
    private func ridePresentation(_ point: ParkMapPoint) -> ParkMapRidePresentation {
        ParkMapRidePresentation.resolve(point: point, parkID: park?.id, snapshot: snapshot,
                                        refreshFailed: refreshFailed, at: now)
    }

    private func selectedPlace(_ point: ParkMapPoint) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: point.category.symbol).foregroundStyle(point.category.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(point.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if point.category == .ride {
                    let presentation = ridePresentation(point)
                    Text(presentation.waitMinutes == nil ? "Ride status" : "Current wait")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                    Text(presentation.title).font(.title2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(presentation.waitMinutes == nil ? Color.white : accent)
                        .accessibilityIdentifier("Selected ride wait")
                    Text(presentation.detail).font(.caption).foregroundStyle(Color.pivotMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(status(point)).font(.caption).foregroundStyle(Color.pivotMuted)
                }
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
                            searchFocused = false
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
        do { catalog = try catalogOverride ?? ParkMapCatalog.load(); loadFailed = false }
        catch { loadFailed = true }
    }
    private func setFullScreen(_ value: Bool) {
        searchFocused = false
        if let lastCamera { position = .camera(lastCamera) }
        isFullScreen = value
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

#if DEBUG
/// Local simulator fixtures only; never compiled into the device Release archive.
struct NativeParkMapUITestScreen: View {
    private let catalog: ParkMapCatalog
    private let snapshot: LiveParkSnapshot
    private let refreshFailed = ProcessInfo.processInfo.arguments.contains("--map-refresh-failed")

    init() {
        let now = Date().timeIntervalSince1970
        let cases: [(String, String, Int?, Double)] = [
            ("Current wait ride", "OPEN", 35, 0), ("Walk-on ride", "OPEN", 0, 0),
            ("Unposted wait ride", "OPEN", nil, 0), ("Closed ride", "DOWN", 99, -3600),
            ("Scheduled ride", "SCHEDULED", 99, 0), ("Inactive ride", "PARK_INACTIVE", 99, 0),
            ("Old wait ride", "OPEN", 80, -901), ("Stale ride", "STALE", 99, 0),
            ("Unknown ride", "NEW_STATUS", 99, 0), ("Unmapped ride", "OPEN", 10, 0)
        ]
        let points = cases.enumerated().map { index, value in
            ParkMapPoint(id: "fixture-\(index + 1)", name: value.0, category: .ride,
                latitude: 28.4177 + Double(index / 4) * 0.001,
                longitude: -81.5812 + Double(index % 4) * 0.001, rideId: index + 1)
        }
        catalog = ParkMapCatalog(generatedAt: "2026-10-30", parks: ["6": ParkMapPark(name: "Magic Kingdom Park", points: points, missing: [])])
        let rides: [[String: Any]] = cases.dropLast().enumerated().map { index, value in
            var ride: [String: Any] = ["id": index + 1, "name": value.0, "land": "Fixture land",
                "status": value.1, "isOpen": value.1 == "OPEN", "lastUpdated": now + value.3,
                "weatherExposure": "INDOOR", "radarEligible": true, "radarCategory": "RIDE",
                "reopenPending": false, "trend": [99]]
            if let wait = value.2 { ride["waitTime"] = wait }
            return ride
        }
        let payload: [String: Any] = ["parkId": 6,
            "park": ["name": "Magic Kingdom Park", "destination": "Walt Disney World", "operator": "Disney", "country": "United States", "timezone": "America/New_York"],
            "parkActive": true, "feedHealthy": true, "fetchedAt": now, "sourceUpdatedAt": now,
            "cacheAgeSeconds": 0, "rides": rides,
            "metrics": ["openCount": 3, "downCount": 1, "scheduledCount": 1, "reportingCount": rides.count],
            "source": ["name": "UI test fixture", "url": "https://example.invalid", "updateCadenceMinutes": 5],
            "weather": ["location": ["parkId": 6, "parkName": "Magic Kingdom Park", "latitude": 28.4177, "longitude": -81.5812],
                "fetchedAt": now, "activeAlerts": [],
                "nws": ["status": "UNAVAILABLE", "observationStatus": "UNAVAILABLE", "forecastStatus": "UNAVAILABLE", "alertsStatus": "UNAVAILABLE", "url": "https://example.invalid"],
                "lightning": ["status": "UNAVAILABLE", "densityDetectedAt": [], "parkCoordinateDensityDetectedAt": [], "sampleRadiusMiles": 5,
                    "periodsDetected30Minutes": 0, "coverageMinutes": 0, "url": "https://example.invalid"]]]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        snapshot = try! decoder.decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    var body: some View {
        NavigationStack {
            ParkMapView(park: .magicKingdom, snapshot: snapshot, onChoosePark: {},
                        refreshFailed: refreshFailed, catalogOverride: catalog)
                .padding(16).background(Color.pivotBackground)
                .navigationTitle("Map test park").navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
