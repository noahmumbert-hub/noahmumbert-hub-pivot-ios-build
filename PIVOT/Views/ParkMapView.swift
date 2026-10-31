import SwiftUI
import MapKit
import UIKit

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

// MapKit owns user-driven camera changes. SwiftUI refreshes only issue a camera
// update when an explicit command ID changes; freshness ticks never reset zoom.
@MainActor
final class ParkMapSession: ObservableObject {
    var camera: MKMapCamera?
#if DEBUG
    @Published var telemetry = ""
    @Published var gestureRect: CGRect?
    @Published var eventTrace = ""
    private var events: [String] = []
    func record(_ event: String) {
        let line = String(format: "%.2f", Date.timeIntervalSinceReferenceDate) + " " + event
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.events.append(line)
            self.events = Array(self.events.suffix(16))
            self.eventTrace = self.events.joined(separator: " | ")
        }
    }
#endif
}
struct ParkMapCameraCommand {
    enum Action { case fit, zoom, focus(CLLocationCoordinate2D) }
    let id = UUID()
    let action: Action
    private let zoomEpoch: UUID
    private let zoomSteps: Int
    init(action: Action) {
        self.action = action
        zoomEpoch = UUID()
        zoomSteps = 0
    }
    private init(zoomEpoch: UUID, zoomSteps: Int) {
        action = .zoom
        self.zoomEpoch = zoomEpoch
        self.zoomSteps = zoomSteps
    }
    func zoomed(by steps: Int) -> Self {
        Self(zoomEpoch: zoomEpoch, zoomSteps: zoomSteps + steps)
    }
    func zoomFactor(since previous: Self?) -> Double {
        let consumed = previous?.zoomEpoch == zoomEpoch ? previous?.zoomSteps ?? 0 : 0
        return pow(2, Double(zoomSteps - consumed))
    }
}
private final class ParkPlaceAnnotation: NSObject, MKAnnotation {
    let point: ParkMapPoint
    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var title: String? { point.name }
    init(_ point: ParkMapPoint) { self.point = point }
}
private final class ParkMarkerView: MKMarkerAnnotationView {
    private func minimumTarget(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: min(0, (rect.width - 44) / 2), dy: min(0, (rect.height - 44) / 2))
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { minimumTarget(bounds).contains(point) }
    override var accessibilityFrame: CGRect {
        get { isHidden || alpha == 0 ? super.accessibilityFrame : minimumTarget(super.accessibilityFrame) }
        set { super.accessibilityFrame = newValue }
    }
}
/// Own the native map without subclassing MKMapView. Camera commands run after
/// the container and child have the final SwiftUI viewport, outside layout itself.
private final class ParkMapContainer: UIView {
    let map = MKMapView()
    var expectedSize = CGSize.zero
    var pendingCameraChange: (() -> Void)?
    private var cameraChangeScheduled = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(map)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func enqueueCameraChange(_ operation: @escaping () -> Void) {
        pendingCameraChange = operation
        setNeedsLayout()
    }
    private var viewportIsReady: Bool {
        guard window != nil, expectedSize.width > 0, expectedSize.height > 0,
              abs(bounds.width - expectedSize.width) < 1,
              abs(bounds.height - expectedSize.height) < 1 else { return false }
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden { return false }
            ancestor = view.superview
        }
        return true
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        map.frame = bounds
        guard !cameraChangeScheduled, pendingCameraChange != nil, viewportIsReady else { return }
        cameraChangeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cameraChangeScheduled = false
            guard self.viewportIsReady, self.map.bounds.size == self.bounds.size,
                  let operation = self.pendingCameraChange else { return }
            self.pendingCameraChange = nil
            operation()
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() }
    }
}

