import Foundation
import Combine
import CoreLocation
import UserNotifications

enum ParkLocationStatus: Equatable, Sendable {
    case idle
    case searching
    case found(ParkLocationMatch)
    case outsideSupportedPark
    case denied
    case unavailable
    case failed

    var label: String {
        switch self {
        case .idle: "Use my location to choose a park"
        case .searching: "Finding the nearest supported park…"
        case .found(let match): "Location set · \(match.park.name) · \(match.distanceMiles.formatted(.number.precision(.fractionLength(1)))) mi away"
        case .outsideSupportedPark: "No supported park found nearby"
        case .denied: "Location permission is off"
        case .unavailable: "Location is unavailable"
        case .failed: "Could not read your location"
        }
    }
}

enum ParkLocationRequest: Sendable {
    case location(latitude: Double, longitude: Double)
    case denied
    case unavailable
    case failed
}

@MainActor
private final class ParkLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<ParkLocationRequest, Never>?

    func requestLocation() async -> ParkLocationRequest {
        await withCheckedContinuation { continuation in
            finish(.failed)
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.denied)
            @unknown default:
                finish(.unavailable)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.denied)
        case .notDetermined:
            break
        @unknown default:
            finish(.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failed)
            return
        }
        finish(.location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failed)
    }

    private func finish(_ result: ParkLocationRequest) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var selectedPark: FloridaPark?
    @Published private(set) var snapshot: LiveParkSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var alertsEnabled: Bool
    @Published private(set) var cachedParkHours: [Int: ParkHoursSnapshot] = [:]
    @Published private(set) var locationStatus: ParkLocationStatus = .idle
    @Published var toastMessage: String?

    let notificationService: NotificationService
    let liveActivityService: LiveActivityService

    private let apiClient: PivotAPIClient
    private let defaults: UserDefaults
    private let locationService = ParkLocationService()
    private var sceneIsActive = false
    private var monitoringTask: Task<Void, Never>?
    private var monitoringGeneration: UInt = 0
    private var parkHoursTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var cachedSnapshots: [Int: LiveParkSnapshot] = [:]
    private var notificationBaselines: [Int: ParkRideBaseline] = [:]

    private static let selectedParkKey = "pivot.selectedPark"
    private static let alertsEnabledKey = "pivot.alertsEnabled"
    private static let noParkValue = -1
    nonisolated static let foregroundRefreshIntervalSeconds: UInt64 = 5
    nonisolated static func foregroundRefreshDelay(elapsed: TimeInterval) -> TimeInterval {
        guard elapsed.isFinite, elapsed >= 0 else { return Double(foregroundRefreshIntervalSeconds) }
        return max(1, Double(foregroundRefreshIntervalSeconds) - elapsed)
    }

    init(
        apiClient: PivotAPIClient = .shared,
        notificationService: NotificationService? = nil,
        liveActivityService: LiveActivityService? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.notificationService = notificationService ?? NotificationService()
        self.liveActivityService = liveActivityService ?? LiveActivityService()
        self.defaults = defaults

        if defaults.object(forKey: Self.selectedParkKey) == nil {
            selectedPark = .magicKingdom
        } else {
            let stored = defaults.integer(forKey: Self.selectedParkKey)
            selectedPark = stored == Self.noParkValue ? nil : FloridaPark(rawValue: stored) ?? .magicKingdom
        }
        alertsEnabled = defaults.bool(forKey: Self.alertsEnabledKey)
    }

    deinit {
        monitoringTask?.cancel()
        parkHoursTask?.cancel()
        locationTask?.cancel()
    }

    var reviewedRides: [LiveRide] {
        (snapshot?.rides ?? []).filter(\.radarEligible)
    }

    var radarRides: [LiveRide] {
        reviewedRides.filter(\.isRadarDown)
    }

    var radarRide: LiveRide? {
        PIVOTLiveActivityRideSelector.mostPopularClosedRide(in: reviewedRides)
    }

    var bestOpenRide: LiveRide? {
        reviewedRides
            .filter { $0.status == .open && $0.waitTime != nil }
            .sorted {
                if $0.waitTime != $1.waitTime { return ($0.waitTime ?? .max) < ($1.waitTime ?? .max) }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .first
    }

    /// Returns the most recent schedule already loaded for a park. The picker
    /// uses this for an at-a-glance schedule without starting background
    /// monitoring for every park just because the menu is open.
    func parkHours(for park: FloridaPark) -> ParkHoursSnapshot? {
        if selectedPark == park {
            return snapshot?.parkHours ?? cachedParkHours[park.rawValue]
        }
        return cachedParkHours[park.rawValue] ?? cachedSnapshots[park.rawValue]?.parkHours
    }

    /// Populate park-picker schedule previews without starting ride/weather
    /// monitoring for every park. Requests run in small batches so the full
    /// catalog loads promptly without creating an unbounded request burst.
    func loadParkHours(for parks: [FloridaPark] = FloridaPark.allCases) {
        let parksToLoad = parks.filter { parkHours(for: $0) == nil }
        guard !parksToLoad.isEmpty else { return }

        parkHoursTask?.cancel()
        let apiClient = self.apiClient
        parkHoursTask = Task { [weak self] in
            for batchStart in stride(from: 0, to: parksToLoad.count, by: 6) {
                guard !Task.isCancelled else { return }
                let batch = Array(parksToLoad[batchStart..<min(batchStart + 6, parksToLoad.count)])
                await withTaskGroup(of: (Int, ParkHoursSnapshot?).self) { group in
                    for park in batch {
                        group.addTask {
                            (park.rawValue, try? await apiClient.parkHours(for: park))
                        }
                    }
                    for await (parkId, hours) in group {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            return
                        }
                        if let hours {
                            self?.cachedParkHours[parkId] = hours
                        }
                    }
                }
            }
        }
    }

    var sourceStatus: String {
        if selectedPark == nil { return "Paused · choose a park" }
        if isLoading && snapshot == nil { return "Refreshing" }
        if snapshot?.feedHealthy == true {
            if snapshot?.themeParksWiki?.cacheStale == true {
                return "Live snapshot · retrying · checked \(ParkTimeFormatter.age(snapshot?.fetchedAt))"
            }
            return "Live · auto 5s · checked \(ParkTimeFormatter.age(snapshot?.fetchedAt))"
        }
        if errorMessage != nil { return "Last update retained" }
        return "Source too old to call live"
    }

    func bootstrap() async {
        await notificationService.refreshAuthorizationStatus()
        if alertsEnabled,
           notificationService.authorizationStatus != .authorized,
           notificationService.authorizationStatus != .provisional {
            alertsEnabled = false
            defaults.set(false, forKey: Self.alertsEnabledKey)
        }
        if selectedPark == nil {
            liveActivityService.synchronize(nil)
        }
        if defaults.object(forKey: Self.selectedParkKey) == nil {
            requestParkFromLocation()
        }
    }

    func requestParkFromLocation() {
        guard locationStatus != .searching else { return }
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self else { return }
            self.locationStatus = .searching
            let result = await self.locationService.requestLocation()
            guard !Task.isCancelled else { return }

            switch result {
            case .location(let latitude, let longitude):
                guard let match = ParkLocationDetector.nearestPark(latitude: latitude, longitude: longitude) else {
                    self.locationStatus = .outsideSupportedPark
                    return
                }
                self.locationStatus = .found(match)
                self.selectPark(match.park)
            case .denied:
                self.locationStatus = .denied
            case .unavailable:
                self.locationStatus = .unavailable
            case .failed:
                self.locationStatus = .failed
            }
        }
    }

    func setSceneActive(_ isActive: Bool) {
        guard sceneIsActive != isActive else { return }
        sceneIsActive = isActive
        if isActive {
            restartMonitoring()
        } else {
            monitoringGeneration &+= 1
            monitoringTask?.cancel()
            monitoringTask = nil
        }
    }

    func selectPark(_ park: FloridaPark?) {
        if selectedPark == park {
            defaults.set(park?.rawValue ?? Self.noParkValue, forKey: Self.selectedParkKey)
            return
        }
        monitoringTask?.cancel()
        monitoringTask = nil
        selectedPark = park
        defaults.set(park?.rawValue ?? Self.noParkValue, forKey: Self.selectedParkKey)
        errorMessage = nil
        toastMessage = nil

        if let park {
            snapshot = cachedSnapshots[park.rawValue]
            notificationBaselines.removeValue(forKey: park.rawValue)
            isLoading = snapshot == nil
        } else {
            snapshot = nil
            isLoading = false
        }
        // Do not start a new park's Live Activity from an in-memory cache.
        // The successful refresh below supplies the first fresh target.
        liveActivityService.synchronize(nil)
        restartMonitoring()
    }

    func refreshNow() async {
        guard let selectedPark else { return }
        await refresh(expectedPark: selectedPark)
    }

    func enableAlerts() async {
        guard selectedPark != nil else { return }
        let granted = await notificationService.requestAuthorization()
        alertsEnabled = granted
        defaults.set(granted, forKey: Self.alertsEnabledKey)
        toastMessage = granted ? "Ride alerts are on for \(selectedPark?.name ?? "the selected park")." : "Notifications were not enabled."
    }

    func disableAlerts() {
        alertsEnabled = false
        defaults.set(false, forKey: Self.alertsEnabledKey)
        toastMessage = "Ride alerts are off."
    }

    func visibleRides(query: String, filter: RideListFilter, sort: RideSort) -> [LiveRide] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return reviewedRides
            .filter { ride in
                switch filter {
                case .all: true
                case .open: ride.status == .open
                case .radar: ride.isRadarDown
                }
            }
            .filter { ride in
                trimmedQuery.isEmpty || "\(ride.name) \(ride.land)".localizedCaseInsensitiveContains(trimmedQuery)
            }
            .sorted { first, second in
                switch sort {
                case .shortest:
                    let firstWait = first.status == .open ? (first.waitTime ?? .max) : .max
                    let secondWait = second.status == .open ? (second.waitTime ?? .max) : .max
                    if firstWait != secondWait { return firstWait < secondWait }
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                case .longest:
                    let firstWait = first.status == .open ? (first.waitTime ?? -1) : -1
                    let secondWait = second.status == .open ? (second.waitTime ?? -1) : -1
                    if firstWait != secondWait { return firstWait > secondWait }
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                case .name:
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                case .status:
                    let firstRank = statusRank(first.status)
                    let secondRank = statusRank(second.status)
                    if firstRank != secondRank { return firstRank < secondRank }
                    return (first.waitTime ?? -1) > (second.waitTime ?? -1)
                }
            }
    }

    private func statusRank(_ status: RideStatus) -> Int {
        switch status {
        case .down: 0
        case .open: 1
        case .stale: 2
        case .scheduled: 3
        case .parkInactive: 4
        case .unknown: 5
        }
    }

    private func restartMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        monitoringGeneration &+= 1
        guard sceneIsActive, let park = selectedPark else { return }
        let generation = monitoringGeneration

        monitoringTask = Task { [weak self] in
            // Give an in-flight task cancelled above a chance to run its
            // cleanup before this generation performs its immediate fetch.
            await Task.yield()
            while !Task.isCancelled {
                guard let self, self.monitoringGeneration == generation else { return }
                let startedAt = ProcessInfo.processInfo.systemUptime
                await self.refresh(expectedPark: park)
                guard !Task.isCancelled, self.monitoringGeneration == generation else { return }
                do {
                    try await Task.sleep(for: .seconds(Self.foregroundRefreshDelay(
                        elapsed: ProcessInfo.processInfo.systemUptime - startedAt
                    )))
                } catch {
                    return
                }
            }
        }
    }

    private func refresh(expectedPark: FloridaPark) async {
        guard selectedPark == expectedPark, !isRefreshing else { return }
        isRefreshing = true
        if snapshot == nil { isLoading = true }
        defer {
            isRefreshing = false
            isLoading = false
        }

        do {
            let nextSnapshot = try await apiClient.snapshot(for: expectedPark)
            guard selectedPark == expectedPark else { return }

            let transition = RideTransitionEngine.evaluate(
                selectedParkId: expectedPark.rawValue,
                previous: notificationBaselines[expectedPark.rawValue],
                current: nextSnapshot
            )
            notificationBaselines[expectedPark.rawValue] = transition.nextBaseline
            cachedSnapshots[expectedPark.rawValue] = nextSnapshot
            if let hours = nextSnapshot.parkHours {
                cachedParkHours[expectedPark.rawValue] = hours
            }
            snapshot = nextSnapshot
            errorMessage = nil
            if nextSnapshot.feedHealthy {
                synchronizeLiveActivity()
            }

            if alertsEnabled, !transition.alerts.isEmpty {
                await notificationService.deliver(
                    alerts: transition.alerts,
                    park: expectedPark,
                    snapshotFetchedAt: nextSnapshot.fetchedAt
                )
                toastMessage = transition.alerts.count == 1
                    ? transition.alerts[0].rideName + (transition.alerts[0].kind == .closed ? " closed" : " reopened")
                    : "\(transition.alerts.count) ride statuses changed at \(expectedPark.name)."
            }
        } catch is CancellationError {
            return
        } catch {
            guard selectedPark == expectedPark else { return }
            errorMessage = error.localizedDescription
        }
    }

    func synchronizeLiveActivity() {
        liveActivityService.synchronize(
            PIVOTLiveActivityTargetBuilder.makeTarget(
                selectedPark: selectedPark,
                snapshot: snapshot,
                featuredRide: radarRide,
                accentName: UserDefaults.standard.string(forKey: PivotAccent.storageKey) ?? "mint"
            )
        )
    }
}
