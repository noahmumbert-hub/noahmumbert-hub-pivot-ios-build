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
    @Published private(set) var waitLearning: WaitLearningHistory
    @Published private(set) var crowdSnapshots: [Int: LiveParkSnapshot] = [:]
    @Published private(set) var crowdRefreshErrors: Set<Int> = []
    @Published private(set) var crowdLoading: Set<Int> = []
    @Published private(set) var selectedPark: FloridaPark?
    @Published private(set) var snapshot: LiveParkSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var alertsEnabled: Bool
    @Published private(set) var isRequestingAlertPermission = false
    @Published private(set) var alertPreferences: NativeAlertPreferences
    @Published private(set) var pinnedRadarRideID: Int? = nil
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
    private var refreshSequence: UInt = 0
    private var activeRefresh: (id: UInt, park: FloridaPark, generation: UInt)?
    private var parkHoursTask: Task<Void, Never>?
    private var requestedParkHours: Set<FloridaPark> = []
    private var locationTask: Task<Void, Never>?
    private var locationGeneration: UInt = 0
    private let locationRequest: (@MainActor () async -> ParkLocationRequest)?
    private var cachedSnapshots: [Int: LiveParkSnapshot] = [:]
    private var cachedRefreshErrors: [Int: String] = [:]
    private var liveActivityObservationParkID: Int?
    private var notificationBaselines: [Int: ParkRideBaseline] = [:]
    private var smartAlertBaselines: [Int: NativeAlertObservation] = [:]
    private var alertCooldown: NativeAlertCooldown
    private var alertDeliveryGeneration: UInt = 0
    private var alertPermissionGeneration: UInt = 0

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
        defaults: UserDefaults = .standard,
        locationRequest: (@MainActor () async -> ParkLocationRequest)? = nil
    ) {
        self.apiClient = apiClient
        self.notificationService = notificationService ?? NotificationService()
        self.liveActivityService = liveActivityService ?? LiveActivityService()
        self.defaults = defaults
        waitLearning = WaitLearningHistory.load(from: defaults)
        self.locationRequest = locationRequest
        alertPreferences = NativeAlertPreferences.load(from: defaults)
        alertCooldown = NativeAlertCooldown(defaults: defaults)

        if defaults.object(forKey: Self.selectedParkKey) == nil {
            selectedPark = .magicKingdom
        } else {
            let stored = defaults.integer(forKey: Self.selectedParkKey)
            selectedPark = stored == Self.noParkValue ? nil : FloridaPark(rawValue: stored) ?? .magicKingdom
        }
        alertsEnabled = defaults.bool(forKey: Self.alertsEnabledKey)
        pinnedRadarRideID = selectedPark.flatMap { defaults.object(forKey: Self.radarPinKey($0.rawValue)) as? Int }
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

    /// One selection is shared by the in-app Radar and the local Live Activity.
    var featuredRadarRide: LiveRide? {
        PIVOTLiveActivityRideSelector.featuredClosedRide(in: reviewedRides, pinnedRideID: pinnedRadarRideID)
    }

    // Compatibility for existing RootView callers.
    var radarRide: LiveRide? { featuredRadarRide }

    private static func radarPinKey(_ parkID: Int) -> String { "pivot.radarPin.\(parkID)" }

    func pinRadarRide(_ rideID: Int?) {
        guard let selectedPark else { return }
        if let rideID, !reviewedRides.contains(where: { $0.id == rideID }) { return }
        pinnedRadarRideID = rideID
        if let rideID {
            defaults.set(rideID, forKey: Self.radarPinKey(selectedPark.rawValue))
        } else {
            defaults.removeObject(forKey: Self.radarPinKey(selectedPark.rawValue))
        }
        synchronizeLiveActivity()
    }

    func updateAlertPreferences(_ value: NativeAlertPreferences) {
        let next = value.normalized
        guard next != alertPreferences else { return }
        alertPreferences = next
        next.save(to: defaults)
        // Preferences never request notification permission or enable delivery.
        alertDeliveryGeneration &+= 1
    }

    var favoriteRideIDsForSelectedPark: Set<Int> {
        guard let selectedPark else { return [] }
        return Set(defaults.array(forKey: "pivot.favoriteRides.\(selectedPark.rawValue)") as? [Int] ?? [])
    }

    private func resetAlertBaselines() {
        notificationBaselines.removeAll()
        smartAlertBaselines.removeAll()
        alertDeliveryGeneration &+= 1
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

    /// Returns the current park-local day's schedule already loaded for a park. The picker
    /// uses this for an at-a-glance schedule without starting background
    /// monitoring for every park just because the menu is open.
    func parkHours(for park: FloridaPark, at now: Date = Date()) -> ParkHoursSnapshot? {
        ParkHoursSnapshot.current(for: park, candidates: [
            selectedPark == park ? snapshot?.parkHours : nil,
            cachedParkHours[park.rawValue],
            cachedSnapshots[park.rawValue]?.parkHours,
        ], at: now)
    }

    /// Populate park-picker schedule previews without starting ride/weather
    /// monitoring for every park. Requests run in small batches so the full
    /// catalog loads promptly without creating an unbounded request burst.
    func loadParkHours(for parks: [FloridaPark] = FloridaPark.allCases) {
        requestedParkHours.formUnion(parks)
        let now = Date()
        let parksToLoad = parks.filter {
            let hours = parkHours(for: $0, at: now)
            return hours == nil || hours?.stale == true
        }
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
                        // The local day may have changed while the request was
                        // in flight, or the provider may have retained yesterday.
                        if let hours, let park = FloridaPark(rawValue: parkId),
                           hours.isCurrent(for: park) {
                            self?.cachedParkHours[parkId] = hours
                        }
                    }
                }
            }
        }
    }

    var sourceStatus: String {
        feedHealth().status
    }

    private func learnWaits(from observation: LiveParkSnapshot, now: Date) {
        var next = waitLearning
        if next.record(observation, now: now) {
            waitLearning = next
            next.save(to: defaults)
        }
    }

    func crowdSnapshot(for park: FloridaPark) -> LiveParkSnapshot? {
        guard selectedPark == park else { return crowdSnapshots[park.rawValue] }
        guard let latest = crowdSnapshots[park.rawValue] else { return snapshot }
        return (snapshot?.fetchedAt ?? .distantPast) > latest.fetchedAt ? snapshot : latest
    }

    func crowdRefreshFailed(for park: FloridaPark) -> Bool {
        if selectedPark == park { return errorMessage != nil || crowdRefreshErrors.contains(park.rawValue) }
        return crowdRefreshErrors.contains(park.rawValue)
    }

    func isCrowdLoading(for park: FloridaPark) -> Bool {
        crowdLoading.contains(park.rawValue) ||
            (selectedPark == park && isRefreshing && activeRefresh?.park == park)
    }

    func refreshCrowd(for park: FloridaPark) async {
        // The selected park's refresh already updates both dashboard and crowd
        // data. Share that path instead of issuing a second live request.
        if selectedPark == park {
            await refreshNow()
            return
        }
        guard !crowdLoading.contains(park.rawValue) else { return }
        crowdLoading.insert(park.rawValue)
        let requestedAt = Date()
        defer { crowdLoading.remove(park.rawValue) }
        do {
            let observation = try await apiClient.snapshot(for: park)
            guard !Task.isCancelled, observation.parkId == park.rawValue else { return }
            if let prior = crowdSnapshots[park.rawValue], observation.fetchedAt < prior.fetchedAt { return }
            crowdSnapshots[park.rawValue] = observation
            crowdRefreshErrors.remove(park.rawValue)
            learnWaits(from: observation, now: Date())
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if (crowdSnapshots[park.rawValue]?.fetchedAt ?? .distantPast) <= requestedAt {
                crowdRefreshErrors.insert(park.rawValue)
            }
        }
    }

    func feedHealth(at now: Date = Date()) -> DashboardFeedHealth {
        DashboardFeedHealth.presentation(
            parkSelected: selectedPark != nil,
            snapshot: snapshot,
            isLoading: isLoading,
            refreshFailed: errorMessage != nil,
            at: now
        )
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

    func canAssertNoClosures(at now: Date = Date()) -> Bool {
        DashboardClosureHealth.canAssertNoClosures(snapshot: snapshot, feedHealth: feedHealth(at: now))
    }

    func requestParkFromLocation() {
        guard locationStatus != .searching else { return }
        locationTask?.cancel()
        locationGeneration &+= 1
        let requestGeneration = locationGeneration
        locationTask = Task { [weak self] in
            guard let self else { return }
            self.locationStatus = .searching
            let result: ParkLocationRequest
            if let request = self.locationRequest { result = await request() }
            else { result = await self.locationService.requestLocation() }
            guard !Task.isCancelled, requestGeneration == self.locationGeneration else { return }

            switch result {
            case .location(let latitude, let longitude):
                guard let match = ParkLocationDetector.nearestPark(latitude: latitude, longitude: longitude) else {
                    self.locationStatus = .outsideSupportedPark
                    return
                }
                self.selectPark(match.park)
                self.locationStatus = .found(match)
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
        // A foreground return is a new observation session, never a replay.
        resetAlertBaselines()
        if isActive {
            // Refresh previously requested picker previews after an overnight
            // suspension without starting ride monitoring for other parks.
            loadParkHours(for: Array(requestedParkHours))
            restartMonitoring()
        } else {
            monitoringGeneration &+= 1
            monitoringTask?.cancel()
            monitoringTask = nil
        }
    }

    func selectPark(_ park: FloridaPark?) {
        // Even reselecting the same park or No Park cancels an older GPS intent.
        locationGeneration &+= 1
        locationTask?.cancel()
        locationStatus = .idle
        if selectedPark == park {
            defaults.set(park?.rawValue ?? Self.noParkValue, forKey: Self.selectedParkKey)
            return
        }
        monitoringTask?.cancel()
        monitoringTask = nil
        selectedPark = park
        liveActivityObservationParkID = nil
        alertPermissionGeneration &+= 1
        pinnedRadarRideID = park.flatMap { defaults.object(forKey: Self.radarPinKey($0.rawValue)) as? Int }
        resetAlertBaselines()
        defaults.set(park?.rawValue ?? Self.noParkValue, forKey: Self.selectedParkKey)
        errorMessage = nil
        toastMessage = nil

        if let park {
            snapshot = cachedSnapshots[park.rawValue]
            errorMessage = cachedRefreshErrors[park.rawValue]
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
        guard let requestedPark = selectedPark, !isRequestingAlertPermission else { return }
        isRequestingAlertPermission = true
        alertPermissionGeneration &+= 1
        let permissionGeneration = alertPermissionGeneration
        defer { isRequestingAlertPermission = false }
        let granted = await notificationService.requestAuthorization()
        guard selectedPark == requestedPark, permissionGeneration == alertPermissionGeneration else { return }
        resetAlertBaselines()
        alertsEnabled = granted
        defaults.set(granted, forKey: Self.alertsEnabledKey)
        toastMessage = granted ? "Foreground ride alerts are on for \(requestedPark.name)." : "Notifications were not enabled."
    }

    func disableAlerts() {
        alertPermissionGeneration &+= 1
        resetAlertBaselines()
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
        guard selectedPark == expectedPark else { return }
        let requestGeneration = monitoringGeneration
        if let activeRefresh, activeRefresh.park == expectedPark,
           activeRefresh.generation == requestGeneration { return }
        refreshSequence &+= 1
        let requestID = refreshSequence
        activeRefresh = (requestID, expectedPark, requestGeneration)
        isRefreshing = true
        if snapshot == nil { isLoading = true }
        defer {
            // A slow/cancelled previous park cannot clear the new request's UI.
            if activeRefresh?.id == requestID {
                activeRefresh = nil
                isRefreshing = false
                isLoading = false
            }
        }

        do {
            let nextSnapshot = try await apiClient.snapshot(for: expectedPark)
            guard !Task.isCancelled, selectedPark == expectedPark, requestGeneration == monitoringGeneration else { return }

            let now = Date()
            let observation = NativeAlertObservation(snapshot: nextSnapshot)
            // Cache grace reports may reuse an older/duplicate fetchedAt while
            // still saying feedHealthy. Invalidate before the ordering guard.
            if observation.providerCacheStale {
                resetAlertBaselines()
                liveActivityObservationParkID = nil
            }
            // A late older response must not move the UI/Activity back in time.
            if let displayed = snapshot, displayed.parkId == expectedPark.rawValue,
               nextSnapshot.fetchedAt < displayed.fetchedAt { return }
            let previousObservation = smartAlertBaselines[expectedPark.rawValue]
            let transition = RideTransitionEngine.evaluate(
                selectedParkId: expectedPark.rawValue,
                previous: notificationBaselines[expectedPark.rawValue],
                current: nextSnapshot
            )
            let candidates = NativeSmartAlertEngine.candidates(
                selectedParkId: expectedPark.rawValue,
                previous: previousObservation, current: observation,
                transitions: transition.alerts, preferences: alertPreferences,
                favorites: favoriteRideIDsForSelectedPark, now: now
            )
            if let nextBaseline = NativeSmartAlertEngine.nextBaseline(
                previous: previousObservation, current: observation, now: now
            ) {
                notificationBaselines[expectedPark.rawValue] = transition.nextBaseline
                smartAlertBaselines[expectedPark.rawValue] = nextBaseline
            } else {
                // The first healthy response after an outage is only a baseline.
                resetAlertBaselines()
            }
            cachedSnapshots[expectedPark.rawValue] = nextSnapshot
            cachedRefreshErrors.removeValue(forKey: expectedPark.rawValue)
            if let hours = nextSnapshot.parkHours {
                cachedParkHours[expectedPark.rawValue] = hours
            }
            snapshot = nextSnapshot
            errorMessage = nil
            crowdSnapshots[expectedPark.rawValue] = nextSnapshot
            crowdRefreshErrors.remove(expectedPark.rawValue)
            learnWaits(from: nextSnapshot, now: now)
            if nextSnapshot.feedHealthy, !observation.providerCacheStale,
               NativeSmartAlertEngine.isFresh(nextSnapshot.fetchedAt, at: now) {
                liveActivityObservationParkID = expectedPark.rawValue
                synchronizeLiveActivity()
            } else {
                liveActivityObservationParkID = nil
            }

            if sceneIsActive, alertsEnabled, !candidates.isEmpty {
                let accepted = alertCooldown.reserve(candidates, at: now)
                alertCooldown.save(to: defaults)
                let deliveryGeneration = alertDeliveryGeneration
                let delivered = await notificationService.deliver(
                    alerts: accepted,
                    park: expectedPark,
                    shouldDeliver: { [weak self] alert in
                        guard let self else { return false }
                        return self.sceneIsActive && self.alertsEnabled
                            && self.selectedPark == expectedPark
                            && self.alertDeliveryGeneration == deliveryGeneration
                            && (!self.alertPreferences.favoritesOnly || self.favoriteRideIDsForSelectedPark.contains(alert.rideId))
                    }
                )
                guard alertDeliveryGeneration == deliveryGeneration else { return }
                if delivered.count == 1 {
                    toastMessage = delivered[0].summary
                } else if !delivered.isEmpty {
                    toastMessage = "\(delivered.count) ride alerts at \(expectedPark.name)."
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard selectedPark == expectedPark, requestGeneration == monitoringGeneration else { return }
            resetAlertBaselines()
            liveActivityObservationParkID = nil
            errorMessage = error.localizedDescription
            cachedRefreshErrors[expectedPark.rawValue] = error.localizedDescription
            crowdRefreshErrors.insert(expectedPark.rawValue)
        }
    }

    func synchronizeLiveActivity() {
        guard let selectedPark else {
            liveActivityService.synchronize(nil)
            return
        }
        // Accent/pin UI changes cannot start a new Activity from a park cache.
        // Keep an existing Activity's timer, allowing its staleDate to expire.
        guard liveActivityObservationParkID == selectedPark.rawValue,
              NativeSmartAlertEngine.isFresh(snapshot?.fetchedAt, at: Date()) else { return }
        liveActivityService.synchronize(
            PIVOTLiveActivityTargetBuilder.makeTarget(
                selectedPark: selectedPark,
                snapshot: snapshot,
                featuredRide: featuredRadarRide,
                accentName: UserDefaults.standard.string(forKey: PivotAccent.storageKey) ?? "mint"
            )
        )
    }
}
