import XCTest
@testable import PIVOT

final class NativeWaitForecastTests: XCTestCase {
    private let park = FloridaPark.magicKingdom
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-10-13T14:30:00Z") }

    func hours(open: String = "2026-10-13T13:00:00Z", close: String = "2026-10-13T23:00:00Z", at: Date? = nil) -> ParkHoursSnapshot {
        ParkHoursSnapshot(parkId: 6, parkName: park.name, timezone: park.timeZoneIdentifier,
            date: "2026-10-13", fetchedAt: at ?? now, sourceUpdatedAt: at ?? now, cacheAgeSeconds: 0, cacheHit: false,
            stale: false, warning: nil, regular: ParkHoursPeriod(openingTime: date(open), closingTime: date(close), label: "Regular", type: "OPERATING"),
            earlyEntry: nil, source: ThemeParksWikiAttribution(name: "ThemeParks.wiki", label: "Schedule", url: "https://themeparks.wiki", termsUrl: "https://themeparks.wiki", updateCadenceMinutes: 60))
    }

    private func seeded(days: [String] = ["2026-10-06", "2026-09-29", "2026-09-22"], parkID: Int = 6, waits: [Int: Double] = [10: 40, 11: 20, 12: 60]) -> WaitLearningHistory {
        var history = WaitLearningHistory()
        for day in days {
            let at = date("\(day)T20:00:00Z")
            let weekday = WaitLearningHistory.calendar(for: park).component(.weekday, from: at)
            for ride in 1...6 {
                for (hour, wait) in waits {
                    history.bins["\(parkID):\(ride):\(day):\(hour)"] = WaitLearningBin(parkID: parkID, rideID: ride, day: day,
                        weekday: weekday, hour: hour, quarters: [0: wait, 1: wait], lastSeen: at)
                    history.eligibleCounts["\(parkID):\(day):\(hour)"] = 6
                }
            }
        }
        return history
    }