private struct NativeParkMapCanvas: UIViewRepresentable {
    let points: [ParkMapPoint]
    let allPoints: [ParkMapPoint]
    let park: FloridaPark
    @Binding var selectedID: String?
    let session: ParkMapSession
    let command: ParkMapCameraCommand
    let margins: UIEdgeInsets
    let viewportSize: CGSize
    let accent: Color
    let onCluster: ([ParkMapPoint]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ParkMapContainer {
        let container = ParkMapContainer()
        container.expectedSize = viewportSize
        let map = container.map
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "Park map"
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.register(ParkMarkerView.self, forAnnotationViewWithReuseIdentifier: "place")
        map.register(ParkMarkerView.self, forAnnotationViewWithReuseIdentifier: "cluster")
        if let camera = session.camera {
            container.enqueueCameraChange { [weak map, weak coordinator = context.coordinator] in
                coordinator?.cameraInitialized = true
                map?.setCamera(camera, animated: false)
            }
            context.coordinator.lastCommand = command.id
            context.coordinator.lastZoomCommand = command
        }
        return container
    }
    func updateUIView(_ container: ParkMapContainer, context: Context) {
        let map = container.map
        container.expectedSize = viewportSize
        container.setNeedsLayout()
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.lastRequestedMargins != margins {
            coordinator.lastRequestedMargins = margins
#if DEBUG
            session.record("margins requested=\(margins) native=\(map.layoutMargins)")
#endif
            let retained = map.camera.copy() as! MKMapCamera
            let alreadyPending = container.pendingCameraChange
            map.layoutMargins = margins
            // An initial restore or explicit command has priority over inset preservation.
            container.enqueueCameraChange(alreadyPending ?? { [weak map] in map?.setCamera(retained, animated: false) })
        }
        coordinator.updatingSelection = true
        defer { coordinator.updatingSelection = false }
        let desired = Set(points.map(\.id))
        let existing = map.annotations.compactMap { $0 as? ParkPlaceAnnotation }
        map.removeAnnotations(existing.filter { !desired.contains($0.point.id) })
        let present = Set(existing.map { $0.point.id })
        map.addAnnotations(points.filter { !present.contains($0.id) }.map(ParkPlaceAnnotation.init))
        if coordinator.lastCommand != command.id {
            coordinator.lastCommand = command.id
            let action = command.action
            // Accumulate rapid presses against the requested destination, not an
            // intermediate animation frame. Coalescing layout work must not drop zoom.
            let zoomAltitude: Double?
            if case .zoom = action {
                let factor = command.zoomFactor(since: coordinator.lastZoomCommand)
                let base = coordinator.zoomTargetAltitude ?? map.camera.altitude
                zoomAltitude = min(100_000, max(35, base * factor))
                coordinator.zoomTargetAltitude = zoomAltitude
#if DEBUG
                session.record("zoom id=\(command.id) current=\(map.camera.altitude) base=\(base) factor=\(factor) target=\(zoomAltitude!)")
#endif
            } else {
                zoomAltitude = nil
                coordinator.zoomTargetAltitude = nil
            }
            coordinator.lastZoomCommand = command
            container.enqueueCameraChange { [weak map, weak coordinator] in
                guard let map, let coordinator else { return }
                coordinator.cameraInitialized = true
                coordinator.applyingCameraCommand = true
                defer { coordinator.applyingCameraCommand = false }
                switch action {
                case .fit:
                    coordinator.fit(coordinator.parent.allPoints.map(\.coordinate), on: map, animated: false)
                case .focus(let coordinate):
                    map.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500), animated: true)
                case .zoom:
                    guard let zoomAltitude else { return }
                    let camera = map.camera.copy() as! MKMapCamera
                    camera.altitude = zoomAltitude
                    map.setCamera(camera, animated: true)
                }
            }
        }
        if let selectedID,
           let annotation = map.annotations.compactMap({ $0 as? ParkPlaceAnnotation }).first(where: { $0.point.id == selectedID }),
           !map.selectedAnnotations.contains(where: { ($0 as? ParkPlaceAnnotation)?.point.id == selectedID }) {
            map.selectAnnotation(annotation, animated: false)
        } else if selectedID == nil {
            map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: false) }
        }
    }
    static func dismantleUIView(_ container: ParkMapContainer, coordinator: Coordinator) {
        container.map.delegate = nil
        container.pendingCameraChange = nil
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeParkMapCanvas
        var lastCommand: UUID?
        var lastZoomCommand: ParkMapCameraCommand?
        var lastRequestedMargins: UIEdgeInsets?
        var updatingSelection = false
        var cameraInitialized = false
        var zoomTargetAltitude: Double?
        var applyingCameraCommand = false
        init(_ parent: NativeParkMapCanvas) { self.parent = parent }
        func fit(_ coordinates: [CLLocationCoordinate2D], on map: MKMapView, animated: Bool, paddingMeters: Double = 250) {
            zoomTargetAltitude = nil
            guard let first = coordinates.first ?? ParkLocationDetector.coordinates[parent.park] else { return }
            var rect = MKMapRect.null
            for coordinate in coordinates.isEmpty ? [first] : coordinates {
                let point = MKMapPoint(coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            let minimum = MKMapPointsPerMeterAtLatitude(first.latitude) * paddingMeters
            rect = rect.insetBy(dx: -max(minimum, rect.width * 0.08), dy: -max(minimum, rect.height * 0.08))
#if DEBUG
            print("Map fit viewport=\(map.bounds.size) margins=\(map.layoutMargins) rect=\(rect)")
#endif
            // Overlay space is already represented by the map's layout margins.
            map.setVisibleMapRect(rect, animated: animated)
        }
        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
#if DEBUG
            parent.session.record("deselect id=\((view.annotation as? ParkPlaceAnnotation)?.point.id ?? "cluster") updating=\(updatingSelection)")
#endif
            guard !updatingSelection, let annotation = view.annotation as? ParkPlaceAnnotation,
                  parent.selectedID == annotation.point.id else { return }
            parent.selectedID = nil
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // An animated programmatic callback can arrive after setCamera returns.
            // Only a real active UIKit gesture takes ownership from its destination.
            let userGesture = hasActiveGesture(in: mapView)
            if !applyingCameraCommand && userGesture { zoomTargetAltitude = nil }
#if DEBUG
            parent.session.record("regionWill animated=\(animated) gesture=\(userGesture) applying=\(applyingCameraCommand) current=\(mapView.camera.altitude)")
#endif
        }
        private func hasActiveGesture(in view: UIView) -> Bool {
            (view.gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
                || view.subviews.contains { hasActiveGesture(in: $0) }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard cameraInitialized else { return }
            if let target = zoomTargetAltitude, abs(mapView.camera.altitude - target) < max(1, target * 0.01) {
                zoomTargetAltitude = nil
            }
            parent.session.camera = mapView.camera.copy() as? MKMapCamera
#if DEBUG
            parent.session.record("regionDid animated=\(animated) current=\(mapView.camera.altitude) target=\(zoomTargetAltitude.map { String($0) } ?? "nil")")
            updateGestureTarget(on: mapView)
            let c = mapView.centerCoordinate
            let value = "\(c.latitude),\(c.longitude),\(mapView.camera.altitude)"
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView, mapView.delegate === self,
                      self.parent.session.telemetry != value else { return }
                self.parent.session.telemetry = value
            }
#endif
        }
#if DEBUG
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            updateGestureTarget(on: mapView)
        }
        private func updateGestureTarget(on map: MKMapView) {
            guard ProcessInfo.processInfo.arguments.contains("--map-gesture-test") else { return }
            // XCTest needs an element rectangle for a two-finger gesture. Choose
            // real empty map pixels, rather than centering touches among clusters.
            // No production gesture recognizer or annotation is altered.
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map, map.delegate === self else { return }
                let occupied = map.annotations.compactMap { map.view(for: $0) }.filter { !$0.isHidden && $0.alpha > 0 }
                    .map { $0.convert($0.bounds, to: map).insetBy(dx: -24, dy: -24) }
                let safe = map.bounds.inset(by: UIEdgeInsets(top: map.layoutMargins.top + 12, left: 20,
                    bottom: map.layoutMargins.bottom + 12, right: 84))
                var target: CGRect?
                if safe.width >= 140 && safe.height >= 140 {
                    search: for y in stride(from: safe.minY, through: safe.maxY - 140, by: 20) {
                        for x in stride(from: safe.minX, through: safe.maxX - 140, by: 20) {
                            let candidate = CGRect(x: x, y: y, width: 140, height: 140)
                            if !occupied.contains(where: { $0.intersects(candidate) }) { target = candidate; break search }
                        }
                    }
                }
                if self.parent.session.gestureRect != target { self.parent.session.gestureRect = target }
            }
        }
