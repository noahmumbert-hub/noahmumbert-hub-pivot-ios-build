import Foundation

enum RideChangeKind: String, Equatable, Sendable {
    case closed
    case reopened
}

struct RideChangeAlert: Equatable, Sendable {
    let kind: RideChangeKind
    let parkId: Int
    let rideId: Int
    let rideName: String
}

struct BaselineRide: Equatable, Sendable {
    let id: Int
    let name: String
    let status: RideStatus
    let radarEligible: Bool
}

struct ParkRideBaseline: Equatable, Sendable {
    let parkId: Int
    let fetchedAt: Date
    let rides: [Int: BaselineRide]
}

struct RideTransitionResult: Equatable, Sendable {
    let alerts: [RideChangeAlert]
    let nextBaseline: ParkRideBaseline?
}

enum RideTransitionEngine {
    static func evaluate(
        selectedParkId: Int?,
        previous: ParkRideBaseline?,
        current: LiveParkSnapshot?
    ) -> RideTransitionResult {
        guard let selectedParkId else {
            return RideTransitionResult(alerts: [], nextBaseline: nil)
        }
        let selectedBaseline = previous?.parkId == selectedParkId ? previous : nil
        guard let current, current.parkId == selectedParkId else {
            return RideTransitionResult(alerts: [], nextBaseline: selectedBaseline)
        }

        guard let selectedBaseline else {
            return RideTransitionResult(
                alerts: [],
                nextBaseline: makeBaseline(from: current, previousRides: [:])
            )
        }

        // fetchedAt identifies a successfully observed API snapshot. Provider
        // timestamps can remain unchanged (or even regress) while a newer
        // snapshot contains a real status transition, so they cannot safely
        // deduplicate observations.
        guard current.fetchedAt > selectedBaseline.fetchedAt else {
            return RideTransitionResult(alerts: [], nextBaseline: selectedBaseline)
        }

        let normalized = makeBaseline(from: current, previousRides: selectedBaseline.rides)

        guard current.feedHealthy, current.parkActive else {
            return RideTransitionResult(alerts: [], nextBaseline: normalized)
        }

        var alerts: [RideChangeAlert] = []
        for ride in normalized.rides.values where ride.radarEligible {
            guard let prior = selectedBaseline.rides[ride.id], prior.radarEligible else { continue }
            if prior.status == .open, ride.status == .down {
                alerts.append(RideChangeAlert(kind: .closed, parkId: current.parkId, rideId: ride.id, rideName: ride.name))
            } else if prior.status == .down, ride.status == .open {
                alerts.append(RideChangeAlert(kind: .reopened, parkId: current.parkId, rideId: ride.id, rideName: ride.name))
            }
        }
        alerts.sort { $0.rideName.localizedCaseInsensitiveCompare($1.rideName) == .orderedAscending }
        return RideTransitionResult(alerts: alerts, nextBaseline: normalized)
    }

    private static func makeBaseline(
        from snapshot: LiveParkSnapshot,
        previousRides: [Int: BaselineRide]
    ) -> ParkRideBaseline {
        let rides = snapshot.rides.reduce(into: [Int: BaselineRide]()) { result, ride in
            let prior = previousRides[ride.id]
            if (ride.status == .stale || ride.status == .scheduled),
               let prior,
               prior.status == .open || prior.status == .down {
                result[ride.id] = prior
                return
            }
            let normalizedStatus: RideStatus = ride.status == .open && ride.reopenPending && prior?.status == .down
                ? .down
                : ride.status
            result[ride.id] = BaselineRide(
                id: ride.id,
                name: ride.name,
                status: normalizedStatus,
                radarEligible: ride.radarEligible
            )
        }
        return ParkRideBaseline(
            parkId: snapshot.parkId,
            fetchedAt: snapshot.fetchedAt,
            rides: rides
        )
    }
}

// Smart alerts intentionally wrap the existing status transition engine rather
// than adding WAIT_BELOW to its closed/reopened contract.
struct NativeAlertRideReading: Equatable, Sendable {
    let id: Int
    let name: String
    let status: RideStatus
    let radarEligible: Bool
    let reopenPending: Bool
    let waitTime: Int?
    let lastUpdated: Date?
}

struct NativeAlertObservation: Equatable, Sendable {
    let parkId: Int
    let fetchedAt: Date
    let feedHealthy: Bool
    let parkActive: Bool
    let providerCacheStale: Bool
    let rides: [NativeAlertRideReading]

    init(parkId: Int, fetchedAt: Date, feedHealthy: Bool = true, parkActive: Bool = true, providerCacheStale: Bool = false, rides: [NativeAlertRideReading]) {
        self.parkId = parkId
        self.fetchedAt = fetchedAt
        self.feedHealthy = feedHealthy
        self.parkActive = parkActive
        self.providerCacheStale = providerCacheStale
        self.rides = rides
    }

    init(snapshot: LiveParkSnapshot) {
        self.init(
            parkId: snapshot.parkId,
            fetchedAt: snapshot.fetchedAt,
            feedHealthy: snapshot.feedHealthy,
            parkActive: snapshot.parkActive,
            providerCacheStale: snapshot.themeParksWiki?.cacheStale == true,
            rides: snapshot.rides.map {
                NativeAlertRideReading(
                    id: $0.id, name: $0.name, status: $0.status,
                    radarEligible: $0.radarEligible, reopenPending: $0.reopenPending,
                    waitTime: $0.waitTime, lastUpdated: $0.lastUpdated
                )
            }
        )
    }
}

