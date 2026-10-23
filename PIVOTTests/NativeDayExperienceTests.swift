import XCTest
@testable import PIVOT

/// Deterministic unit/persistence coverage. Must be run on Xcode; no Swift SDK exists in the authoring environment.
final class NativeDayExperienceTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-04T13:00:00Z")!
    private let park = FloridaPark.magicKingdom
    private let location = AttractionLocation(latitude: 28.416, longitude: -81.581)

    func testParkLocalDayAcrossUTCAndDaylightSavingBoundaries() {
        let beforeFloridaMidnight = ISO8601DateFormatter().date(from: "2026-10-05T03:59:00Z")!
        let afterFloridaMidnight = ISO8601DateFormatter().date(from: "2026-10-05T04:01:00Z")!
        XCTAssertEqual(NativeDayPlanning.localDay(park: park, at: beforeFloridaMidnight), "2026-10-04")
        XCTAssertEqual(NativeDayPlanning.localDay(park: park, at: afterFloridaMidnight), "2026-10-05")
        for time in ["2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z"] {
            XCTAssertEqual(NativeDayPlanning.localDay(park: park, at: ISO8601DateFormatter().date(from: time)!), "2026-11-01")
        }
    }

    func testCommitmentValidationAndAdjacentWindows() {
        let first = stop(start: 30, end: 60)
        XCTAssertTrue(first.isValid)
        XCTAssertFalse(first.overlaps(stop(start: 60, end: 90)))
        XCTAssertTrue(first.overlaps(stop(start: 59, end: 90)))
        XCTAssertFalse(stop(start: 60, end: 60).isValid)
        XCTAssertFalse(stop(start: 0, end: 721).isValid)
        XCTAssertFalse(NativeDayCommitment(id: "x", title: " ", kind: .lunch, startAt: now, endAt: now.addingTimeInterval(60), bufferMinutes: 0, location: nil).isValid)
    }

    func testReviewedRideAndApproximateLandStarts() {
        let rides = [ride(1, location: location), ride(2, location: AttractionLocation(latitude: 28.418, longitude: -81.583))]
        let actual = NativeDayPlanning.resolveStart("ride:2", rides: rides, park: park)
        XCTAssertEqual(actual.location, rides[1].location)
        let land = NativeDayPlanning.resolveStart("land:Tomorrowland", rides: rides, park: park)
        XCTAssertEqual(land.location?.latitude ?? 0, 28.417, accuracy: 0.000001)
        XCTAssertTrue(land.label.contains("approximate"))
        XCTAssertEqual(NativeDayPlanning.resolveStart("ride:999", rides: rides, park: park).location, NativeDayPlanning.entrance(for: park))
    }

    func testProgressExcludesOnlyDoneAndSkippedRidesAndUndoRestores() {
        let rides = [ride(1), ride(2), ride(3)]
        var day = NativeDayState()
        day.progress = [1: .done, 2: .skip]
        XCTAssertEqual(plan(rides, day: day).stops.map(\.rideID), [3])
        day.progress.removeValue(forKey: 1)
        XCTAssertEqual(Set(plan(rides, day: day).stops.map(\.rideID)), Set([1, 3]))
    }

    func testFixedStopReservesUnknownLocationWalkAndArrivalBuffer() {
        var day = NativeDayState()
        day.commitments = [stop(start: 60, end: 90)]
        let route = plan([ride(1), ride(2), ride(3)], day: day)
        XCTAssertEqual(route.commitments.count, 1)
        XCTAssertEqual(route.commitments[0].transferMinutes, 15)
        XCTAssertEqual(route.commitments[0].leaveBy, now.addingTimeInterval(35 * 60))
        XCTAssertTrue(route.stops.allSatisfy {
            $0.completeAt <= route.commitments[0].leaveBy || $0.arriveAt >= day.commitments[0].endAt
        })
        XCTAssertTrue(route.isValid)
    }

    func testLateAndOutsideWindowWarnings() {
        var day = NativeDayState()
        day.commitments = [stop(start: 5, end: 210)]
        let route = plan([], day: day, endMinutes: 180)
        XCTAssertEqual(route.commitments[0].warnings.count, 2)
        XCTAssertTrue(route.commitments[0].warnings.contains { $0.contains("Not enough time") })
        XCTAssertTrue(route.commitments[0].warnings.contains { $0.contains("after your visit") })
    }

    func testLateTransferDelaysFollowingRouteBeyondCommitmentEnd() throws {
        var day = NativeDayState()
        day.commitments = [stop(start: 5, end: 10)]
        let route = plan([ride(1)], day: day)
        XCTAssertTrue(route.commitments[0].warnings.contains { $0.contains("Not enough time") })
        // Fifteen-minute unknown-location transfer cannot finish at the stop's minute-10 end.
        let next = try XCTUnwrap(route.stops.first)
        let nextDeparture = next.arriveAt.addingTimeInterval(-Double(next.walkMinutes) * 60)
        XCTAssertGreaterThanOrEqual(nextDeparture, now.addingTimeInterval(15 * 60))
    }

    func testPartialFeedKeepsMissingFavoritesVisibleAndDoesNotClaimAllFit() {
        let route = NativeDayPlanning.build(rides: [ride(1)], favoriteIDs: [1, 999], day: NativeDayState(),
                                           park: park, startAt: now, endAt: now.addingTimeInterval(3600), now: now)
        XCTAssertEqual(route.missingRideIDs, [999])
        XCTAssertFalse(route.fitsAll)
    }

    func testDuplicateFeedIDsDoNotCrashOrDuplicateRoute() {
        let item = ride(1)
        let route = plan([item, item])
        XCTAssertEqual(route.stops.count, 1)
    }

    func testUnknownWaitIsUnavailableNotZero() {
        let route = plan([ride(1, wait: nil)])
        XCTAssertTrue(route.stops.isEmpty)
        XCTAssertEqual(route.unavailableRideIDs, [1])
    }

    @MainActor
    func testDoneSkipUndoPersistAndDoNotChangeLegacyFavorites() throws {
        try withStore { store, directory, defaults in
            defaults.set([1, 999], forKey: "pivot.favoriteRides.6")
            try store.setProgress(.done, rideID: 1, park: park, now: now)
            XCTAssertEqual(store.favorites(for: park), [1, 999])
            XCTAssertEqual(store.state(for: park, at: now).progress[1], .done)
            XCTAssertNil(store.state(for: .epcot, at: now).progress[1])
            XCTAssertNil(store.state(for: park, at: now.addingTimeInterval(24 * 3600)).progress[1])
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertEqual(reopened.state(for: park, at: now).progress[1], .done)
            try reopened.setProgress(.skip, rideID: 1, park: park, now: now)
            try reopened.setProgress(nil, rideID: 1, park: park, now: now)
            XCTAssertNil(reopened.state(for: park, at: now).progress[1])
            XCTAssertEqual(reopened.favorites(for: park), [1, 999])
        }
    }

    @MainActor
    func testLegacyVisitWindowMigratesBothKeysWithoutDeletingData() throws {
        for label in [NativeDayPlanning.localDay(park: park, at: now), ParkTimeFormatter.parkDate(now, timeZone: park.timeZone)] {
            try withStore { _, directory, defaults in
                let key = "pivot.dayPlan.6.\(label)"
                let end = now.addingTimeInterval(8 * 3600)
                defaults.set(now, forKey: key + ".start")
                defaults.set(end, forKey: key + ".end")
                let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
                XCTAssertEqual(reopened.state(for: park, at: now).visitStart, now)
                XCTAssertEqual(reopened.state(for: park, at: now).visitEnd, end)
                try reopened.setProgress(.done, rideID: 1, park: park, now: now)
                XCTAssertEqual(reopened.state(for: park, at: now).visitEnd, end)
                XCTAssertEqual(defaults.object(forKey: key + ".start") as? Date, now)
                XCTAssertEqual(defaults.object(forKey: key + ".end") as? Date, end)
            }
        }
    }

    @MainActor
    func testLegacyWindowRejectsPreviousDayOrInvalidInterval() throws {
        try withStore { store, _, defaults in
            let key = "pivot.dayPlan.6.\(NativeDayPlanning.localDay(park: park, at: now))"
            defaults.set(now.addingTimeInterval(-24 * 3600), forKey: key + ".start")
            defaults.set(now.addingTimeInterval(3600), forKey: key + ".end")
            XCTAssertNil(store.state(for: park, at: now).visitStart)
            defaults.set(now, forKey: key + ".start")
            defaults.set(now.addingTimeInterval(-60), forKey: key + ".end")
            XCTAssertNil(store.state(for: park, at: now).visitStart)
            XCTAssertNotNil(defaults.object(forKey: key + ".start"))
        }
    }

    @MainActor
    func testActiveOvernightWindowAndCommitmentsSurviveLocalMidnight() throws {
        try withStore { store, directory, defaults in
            let start = ISO8601DateFormatter().date(from: "2026-10-05T03:00:00Z")! // 23:00 local
            let afterMidnight = ISO8601DateFormatter().date(from: "2026-10-05T04:10:00Z")!
            let end = ISO8601DateFormatter().date(from: "2026-10-05T05:00:00Z")!
            try store.setVisitWindow(start: start, end: end, park: park, now: start)
            try store.setProgress(.done, rideID: 1, park: park, now: start)
            let fixed = NativeDayCommitment(id: "overnight", title: "Return", kind: .manualReturn,
                                            startAt: afterMidnight.addingTimeInterval(20 * 60), endAt: end,
                                            bufferMinutes: 10, location: nil)
            try store.addCommitment(fixed, park: park, now: start)
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            let day = reopened.state(for: park, at: afterMidnight)
            XCTAssertEqual(day.visitStart, start)
            XCTAssertEqual(day.visitEnd, end)
            XCTAssertEqual(day.commitments, [fixed])
            XCTAssertNil(day.progress[1], "Progress intentionally resets for the new park-local day")
            try reopened.setProgress(.skip, rideID: 2, park: park, now: afterMidnight)
            XCTAssertEqual(reopened.state(for: park, at: afterMidnight).commitments, [fixed])
            XCTAssertEqual(reopened.state(for: park, at: start).progress[1], .done)
        }
    }

    @MainActor
    func testFutureVisitIsInheritedOnItsLocalDayBeforeArrival() throws {
        try withStore { store, directory, defaults in
            let arrival = ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z")! // Tomorrow 09:00 local
            let departure = ISO8601DateFormatter().date(from: "2026-10-05T22:00:00Z")!
            let beforeArrival = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")!
            let lunch = NativeDayCommitment(id: "future-lunch", title: "Lunch", kind: .lunch,
                                            startAt: arrival.addingTimeInterval(3 * 3600), endAt: arrival.addingTimeInterval(4 * 3600),
                                            bufferMinutes: 10, location: nil)
            try store.setVisitWindow(start: arrival, end: departure, park: park, now: now)
            try store.setStart("ride:1", park: park, now: now)
            try store.addCommitment(lunch, park: park, now: now)
            try store.setProgress(.done, rideID: 1, park: park, now: now)
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            let day = reopened.state(for: park, at: beforeArrival)
            XCTAssertEqual(day.visitStart, arrival)
            XCTAssertEqual(day.visitEnd, departure)
            XCTAssertEqual(day.start, "ride:1")
            XCTAssertEqual(day.commitments, [lunch])
            XCTAssertTrue(day.progress.isEmpty)
            try reopened.setProgress(.skip, rideID: 2, park: park, now: beforeArrival)
            let persisted = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertEqual(persisted.state(for: park, at: beforeArrival).visitStart, arrival)
            XCTAssertEqual(persisted.state(for: park, at: beforeArrival).commitments, [lunch])
        }
    }

    @MainActor
    func testPendingShowAndReturnCarryPastMidnightWithoutExplicitWindow() throws {
        try withStore { store, directory, defaults in
            let beforeMidnight = ISO8601DateFormatter().date(from: "2026-10-05T03:50:00Z")!
            let afterMidnight = ISO8601DateFormatter().date(from: "2026-10-05T04:10:00Z")!
            let showAt = ISO8601DateFormatter().date(from: "2026-10-05T04:30:00Z")!
            let time = LiveShowtime(type: nil, startTime: showAt, endTime: showAt.addingTimeInterval(15 * 60))
            let show = LiveShow(id: "night-show", name: "Night Show", status: nil, showtimes: [time], nextShowAt: nil,
                                nextShowEndAt: nil, nextShowType: nil, sourceUpdatedAt: beforeMidnight)
            let manualReturn = NativeDayCommitment(id: "night-return", title: "Return", kind: .manualReturn,
                                                  startAt: showAt.addingTimeInterval(30 * 60), endAt: showAt.addingTimeInterval(50 * 60),
                                                  bufferMinutes: 10, location: nil)
            try store.addShow(show, showtime: time, park: park, now: beforeMidnight)
            try store.addCommitment(manualReturn, park: park, now: beforeMidnight)
            try store.setProgress(.done, rideID: 1, park: park, now: beforeMidnight)
            XCTAssertNil(store.state(for: park, at: beforeMidnight).visitStart)
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            let day = reopened.state(for: park, at: afterMidnight)
            XCTAssertEqual(day.commitments.count, 2)
            XCTAssertTrue(day.commitments.contains { $0.kind == .show && $0.startAt == showAt })
            XCTAssertTrue(day.commitments.contains(manualReturn))
            XCTAssertNil(day.visitStart)
            XCTAssertNil(day.visitEnd)
            XCTAssertTrue(day.progress.isEmpty)
            try reopened.setStart("entrance", park: park, now: afterMidnight)
            let persisted = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertEqual(persisted.state(for: park, at: afterMidnight).commitments.count, 2)
        }
    }

    @MainActor
    func testExplicitNewDayRemovalDoesNotResurrectInheritedStops() throws {
        try withStore { store, directory, defaults in
            let beforeMidnight = ISO8601DateFormatter().date(from: "2026-10-05T03:50:00Z")!
            let afterMidnight = ISO8601DateFormatter().date(from: "2026-10-05T04:10:00Z")!
            let stopAt = ISO8601DateFormatter().date(from: "2026-10-05T04:30:00Z")!
            let pending = NativeDayCommitment(id: "pending", title: "Return", kind: .manualReturn,
                                             startAt: stopAt, endAt: stopAt.addingTimeInterval(30 * 60), bufferMinutes: 10, location: nil)
            try store.addCommitment(pending, park: park, now: beforeMidnight)
            XCTAssertEqual(store.state(for: park, at: afterMidnight).commitments, [pending])
            try store.removeCommitment(id: pending.id, park: park, now: afterMidnight)
            XCTAssertTrue(store.state(for: park, at: afterMidnight).commitments.isEmpty)
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertTrue(reopened.state(for: park, at: afterMidnight.addingTimeInterval(60)).commitments.isEmpty)
            XCTAssertEqual(reopened.state(for: park, at: beforeMidnight).commitments, [pending], "Prior-day record is retained without overriding an explicit new-day removal")
        }
    }

    @MainActor
    func testOverlapRejectedWithoutChangingSavedDay() throws {
        try withStore { store, _, _ in
            try store.addCommitment(stop(start: 30, end: 60), park: park, now: now)
            XCTAssertThrowsError(try store.addCommitment(stop(start: 45, end: 90), park: park, now: now))
            XCTAssertEqual(store.state(for: park, at: now).commitments.count, 1)
            try store.addCommitment(stop(start: 60, end: 90), park: park, now: now)
            XCTAssertEqual(store.state(for: park, at: now).commitments.count, 2)
        }
    }

    @MainActor
    func testAddShowUsesPublishedEndOrExplicitThirtyMinuteAssumption() throws {
        try withStore { store, _, _ in
            let time = LiveShowtime(type: nil, startTime: now.addingTimeInterval(3600), endTime: nil)
            let show = LiveShow(id: "show", name: "Parade", status: nil, showtimes: [time], nextShowAt: nil,
                                nextShowEndAt: nil, nextShowType: nil, sourceUpdatedAt: now)
            try store.addShow(show, showtime: time, park: park, now: now)
            let saved = try XCTUnwrap(store.state(for: park, at: now).commitments.first)
            XCTAssertEqual(saved.endAt.timeIntervalSince(saved.startAt), 30 * 60)
            XCTAssertEqual(saved.bufferMinutes, 15)
            XCTAssertTrue(saved.note?.contains("30 minutes") == true)
            XCTAssertThrowsError(try store.addShow(show, showtime: time, park: park, now: now))
        }
    }

    @MainActor
    func testExplicitPackSaveColdLaunchAndImmutableProgress() throws {
        try withStore { store, directory, defaults in
            store.setFavorite(true, rideID: 1, park: park)
            let snapshot = snapshot()
            let route = plan(snapshot.rides)
            try store.savePack(snapshot: snapshot, park: park, route: route, sourceIsLive: true, now: now)
            try store.setProgress(.done, rideID: 1, park: park, now: now)
            XCTAssertNil(store.pack(for: park)?.day.progress[1], "Progress edits must not silently change a saved pack")
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            let pack = try XCTUnwrap(reopened.pack(for: park))
            XCTAssertEqual(pack.savedAt, now)
            XCTAssertEqual(pack.fetchedAt, now)
            XCTAssertEqual(pack.route?.stops.count, 1)
            XCTAssertEqual(reopened.state(for: park, at: now).progress[1], .done)
            try reopened.savePack(snapshot: snapshot, park: park, route: nil, sourceIsLive: true, now: now)
            XCTAssertEqual(reopened.pack(for: park)?.day.progress[1], .done)
        }
    }

    @MainActor
    func testOfflinePackPayloadHasNoLiveOrForecastFields() throws {
        try withStore { store, directory, _ in
            try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now)
            let data = try Data(contentsOf: directory.appendingPathComponent("pack-v1-6.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rides = try XCTUnwrap(object["rides"] as? [[String: Any]])
            XCTAssertNil(rides.first?["estimate"])
            XCTAssertNil(rides.first?["delayEvidence"])
            XCTAssertNil(rides.first?["trend"])
            XCTAssertNil(object["feedHealthy"])
            XCTAssertNil(object["weather"])
            XCTAssertEqual(rides.first?["savedWaitMinutes"] as? Int, 5)
        }
    }

    @MainActor
    func testStaleOrFailedSourceCannotReplacePack() throws {
        try withStore { store, _, _ in
            try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now)
            XCTAssertThrowsError(try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: false, now: now))
            XCTAssertThrowsError(try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now.addingTimeInterval(901)))
            XCTAssertEqual(store.pack(for: park)?.savedAt, now)
        }
    }

    @MainActor
    func testCorruptPackDoesNotBlockGoodPackOrLaunch() throws {
        try withStore { store, directory, defaults in
            try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now)
            try Data("{damaged".utf8).write(to: directory.appendingPathComponent("pack-v1-5.json"))
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertNotNil(reopened.pack(for: park))
            XCTAssertNil(reopened.pack(for: .epcot))
            XCTAssertNotNil(reopened.storageMessage)
        }
    }

    @MainActor
    func testOversizedEarlierParkDoesNotHideLaterGoodPack() throws {
        try withStore { store, directory, defaults in
            try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now)
            try Data(repeating: 32, count: NativeDayExperienceStore.maximumTotalBytes + 1)
                .write(to: directory.appendingPathComponent("pack-v1-5.json"))
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertNotNil(reopened.pack(for: park))
            XCTAssertNil(reopened.pack(for: .epcot))
            XCTAssertTrue(reopened.hasPackFile(for: .epcot))
            try reopened.removePack(for: .epcot)
            XCTAssertFalse(reopened.hasPackFile(for: .epcot))
        }
    }

    @MainActor
    func testOversizedPackRejectedBeforeReadingPayload() throws {
        try withStore { _, directory, defaults in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 32, count: NativeDayExperienceStore.maximumPackBytes + 1)
                .write(to: directory.appendingPathComponent("pack-v1-6.json"))
            let reopened = NativeDayExperienceStore(directory: directory, defaults: defaults)
            XCTAssertNil(reopened.pack(for: park))
            XCTAssertNotNil(reopened.storageMessage)
        }
    }

    @MainActor
    func testQuotaFailureKeepsPreviouslySavedPack() throws {
        try withStore { store, directory, _ in
            try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now)
            let old = try Data(contentsOf: directory.appendingPathComponent("pack-v1-6.json"))
            try Data(repeating: 32, count: NativeDayExperienceStore.maximumTotalBytes)
                .write(to: directory.appendingPathComponent("pack-v1-5.json"))
            XCTAssertThrowsError(try store.savePack(snapshot: snapshot(), park: park, route: nil, sourceIsLive: true, now: now))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("pack-v1-6.json")), old)
            XCTAssertNotNil(store.storageMessage)
        }
    }

    @MainActor
    func testDayStateCountIsBounded() throws {
        try withStore { store, _, _ in
            for index in 0..<100 {
                try store.setProgress(.done, rideID: 1, park: park, now: now.addingTimeInterval(Double(index) * 24 * 3600))
            }
            XCTAssertTrue(store.state(for: park, at: now).progress.isEmpty)
            XCTAssertEqual(store.state(for: park, at: now.addingTimeInterval(99 * 24 * 3600)).progress[1], .done)
        }
    }

    private func stop(start: Int, end: Int) -> NativeDayCommitment {
        NativeDayCommitment(id: "stop-\(start)-\(end)", title: "Lunch", kind: .lunch,
                            startAt: now.addingTimeInterval(Double(start) * 60), endAt: now.addingTimeInterval(Double(end) * 60),
                            bufferMinutes: 10, location: nil)
    }

    private func plan(_ rides: [LiveRide], day: NativeDayState = NativeDayState(), endMinutes: Int = 180) -> NativeDayRoute {
        NativeDayPlanning.build(rides: rides, favoriteIDs: Set(rides.map(\.id)), day: day, park: park,
                                startAt: now, endAt: now.addingTimeInterval(Double(endMinutes) * 60), now: now)
    }

    @MainActor
    private func withStore(_ block: (NativeDayExperienceStore, URL, UserDefaults) throws -> Void) throws {
        let suite = "PIVOTNativeDayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        try block(NativeDayExperienceStore(directory: directory, defaults: defaults), directory, defaults)
    }

    private func ride(_ id: Int, wait: Int? = 5, location: AttractionLocation? = nil) -> LiveRide {
        LiveRide(id: id, name: "Ride \(id)", land: "Tomorrowland", status: .open, isOpen: true, waitTime: wait,
                 lastUpdated: now, downSince: nil, elapsedDownMinutes: nil, minimumDownMinutes: nil,
                 estimate: nil, estimateReason: nil, delayType: nil, delayEvidence: nil, weatherExposure: "INDOOR",
                 radarEligible: true, radarCategory: "RIDE", reopenPending: false, trend: [], location: location,
                 themeParksWikiStatus: nil, waitTimeSource: "THEMEPARKS_WIKI", scheduledClosure: nil,
                 statusAgreement: nil, statusProvenance: nil, statusComparisonReason: nil, scheduledReason: nil, operatingWindow: nil)
    }

    private func snapshot() -> LiveParkSnapshot {
        LiveParkSnapshot(parkId: 6, park: ParkMetadata(name: "Magic Kingdom Park", destination: "Walt Disney World",
                                                    operatorName: "Disney", country: "United States", timezone: "America/New_York"),
                         parkActive: true, feedHealthy: true, fetchedAt: now, sourceUpdatedAt: now,
                         sourceUpdatedAtByProvider: nil, cacheAgeSeconds: 0, rides: [ride(1)],
                         metrics: ParkMetrics(openCount: 1, downCount: 0, scheduledCount: 0, averageWait: 5, reportingCount: 1),
                         source: SourceDetails(name: "ThemeParks.wiki", url: "https://www.themeparks.wiki/", updateCadenceMinutes: 5),
                         themeParksWiki: nil, weather: makeWeather(at: now))
    }
    private func makeWeather(at date: Date) -> WeatherSnapshot {
        WeatherSnapshot(
            location: WeatherLocation(parkId: 6, parkName: "Magic Kingdom Park", latitude: 28.4177, longitude: -81.5812),
            fetchedAt: date,
            condition: "Partly Cloudy",
            temperatureF: 84,
            windMph: 8,
            precipitationChance: 20,
            observedThunderstorm: false,
            forecastThunderstorm: false,
            forecastThunderstormUntil: nil,
            convectiveAlertLevel: nil,
            activeAlerts: [],
            nws: NWSDetails(
                status: "LIVE",
                observedAt: date,
                forecastUpdatedAt: date,
                alertsCheckedAt: date,
                observationStatus: "LIVE",
                forecastStatus: "LIVE",
                alertsStatus: "LIVE",
                stationName: "KMCO",
                url: "https://weather.gov/"
            ),
            lightning: LightningDetails(
                status: "LIVE",
                checkedAt: date,
                densityDetectedAt: [],
                parkCoordinateDensityDetectedAt: [],
                lastDensityDetectedAt: nil,
                nearestPositiveSampleMiles: nil,
                sampleRadiusMiles: 5,
                periodsDetected30Minutes: 0,
                maximumStrikeDensity: nil,
                coverageMinutes: 30,
                sourceUpdatedAt: date,
                url: "https://nowcoast.noaa.gov/",
                clearSinceAt: nil,
                clearMinutes: 0,
                requiredClearMinutes: 30,
                clearanceAt: nil,
                clearanceVerifiedAt: nil,
                clearanceState: "UNKNOWN",
                completeFrames30Minutes: 0,
                gridResolutionMiles: 5
            ),
            radar: RadarDetails(
                status: "LIVE",
                checkedAt: date,
                sourceUpdatedAt: date,
                sampleRadiusMiles: 5,
                maximumReflectivityDbz: 0,
                trend: "CLEAR",
                trendDbzPerMinute: 0,
                projectedClearAt: date,
                coverageMinutes: 28,
                url: "https://nowcoast.noaa.gov/"
            )
        )
    }
}