#endif
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cluster", for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(parent.accent)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.glyphTintColor = UIColor { $0.userInterfaceStyle == .dark ? .black : .white }
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                view.isAccessibilityElement = true
                view.accessibilityTraits = .button
                view.accessibilityLabel = "\(cluster.memberAnnotations.count) places. Zoom in"
                view.accessibilityIdentifier = "Map place cluster"
                return view
            }
            guard let annotation = annotation as? ParkPlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place", for: annotation) as! MKMarkerAnnotationView
            view.markerTintColor = UIColor(annotation.point.category.color)
            view.glyphImage = UIImage(systemName: annotation.point.category.symbol)
            view.glyphTintColor = annotation.point.category == .ride
                ? UIColor { $0.userInterfaceStyle == .dark ? .black : .white } : .black
            view.clusteringIdentifier = "park-places"
            view.canShowCallout = false
            view.titleVisibility = .adaptive
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityLabel = annotation.point.name
            view.accessibilityIdentifier = "map-pin-\(annotation.point.id)"
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
#if DEBUG
            parent.session.record("select id=\((view.annotation as? ParkPlaceAnnotation)?.point.id ?? "cluster") updating=\(updatingSelection)")
#endif
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                let members = cluster.memberAnnotations.compactMap { ($0 as? ParkPlaceAnnotation)?.point }
                let coordinates = members.map(\.coordinate)
                if let first = coordinates.first,
                   coordinates.allSatisfy({ MKMapPoint(first).distance(to: MKMapPoint($0)) < 20 }) {
                    parent.onCluster(members)
                } else {
                    fit(coordinates, on: mapView, animated: true, paddingMeters: 20)
                }
                return
            }
            guard let annotation = view.annotation as? ParkPlaceAnnotation else { return }
            parent.selectedID = annotation.point.id
        }
    }
}
private struct MapBottomHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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
    @StateObject private var session = ParkMapSession()
    @State private var command = ParkMapCameraCommand(action: .fit)
    @State private var clusterPoints: [ParkMapPoint]?
    @State private var showPlaces = false
    @State private var selectedRide: LiveRide?
    @State private var isFullScreen = false
    @State private var now = Date()
    @State private var bottomHeight: CGFloat = 60
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
            if isFullScreen { Color.clear } else { mapScreen }
        }
        .task(id: park?.id) { loadCatalog() }
        .onChange(of: category) { _, _ in openOnly = false; selectedID = nil }
        .fullScreenCover(isPresented: $isFullScreen) {
#if DEBUG
            mapScreen.modifier(PivotUITestTypeSize(probeIdentifier: "Map body size"))
#else
            mapScreen
#endif
        }
    }
    private var mapScreen: some View {
        GeometryReader { geometry in
            ZStack {
                if let park, parkData != nil {
                    NativeParkMapCanvas(points: points, allPoints: allPoints, park: park, selectedID: $selectedID,
                        session: session, command: command,
                        margins: UIEdgeInsets(top: geometry.safeAreaInsets.top + 72, left: 12,
                                              // The selected card has a190pt content limit plus its44pt Browse row.
                                              // Reserve that complete resting height immediately, before preferences update.
                                              // Keep the native Legal text clear even when Browse
                                              // wraps to two accessibility-size lines on compact phones.
                                              bottom: geometry.safeAreaInsets.bottom + max(bottomHeight, selected == nil ? 60 : 250) + 32, right: 12),
                        viewportSize: CGSize(width: geometry.size.width,
                            height: geometry.size.height + (isFullScreen ? geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom : 0)),
                        accent: accent,
                        onCluster: { clusterPoints = $0; showPlaces = true })
                        .ignoresSafeArea(edges: isFullScreen ? .all : [])
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--park-map-ui-test") || ProcessInfo.processInfo.arguments.contains("--apple-ui-test") {
                        if ProcessInfo.processInfo.arguments.contains("--map-gesture-test"), let rect = session.gestureRect {
                            // XCTest's whole-window pinch begins over the floating controls.
                            // This transparent, noninteractive target only supplies an empty
                            // rectangle; synthesized touches still reach the real MKMapView.
                            Rectangle().fill(Color.black.opacity(0.001))
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY - (isFullScreen ? geometry.safeAreaInsets.top : 0))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Map gesture area")
                                .accessibilityIdentifier("Map gesture area")
                                .allowsHitTesting(false)
                        }
                        Text(session.telemetry).font(.system(size: 1)).opacity(0.02)
                            .accessibilityIdentifier("Map camera state")
                            .frame(width: 1, height: 1).allowsHitTesting(false)
                        Text(session.eventTrace).font(.system(size: 1)).opacity(0.02)
                            .accessibilityIdentifier("Map event trace")
                            .frame(width: 1, height: 1).allowsHitTesting(false)
                    }
#endif
                } else if park == nil {
                    ContentUnavailableView {
                        Label("Explore the park", systemImage: "map")
                    } description: { Text("Choose a park to see rides, food, and shows.")
                    } actions: { Button("Choose park", action: onChoosePark).buttonStyle(.borderedProminent) }
                } else if loadFailed {
                    ContentUnavailableView {
                        Label("Locations unavailable", systemImage: "map")
                    } description: { Text("The park catalog could not load.")
                    } actions: { Button("Try again", action: loadCatalog) }
                } else { ProgressView("Loading park locations…") }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .top) {
                if park != nil, parkData != nil { mapToolbar.padding(10) }
            }
            .overlay(alignment: .trailing) {
                if park != nil, parkData != nil {
                    VStack(spacing: 0) {
                        mapControl("Zoom in", symbol: "plus") { command = command.zoomed(by: -1) }
                        Divider().frame(width: 32)
                        mapControl("Zoom out", symbol: "minus") { command = command.zoomed(by: 1) }
                        Divider().frame(width: 32)
                        mapControl("Show whole park", symbol: "location") { command = .init(action: .fit) }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.trailing, 10)
                }
            }
            .overlay(alignment: .bottom) {
                if park != nil, parkData != nil {
                    bottomPanel
                        .background(GeometryReader { proxy in Color.clear.preference(key: MapBottomHeightKey.self, value: proxy.size.height) })
                        .padding(.horizontal, 10).padding(.bottom, 8)
                }
            }
            .onPreferenceChange(MapBottomHeightKey.self) { height in
                // Removing the embedded tree during fullscreen presentation emits
                // the preference default; it must not erase the visible panel's inset.
                if height > 0 { bottomHeight = height }
            }
        }
        .background(Color.pivotBackground)
        .task {
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { break }
            }
        }
        .onChange(of: selectedID) { _, _ in searchFocused = false }
        .sheet(isPresented: $showPlaces) { placesSheet }
        .sheet(item: $selectedRide) { ride in
            RideDetailScreenView(initialRide: ride, timeZone: park?.timeZone ?? .current,
                                 mapPoint: allPoints.first { $0.rideId == ride.id })
        }
    }
    private var mapToolbar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).padding(.leading, 12)
            TextField("Search park places", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("Search park places")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .frame(width: 36, height: 44).accessibilityLabel("Clear place search")
            }
            Menu {
                Picker("Places", selection: $category) {
                    Text("All places").tag(Optional<ParkMapCategory>.none)
                    ForEach(ParkMapCategory.allCases) { Text($0.title).tag(Optional($0)) }
                }
                if category == .ride { Toggle("Open rides only", isOn: $openOnly) }
            } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44) }
                .accessibilityLabel("Filter map places").accessibilityIdentifier("Filter map places")
                .accessibilityValue(category?.title ?? "All places")
            Button {
                searchFocused = false
                isFullScreen.toggle()
            } label: {
                Image(systemName: isFullScreen ? "xmark" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isFullScreen ? "Close full screen map" : "Full screen map")
            .accessibilityIdentifier(isFullScreen ? "Close full screen map" : "Full screen map")
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .tint(accent)
    }
    private func mapControl(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 44, height: 44) }
            .accessibilityLabel(title).accessibilityIdentifier(title).tint(accent)
    }
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if let point = selected {
                ScrollView { selectedPlace(point) }.frame(maxHeight: 190).fixedSize(horizontal: false, vertical: true)
                Divider()
            } else if points.isEmpty {
                Text(query.isEmpty ? "No locations match these filters." : "No matching places.")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
            }
            Button { searchFocused = false; clusterPoints = nil; showPlaces = true } label: {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("Browse \(points.count) \(points.count == 1 ? "place" : "places")")
                    Spacer()
                    Text(category?.title ?? "All").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up").font(.caption)
                }.frame(minHeight: 44).padding(.horizontal, 14)
            }.accessibilityIdentifier("Browse map places")
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).tint(accent)
    }
    private func status(_ point: ParkMapPoint) -> String {
        if point.category == .restaurant { return "Dining location · hours unavailable" }
        if point.category == .show {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = park?.timeZone ?? .current
            if let current = freshSnapshot, !current.showScheduleIsStale,
               let next = current.showList.first(where: { $0.id == point.id })?.nextShowAt,
               next >= now, calendar.isDate(next, inSameDayAs: now) {
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
            VStack(alignment: .leading, spacing: 5) {
                Text(point.name).font(.headline).accessibilityIdentifier("Selected place name")
                if point.category == .ride {
                    let value = ridePresentation(point)
                    Text(value.waitMinutes == nil ? "Ride status" : "Current wait").font(.caption).foregroundStyle(.secondary)
                    Text(value.title).font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier("Selected ride wait")
                    Text(value.detail).font(.caption).foregroundStyle(.secondary)
                } else { Text(status(point)).font(.subheadline).foregroundStyle(.secondary) }
                if let ride = rides.first(where: { $0.id == point.rideId }) {
                    Button("Ride details") { selectedRide = ride }.font(.subheadline).frame(minHeight: 44)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { selectedID = nil } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                .accessibilityLabel("Close place details")
        }.padding(14)
    }
    private var placesSheet: some View {
        NavigationStack {
            List {
                Section("\((clusterPoints ?? points).count) places shown") {
                    ForEach(clusterPoints ?? points) { point in
                        Button {
                            selectedID = point.id
                            command = .init(action: .focus(point.coordinate))
                            showPlaces = false
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(point.name).foregroundStyle(.primary)
                                    Text(status(point)).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: point.category.symbol).foregroundStyle(point.category.color) }
                        }.accessibilityIdentifier("map-place-row-\(point.id)")
                    }
                }
                Section("Map coverage & sources") {
                    Link("Locations by ThemeParks.wiki", destination: URL(string: "https://www.themeparks.wiki/")!)
                    Text("Catalog checked \(String(catalog?.generatedAt.prefix(10) ?? "Unknown")). \(parkData?.missing.count ?? 0) places omitted because coordinates are unavailable or outside the park area.")
                    Text("Provider listings may be incomplete, seasonal, or closed. A pin does not confirm operation. Restaurant hours and menus are unavailable. Check Shows for today’s performances. Follow posted paths; this map is for orientation.")
                }.font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle(park?.name ?? "Park places").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPlaces = false } } }
        }
    }
    private func loadCatalog() {
        do { catalog = try catalogOverride ?? ParkMapCatalog.load(); loadFailed = false }
        catch { loadFailed = true }
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
        var points = cases.enumerated().map { index, value in
            ParkMapPoint(id: "fixture-\(index + 1)", name: value.0, category: .ride,
                latitude: 28.4177 + Double(index / 4) * 0.001,
                longitude: -81.5812 + Double(index % 4) * 0.001, rideId: index + 1)
        }
        points += [
            ParkMapPoint(id: "fixture-food-a", name: "North counter", category: .restaurant, latitude: 28.4177, longitude: -81.5812, rideId: nil),
            ParkMapPoint(id: "fixture-food-b", name: "South counter", category: .restaurant, latitude: 28.4177, longitude: -81.5812, rideId: nil)
        ]
        catalog = ParkMapCatalog(generatedAt: "2026-10-30", parks: ["6": ParkMapPark(name: "Magic Kingdom Park", points: points, missing: [])])
        let rides: [[String: Any]] = cases.dropLast().enumerated().map { index, value in
            let offset = index == 0 && ProcessInfo.processInfo.arguments.contains("--map-wait-expiring") ? -880 : value.3
            var ride: [String: Any] = ["id": index + 1, "name": value.0, "land": "Fixture land",
                "status": value.1, "isOpen": value.1 == "OPEN", "lastUpdated": now + offset,
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

    static func rootSnapshot() -> LiveParkSnapshot {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let base = NativeParkMapUITestScreen().snapshot
        var payload = try! JSONSerialization.jsonObject(with: encoder.encode(base)) as! [String: Any]
        let points = try! ParkMapCatalog.load().parks["6"]!.points.filter { $0.rideId != nil }
        let selected = points.filter { [138, 137, 131].contains($0.rideId!) }
        let original = (payload["rides"] as! [[String: Any]])[0]
        payload["rides"] = selected.enumerated().map { index, point -> [String: Any] in
            var ride = original
            ride["id"] = point.rideId!; ride["name"] = point.name; ride["waitTime"] = 35 + index * 5
            ride["location"] = ["latitude": point.latitude, "longitude": point.longitude]
            return ride
        }
        let now = Date().timeIntervalSince1970
        payload["shows"] = [["id": "apple-ui-show", "name": "Castle afternoon performance", "sourceUpdatedAt": now,
            "nextShowAt": now + 7200, "showtimes": [["startTime": now + 7200, "endTime": now + 9000]]]]
        payload["showsSourceUpdatedAt"] = now
        payload["parkHours"] = ["parkId": 6, "parkName": "Magic Kingdom Park", "timezone": "America/New_York",
            "date": ParkHoursSnapshot.localDate(for: .magicKingdom, at: Date()), "fetchedAt": now,
            "cacheAgeSeconds": 0, "cacheHit": false, "stale": false,
            "regular": ["openingTime": now - 3600, "closingTime": now + 28800, "label": "Park open", "type": "OPERATING"],
            "earlyEntry": ["openingTime": now - 5400, "closingTime": now - 3600, "label": "Early entry", "type": "EXTRA_HOURS"],
            "source": ["name": "UI fixture", "label": "UI fixture", "url": "https://example.invalid", "termsUrl": "https://example.invalid", "updateCadenceMinutes": 5]]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try! decoder.decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    var body: some View {
        NavigationStack {
            ParkMapView(park: .magicKingdom, snapshot: snapshot, onChoosePark: {},
                        refreshFailed: refreshFailed, catalogOverride: catalog)
                .background(Color.pivotBackground)
                .navigationTitle("Map test park").navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
