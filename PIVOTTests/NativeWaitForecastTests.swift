import XCTest
@testable import PIVOT

final class NativeWaitForecastTests: XCTestCase {
    private let park = FloridaPark.magicKingdom
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-10-13T14:30:00Z") }

    func hours(open: String = "2026-10-13T13:00:00Z", close: String = "2026-10-13T23:00:00Z", at: Date? = nil) -> ParkHoursSnapshot {
        ParkHoursSnapshot(parkId: 6, parkName: park.name, timezone: park.timeZoneIdentifier,
            date: "2026-10-13", fetchedAt: at ?? now, sourceUpdatedAt: now, cacheAgeSeconds: 0, cacheHit: false,
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

    func testHourlyPatternAndLowestRemainingHourUseSameWeekdayDays() {
        let points = seeded().forecast(rideID: 1, park: park, hours: hours(), snapshot: nil, failed: false, now: now)
        XCTAssertEqual(points.map(\.minutes), [40, 20, 60])
        XCTAssertEqual(points.min { $0.minutes < $1.minutes }?.start, date("2026-10-13T15:00:00Z"))
        XCTAssertTrue(points.allSatisfy { $0.days == 3 && $0.sameWeekday && !$0.crowdAdjusted })
        XCTAssertEqual(points[1].lower, 15)
        XCTAssertEqual(points[1].upper, 25)
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
