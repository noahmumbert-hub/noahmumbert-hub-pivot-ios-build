import XCTest
@testable import PIVOT

/// Add this file to PIVOTTests. These deterministic tests use fixtures only;
/// none of the fixture waits or movement windows are displayed by the app.
final class NativeParkExtrasTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-05T05:00:00Z")!

    func testHHNUsesEventDateAfterMidnightAndStopsAtClosing() {
        let event = makeEvent()
        XCTAssertEqual(HorrorNightPresentation.phase(for: event, at: now), .live)
        XCTAssertEqual(HorrorNightPreferences.doneKey(eventDate: event.night.date), "pivot.hhn.done.v1.65.2026-10-04")
        XCTAssertEqual(HorrorNightPresentation.phase(for: event, at: date("2026-10-05T06:00:00Z")), .hidden)
        XCTAssertNotEqual(HorrorNightPreferences.doneKey(eventDate: "2026-10-04"), HorrorNightPreferences.doneKey(eventDate: "2026-10-05"))
    }

    func testHHNTonightPreviewIsNotTomorrowPreview() {
        let afternoon = date("2026-10-04T17:00:00Z")
        let event = makeEvent(fetchedAt: afternoon, checkedAt: afternoon)
        XCTAssertEqual(HorrorNightPresentation.phase(for: event, at: afternoon), .preview)
        XCTAssertNil(HorrorNightPresentation.liveWait(for: event.houses[0], event: event, now: afternoon, refreshFailed: false))
        let yesterday = date("2026-10-03T23:00:00Z")
        XCTAssertEqual(HorrorNightPresentation.phase(for: makeEvent(checkedAt: yesterday), at: yesterday), .hidden)
    }

    func testHHNModeSwitchesAtServerModeStartButWaitsAwaitOpening() {
        let modeStart = date("2026-10-04T22:00:00Z")
        let event = makeEvent(fetchedAt: modeStart, checkedAt: modeStart)
        XCTAssertEqual(HorrorNightPresentation.phase(for: event, at: modeStart), .live)
        XCTAssertNil(HorrorNightPresentation.liveWait(for: makeHouse(updatedAt: modeStart), event: event, now: modeStart, refreshFailed: false))
    }

    func testHHNRejectsStaleAndFutureSchedules() {
        for checkedAt in [now.addingTimeInterval(-36 * 3600), now.addingTimeInterval(121)] {
            XCTAssertEqual(HorrorNightPresentation.phase(for: makeEvent(checkedAt: checkedAt), at: now), .hidden)
        }
    }

    func testHHNFavoritesAreStringIDsAndDoneCanBeUndone() {
        let selected = HorrorNightPreferences.toggling("provider-house:abc", in: "[]")
        XCTAssertEqual(HorrorNightPreferences.ids(from: selected), Set(["provider-house:abc"]))
        XCTAssertEqual(HorrorNightPreferences.ids(from: HorrorNightPreferences.toggling("provider-house:abc", in: selected)), [])
        XCTAssertNotEqual(HorrorNightPreferences.favoritesKey, HorrorNightPreferences.doneKey(eventDate: "2026-10-04"))
        XCTAssertEqual(HorrorNightPreferences.ids(from: "invalid json"), [])
    }

    func testHHNWaitsStayUnknownWhenMissingStaleNegativeFutureOrRefreshFails() {
        let event = makeEvent()
        XCTAssertEqual(HorrorNightPresentation.liveWait(for: event.houses[0], event: event, now: now, refreshFailed: false), 20)
        XCTAssertNil(HorrorNightPresentation.liveWait(for: event.houses[0], event: event, now: now, refreshFailed: true))
        for house in [
            makeHouse(wait: nil), makeHouse(wait: -1), makeHouse(status: "DOWN", wait: 0),
            makeHouse(updatedAt: now.addingTimeInterval(-900)), makeHouse(updatedAt: now.addingTimeInterval(121))
        ] {
            XCTAssertNil(HorrorNightPresentation.liveWait(for: house, event: event, now: now, refreshFailed: false))
        }
        let stale = makeEvent(fetchedAt: now.addingTimeInterval(-900))
        XCTAssertNil(HorrorNightPresentation.liveWait(for: stale.houses[0], event: stale, now: now, refreshFailed: false))
    }

    func testHHNSortsKnownWaitsAheadOfUnknownAndNameSeparately() {
        let event = makeEvent(houses: [
            makeHouse(id: "a", name: "Alpha", wait: nil),
            makeHouse(id: "c", name: "Charlie", wait: 10),
            makeHouse(id: "b", name: "Bravo", wait: 0)
        ])
        XCTAssertEqual(HorrorNightPresentation.sortedHouses(event, sort: .shortest, now: now, refreshFailed: false).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(HorrorNightPresentation.sortedHouses(event, sort: .name, now: now, refreshFailed: false).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(HorrorNightPresentation.sortedHouses(event, sort: .shortest, now: now, refreshFailed: true).map(\.id), ["a", "b", "c"])
    }

    func testHistoryKeepsActualTimesFiltersInvalidAndCapsAtTwelve() {
        let valid = (0..<15).map { WaitHistorySample(observedAt: now.addingTimeInterval(Double(-$0 * 60)), waitTime: Double($0)) }
        let invalid = [
            WaitHistorySample(observedAt: now.addingTimeInterval(-6 * 3600 - 1), waitTime: 30),
            WaitHistorySample(observedAt: now.addingTimeInterval(1), waitTime: 30),
            WaitHistorySample(observedAt: now.addingTimeInterval(-1500), waitTime: -1),
            WaitHistorySample(observedAt: now.addingTimeInterval(-1600), waitTime: .infinity)
        ]
        let result = WaitHistoryPresentation.samples(valid + invalid + [valid[0]], at: now)
        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(result.first?.observedAt, now.addingTimeInterval(-11 * 60))
        XCTAssertEqual(result.last?.observedAt, now)
        XCTAssertEqual(Set(result.map(\.observedAt)).count, result.count)
        XCTAssertEqual(WaitHistoryPresentation.samples(nil, at: now), [])
    }

    func testHistoryPreservesGapsAndSingleObservationAndSixHourBoundary() {
        let samples = [WaitHistorySample(observedAt: now.addingTimeInterval(-6 * 3600), waitTime: 0), WaitHistorySample(observedAt: now, waitTime: 45)]
        XCTAssertEqual(WaitHistoryPresentation.samples(samples, at: now), samples)
        XCTAssertEqual(WaitHistoryPresentation.samples([samples[1]], at: now), [samples[1]])
    }

    func testLegacyRideDecodesWithNoHistoryAndNewTimestampHistoryDecodes() throws {
        let legacy = #"{"id":1,"name":"Test Ride","land":"Test","status":"OPEN","isOpen":true,"weatherExposure":"INDOOR","radarEligible":true,"radarCategory":"RIDE","reopenPending":false,"trend":[10,20]}"#
        let ride = try PivotAPIClient.makeDecoder().decode(LiveRide.self, from: Data(legacy.utf8))
        XCTAssertNil(ride.waitHistory)
        XCTAssertEqual(WaitHistoryPresentation.samples(ride.waitHistory, at: now), [], "Untimed legacy trend must not become chart samples")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any])
        object["waitHistory"] = [["observedAt": "2026-10-05T05:00:00.000Z", "waitTime": 12.5]]
        let updated = try PivotAPIClient.makeDecoder().decode(LiveRide.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(updated.waitHistory?.first?.observedAt, now)
        XCTAssertEqual(updated.waitHistory?.first?.waitTime, 12.5)
    }

    func testLegacyWeatherDecodesWithNoExperimentAndOptionalPayloadRoundTrips() throws {
        let legacy = #"{"location":{"parkId":65,"parkName":"Universal Studios Florida","latitude":28.47,"longitude":-81.46},"fetchedAt":"2026-10-05T05:00:00Z","activeAlerts":[],"nws":{"status":"LIVE","observationStatus":"LIVE","forecastStatus":"LIVE","alertsStatus":"LIVE","url":"https://weather.gov"},"lightning":{"status":"LIVE","densityDetectedAt":[],"parkCoordinateDensityDetectedAt":[],"sampleRadiusMiles":5,"periodsDetected30Minutes":0,"coverageMinutes":30,"url":"https://nowcoast.noaa.gov"}}"#
        let weather = try PivotAPIClient.makeDecoder().decode(WeatherSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(weather.lightningDeparture)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any])
        object["lightningDeparture"] = departureObject(status: "DISABLED")
        let updated = try PivotAPIClient.makeDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(updated.lightningDeparture?.status, "DISABLED")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(updated)
        XCTAssertEqual(try PivotAPIClient.makeDecoder().decode(WeatherSnapshot.self, from: encoded).lightningDeparture?.status, "DISABLED")
    }

    func testOnlyFreshExperimentalRangeDisplaysNumbers() throws {
        let estimate = try makeDeparture()
        XCTAssertNotNil(LightningDeparturePresentation(estimate: estimate, now: now).range)
        XCTAssertNil(LightningDeparturePresentation(estimate: estimate, now: now, refreshFailed: true).range)
        for status in ["ABSTAIN", "DISABLED", "FUTURE_UNKNOWN_STATUS"] {
            XCTAssertNil(LightningDeparturePresentation(estimate: try makeDeparture(status: status), now: now).range)
        }
    }

    func testExperimentalRangeExpiresWithoutFreshResponseAndRejectsIncompleteCoverage() throws {
        let estimate = try makeDeparture()
        XCTAssertNil(LightningDeparturePresentation(estimate: estimate, now: now.addingTimeInterval(13 * 60)).range)
        let invalidUpdates: [[String: Any]] = [
            ["latestDepartureAt": "2026-10-05T05:00:00Z"],
            ["radarObservedAt": "2026-10-05T05:00:01Z"],
            ["lightningIntervalEndAt": NSNull()],
            ["calibration": "UNKNOWN"],
            ["frameTimes": ["2026-10-05T04:59:00Z"]],
            ["algorithmVersion": "FUTURE_VERSION"]
        ]
        for updates in invalidUpdates {
            XCTAssertNil(LightningDeparturePresentation(estimate: try makeDeparture(updates: updates), now: now).range)
        }
        var object = departureObject(status: "EXPERIMENTAL_RANGE")
        var diagnostics = try XCTUnwrap(object["diagnostics"] as? [String: Any])
        diagnostics["unknownLightningCells"] = 1
        object["diagnostics"] = diagnostics
        let incomplete = try PivotAPIClient.makeDecoder().decode(LightningDepartureEstimate.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(LightningDeparturePresentation(estimate: incomplete, now: now).range)
    }

    private func makeHouse(id: String = "house-one", name: String = "One", status: String = "OPEN", wait: Int? = 20, updatedAt: Date? = nil) -> HorrorHouse {
        HorrorHouse(id: id, name: name, status: status, waitTime: wait, sourceUpdatedAt: updatedAt ?? now)
    }

    private func makeEvent(fetchedAt: Date? = nil, checkedAt: Date? = nil, houses: [HorrorHouse]? = nil) -> HorrorNightSnapshot {
        HorrorNightSnapshot(
            night: HorrorNight(date: "2026-10-04", modeStartsAt: date("2026-10-04T22:00:00Z"), openingTime: date("2026-10-04T22:30:00Z"), closingTime: date("2026-10-05T06:00:00Z")),
            scheduleCheckedAt: checkedAt ?? now, fetchedAt: fetchedAt ?? now, houses: houses ?? [makeHouse()]
        )
    }

    private func makeDeparture(status: String = "EXPERIMENTAL_RANGE", updates: [String: Any] = [:]) throws -> LightningDepartureEstimate {
        var object = departureObject(status: status)
        updates.forEach { object[$0.key] = $0.value }
        return try PivotAPIClient.makeDecoder().decode(LightningDepartureEstimate.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func departureObject(status: String) -> [String: Any] {
        [
            "status": status, "reason": "PATTERN_TRANSLATING", "label": "Fixture movement evidence",
            "algorithmVersion": "PIVOT_SPATIAL_DEPARTURE_EXPERIMENT_V1", "calibration": "UNCALIBRATED",
            "issuedAt": "2026-10-05T05:00:00Z", "radarObservedAt": "2026-10-05T04:59:00Z",
            "lightningIntervalEndAt": "2026-10-05T04:55:00Z", "earliestDepartureAt": "2026-10-05T05:05:00Z", "latestDepartureAt": "2026-10-05T05:20:00Z",
            "diagnostics": ["radarAgeMinutes": 1, "lightningAgeMinutes": 5, "footprintPixelCounts": [20,20,20], "componentCounts": [1,1,1], "componentPixelCounts": [[20,20,20]], "unknownRadarCells": [0,0,0], "unknownLightningCells": 0, "pairOverlap": [0.9,0.9], "pairSpeedsMph": [20,20], "densityIntervalMinutes": 15, "reflectivityUnits": "indexed categories, not dBZ"] as [String: Any],
            "frameCount": 3, "frameTimes": ["2026-10-05T04:49:00Z", "2026-10-05T04:54:00Z", "2026-10-05T04:59:00Z"],
            "trackedRadiusMiles": 5, "watchRadiusMiles": 32,
            "motion": ["eastMilesPerMinute": 0.3, "northMilesPerMinute": 0, "speedMph": 18, "bearingDegrees": 90, "agreement": "Three frames"] as [String: Any],
            "source": ["radar": "NOAA radar fixture", "lightning": "NOAA density fixture"],
            "limitations": "Uncalibrated fixture. Does not establish lightning clearance, safety, or ride operations."
        ]
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