struct NativeSmartAlert: Equatable, Sendable {
    enum Kind: String, Sendable { case closed = "CLOSED", reopened = "REOPENED", waitBelow = "WAIT_BELOW" }
    let kind: Kind
    let parkId: Int
    let rideId: Int
    let rideName: String
    let waitTime: Int?
    let observationAt: Date

    var cooldownKey: String { "\(parkId):\(rideId):\(kind.rawValue)" }
    var eventIdentifier: String {
        "pivot-smart-\(cooldownKey):\(Int64(observationAt.timeIntervalSince1970 * 1_000))"
    }
    var summary: String {
        switch kind {
        case .closed: "\(rideName) closed"
        case .reopened: "\(rideName) reopened"
        case .waitBelow: "\(rideName) is now \(waitTime.map(String.init) ?? "unknown") min"
        }
    }
}

enum NativeSmartAlertEngine {
    static let freshnessInterval: TimeInterval = 15 * 60

    static func isFresh(_ timestamp: Date?, at now: Date) -> Bool {
        guard let timestamp, timestamp.timeIntervalSince1970.isFinite else { return false }
        let age = now.timeIntervalSince(timestamp)
        return age >= -120 && age <= freshnessInterval
    }

    /// Failed-provider cache grace can retain feedHealthy=true. It remains a
    /// saved observation, not a live baseline. Reset even duplicate cache reads
    /// so the first successful provider response after recovery stays silent.
    static func nextBaseline(
        previous: NativeAlertObservation?,
        current: NativeAlertObservation,
        now: Date
    ) -> NativeAlertObservation? {
        guard current.feedHealthy, current.parkActive, !current.providerCacheStale,
              isFresh(current.fetchedAt, at: now) else { return nil }
        guard let previous, previous.parkId == current.parkId,
              previous.feedHealthy, previous.parkActive, !previous.providerCacheStale,
              isFresh(previous.fetchedAt, at: now) else { return current }
        return current.fetchedAt > previous.fetchedAt ? current : previous
    }

    static func candidates(
        selectedParkId: Int?,
        previous: NativeAlertObservation?,
        current: NativeAlertObservation?,
        transitions: [RideChangeAlert],
        preferences: NativeAlertPreferences,
        favorites: Set<Int>,
        now: Date
    ) -> [NativeSmartAlert] {
        guard let selectedParkId, let previous, let current,
              previous.parkId == selectedParkId, current.parkId == selectedParkId,
              previous.feedHealthy, previous.parkActive, current.feedHealthy, current.parkActive,
              !previous.providerCacheStale, !current.providerCacheStale,
              isFresh(previous.fetchedAt, at: now), isFresh(current.fetchedAt, at: now),
              current.fetchedAt > previous.fetchedAt else { return [] }
        let preferences = preferences.normalized
        let selected: (Int) -> Bool = { !preferences.favoritesOnly || favorites.contains($0) }

        if preferences.mode != .threshold {
            return transitions.compactMap { alert in
                guard alert.parkId == selectedParkId, selected(alert.rideId),
                      preferences.mode == .all || alert.kind == .reopened else { return nil }
                return NativeSmartAlert(
                    kind: alert.kind == .closed ? .closed : .reopened,
                    parkId: alert.parkId, rideId: alert.rideId, rideName: alert.rideName,
                    waitTime: nil, observationAt: current.fetchedAt
                )
            }
        }

        // Provider ride versions must advance for wait alerts: a newly fetched
        // copy of an old wait is not a new crossing. Unknown waits stay unknown.
        let priorByID = previous.rides.reduce(into: [Int: NativeAlertRideReading]()) { $0[$1.id] = $1 }
        return current.rides.compactMap { ride in
            guard selected(ride.id), ride.radarEligible, ride.status == .open, !ride.reopenPending,
                  let wait = ride.waitTime, wait >= 0, wait <= preferences.threshold,
                  let updatedAt = ride.lastUpdated, isFresh(updatedAt, at: now),
                  let prior = priorByID[ride.id], prior.radarEligible,
                  prior.status == .open, !prior.reopenPending,
                  let priorWait = prior.waitTime, priorWait > preferences.threshold,
                  let priorUpdatedAt = prior.lastUpdated, isFresh(priorUpdatedAt, at: now),
                  updatedAt > priorUpdatedAt else { return nil }
            return NativeSmartAlert(
                kind: .waitBelow, parkId: current.parkId, rideId: ride.id, rideName: ride.name,
                waitTime: wait, observationAt: updatedAt
            )
        }.sorted { $0.rideName.localizedCaseInsensitiveCompare($1.rideName) == .orderedAscending }
    }
}

struct NativeAlertCooldown {
    static let storageKey = "pivot.smartAlertHistory.v1"
    private(set) var history: [String: Double]

    init(history: [String: Double] = [:]) { self.history = history }

    init(defaults: UserDefaults) {
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            history = saved
        } else {
            history = [:]
        }
    }

    /// Reserves before notification submission for at-most-once local delivery.
    /// Failed/blocked submissions are deliberately not replayed later.
    mutating func reserve(_ alerts: [NativeSmartAlert], at now: Date) -> [NativeSmartAlert] {
        let timestamp = now.timeIntervalSince1970
        guard timestamp.isFinite else { return [] }
        history = history.filter { $0.value.isFinite && $0.value <= timestamp && timestamp - $0.value < 24 * 60 * 60 }
        return alerts.filter { alert in
            let eventKey = "event:\(alert.eventIdentifier)"
            guard history[eventKey] == nil else { return false }
            if let previous = history[alert.cooldownKey],
               timestamp - previous < Double(NativeAlertPreferences.cooldownMinutes * 60) { return false }
            history[alert.cooldownKey] = timestamp
            history[eventKey] = timestamp
            return true
        }
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
