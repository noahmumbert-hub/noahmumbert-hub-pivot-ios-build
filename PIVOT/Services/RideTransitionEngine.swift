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