    @MainActor
    private func liveSnapshot(edit: (inout [String: Any]) -> Void = { _ in }) throws -> LiveParkSnapshot {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(NativeParkMapUITestScreen.rootSnapshot())) as? [String: Any])
        json["fetchedAt"] = now.timeIntervalSince1970
        json["rides"] = [["id": 1, "name": "Test Ride", "land": "Test", "status": "OPEN", "isOpen": true,
                           "waitTime": 20, "lastUpdated": now.timeIntervalSince1970, "weatherExposure": "INDOOR",
                           "radarEligible": true, "radarCategory": "RIDE", "reopenPending": false, "trend": []]]
        edit(&json)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testHourlyPatternAndLowestRemainingHourUseSameWeekdayDays() {
        let points = seeded().forecast(rideID: 1, park: park, hours: hours(), snapshot: nil, failed: false, now: now)
        XCTAssertEqual(points.map(\.minutes), [40, 20, 60])
        XCTAssertEqual(points.min { $0.minutes < $1.minutes }?.start, date("2026-10-13T15:00:00Z"))
        XCTAssertTrue(points.allSatisfy { $0.days == 3 && $0.sameWeekday && !$0.crowdAdjusted })
        XCTAssertEqual(points[1].lower, 15)
        XCTAssertEqual(points[1].upper, 25)
    }

    @MainActor
    func testLowestWaitSummaryUsesSupportedWindowAndWithholdsUnavailableStates() throws {
        let snapshot = try liveSnapshot()
        func resolve(_ value: LiveParkSnapshot?, failed: Bool = false, history: WaitLearningHistory? = nil,
                     schedule: ParkHoursSnapshot? = nil, at: Date? = nil) -> LowestWaitPrediction {
            LowestWaitPrediction.resolve(history: history ?? seeded(), rideID: 1, park: park,
                hours: schedule ?? hours(), snapshot: value, failed: failed, now: at ?? now)
        }
        let current = resolve(snapshot)
        XCTAssertEqual(current.window?.minutes, 20)
        XCTAssertEqual(current.window?.start, date("2026-10-13T15:00:00Z"))
        XCTAssertEqual(current.window?.lower, 15)
        XCTAssertEqual(current.supportedHours, 3)
        XCTAssertTrue(current.detail.contains("limited confidence"))
        XCTAssertEqual(current.sourceCheckedAt, now)
        XCTAssertEqual(current.window?.latestObservationAt, date("2026-10-06T20:00:00Z"))
        for value in [resolve(nil), resolve(snapshot, failed: true), resolve(snapshot, at: now.addingTimeInterval(901)),
                      resolve(snapshot, history: seeded(days: ["2026-10-06"])),
                      resolve(snapshot, schedule: hours(at: now.addingTimeInterval(-36 * 3600)))] {
            XCTAssertNil(value.window)
        }
        var closed = snapshot; closed.rides[0].status = .down; closed.rides[0].isOpen = false
        XCTAssertNil(resolve(closed).window, "A low-wait window must not predict reopening")
        let sparse = resolve(snapshot, history: seeded(waits: [12: 30]))
        XCTAssertEqual(sparse.supportedHours, 1)
        XCTAssertTrue(sparse.detail.contains("Unobserved hours are excluded"))
    }

    @MainActor
    func testLowestWaitPredictionRejectsAmbiguousInvalidAndNonOperatingRides() throws {
        let snapshot = try liveSnapshot()
        func resolve(_ value: LiveParkSnapshot) -> LowestWaitPrediction {
            LowestWaitPrediction.resolve(history: seeded(), rideID: 1, park: park,
                hours: hours(), snapshot: value, failed: false, now: now)
        }
        var duplicate = snapshot; duplicate.rides.append(snapshot.rides[0])
        var inconsistent = snapshot; inconsistent.rides[0].isOpen = false
        var missing = snapshot; missing.rides = []
        var noWait = snapshot; noWait.rides[0].waitTime = nil
        var invalid = snapshot; invalid.rides[0].waitTime = 1441
        var negative = snapshot; negative.rides[0].waitTime = -1
        var stale = snapshot; stale.rides[0].status = .stale
        for value in [duplicate, inconsistent, missing, noWait, invalid, negative, stale] {
            let result = resolve(value)
            XCTAssertNil(result.window)
            XCTAssertNil(result.sourceCheckedAt)
            XCTAssertEqual(result.points.count, 3, "Historical chart may remain available without a current recommendation")
        }
        for field in ["parkActive", "feedHealthy"] {
            XCTAssertNil(resolve(try liveSnapshot { $0[field] = false }).window)
        }
        XCTAssertNil(resolve(try liveSnapshot { $0["parkId"] = 5 }).window)
    }

    @MainActor
    func testLowestWaitPredictionKeepsZeroTiesAndOnlyTheRemainingOperatingWindow() throws {
        var snapshot = try liveSnapshot(); snapshot.rides[0].waitTime = 0
        let history = seeded(waits: [10: 0, 11: 0, 12: 20])
        func resolve(at: Date, schedule: ParkHoursSnapshot? = nil) -> LowestWaitPrediction {
            LowestWaitPrediction.resolve(history: history, rideID: 1, park: park,
                hours: schedule ?? hours(), snapshot: snapshot, failed: false, now: at)
        }
        let current = resolve(at: now)
        XCTAssertEqual(current.window?.minutes, 0, "An observed zero is usable evidence")
        XCTAssertEqual(current.window?.start, now, "Equal minima choose the first remaining slot")
        XCTAssertEqual(current.window?.end, date("2026-10-13T15:00:00Z"))
        let clipped = resolve(at: now, schedule: hours(close: "2026-10-13T14:45:00Z"))
        XCTAssertEqual(clipped.window?.end, date("2026-10-13T14:45:00Z"))
        XCTAssertEqual(clipped.supportedHours, 1)
        XCTAssertNil(resolve(at: now, schedule: hours(close: "2026-10-13T14:30:00Z")).window)
    }

    @MainActor
    func testLowestWaitPredictionUsesProviderCheckTimeAndRejectsExpiredOrFutureEvidence() throws {
        func snapshot(checkedAt: Date, versionAt: Date? = nil) throws -> LiveParkSnapshot {
            try liveSnapshot { json in
                json["themeParksWiki"] = ["available": true, "cacheStale": false,
                    "fetchedAt": checkedAt.timeIntervalSince1970, "matchedRideCount": 1, "unmatchedRides": [],
                    "role": "PRIMARY", "statusSemantics": "RAW_PROVIDER_STATUS", "usedForWaitTimes": true,
                    "usedForOperationalTraining": true,
                    "source": ["name": "ThemeParks.wiki", "label": "Waits", "url": "https://themeparks.wiki",
                        "termsUrl": "https://themeparks.wiki", "updateCadenceMinutes": 5]]
                if let versionAt {
                    var rides = json["rides"] as! [[String: Any]]
                    rides[0]["lastUpdated"] = versionAt.timeIntervalSince1970; json["rides"] = rides
                }
            }
        }
        func resolve(_ value: LiveParkSnapshot) -> LowestWaitPrediction {
            LowestWaitPrediction.resolve(history: seeded(), rideID: 1, park: park,
                hours: hours(), snapshot: value, failed: false, now: now)
        }
        let checkedAt = now.addingTimeInterval(-300)
        XCTAssertEqual(resolve(try snapshot(checkedAt: checkedAt)).sourceCheckedAt, checkedAt,
                       "A new API response cannot make the upstream check newer")
        for offset in [TimeInterval(-900), 121] {
            XCTAssertNil(resolve(try snapshot(checkedAt: now.addingTimeInterval(offset))).window)
            XCTAssertNil(resolve(try snapshot(checkedAt: now, versionAt: now.addingTimeInterval(offset))).window)
        }
    }

    func testOneDayAndUnknownHoursProduceNoInventedPredictions() {
        XCTAssertTrue(seeded(days: ["2026-10-06"]).forecast(rideID: 1, park: park, hours: hours(), snapshot: nil, failed: false, now: now).isEmpty)
        XCTAssertTrue(seeded().forecast(rideID: 1, park: park, hours: nil, snapshot: nil, failed: false, now: now).isEmpty)
        let points = seeded(waits: [12: 30]).forecast(rideID: 1, park: park, hours: hours(), snapshot: nil, failed: false, now: now)
        XCTAssertEqual(points.count, 1, "No interpolation through missing 10 and 11 o’clock hours")
    }

    func testOvernightSessionPreservesPreviousOperatingDayAndStopsAtClosing() {
        let afterMidnight = date("2026-10-14T04:30:00Z")
        let period = hours(open: "2026-10-13T13:00:00Z", close: "2026-10-14T05:00:00Z", at: afterMidnight)
        let points = seeded(waits: [0: 10, 1: 50, 23: 20]).forecast(rideID: 1, park: park, hours: period, snapshot: nil, failed: false, now: afterMidnight)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.minutes, 10)
        XCTAssertEqual(points.first?.end, date("2026-10-14T05:00:00Z"))
        XCTAssertTrue(seeded().forecast(rideID: 1, park: park, hours: period, snapshot: nil, failed: false, now: date("2026-10-14T05:00:00Z")).isEmpty)
    }

    func testParkComparisonPreservesChosenLocalDateAcrossTimeZones() {
        let chosen = date("2026-10-14T04:00:00Z") // midnight in New York
        let converted = WaitLearningHistory.matchingDay(chosen, from: park, to: .sixFlagsMagicMountain)
        XCTAssertEqual(WaitLearningHistory.dayKey(converted, park: .sixFlagsMagicMountain), "2026-10-14")
        XCTAssertEqual(WaitLearningHistory.dayKey(chosen, park: .sixFlagsMagicMountain), "2026-10-13")
    }

    func testFutureAndExpiredSchedulesCannotGenerateForecasts() {
        for at in [now.addingTimeInterval(121), now.addingTimeInterval(-36 * 3600)] {
            XCTAssertTrue(seeded().forecast(rideID: 1, park: park, hours: hours(at: at), snapshot: nil, failed: false, now: now).isEmpty)
        }
    }

    func testParkIsolationAndDifferentWeekdayFallbackRemainLimited() {
        XCTAssertTrue(seeded(parkID: 65).forecast(rideID: 1, park: park, hours: hours(), snapshot: nil, failed: false, now: now).isEmpty)
        let points = seeded(days: ["2026-10-05", "2026-10-04", "2026-10-03"]).forecast(rideID: 1, park: park, hours: hours(), snapshot: nil, failed: false, now: now)
        XCTAssertEqual(points.count, 3)
        XCTAssertTrue(points.allSatisfy { !$0.sameWeekday })
    }

    func testDailyCrowdAndFutureCrowdUseObservedHoursAndDaysOnly() throws {
        let history = seeded()
        let actual = try XCTUnwrap(history.dailyCrowd(park: park, date: date("2026-10-06T14:00:00Z"), now: now))
        XCTAssertEqual(actual.typicalWait, 40)
        XCTAssertEqual(actual.hourCount, 3)
        XCTAssertEqual(actual.score, 4)
        XCTAssertEqual(actual.label, "Busy")
        let expected = try XCTUnwrap(history.dailyCrowd(park: park, date: date("2026-10-20T14:00:00Z"), now: now))
        XCTAssertEqual(expected.days, 3)
        XCTAssertTrue(expected.basis.contains("same weekday"))
        XCTAssertNil(history.dailyCrowd(park: park, date: date("2026-10-07T14:00:00Z"), now: now), "Unobserved past dates stay unavailable")
        XCTAssertNil(seeded(days: ["2026-10-06"]).dailyCrowd(park: park, date: date("2026-10-20T14:00:00Z"), now: now))
    }

    func testSparseCoverageCannotClaimDailyQuietCrowds() {
        var history = seeded(waits: [10: 0])
        for key in history.eligibleCounts.keys { history.eligibleCounts[key] = 100 }
        XCTAssertNil(history.dailyCrowd(park: park, date: date("2026-10-06T14:00:00Z"), now: now))
    }

    func testRestorePrunesFutureExpiredAndMalformedObservationsAndKeepsPreferences() throws {
        let suite = "wait-learning-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([126], forKey: "pivot.favorites.6")
        var history = seeded()
        history.bins["bad"] = WaitLearningBin(parkID: 6, rideID: 2, day: "2026-10-13", weekday: 3, hour: 10, quarters: [0: -1], lastSeen: now)
        history.bins["future"] = WaitLearningBin(parkID: 6, rideID: 3, day: "2026-10-13", weekday: 3, hour: 10, quarters: [0: 0], lastSeen: now.addingTimeInterval(1))
        history.bins["expired"] = WaitLearningBin(parkID: 6, rideID: 4, day: "2026-08-01", weekday: 7, hour: 10, quarters: [0: 0], lastSeen: date("2026-08-01T14:00:00Z"))
        history.save(to: defaults)
        let restored = WaitLearningHistory.load(from: defaults, now: now)
        XCTAssertEqual(restored.bins.count, seeded().bins.count)
        XCTAssertEqual(defaults.array(forKey: "pivot.favorites.6") as? [Int], [126])
        defaults.set(Data("broken".utf8), forKey: WaitLearningHistory.storageKey)
        XCTAssertTrue(WaitLearningHistory.load(from: defaults, now: now).bins.isEmpty)
    }

    func testCrowdScoreBoundsAndFiniteWaitValidation() {
        for wait in [-1.0, Double.nan, Double.infinity, 1441] { XCTAssertFalse(WaitLearningHistory.validWait(wait)) }
        XCTAssertTrue(WaitLearningHistory.validWait(0))
        XCTAssertEqual(ParkCrowdEstimate(typicalWait: 0, rideCount: 5, hourCount: 1, days: 1, basis: "Live").score, 1)
        XCTAssertEqual(ParkCrowdEstimate(typicalWait: 600, rideCount: 5, hourCount: 1, days: 1, basis: "Live").score, 10)
    }
}
