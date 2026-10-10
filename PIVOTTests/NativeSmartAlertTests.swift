import XCTest
@testable import PIVOT

final class NativeSmartAlertTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_141_600)

    private func reading(
        id: Int = 126, status: RideStatus = .open, wait: Int? = 30,
        offset: TimeInterval = -30, eligible: Bool = true, pending: Bool = false,
        hasTimestamp: Bool = true
    ) -> NativeAlertRideReading {
        NativeAlertRideReading(
            id: id, name: "Ride \(id)", status: status, radarEligible: eligible,
            reopenPending: pending, waitTime: wait,
            lastUpdated: hasTimestamp ? now.addingTimeInterval(offset) : nil
        )
    }

    private func observation(
        _ rides: [NativeAlertRideReading], park: Int = 6, offset: TimeInterval = -5,
        healthy: Bool = true, active: Bool = true, cacheStale: Bool = false
    ) -> NativeAlertObservation {
        NativeAlertObservation(
            parkId: park, fetchedAt: now.addingTimeInterval(offset),
            feedHealthy: healthy, parkActive: active, providerCacheStale: cacheStale, rides: rides
        )
    }

    private func candidates(
        previous: NativeAlertObservation?, current: NativeAlertObservation?,
        park: Int? = 6, mode: NativeAlertPreferences.Mode = .threshold,
        favoritesOnly: Bool = false, favorites: Set<Int> = [], threshold: Int = 20,
        transitions: [RideChangeAlert] = []
    ) -> [NativeSmartAlert] {
        NativeSmartAlertEngine.candidates(
            selectedParkId: park, previous: previous, current: current,
            transitions: transitions,
            preferences: NativeAlertPreferences(favoritesOnly: favoritesOnly, mode: mode, threshold: threshold),
            favorites: favorites, now: now
        )
    }

    func testFreshWaitCrossingIncludesEqualityAndRealZero() {
        let previous = observation([reading(wait: 30, offset: -60)], offset: -40)
        let equal = observation([reading(wait: 20, offset: -10)])
        let zero = observation([reading(wait: 0, offset: -10)])
        XCTAssertEqual(candidates(previous: previous, current: equal).map(\.kind), [.waitBelow])
        XCTAssertEqual(candidates(previous: previous, current: equal).first?.waitTime, 20)
        XCTAssertEqual(candidates(previous: previous, current: zero, threshold: 0).first?.waitTime, 0)
    }

    func testUnknownAndNegativeWaitsNeverBecomeZero() {
        let previous = observation([reading(wait: 30, offset: -60)], offset: -40)
        for value in [nil, -1] as [Int?] {
            XCTAssertTrue(candidates(previous: previous, current: observation([reading(wait: value, offset: -10)])).isEmpty)
        }
        XCTAssertTrue(candidates(
            previous: observation([reading(wait: nil, offset: -60)], offset: -40),
            current: observation([reading(wait: 10, offset: -10)])
        ).isEmpty)
    }

    func testAlreadyBelowThresholdDoesNotAlertAgain() {
        XCTAssertTrue(candidates(
            previous: observation([reading(wait: 20, offset: -60)], offset: -40),
            current: observation([reading(wait: 10, offset: -10)])
        ).isEmpty)
    }

    func testFirstLoadNoParkAndParkSwitchStayQuiet() {
        let previous = observation([reading(wait: 30, offset: -60)], offset: -40)
        let current = observation([reading(wait: 10, offset: -10)])
        XCTAssertTrue(candidates(previous: nil, current: current).isEmpty)
        XCTAssertTrue(candidates(previous: previous, current: current, park: nil).isEmpty)
        XCTAssertTrue(candidates(previous: previous, current: current, park: 7).isEmpty)
        XCTAssertTrue(candidates(previous: observation(previous.rides, park: 7), current: current).isEmpty)
    }

    func testDuplicateAndOutOfOrderSnapshotStayQuiet() {
        let prior = observation([reading(wait: 30, offset: -60)], offset: -40)
        for offset in [-40, -41] as [TimeInterval] {
            XCTAssertTrue(candidates(previous: prior, current: observation([reading(wait: 10, offset: -10)], offset: offset)).isEmpty)
        }
    }

    func testStaleAndFutureSnapshotsStayQuiet() {
        let current = observation([reading(wait: 10, offset: -10)])
        XCTAssertTrue(candidates(previous: observation([reading()], offset: -901), current: current).isEmpty)
        XCTAssertTrue(candidates(previous: observation([reading()], offset: -40), current: observation(current.rides, offset: 121)).isEmpty)
    }

    func testUnhealthyInactiveAndReconnectResponsesStayQuiet() {
        let priorRides = [reading(wait: 30, offset: -60)]
        let current = observation([reading(wait: 10, offset: -10)])
        XCTAssertTrue(candidates(previous: observation(priorRides, offset: -40, healthy: false), current: current).isEmpty)
        XCTAssertTrue(candidates(previous: observation(priorRides, offset: -40, active: false), current: current).isEmpty)
        XCTAssertTrue(candidates(previous: observation(priorRides, offset: -40), current: observation(current.rides, healthy: false)).isEmpty)
        XCTAssertTrue(candidates(previous: observation(priorRides, offset: -40), current: observation(current.rides, active: false)).isEmpty)
    }

    func testProviderCacheGraceAndFirstFreshRecoveryAreSilentThenNewCrossingAlerts() {
        let original = observation([reading(wait: 30, offset: -80)], offset: -60)
        // Explicit cacheStale, despite feedHealthy=true and a fresh fetch age.
        // Repeated/older provider caches must invalidate before version checks.
        for cacheOffset in [-65, -60, -40] as [TimeInterval] {
            let cacheGrace = observation([reading(wait: 15, offset: -70)], offset: cacheOffset, cacheStale: true)
            XCTAssertTrue(cacheGrace.feedHealthy)
            XCTAssertTrue(candidates(previous: original, current: cacheGrace).isEmpty)
            var baseline = NativeSmartAlertEngine.nextBaseline(previous: original, current: cacheGrace, now: now)
            XCTAssertNil(baseline)

            let recovery = observation([reading(wait: 10, offset: -30)], offset: -25)
            XCTAssertTrue(candidates(previous: cacheGrace, current: recovery).isEmpty)
            XCTAssertTrue(candidates(previous: baseline, current: recovery).isEmpty)
            baseline = NativeSmartAlertEngine.nextBaseline(previous: baseline, current: recovery, now: now)
            XCTAssertEqual(baseline, recovery)

            let above = observation([reading(wait: 35, offset: -20)], offset: -15)
            XCTAssertTrue(candidates(previous: baseline, current: above).isEmpty)
            baseline = NativeSmartAlertEngine.nextBaseline(previous: baseline, current: above, now: now)
            let newCrossing = observation([reading(wait: 15, offset: -10)], offset: -5)
            XCTAssertEqual(candidates(previous: baseline, current: newCrossing).map(\.kind), [.waitBelow])
        }
    }

    func testStatusAlertsCannotCrossProviderCacheGraceRecovery() {
        let original = observation([reading(status: .down, wait: nil, offset: -80)], offset: -60)
        let cacheGrace = observation([reading(status: .down, wait: nil, offset: -80)], offset: -40, cacheStale: true)
        let recovery = observation([reading(status: .open, wait: 15, offset: -30)], offset: -25)
        let reopened = RideChangeAlert(kind: .reopened, parkId: 6, rideId: 126, rideName: "Space Mountain")
        XCTAssertTrue(candidates(previous: original, current: cacheGrace, mode: .all, transitions: [reopened]).isEmpty)
        XCTAssertTrue(candidates(previous: cacheGrace, current: recovery, mode: .all, transitions: [reopened]).isEmpty)
        let reset = NativeSmartAlertEngine.nextBaseline(previous: original, current: cacheGrace, now: now)
        XCTAssertTrue(candidates(previous: reset, current: recovery, mode: .all, transitions: [reopened]).isEmpty)
        let baseline = NativeSmartAlertEngine.nextBaseline(previous: reset, current: recovery, now: now)
        let later = observation([reading(status: .down, wait: nil, offset: -10)], offset: -5)
        let closed = RideChangeAlert(kind: .closed, parkId: 6, rideId: 126, rideName: "Space Mountain")
        XCTAssertEqual(candidates(previous: baseline, current: later, mode: .all, transitions: [closed]).map(\.kind), [.closed])
    }

    func testThresholdRequiresNewFreshPerRideVersion() {
        let previous = observation([reading(wait: 30, offset: -60)], offset: -40)
        for offset in [-60, -61, -901, 121] as [TimeInterval] {
            XCTAssertTrue(candidates(previous: previous, current: observation([reading(wait: 10, offset: offset)])).isEmpty)
        }
        XCTAssertTrue(candidates(previous: previous, current: observation([reading(wait: 10, hasTimestamp: false)])).isEmpty)
        XCTAssertTrue(candidates(previous: observation([reading(offset: -901)], offset: -40), current: observation([reading(wait: 10)])).isEmpty)
    }

    func testThresholdOnlyUsesConfirmedEligibleOpenRides() {
        let previous = observation([reading(wait: 30, offset: -60)], offset: -40)
        for status in [RideStatus.down, .stale, .scheduled, .parkInactive, .unknown("UNRECOGNIZED")] {
            XCTAssertTrue(candidates(previous: previous, current: observation([reading(status: status, wait: 10)])).isEmpty)
        }
        XCTAssertTrue(candidates(previous: previous, current: observation([reading(wait: 10, pending: true)])).isEmpty)
        XCTAssertTrue(candidates(previous: previous, current: observation([reading(wait: 10, eligible: false)])).isEmpty)
        XCTAssertTrue(candidates(previous: observation([reading(pending: true)], offset: -40), current: observation([reading(wait: 10)])).isEmpty)
    }

    func testReopenOnlyAndFavoritesFilters() {
        let transitions = [
            RideChangeAlert(kind: .closed, parkId: 6, rideId: 126, rideName: "Space Mountain"),
            RideChangeAlert(kind: .reopened, parkId: 6, rideId: 127, rideName: "Pirates"),
            RideChangeAlert(kind: .reopened, parkId: 7, rideId: 128, rideName: "Other park"),
        ]
        let previous = observation([], offset: -40)
        let current = observation([])
        XCTAssertEqual(candidates(previous: previous, current: current, mode: .reopened, transitions: transitions).map(\.rideId), [127])
        XCTAssertEqual(candidates(previous: previous, current: current, mode: .all, favoritesOnly: true, favorites: [126], transitions: transitions).map(\.rideId), [126])
        XCTAssertTrue(candidates(previous: previous, current: current, mode: .all, favoritesOnly: true, transitions: transitions).isEmpty)
    }

    func testFavoritesFilterAlsoAppliesToThreshold() {
        let previous = observation([reading(wait: 30, offset: -60)], offset: -40)
        let current = observation([reading(wait: 10)])
        XCTAssertTrue(candidates(previous: previous, current: current, favoritesOnly: true).isEmpty)
        XCTAssertEqual(candidates(previous: previous, current: current, favoritesOnly: true, favorites: [126]).count, 1)
    }

    private func alert(kind: NativeSmartAlert.Kind = .waitBelow, park: Int = 6, offset: TimeInterval = 0) -> NativeSmartAlert {
        NativeSmartAlert(kind: kind, parkId: park, rideId: 126, rideName: "Space Mountain", waitTime: 15, observationAt: now.addingTimeInterval(offset))
    }

    func testCooldownIsPerRideParkAndKindAndDeduplicatesSameBatch() {
        var cooldown = NativeAlertCooldown()
        XCTAssertEqual(cooldown.reserve([alert(), alert()], at: now).count, 1)
        XCTAssertTrue(cooldown.reserve([alert(offset: 1)], at: now.addingTimeInterval(899)).isEmpty)
        XCTAssertEqual(cooldown.reserve([alert(kind: .reopened), alert(park: 7)], at: now).count, 2)
        XCTAssertEqual(cooldown.reserve([alert(offset: 900)], at: now.addingTimeInterval(900)).count, 1)
        XCTAssertTrue(cooldown.reserve([alert()], at: now.addingTimeInterval(1_801)).isEmpty)
    }

    func testCooldownPersistsAcrossRelaunchAndPrunesBadClockRecords() throws {
        let suite = "pivot-smart-alert-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = NativeAlertCooldown()
        XCTAssertEqual(original.reserve([alert()], at: now).count, 1)
        original.save(to: defaults)
        var restored = NativeAlertCooldown(defaults: defaults)
        XCTAssertTrue(restored.reserve([alert(offset: 1)], at: now.addingTimeInterval(10)).isEmpty)
        XCTAssertTrue(restored.reserve([alert()], at: now.addingTimeInterval(1_000)).isEmpty)
        var invalid = NativeAlertCooldown(history: ["bad": .infinity, "future": now.timeIntervalSince1970 + 1, "old": now.timeIntervalSince1970 - 86_400])
        _ = invalid.reserve([], at: now)
        XCTAssertTrue(invalid.history.isEmpty)
    }

    @MainActor
    func testPreferencesPersistWithoutEnablingNotifications() throws {
        let suite = "pivot-smart-alert-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(defaults: defaults)
        store.updateAlertPreferences(NativeAlertPreferences(favoritesOnly: true, mode: .reopened, threshold: 25))
        XCTAssertFalse(store.alertsEnabled)
        XCTAssertFalse(defaults.bool(forKey: "pivot.alertsEnabled"))
        XCTAssertEqual(NativeAlertPreferences.load(from: defaults), store.alertPreferences)
        XCTAssertEqual(NativeAlertPreferences(threshold: -1).normalized.threshold, 20)
        defaults.set(Data("broken".utf8), forKey: NativeAlertPreferences.storageKey)
        XCTAssertEqual(NativeAlertPreferences.load(from: defaults), .default)
    }

    @MainActor
    func testRadarPinsAndFavoritesAreParkScopedAndClearable() throws {
        let suite = "pivot-smart-alert-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let otherPark = try XCTUnwrap(FloridaPark.allCases.first { $0.rawValue != 6 })
        defaults.set(6, forKey: "pivot.selectedPark")
        defaults.set(126, forKey: "pivot.radarPin.6")
        defaults.set(999, forKey: "pivot.radarPin.\(otherPark.rawValue)")
        defaults.set([126], forKey: "pivot.favoriteRides.6")
        defaults.set([999], forKey: "pivot.favoriteRides.\(otherPark.rawValue)")
        let store = DashboardStore(defaults: defaults)
        XCTAssertEqual(store.pinnedRadarRideID, 126)
        XCTAssertEqual(store.favoriteRideIDsForSelectedPark, [126])
        store.selectPark(otherPark)
        XCTAssertEqual(store.pinnedRadarRideID, 999)
        XCTAssertEqual(store.favoriteRideIDsForSelectedPark, [999])
        store.pinRadarRide(nil)
        XCTAssertNil(store.pinnedRadarRideID)
        XCTAssertNil(defaults.object(forKey: "pivot.radarPin.\(otherPark.rawValue)"))
        store.selectPark(.magicKingdom)
        XCTAssertEqual(store.pinnedRadarRideID, 126)
        store.selectPark(nil)
        XCTAssertNil(store.pinnedRadarRideID)
        XCTAssertTrue(store.favoriteRideIDsForSelectedPark.isEmpty)
    }

    private func radarRide(id: Int, status: String = "DOWN", typicalWait: Int) throws -> LiveRide {
        let json: [String: Any] = [
            "id": id, "name": "Ride \(id)", "land": "Test land", "status": status,
            "isOpen": status == "OPEN", "weatherExposure": "INDOOR", "radarEligible": true,
            "radarCategory": "RIDE", "reopenPending": false, "trend": [typicalWait],
        ]
        return try JSONDecoder().decode(LiveRide.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testRadarPinWinsWhileDownAndFallsBackWhenUnavailable() throws {
        let quiet = try radarRide(id: 1, typicalWait: 20)
        let popular = try radarRide(id: 2, typicalWait: 80)
        let open = try radarRide(id: 3, status: "OPEN", typicalWait: 100)
        let rides = [quiet, popular, open]
        XCTAssertEqual(PIVOTLiveActivityRideSelector.featuredClosedRide(in: rides, pinnedRideID: 1)?.id, 1)
        XCTAssertEqual(PIVOTLiveActivityRideSelector.featuredClosedRide(in: rides, pinnedRideID: nil)?.id, 2)
        XCTAssertEqual(PIVOTLiveActivityRideSelector.featuredClosedRide(in: rides, pinnedRideID: 3)?.id, 2)
        XCTAssertEqual(PIVOTLiveActivityRideSelector.featuredClosedRide(in: rides, pinnedRideID: 999)?.id, 2)
        XCTAssertNil(PIVOTLiveActivityRideSelector.featuredClosedRide(in: [open], pinnedRideID: 3))
    }
}
