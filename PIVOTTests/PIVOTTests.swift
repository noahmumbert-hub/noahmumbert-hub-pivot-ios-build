import XCTest
@testable import PIVOT

final class PIVOTTests: XCTestCase {
    private func openingFixture(id: Int, at: String, source: String = "2026-10-18T09:50:22Z", status: String = "DOWN", hours: Bool = true) throws -> LiveParkSnapshot {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let raw = makeSnapshot(sourceOffset: 0, ride: makeRide(id: id, status: .down,
            downSince: Date(timeIntervalSince1970: 1792285211.7), elapsedDownMinutes: 695))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(raw)) as? [String: Any])
        json["parkId"] = 5; json["fetchedAt"] = at
        var rides = try XCTUnwrap(json["rides"] as? [[String: Any]])
        rides[0]["lastUpdated"] = source; rides[0]["status"] = status; rides[0]["isOpen"] = status == "OPEN"
        rides[0]["themeParksWikiStatus"] = ["entityId":"fixture", "entityName":"fixture", "status": status == "OPEN" ? "OPERATING" : "CLOSED", "sourceUpdatedAt":source, "matchedBy":"id"]
        json["rides"] = rides
        if hours {
            let calendar = makeParkHours(park: .epcot, date: "2026-10-18")
            var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(calendar)) as? [String: Any])
            encoded["regular"] = ["openingTime":"2026-10-18T13:00:00Z", "closingTime":"2026-10-19T01:00:00Z", "label":"Regular", "type":"OPERATING"]
            encoded["earlyEntry"] = ["openingTime":"2026-10-18T12:30:00Z", "closingTime":"2026-10-18T13:00:00Z", "label":"Early", "type":"EARLY_ENTRY"]
            json["parkHours"] = encoded
        }
        return try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testOpeningEligibilityProtectsThreeScheduledRidesAndRetainsRawForecast() throws {
        for id in [155, 156, 466] {
            let raw = try openingFixture(id: id, at: "2026-10-18T12:35:00Z")
            let originalAnchor = raw.rides[0].estimate?.episodeAnchorAt
            let result = NativeOpeningEligibility.applying(to: raw)
            let ride = result.rides[0]
            XCTAssertEqual(ride.status, .scheduled); XCTAssertFalse(ride.isRadarDown)
            XCTAssertEqual(ride.operatingWindow?.label, "Opens at 9:00 AM")
            XCTAssertNil(ride.estimate); XCTAssertNil(ride.downSince); XCTAssertNil(ride.elapsedDownMinutes)
            XCTAssertEqual(raw.rides[0].elapsedDownMinutes, 695)
            XCTAssertEqual(raw.rides[0].estimate?.episodeAnchorAt, originalAnchor)
            XCTAssertEqual(result.fetchedAt, raw.fetchedAt)
        }
    }

    func testOpeningBoundaryCannotFabricateOpenOrFreshDowntime() throws {
        let before = try openingFixture(id: 155, at: "2026-10-18T12:59:00Z")
        let boundary = try openingFixture(id: 155, at: "2026-10-18T13:00:00Z")
        let result = NativeOpeningEligibility.applying(to: boundary)
        XCTAssertEqual(result.rides[0].status, .stale); XCTAssertFalse(result.rides[0].isOpen)
        XCTAssertNil(result.rides[0].estimate)
        let transition = RideTransitionEngine.evaluate(selectedParkId: 5, previous: nil, current: NativeOpeningEligibility.applying(to: before))
        XCTAssertTrue(RideTransitionEngine.evaluate(selectedParkId: 5, previous: transition.nextBaseline, current: result).alerts.isEmpty)
        let freshDown = try openingFixture(id: 155, at: "2026-10-18T13:06:00Z", source: "2026-10-18T13:05:00Z")
        XCTAssertEqual(NativeOpeningEligibility.applying(to: freshDown).rides[0].status, .down)
    }

    func testGuardiansIsEligibleButOldSourceIsNotBreakdownEvidence() throws {
        let raw = try openingFixture(id: 10916, at: "2026-10-18T12:35:00Z")
        XCTAssertEqual(NativeOpeningEligibility.applying(to: raw).rides[0].status, .stale)
        let opened = try openingFixture(id: 10916, at: "2026-10-18T12:41:15Z", source: "2026-10-18T12:35:20Z", status: "OPEN")
        XCTAssertEqual(NativeOpeningEligibility.applying(to: opened).rides[0].status, .open)
        XCTAssertEqual(NativeOpeningEligibility.applying(to: opened).rides[0].lastUpdated, opened.rides[0].lastUpdated)
    }

    func testMissingOpeningEvidenceDoesNotGrantEarlyEntry() throws {
        for id in [10916, 999] {
            let missing = try openingFixture(id: id, at: "2026-10-18T12:35:00Z", source: "2026-10-18T12:34:00Z", hours: false)
            XCTAssertEqual(NativeOpeningEligibility.applying(to: missing).rides[0].status, .stale)
            XCTAssertNil(NativeOpeningEligibility.applying(to: missing).rides[0].estimate)
        }
        let unknown = try openingFixture(id: 999, at: "2026-10-18T12:35:00Z", source: "2026-10-18T12:34:00Z")
        XCTAssertEqual(NativeOpeningEligibility.applying(to: unknown).rides[0].status, .stale)
    }

    func testOpeningGuardRunsOnAPIResponseBeforeNativeConsumers() async throws {
        let raw = try openingFixture(id: 155, at: "2026-10-18T12:35:00Z")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(raw)
        AuditURLProtocol.response = { _ in payload }
        defer { AuditURLProtocol.response = nil }
        let result = try await hhnTestClient().snapshot(for: .epcot)
        XCTAssertEqual(result.rides[0].status, .scheduled)
        XCTAssertFalse(result.rides[0].isRadarDown)
    }

    func testHHNRefreshRestoresPostedWaitFromFreshProviderAndBoundsRequests() async throws {
        let now = Date()
        let sourceAt = now.addingTimeInterval(-7200)
        let payload = try hhnServerPayload(at: now, sourceAt: sourceAt)
        let provider = try JSONSerialization.data(withJSONObject: ["id": NativeHorrorHouseFeed.parkEntityID, "liveData": [
            ["id": "house", "name": "House", "entityType": "ATTRACTION", "parkId": NativeHorrorHouseFeed.parkEntityID,
             "externalId": "uor.usf.rides.hhn_haunted_house_test", "status": "OPERATING",
             "lastUpdated": ISO8601DateFormatter().string(from: sourceAt), "queue": ["STANDBY": ["waitTime": 10]]]
        ]])
        var requests = 0
        AuditURLProtocol.response = { request in
            if request.url?.path == "/houses" { requests += 1; return provider }
            return payload
        }
        defer { AuditURLProtocol.response = nil }
        let client = hhnTestClient()
        for _ in 0..<2 {
            let result = try await client.snapshot(for: .universalStudiosFlorida)
            XCTAssertFalse(result.feedHealthy, "Regular-ride feed health must remain independent of HHN house observations")
            let event = try XCTUnwrap(result.halloweenHorrorNights)
            XCTAssertEqual(event.houses.first?.waitTime, 10)
            XCTAssertEqual(HorrorNightPresentation.liveWait(for: event.houses[0], event: event, now: Date(), refreshFailed: false), 10)
            XCTAssertEqual(event.houses.first?.sourceUpdatedAt.timeIntervalSince1970 ?? 0, sourceAt.timeIntervalSince1970, accuracy: 1)
        }
        XCTAssertEqual(requests, 1, "Rapid polls reuse the original successful observation for at most one minute")
    }

    func testFailedHHNProviderRefreshPreservesOriginalUnknownAndDoesNotRenewAge() async throws {
        let now = Date()
        let payload = try hhnServerPayload(at: now, sourceAt: now.addingTimeInterval(-7200))
        var requests = 0
        AuditURLProtocol.response = { request in
            if request.url?.path == "/houses" { requests += 1; throw URLError(.notConnectedToInternet) }
            return payload
        }
        defer { AuditURLProtocol.response = nil }
        let client = hhnTestClient()
        for _ in 0..<2 {
            let result = try await client.snapshot(for: .universalStudiosFlorida)
            let event = try XCTUnwrap(result.halloweenHorrorNights)
            XCTAssertNil(event.houses.first?.waitTime)
            XCTAssertEqual(event.fetchedAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        }
        XCTAssertEqual(requests, 1, "Failed provider attempts have a retry backoff")
    }

    private func hhnTestClient() -> PivotAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuditURLProtocol.self]
        return PivotAPIClient(baseURL: URL(string: "https://audit.invalid")!, session: URLSession(configuration: configuration),
                              horrorHouseURL: URL(string: "https://audit.invalid/houses")!)
    }

    private func hhnServerPayload(at now: Date, sourceAt: Date) throws -> Data {
        let formatter = ISO8601DateFormatter()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(makeSnapshot(sourceOffset: 0, feedHealthy: false, ride: makeRide(status: .open)))) as? [String: Any])
        json["parkId"] = 65
        json["halloweenHorrorNights"] = [
            "night": ["date": "2026-10-10", "modeStartsAt": formatter.string(from: now.addingTimeInterval(-7200)),
                      "openingTime": formatter.string(from: now.addingTimeInterval(-3600)), "closingTime": formatter.string(from: now.addingTimeInterval(3600))],
            "scheduleCheckedAt": formatter.string(from: now), "fetchedAt": formatter.string(from: now),
            "houses": [["id": "house", "name": "House", "status": "OPEN", "waitTime": NSNull(), "sourceUpdatedAt": formatter.string(from: sourceAt)]]
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testLightningPanelExpiresChecksSourceAgeAndFailedRefresh() throws {
        let snapshot = makeSnapshot(sourceOffset: 0, ride: makeRide(status: .open))
        let live = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: false, at: start)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.weather.lightning)) as? [String: Any])
        data["clearanceState"] = "VERIFIED"
        data["completeFrames30Minutes"] = 3
        func lightning() throws -> LightningDetails {
            try JSONDecoder().decode(LightningDetails.self, from: JSONSerialization.data(withJSONObject: data))
        }
        XCTAssertTrue(DashboardLightningHealth.presentation(lightning: try lightning(), feedHealth: live, at: start).isCurrent)
        for age in [DashboardLightningHealth.maximumCheckAge, DashboardLightningHealth.maximumCheckAge + 1] {
            let result = DashboardLightningHealth.presentation(lightning: try lightning(), feedHealth: live, at: start.addingTimeInterval(age))
            XCTAssertFalse(result.isCurrent)
            XCTAssertTrue(result.title.contains("Saved"))
        }
        let failed = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: true, at: start)
        XCTAssertFalse(DashboardLightningHealth.presentation(lightning: try lightning(), feedHealth: failed, at: start).isCurrent)
        for offset in [-DashboardLightningHealth.maximumDensityAge, 121] {
            data["sourceUpdatedAt"] = start.addingTimeInterval(offset).timeIntervalSinceReferenceDate
            XCTAssertFalse(DashboardLightningHealth.presentation(lightning: try lightning(), feedHealth: live, at: start).isCurrent)
        }
        data.removeValue(forKey: "sourceUpdatedAt")
        XCTAssertTrue(DashboardLightningHealth.presentation(lightning: try lightning(), feedHealth: live, at: start).title.contains("unavailable"))
    }

    func testColdFailureEmptyAndUnknownRideDataCannotAssertNoClosures() throws {
        let liveSnapshot = makeSnapshot(sourceOffset: 0, ride: makeRide(status: .open))
        let live = DashboardFeedHealth.presentation(parkSelected: true, snapshot: liveSnapshot, isLoading: false, refreshFailed: false, at: start)
        XCTAssertTrue(DashboardClosureHealth.canAssertNoClosures(snapshot: liveSnapshot, feedHealth: live))
        XCTAssertFalse(DashboardClosureHealth.canAssertNoClosures(snapshot: nil, feedHealth: live))
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(liveSnapshot)) as? [String: Any])
        data["rides"] = []
        let empty = try JSONDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertFalse(DashboardClosureHealth.canAssertNoClosures(snapshot: empty, feedHealth: live))
        for status: RideStatus in [.stale, .unknown("UNAVAILABLE"), .down] {
            XCTAssertFalse(DashboardClosureHealth.canAssertNoClosures(snapshot: makeSnapshot(sourceOffset: 0, ride: makeRide(status: status)), feedHealth: live))
        }
        let failed = DashboardFeedHealth.presentation(parkSelected: true, snapshot: liveSnapshot, isLoading: false, refreshFailed: true, at: start)
        XCTAssertFalse(DashboardClosureHealth.canAssertNoClosures(snapshot: liveSnapshot, feedHealth: failed))
    }

    @MainActor
    func testLateStartupAndExplicitGPSCannotOverrideManualParkOrNoPark() async throws {
        for automatic in [true, false] {
            for manual: FloridaPark? in [.magicKingdom, .epcot, nil] {
                let defaults = try XCTUnwrap(UserDefaults(suiteName: "gps-race-\(UUID())"))
                if !automatic { defaults.set(FloridaPark.magicKingdom.rawValue, forKey: "pivot.selectedPark") }
                var pending: CheckedContinuation<ParkLocationRequest, Never>?
                let store = DashboardStore(defaults: defaults, locationRequest: {
                    await withCheckedContinuation { pending = $0 }
                })
                if automatic { await store.bootstrap() } else { store.requestParkFromLocation() }
                for _ in 0..<50 where pending == nil { await Task.yield() }
                let callback = try XCTUnwrap(pending)
                store.selectPark(manual)
                callback.resume(returning: .location(latitude: 28.4177, longitude: -81.5812))
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(store.selectedPark, manual)
                XCTAssertEqual(store.locationStatus, .idle)
            }
        }
    }

    @MainActor
    func testFailedParkCacheStaysSavedAcrossRepeatedSwitchesUntilRevalidation() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "cache-switch-\(UUID())"))
        defaults.set(6, forKey: "pivot.selectedPark")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuditURLProtocol.self]
        let client = PivotAPIClient(baseURL: URL(string: "https://audit.invalid")!, session: URLSession(configuration: config))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(makeSnapshot(sourceOffset: 0, ride: makeRide(status: .open)))
        AuditURLProtocol.response = { _ in payload }
        defer { AuditURLProtocol.response = nil }
        let store = DashboardStore(apiClient: client, defaults: defaults)
        await store.refreshNow()
        XCTAssertTrue(store.feedHealth(at: start).isLive)
        AuditURLProtocol.response = { _ in throw URLError(.notConnectedToInternet) }
        await store.refreshNow()
        XCTAssertEqual(store.feedHealth(at: start).badgeLabel, "Saved")
        for _ in 0..<3 {
            store.selectPark(.epcot)
            XCTAssertTrue(store.crowdRefreshFailed(for: .magicKingdom), "Crowd browsing retains the failed park state while another park is selected")
            store.selectPark(.magicKingdom)
            XCTAssertEqual(store.feedHealth(at: start).badgeLabel, "Saved")
            XCTAssertNotNil(store.errorMessage)
            XCTAssertFalse(store.canAssertNoClosures(at: start))
        }
        AuditURLProtocol.response = { _ in payload }
        await store.refreshNow()
        XCTAssertTrue(store.feedHealth(at: start).isLive)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.crowdRefreshFailed(for: .magicKingdom))
    }

    func testFeedHealthFailureOverridesHealthyRetainedSnapshotAndRecovers() throws {
        let snapshot = makeSnapshot(sourceOffset: 0, ride: makeRide(status: .down))
        let healthy = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: false, at: start)
        XCTAssertTrue(healthy.isLive)
        XCTAssertEqual(healthy.badgeLabel, "Live")
        XCTAssertNil(healthy.retainedGuidance)

        // A retry must not turn the saved response green while it is in flight.
        for loading in [false, true] {
            let failed = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: loading, refreshFailed: true, at: start.addingTimeInterval(5))
            XCTAssertFalse(failed.isLive)
            XCTAssertEqual(failed.badgeLabel, "Saved")
            XCTAssertTrue(failed.status.contains("last update retained"))
            XCTAssertTrue(try XCTUnwrap(failed.retainedGuidance).contains("reopening guidance"))
            XCTAssertNotNil(snapshot.rides.first?.estimate, "Keep the saved forecast available with the warning")
        }

        let recovered = DashboardFeedHealth.presentation(parkSelected: true, snapshot: makeSnapshot(sourceOffset: 10, ride: makeRide(status: .down)), isLoading: false, refreshFailed: false, at: start.addingTimeInterval(10))
        XCTAssertTrue(recovered.isLive)
        XCTAssertNil(recovered.retainedGuidance)
    }

    func testFeedHealthExpiresAtFreshnessBoundaryWithoutAnotherResponse() {
        let snapshot = makeSnapshot(sourceOffset: 0, ride: makeRide(status: .open))
        for age in [DashboardFeedHealth.maximumAge - 1, DashboardFeedHealth.maximumAge, DashboardFeedHealth.maximumAge + 1] {
            let health = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: false, at: start.addingTimeInterval(age))
            XCTAssertEqual(health.isLive, age < DashboardFeedHealth.maximumAge)
            XCTAssertEqual(health.retainedGuidance == nil, health.isLive)
            if !health.isLive { XCTAssertEqual(health.badgeLabel, "Saved") }
        }
    }

    func testFeedHealthChecksProviderFetchAgeAndRetainedCacheFlag() {
        for provider in [
            makeThemeParksWikiSummary(available: false),
            makeThemeParksWikiSummary(cacheStale: true),
            makeThemeParksWikiSummary(fetchedAt: start.addingTimeInterval(-DashboardFeedHealth.maximumAge)),
        ] {
            let snapshot = makeSnapshot(sourceOffset: 0, themeParksWiki: provider, ride: makeRide(status: .down))
            let health = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: false, at: start)
            XCTAssertFalse(health.isLive)
            XCTAssertEqual(health.badgeLabel, "Saved")
            XCTAssertNotNil(health.retainedGuidance)
        }
    }

    func testFeedHealthDoesNotConfuseOldSourceVersionWithOldFetch() {
        let snapshot = makeSnapshot(sourceOffset: 0, waitStatusSourceOffset: -3600, themeParksWiki: makeThemeParksWikiSummary(), ride: makeRide(status: .down))
        let health = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: false, at: start)
        XCTAssertTrue(health.isLive, "An unchanged closure is allowed when the provider was freshly checked")
        XCTAssertNil(health.retainedGuidance)
    }

    func testFeedHealthRejectsUnhealthyAndFutureDatedSnapshots() {
        for snapshot in [
            makeSnapshot(sourceOffset: 0, feedHealthy: false, ride: makeRide(status: .open)),
            makeSnapshot(sourceOffset: 121, ride: makeRide(status: .open)),
        ] {
            let health = DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false, refreshFailed: false, at: start)
            XCTAssertFalse(health.isLive)
            XCTAssertNotNil(health.retainedGuidance)
        }
    }

    func testFeedHealthHandlesPausedLoadingAndMissingSnapshotFailures() {
        let paused = DashboardFeedHealth.presentation(parkSelected: false, snapshot: makeSnapshot(sourceOffset: 0, ride: makeRide(status: .open)), isLoading: false, refreshFailed: true, at: start)
        XCTAssertFalse(paused.isLive)
        XCTAssertEqual(paused.status, "Paused · choose a park")
        XCTAssertNil(paused.retainedGuidance)
        let loading = DashboardFeedHealth.presentation(parkSelected: true, snapshot: nil, isLoading: true, refreshFailed: false, at: start)
        XCTAssertFalse(loading.isLive)
        XCTAssertEqual(loading.status, "Refreshing")
        XCTAssertNil(loading.retainedGuidance)
        let failed = DashboardFeedHealth.presentation(parkSelected: true, snapshot: nil, isLoading: false, refreshFailed: true, at: start)
        XCTAssertFalse(failed.isLive)
        XCTAssertEqual(failed.status, "Refresh failed")
        XCTAssertNil(failed.retainedGuidance)
    }

    func testParkHoursExpireAtParkLocalMidnightNotDeviceOrUTCMidnight() throws {
        let formatter = ISO8601DateFormatter()
        let beforeEasternMidnight = try XCTUnwrap(formatter.date(from: "2026-09-30T03:59:59Z"))
        let easternMidnight = beforeEasternMidnight.addingTimeInterval(1)
        let easternHours = makeParkHours(date: "2026-09-29")
        let pacificHours = makeParkHours(park: .sixFlagsMagicMountain, date: "2026-09-29")
        XCTAssertTrue(easternHours.isCurrent(for: .magicKingdom, at: beforeEasternMidnight))
        XCTAssertFalse(easternHours.isCurrent(for: .magicKingdom, at: easternMidnight))
        XCTAssertTrue(pacificHours.isCurrent(for: .sixFlagsMagicMountain, at: easternMidnight))
        XCTAssertFalse(pacificHours.isCurrent(for: .sixFlagsMagicMountain, at: easternMidnight.addingTimeInterval(3 * 3600)))
        XCTAssertEqual(ParkHoursSnapshot.localDate(for: .magicKingdom, at: easternMidnight), "2026-09-30")
        XCTAssertEqual(ParkHoursSnapshot.localDate(for: .sixFlagsMagicMountain, at: easternMidnight), "2026-09-29")
    }

    func testParkHoursUseDaylightSavingAndYearBoundaries() throws {
        let formatter = ISO8601DateFormatter()
        for timestamp in ["2026-03-09T04:00:00Z", "2026-11-02T05:00:00Z", "2027-01-01T05:00:00Z"] {
            let midnight = try XCTUnwrap(formatter.date(from: timestamp))
            let date = ParkHoursSnapshot.localDate(for: .magicKingdom, at: midnight.addingTimeInterval(-1))
            let hours = makeParkHours(date: date)
            XCTAssertTrue(hours.isCurrent(for: .magicKingdom, at: midnight.addingTimeInterval(-1)))
            XCTAssertFalse(hours.isCurrent(for: .magicKingdom, at: midnight))
        }
    }

    func testParkHoursRejectWrongParkYesterdayAndTomorrowAndFindCurrentCache() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T16:00:00Z"))
        let yesterday = makeParkHours(date: "2026-09-29")
        let tomorrow = makeParkHours(date: "2026-10-01")
        let wrongPark = makeParkHours(park: .epcot)
        let current = makeParkHours(fetchedAt: now)
        XCTAssertNil(ParkHoursSnapshot.current(for: .magicKingdom, candidates: [nil, yesterday, tomorrow, wrongPark], at: now))
        let selected = try XCTUnwrap(ParkHoursSnapshot.current(for: .magicKingdom, candidates: [yesterday, current, wrongPark], at: now))
        XCTAssertEqual(selected.date, "2026-09-30")
        XCTAssertEqual(selected.fetchedAt, now)
    }

    func testParkHoursPreferFreshThenNewestButRetainCurrentDayStaleFallback() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T16:00:00Z"))
        let old = makeParkHours(fetchedAt: now.addingTimeInterval(-120))
        let recent = makeParkHours(fetchedAt: now.addingTimeInterval(-60))
        let stale = makeParkHours(fetchedAt: now, stale: true)
        for candidates in [[old, stale, recent], [recent, old, stale]] {
            let selected = try XCTUnwrap(ParkHoursSnapshot.current(for: .magicKingdom, candidates: candidates.map { Optional($0) }, at: now))
            XCTAssertFalse(selected.stale)
            XCTAssertEqual(selected.fetchedAt, recent.fetchedAt)
        }
        XCTAssertTrue(try XCTUnwrap(ParkHoursSnapshot.current(for: .magicKingdom, candidates: [stale], at: now)).stale)
    }

    func testHorrorNightSwitchesAtSixAndRemainsActiveAfterMidnight() throws {
        let formatter = ISO8601DateFormatter()
        let night = HorrorNight(date: "2026-09-26", modeStartsAt: try XCTUnwrap(formatter.date(from: "2026-09-26T22:00:00Z")), openingTime: try XCTUnwrap(formatter.date(from: "2026-09-26T22:30:00Z")), closingTime: try XCTUnwrap(formatter.date(from: "2026-09-27T06:00:00Z")))
        XCTAssertFalse(night.isActive(at: night.modeStartsAt.addingTimeInterval(-1)))
        XCTAssertTrue(night.isActive(at: night.modeStartsAt))
        XCTAssertTrue(night.isActive(at: night.closingTime.addingTimeInterval(-1)))
        XCTAssertFalse(night.isActive(at: night.closingTime))
        let stale = HorrorNightSnapshot(night: night, scheduleCheckedAt: night.modeStartsAt.addingTimeInterval(-37 * 3600), fetchedAt: night.modeStartsAt, houses: [])
        XCTAssertFalse(stale.isActive(at: night.modeStartsAt))
    }

    func testRidePhotoDecodesWithAttributionAndOldRecordsRemainCompatible() throws {
        let payload = #"{"reviewedAt":"2026-09-06","photo":{"url":"https://upload.wikimedia.org/test.jpg","sourceURL":"https://commons.wikimedia.org/wiki/File:Test.jpg","credit":"Photographer","license":"CC BY 2.0","licenseURL":"https://creativecommons.org/licenses/by/2.0/","alt":"Ride train"},"facts":[],"sources":[],"unverified":[],"riderNote":"Check posted restrictions."}"#
        let details = try JSONDecoder().decode(RideDetails.self, from: Data(payload.utf8))
        XCTAssertEqual(details.photo?.credit, "Photographer")
        XCTAssertEqual(details.photo?.alt, "Ride train")
        XCTAssertEqual(details.photo?.licenseURL.host, "creativecommons.org")
    }

    func testExpandedParkRideInformationSupportsPartialFacts() throws {
        let payload = #"{"reviewedAt":"2026-09-06","facts":[],"sources":[{"id":"operator","label":"Official ride information","url":"https://www.sixflags.com/cedarpoint/attractions/sky-ride"}],"unverified":["Ride height","Top speed","Manufacturer"],"riderNote":"Check posted restrictions."}"#
        let details = try JSONDecoder().decode(RideDetails.self, from: Data(payload.utf8))
        XCTAssertTrue(details.facts.isEmpty)
        XCTAssertEqual(details.unverified.count, 3)
        XCTAssertEqual(details.sources.first?.url.host, "www.sixflags.com")
    }

    func testRideDetailsDecodeWithoutChangingLiveStatus() throws {
        var ride = makeRide(status: .down, weatherExposure: "OUTDOOR")
        ride.details = try JSONDecoder().decode(RideDetails.self, from: Data(#"{"reviewedAt":"2026-09-06","facts":[{"id":"height","label":"Ride height","value":"110 ft","sourceId":"specs"}],"sources":[{"id":"specs","label":"RCDB","url":"https://rcdb.com/557.htm"}],"unverified":[],"riderNote":"Check posted restrictions."}"#.utf8))
        let decoded = try JSONDecoder().decode(LiveRide.self, from: JSONEncoder().encode(ride))
        XCTAssertEqual(decoded.details?.facts.first?.value, "110 ft")
        XCTAssertEqual(decoded.details?.sources.first?.url.host, "rcdb.com")
        XCTAssertEqual(decoded.status, .down)
        XCTAssertEqual(decoded.estimate?.windowEnd, ride.estimate?.windowEnd)
    }

    func testOlderPayloadWithoutRideDetailsStillDecodes() throws {
        let ride = makeRide(status: .open)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ride)) as? [String: Any])
        json.removeValue(forKey: "details")
        let decoded = try JSONDecoder().decode(LiveRide.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.details)
        XCTAssertEqual(decoded.status, .open)
    }

    func testCurrentWeatherHoldIsIndependentOfOriginalBreakdownForecast() throws {
        for name in ["Astro Orbiter", "Big Thunder Mountain Railroad", "Jungle Cruise", "Dumbo the Flying Elephant"] {
            var ride = makeRide(name: name, status: .down, weatherExposure: "OUTDOOR")
            let originalEnd = ride.estimate?.windowEnd
            ride.weatherHoldActive = true
            let decoded = try JSONDecoder().decode(LiveRide.self, from: JSONEncoder().encode(ride))
            XCTAssertEqual(decoded.weatherHoldActive, true)
            XCTAssertTrue(decoded.hasWeatherHold)
            XCTAssertEqual(decoded.downStatusLabel, "Weather delay · lightning hold")
            XCTAssertNotNil(decoded.retainedOperationalWeatherNote)
            XCTAssertEqual(decoded.delayType, "RIDE")
            XCTAssertEqual(decoded.estimate?.estimateKind, "OPERATIONAL")
            XCTAssertEqual(decoded.estimate?.windowEnd, originalEnd)
            XCTAssertEqual(decoded.statusDescription, "Ride delay · lightning nearby")
        }
    }

    func testMissingOrClearedWeatherFlagIsBackwardCompatible() throws {
        let ride = makeRide(status: .down, weatherExposure: "OUTDOOR")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ride)) as? [String: Any])
        json.removeValue(forKey: "weatherHoldActive")
        let decoded = try JSONDecoder().decode(LiveRide.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.weatherHoldActive)
        XCTAssertFalse(decoded.hasWeatherHold)
        XCTAssertEqual(decoded.downStatusLabel, "Temporarily down")
        XCTAssertNil(decoded.retainedOperationalWeatherNote)
        XCTAssertTrue(makeRide(status: .down, delayType: "WEATHER").hasWeatherHold)
        XCTAssertTrue(makeRide(status: .down, estimateKind: "WEATHER").hasWeatherHold)
    }

    func testCurrentHoldDoesNotOverrideReportedOpenScheduledOrStaleStatus() {
        for status: RideStatus in [.open, .scheduled, .stale, .parkInactive] {
            var ride = makeRide(status: status, weatherExposure: "OUTDOOR")
            ride.weatherHoldActive = true
            XCTAssertFalse(ride.hasWeatherHold)
            XCTAssertEqual(ride.downStatusLabel, "")
            XCTAssertNil(ride.retainedOperationalWeatherNote)
            XCTAssertEqual(ride.status, status)
        }
    }

    func testSortChoicesPersistWithoutChangingOtherPreferences() {
        let suite = "PIVOT-sort-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("purple", forKey: PivotAccent.storageKey)
        defaults.set(6, forKey: "pivot.selectedPark")
        for sort in RideSort.allCases {
            defaults.set(sort.rawValue, forKey: RideSort.storageKey)
            let reloaded = UserDefaults(suiteName: suite)!
            XCTAssertEqual(RideSort(rawValue: reloaded.string(forKey: RideSort.storageKey)!), sort)
            XCTAssertEqual(reloaded.integer(forKey: "pivot.selectedPark"), 6)
            XCTAssertEqual(reloaded.string(forKey: PivotAccent.storageKey), "purple")
        }
    }

    func testAccentChoicesMatchWebsiteAndRejectUnknownPreferences() {
        XCTAssertEqual(PivotAccent.allCases.map(\.rawValue), ["mint", "blue", "purple", "pink", "orange", "gold"])
        XCTAssertEqual(PivotAccent.allCases.map(\.hex), [0x78e3bf, 0x87c7ff, 0xc1a5ff, 0xff9fce, 0xffb477, 0xf2d369])
        XCTAssertEqual(PivotAccent.resolve("unknown"), .mint)
        XCTAssertEqual(PivotAccent.resolve(""), .mint)
        for accent in PivotAccent.allCases { XCTAssertEqual(PivotAccent.resolve(accent.rawValue), accent) }
    }

    func testAccentPreferenceSurvivesReloadWithoutChangingPark() {
        let suite = "PIVOT-accent-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(6, forKey: "pivot.selectedPark")
        defaults.set("purple", forKey: PivotAccent.storageKey)
        let reloaded = UserDefaults(suiteName: suite)!
        XCTAssertEqual(PivotAccent.resolve(reloaded.string(forKey: PivotAccent.storageKey) ?? ""), .purple)
        XCTAssertEqual(reloaded.integer(forKey: "pivot.selectedPark"), 6)
    }

    func testRefreshCadenceAccountsForRequestTimeWithoutOverlappingRequests() {
        XCTAssertEqual(DashboardStore.foregroundRefreshDelay(elapsed: 0), 5)
        XCTAssertEqual(DashboardStore.foregroundRefreshDelay(elapsed: 2), 3)
        XCTAssertEqual(DashboardStore.foregroundRefreshDelay(elapsed: 10), 1)
        XCTAssertEqual(DashboardStore.foregroundRefreshDelay(elapsed: .nan), 5)
    }

    private let start = Date(timeIntervalSince1970: 1_775_320_800) // 2026-04-05 17:00 UTC
    private let best = Date(timeIntervalSince1970: 1_775_321_700)
    private let end = Date(timeIntervalSince1970: 1_775_322_600)

    func testNativeParkCatalogMatchesTheExpandedServerReleaseManifest() {
        XCTAssertEqual(FloridaPark.allCases.map(\.rawValue), [
            5, 6, 7, 8, 21, 24,
            32, 33, 34, 35, 37, 38, 39, 41, 43, 44,
            50, 57, 58, 59, 60, 61, 62, 64, 65, 67, 69,
            281, 282, 295, 334, 339,
        ])
        XCTAssertEqual(FloridaPark.allCases.count, 32)
        XCTAssertEqual(Set(FloridaPark.allCases.map(\.name)).count, 32)
        XCTAssertTrue(FloridaPark.allCases.allSatisfy { !$0.destination.isEmpty && !$0.portfolioName.isEmpty })
        XCTAssertTrue(FloridaPark.allCases.allSatisfy { TimeZone(identifier: $0.timeZoneIdentifier) != nil })
        XCTAssertEqual(ParkLocationDetector.coordinates.count, FloridaPark.allCases.count)
        for park in FloridaPark.allCases {
            let coordinate = try! XCTUnwrap(ParkLocationDetector.coordinates[park])
            XCTAssertEqual(
                ParkLocationDetector.nearestPark(latitude: coordinate.latitude, longitude: coordinate.longitude)?.park,
                park,
                "Location matching must include \(park.name)"
            )
        }
    }

    func testExpandedParkMetadataPreservesPortfolioAndLocalTimeZone() {
        XCTAssertEqual(FloridaPark.seaWorldOrlando.operatorName, "United Parks & Resorts")
        XCTAssertEqual(FloridaPark.buschGardensTampaBay.portfolioName, "United Parks")
        XCTAssertEqual(FloridaPark.cedarPoint.portfolioName, "Legacy Cedar Fair")
        XCTAssertEqual(FloridaPark.sixFlagsMagicMountain.portfolioName, "Legacy Six Flags")
        XCTAssertEqual(FloridaPark.sixFlagsMagicMountain.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(FloridaPark.sixFlagsOverTexas.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(FloridaPark.canadasWonderland.country, "Canada")
    }

    func testExpandedLocationDetectorFindsARegionalParkAtItsCenter() {
        let match = ParkLocationDetector.nearestPark(
            latitude: 41.482612666666675,
            longitude: -82.68423844927537
        )

        XCTAssertEqual(match?.park, .cedarPoint)
        XCTAssertEqual(match?.distanceMiles ?? -1, 0, accuracy: 0.0001)
    }

    func testEverySupportedParkHasAValidEntranceRouteAnchor() throws {
        XCTAssertEqual(ParkEntranceLocations.coordinates.count, FloridaPark.allCases.count)
        for park in FloridaPark.allCases {
            let coordinate = try XCTUnwrap(
                ParkEntranceLocations.coordinates[park],
                "Missing entrance route anchor for \(park.name)"
            )
            XCTAssertTrue(coordinate.latitude.isFinite)
            XCTAssertTrue(coordinate.longitude.isFinite)
            XCTAssertTrue((-90...90).contains(coordinate.latitude))
            XCTAssertTrue((-180...180).contains(coordinate.longitude))
        }

        let magicKingdom = try XCTUnwrap(ParkEntranceLocations.coordinates[.magicKingdom])
        XCTAssertEqual(magicKingdom.latitude, 28.4160036778, accuracy: 0.0000000001)
        XCTAssertEqual(magicKingdom.longitude, -81.5811902834, accuracy: 0.0000000001)
    }

    func testDayPlannerUsesCoordinatesAndKeepsClosedRidesOutOfTheRoute() throws {
        let center = AttractionLocation(latitude: 28.4177, longitude: -81.5812)
        let nearby = makeRide(
            id: 1,
            name: "Nearby Ride",
            status: .open,
            waitTime: 20,
            trend: [35, 40, 45],
            location: AttractionLocation(latitude: 28.4180, longitude: -81.5810)
        )
        let distant = makeRide(
            id: 2,
            name: "Distant Ride",
            status: .open,
            waitTime: 20,
            trend: [35, 40, 45],
            location: AttractionLocation(latitude: 28.4060, longitude: -81.5700)
        )
        let closed = makeRide(
            id: 3,
            name: "Closed Ride",
            status: .down,
            location: AttractionLocation(latitude: 28.4178, longitude: -81.5811)
        )
        let plan = DayPlanner.build(
            rides: [distant, closed, nearby],
            requestedRideIDs: [nearby.id, distant.id, closed.id],
            startAt: start,
            endAt: start.addingTimeInterval(3 * 60 * 60),
            now: start.addingTimeInterval(-60),
            startLocation: center
        )

        XCTAssertEqual(try XCTUnwrap(plan.stops.first).rideName, "Nearby Ride")
        XCTAssertFalse(plan.stops.contains { $0.rideName == "Closed Ride" })
        XCTAssertLessThanOrEqual(plan.stops.last?.completeAt ?? .distantFuture, plan.endAt)
        XCTAssertEqual(plan.eligibleRideCount, 2)
        XCTAssertEqual(plan.locatedRideCount, 2)
        XCTAssertEqual(plan.unavailableRides.map(\.rideName), ["Closed Ride"])
    }

    func testDayPlannerAlwaysStartsWithTheNearestLocatedRideToTheEntrance() throws {
        let entrance = AttractionLocation(latitude: 28, longitude: -81)
        let closest = makeRide(
            id: 31,
            name: "Closest High Wait Ride",
            status: .open,
            waitTime: 60,
            trend: [10, 10, 10],
            location: AttractionLocation(latitude: 28, longitude: -81.001)
        )
        let farther = makeRide(
            id: 32,
            name: "Farther Low Wait Ride",
            status: .open,
            waitTime: 5,
            trend: [90, 90, 90],
            location: AttractionLocation(latitude: 28, longitude: -81.01)
        )
        let plan = DayPlanner.build(
            rides: [farther, closest],
            requestedRideIDs: [closest.id, farther.id],
            startAt: start,
            endAt: start.addingTimeInterval(3 * 60 * 60),
            now: start,
            startLocation: entrance
        )

        XCTAssertEqual(try XCTUnwrap(plan.stops.first).rideName, closest.name)
    }

    func testDayPlannerPrefersALocatedRideOverMissingLocationForTheFirstLeg() throws {
        let entrance = AttractionLocation(latitude: 28, longitude: -81)
        let located = makeRide(
            id: 33,
            name: "Located Ride",
            status: .open,
            waitTime: 50,
            trend: [10, 10, 10],
            location: AttractionLocation(latitude: 28, longitude: -81.005)
        )
        let missingLocation = makeRide(
            id: 34,
            name: "Unknown Location Ride",
            status: .open,
            waitTime: 0,
            trend: [100, 100, 100],
            location: nil
        )
        let plan = DayPlanner.build(
            rides: [missingLocation, located],
            requestedRideIDs: [located.id, missingLocation.id],
            startAt: start,
            endAt: start.addingTimeInterval(3 * 60 * 60),
            now: start,
            startLocation: entrance
        )

        XCTAssertEqual(try XCTUnwrap(plan.stops.first).rideName, located.name)
    }

    func testDayPlannerMovesAPastStartToNowWithoutExtendingDeparture() {
        let ride = makeRide(
            id: 4,
            name: "Current Ride",
            status: .open,
            waitTime: 10,
            location: AttractionLocation(latitude: 28.4180, longitude: -81.5810)
        )
        let now = start.addingTimeInterval(45 * 60)
        let end = start.addingTimeInterval(2 * 60 * 60)
        let plan = DayPlanner.build(
            rides: [ride],
            requestedRideIDs: [ride.id],
            startAt: start,
            endAt: end,
            now: now,
            startLocation: nil
        )

        XCTAssertEqual(plan.effectiveStartAt, now)
        XCTAssertTrue(plan.startsFromNow)
        XCTAssertLessThanOrEqual(plan.stops.last?.completeAt ?? .distantFuture, end)
    }

    func testDayPlannerKeepsAFutureRequestedStart() {
        let ride = makeRide(id: 40, name: "Future Ride", status: .open, waitTime: 15)
        let futureStart = start.addingTimeInterval(60 * 60)
        let plan = DayPlanner.build(
            rides: [ride],
            requestedRideIDs: [ride.id],
            startAt: futureStart,
            endAt: futureStart.addingTimeInterval(2 * 60 * 60),
            now: start,
            startLocation: nil
        )

        XCTAssertEqual(plan.effectiveStartAt, futureStart)
        XCTAssertFalse(plan.startsFromNow)
    }

    func testDayPlannerNeverAddsAnUnselectedLowPriorityRide() {
        let favorite = makeRide(id: 5, name: "Favorite Coaster", status: .open, waitTime: 35)
        let unselected = makeRide(id: 6, name: "Unselected Kiddie Ride", status: .open, waitTime: 0)
        let plan = DayPlanner.build(
            rides: [favorite, unselected],
            requestedRideIDs: [favorite.id],
            startAt: start,
            endAt: start.addingTimeInterval(2 * 60 * 60),
            now: start,
            startLocation: nil
        )

        XCTAssertEqual(plan.stops.map(\.rideName), ["Favorite Coaster"])
        XCTAssertTrue(plan.fitsAllRequested)
    }

    func testDayPlannerReturnsSpecificCutsWhenFavoritesDoNotFit() {
        let first = makeRide(id: 7, name: "Long Favorite", status: .open, waitTime: 60, trend: [80, 80, 80])
        let second = makeRide(id: 8, name: "Second Favorite", status: .open, waitTime: 55, trend: [70, 70, 70])
        let third = makeRide(id: 9, name: "Third Favorite", status: .open, waitTime: 45, trend: [60, 60, 60])
        let plan = DayPlanner.build(
            rides: [first, second, third],
            requestedRideIDs: [first.id, second.id, third.id],
            startAt: start,
            endAt: start.addingTimeInterval(90 * 60),
            now: start,
            startLocation: nil
        )

        XCTAssertFalse(plan.fitsAllRequested)
        XCTAssertFalse(plan.cutRides.isEmpty)
        XCTAssertEqual(plan.stops.count + plan.cutRides.count, 3)
        XCTAssertLessThanOrEqual(plan.stops.last?.completeAt ?? .distantFuture, plan.endAt)
        XCTAssertGreaterThan(plan.extraMinutesNeeded, 0)
    }

    func testDayPlannerKeepsNineteenFavoritesWhenTheyFitTheVisitWindow() {
        let entrance = AttractionLocation(latitude: 28, longitude: -81)
        let rides = (1...19).map { index in
            makeRide(
                id: 1_000 + index,
                name: "Favorite \(index)",
                status: .open,
                waitTime: 0,
                trend: [0, 0, 0],
                location: AttractionLocation(
                    latitude: 28,
                    longitude: -81 - Double(index) * 0.00001
                )
            )
        }
        let plan = DayPlanner.build(
            rides: rides,
            requestedRideIDs: Set(rides.map(\.id)),
            startAt: start,
            endAt: start.addingTimeInterval(4 * 60 * 60),
            now: start,
            startLocation: entrance
        )

        XCTAssertEqual(plan.stops.count, 19)
        XCTAssertTrue(plan.cutRides.isEmpty)
        XCTAssertTrue(plan.fitsAllRequested)
    }

    func testReopeningForecastCanRenderInTheSelectedParksLocalTime() {
        let estimate = makeEstimate(phase: .upcoming)
        let eastern = estimate.presentation(timeZone: FloridaPark.magicKingdom.timeZone)
        let pacific = estimate.presentation(timeZone: FloridaPark.sixFlagsMagicMountain.timeZone)

        XCTAssertNotEqual(eastern.range, pacific.range)
        XCTAssertEqual(
            pacific.range,
            "\(ParkTimeFormatter.time(estimate.windowStart, timeZone: FloridaPark.sixFlagsMagicMountain.timeZone))–\(ParkTimeFormatter.time(estimate.windowEnd, timeZone: FloridaPark.sixFlagsMagicMountain.timeZone))"
        )
        XCTAssertTrue(pacific.detail.contains("best guess \(pacific.bestGuess)"))
    }

    func testParkLocationDetectorFindsMagicKingdomAtParkCenter() {
        let match = ParkLocationDetector.nearestPark(latitude: 28.4177, longitude: -81.5812)

        XCTAssertEqual(match?.park, .magicKingdom)
        XCTAssertEqual(match?.distanceMiles ?? -1, 0, accuracy: 0.0001)
    }

    func testParkLocationDetectorFindsUniversalStudiosFloridaAtParkCenter() {
        let match = ParkLocationDetector.nearestPark(latitude: 28.4758, longitude: -81.4682)

        XCTAssertEqual(match?.park, .universalStudiosFlorida)
        XCTAssertEqual(match?.distanceMiles ?? -1, 0, accuracy: 0.0001)
    }

    func testParkLocationDetectorRejectsCoordinatesOutsideSupportedParkGeofences() {
        XCTAssertNil(ParkLocationDetector.nearestPark(latitude: 25.7617, longitude: -80.1918))
    }

    func testInWindowForecastKeepsFullWindowAndBestGuess() {
        let estimate = makeEstimate(phase: .inWindow)
        let presentation = estimate.presentation

        XCTAssertEqual(presentation.headline, "Inside predicted window")
        XCTAssertTrue(presentation.detail.contains(presentation.range))
        XCTAssertTrue(presentation.detail.contains("best guess \(presentation.bestGuess)"))
        XCTAssertTrue(presentation.inline.contains(presentation.range))
        XCTAssertTrue(presentation.inline.contains("best guess \(presentation.bestGuess)"))
    }

    func testMissedWindowRevisionClearlyPresentsTheFollowUpRange() {
        let upcoming = makeEstimate(
            phase: .upcoming,
            revision: 1,
            revisionReason: "WINDOW_MISSED"
        ).presentation
        let inWindow = makeEstimate(
            phase: .inWindow,
            revision: 2,
            revisionReason: "WINDOW_MISSED"
        ).presentation
        let missedAgain = makeEstimate(
            phase: .pastWindow,
            revision: 2,
            revisionReason: "WINDOW_MISSED"
        ).presentation

        XCTAssertEqual(upcoming.headline, "Revised reopening window")
        XCTAssertTrue(upcoming.inline.contains(upcoming.range))
        XCTAssertTrue(upcoming.inline.contains("best guess \(upcoming.bestGuess)"))
        XCTAssertEqual(inWindow.headline, "Inside revised window")
        XCTAssertEqual(missedAgain.headline, "Window ended · waiting for a fresh ride update")
        XCTAssertFalse(missedAgain.detail.contains("original"))
    }

    func testMinimumDowntimeUsesClearAtLeastWording() {
        let ride = makeRide(status: .down, minimumDownMinutes: 50)
        let display = ride.downTimePresentation

        XCTAssertEqual(display?.text, "Closed for at least 50 min")
        XCTAssertFalse(display?.text.contains("+") ?? true)
        XCTAssertFalse(display?.text.localizedCaseInsensitiveContains("seen") ?? true)
        XCTAssertTrue(display?.accessibilityLabel.contains("at least 50 min") ?? false)
    }

    func testExactDowntimeUsesClearClosedForWording() {
        let ride = makeRide(status: .down, elapsedDownMinutes: 42, minimumDownMinutes: 50)

        XCTAssertEqual(ride.downTimePresentation?.text, "Closed for 42 min")
    }

    func testDowntimeFormatsHoursAndMinutes() {
        let exact = makeRide(status: .down, elapsedDownMinutes: 125)
        let minimum = makeRide(status: .down, minimumDownMinutes: 60)

        XCTAssertEqual(exact.downTimePresentation?.text, "Closed for 2 hr 5 min")
        XCTAssertEqual(minimum.downTimePresentation?.text, "Closed for at least 1 hr")
    }

    func testMissingDowntimeUsesExplicitUnavailableWording() {
        let ride = makeRide(status: .down)

        XCTAssertEqual(ride.downTimePresentation?.text, "Closed · duration unavailable")
        XCTAssertFalse(ride.downTimePresentation?.text.localizedCaseInsensitiveContains("unknown") ?? true)
    }

    func testStableClosureTimestampOverridesStaleCounterAndAdvancesWithClock() {
        let closedAt = start.addingTimeInterval(-65 * 60)
        let ride = makeRide(
            status: .down,
            downSince: closedAt,
            elapsedDownMinutes: 2
        )

        XCTAssertEqual(
            ride.downTimePresentation(referenceDate: start)?.text,
            "Closed for 1 hr 5 min"
        )
        XCTAssertEqual(
            ride.downTimePresentation(referenceDate: start.addingTimeInterval(60))?.text,
            "Closed for 1 hr 6 min"
        )
    }

    func testRideTransitionsRequireBaselineAndConfirmedReopening() {
        let first = makeSnapshot(sourceOffset: 1, ride: makeRide(status: .open))
        let baselineResult = RideTransitionEngine.evaluate(selectedParkId: 6, previous: nil, current: first)
        XCTAssertTrue(baselineResult.alerts.isEmpty)

        let closed = makeSnapshot(sourceOffset: 2, ride: makeRide(status: .down))
        let closedResult = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: baselineResult.nextBaseline,
            current: closed
        )
        XCTAssertEqual(closedResult.alerts.map(\.kind), [.closed])

        let pendingOpen = makeSnapshot(sourceOffset: 3, ride: makeRide(status: .open, reopenPending: true))
        let pendingResult = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: closedResult.nextBaseline,
            current: pendingOpen
        )
        XCTAssertTrue(pendingResult.alerts.isEmpty)

        let confirmedOpen = makeSnapshot(sourceOffset: 4, ride: makeRide(status: .open))
        let reopenedResult = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: pendingResult.nextBaseline,
            current: confirmedOpen
        )
        XCTAssertEqual(reopenedResult.alerts.map(\.kind), [.reopened])
    }

    func testSameSnapshotFetchCannotReplayWhenProviderTimestampChanges() {
        let baseline = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: nil,
            current: makeSnapshot(
                sourceOffset: 2,
                waitStatusSourceOffset: 2,
                ride: makeRide(status: .open)
            )
        ).nextBaseline

        let repeated = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: baseline,
            current: makeSnapshot(
                sourceOffset: 2,
                waitStatusSourceOffset: 30,
                ride: makeRide(status: .down)
            )
        )

        XCTAssertTrue(repeated.alerts.isEmpty)
        XCTAssertEqual(repeated.nextBaseline, baseline)
    }

    func testScheduledClosureIsDecodedButNeverTreatedAsAnUnexpectedOutage() throws {
        let status = try JSONDecoder().decode(RideStatus.self, from: Data(#""SCHEDULED""#.utf8))
        XCTAssertEqual(status, .scheduled)

        let baseline = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: nil,
            current: makeSnapshot(sourceOffset: 1, ride: makeRide(status: .open))
        ).nextBaseline
        let scheduled = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: baseline,
            current: makeSnapshot(sourceOffset: 2, ride: makeRide(status: .scheduled))
        )

        XCTAssertTrue(scheduled.alerts.isEmpty)
        XCTAssertEqual(
            makeRide(status: .scheduled).statusDescription,
            "ThemeParks.wiki reports closed"
        )
    }

    func testAttractionOperatingWindowIsShownAsScheduledHours() {
        let window = AttractionOperatingWindow(
            state: "BEFORE_OPEN",
            openingTime: "10:00 AM",
            closingTime: nil,
            label: "Opens around 10:00 AM",
            source: "PIVOT_SCHEDULE_HINT",
            confidence: "HIGH",
            observedDays: 0
        )
        let ride = makeRide(status: .scheduled, operatingWindow: window)
        XCTAssertEqual(ride.statusDescription, "Opens around 10:00 AM")
    }

    func testProviderClosureAndConflictWordingRemainDistinct() {
        XCTAssertEqual(
            makeRide(status: .scheduled, scheduledReason: "CLOSED").statusDescription,
            "ThemeParks.wiki reports closed"
        )
        XCTAssertEqual(
            makeRide(status: .scheduled, scheduledReason: "REFURBISHMENT").statusDescription,
            "ThemeParks.wiki reports refurbishment"
        )
        XCTAssertEqual(
            makeRide(status: .stale, statusAgreement: "CONFLICT").statusDescription,
            "Status update pending · checking the newest source"
        )
        XCTAssertTrue(makeRide(status: .stale).statusDescription.hasPrefix("Source updated "))
    }

    func testForegroundRefreshAndOpenRideCopyUseThemeParksWiki() {
        XCTAssertEqual(DashboardStore.foregroundRefreshIntervalSeconds, 5)
        XCTAssertEqual(
            makeRide(status: .open, waitTime: 25).statusDescription,
            "ThemeParks.wiki reports open"
        )
        XCTAssertEqual(
            makeRide(status: .open, waitTime: 0).statusDescription,
            "Walk-on reported · ThemeParks.wiki"
        )
        XCTAssertEqual(
            makeRide(status: .open, waitTime: nil).statusDescription,
            "ThemeParks.wiki reports open · wait not recently posted"
        )
    }

    func testGlmDetectionClockDecodesWithoutLosingSourceMetadata() throws {
        let json = #"""
        {"status":"LIVE","sourceKind":"GLM","densityDetectedAt":[],"parkCoordinateDensityDetectedAt":[],"sampleRadiusMiles":5,"periodsDetected30Minutes":1,"coverageMinutes":1,"url":"https://nowcoast.noaa.gov/","glm":{"satellite":19,"status":"LIVE","lastDetectedAt":"2026-09-04T22:00:10.123Z","targetAt":"2026-09-04T22:30:10.123Z","observedThrough":"2026-09-04T22:01:00.000Z","state":"COUNTDOWN","clearMinutes":0,"boundaryUncertain":false}}
        """#
        let lightning = try PivotAPIClient.makeDecoder().decode(LightningDetails.self, from: Data(json.utf8))
        XCTAssertEqual(lightning.sourceKind, "GLM")
        let glm = try XCTUnwrap(lightning.glm)
        XCTAssertEqual(try XCTUnwrap(glm.targetAt).timeIntervalSince(try XCTUnwrap(glm.lastDetectedAt)), 1800, accuracy: 0.001)
        XCTAssertTrue(ParkTimeFormatter.observationTime(glm.lastDetectedAt, timeZone: TimeZone(secondsFromGMT: 0)).contains(":00:10"))
    }

    func testLaterLightningConstraintDoesNotRewriteTheRideClosureOrigin() {
        let evidence = makeDelayEvidence(closureTimingMatched: false)
        let ride = makeRide(
            status: .down,
            estimateKind: "WEATHER",
            delayType: "WEATHER",
            delayEvidence: evidence,
            weatherExposure: "OUTDOOR",
            forecastRevision: 1,
            forecastRevisionReason: "NEW_LIGHTNING"
        )

        XCTAssertTrue(ride.isPostOperationalWeatherConstraint)
        XCTAssertEqual(ride.statusDescription, "Ride delay · reopening now limited by lightning")
        XCTAssertEqual(ride.estimate?.estimateKind, "WEATHER")
        XCTAssertEqual(ride.delayEvidence?.closureTimingMatched, false)
        XCTAssertEqual(evidence.rideWeatherClearanceDescription, "Lightning clear clock reset")
    }

    func testRadarClosureWaveCopyDoesNotClaimVerifiedLightning() {
        let evidence = makeDelayEvidence(
            weatherOriginSignal: "RADAR_CLOSURE_WAVE",
            closureWaveUnknownRideCount: 1,
            clearanceState: "UNKNOWN"
        )

        XCTAssertEqual(
            evidence.rideWeatherClearanceDescription,
            "Provisional radar/NWS weather range · no verified strike"
        )
        XCTAssertEqual(evidence.closureWaveUnknownRideCount, 1)
        XCTAssertEqual(
            evidence.closureWaveOpenNonVetoDescription,
            "One contradictory OPEN row did not veto the park signal; its raw provider status was not overridden."
        )
    }

    func testRadarFallbackRejectedRevisionExplainsOperationalReplacement() throws {
        let estimate = makeEstimate(
            phase: .upcoming,
            revision: 1,
            revisionReason: "RADAR_FALLBACK_REJECTED"
        )
        let description = try XCTUnwrap(estimate.radarFallbackRejectedRevisionDescription)

        XCTAssertTrue(description.contains(
            "NOAA covering evidence rejected provisional park-weather classification, so a new operational estimate replaced it."
        ))
        XCTAssertNil(makeEstimate(phase: .upcoming).radarFallbackRejectedRevisionDescription)
    }

    func testReviewedRefurbishmentShowsOperatorAndExpectedReopenDate() {
        let closure = ScheduledClosure(
            parkId: 64,
            rideId: 5994,
            rideName: "Jurassic Park River Adventure",
            startsAt: Self.isoDate("2026-01-05T05:00:00.000Z"),
            expectedReopenAt: Self.isoDate("2026-11-20T05:00:00.000Z"),
            source: ScheduledClosureSource(
                name: "Universal Orlando",
                url: "https://www.universalorlando.com/web/en/us/things-to-do/rides-attractions/jurassic-park-river-adventure",
                verifiedAt: Self.isoDate("2026-08-03T00:00:00.000Z")
            ),
            reason: "REFURBISHMENT"
        )
        let ride = makeRide(status: .scheduled, scheduledReason: "REFURBISHMENT", scheduledClosure: closure)

        XCTAssertEqual(ride.statusDescription, "Universal Orlando lists refurbishment")
        XCTAssertEqual(ride.scheduledClosure?.expectedReopenAt, Self.isoDate("2026-11-20T05:00:00.000Z"))
    }

    func testOpenToStaleToDownRetainsOpenAndEmitsEventualClosure() {
        let open = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: nil,
            current: makeSnapshot(sourceOffset: 1, ride: makeRide(status: .open))
        )
        let stale = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: open.nextBaseline,
            current: makeSnapshot(sourceOffset: 2, ride: makeRide(status: .stale))
        )

        XCTAssertTrue(stale.alerts.isEmpty)
        XCTAssertEqual(stale.nextBaseline?.rides[126]?.status, .open)

        let down = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: stale.nextBaseline,
            current: makeSnapshot(sourceOffset: 3, ride: makeRide(status: .down))
        )
        XCTAssertEqual(down.alerts.map(\.kind), [.closed])
    }

    func testDownToScheduledOrStaleToOpenRetainsDownAndEmitsEventualReopening() {
        for nonActionableStatus in [RideStatus.scheduled, .stale] {
            let down = RideTransitionEngine.evaluate(
                selectedParkId: 6,
                previous: nil,
                current: makeSnapshot(sourceOffset: 1, ride: makeRide(status: .down))
            )
            let intermediate = RideTransitionEngine.evaluate(
                selectedParkId: 6,
                previous: down.nextBaseline,
                current: makeSnapshot(
                    sourceOffset: 2,
                    ride: makeRide(status: nonActionableStatus, radarEligible: false)
                )
            )

            XCTAssertTrue(intermediate.alerts.isEmpty)
            XCTAssertEqual(intermediate.nextBaseline?.rides[126]?.status, .down)
            XCTAssertEqual(intermediate.nextBaseline?.rides[126]?.radarEligible, true)

            let open = RideTransitionEngine.evaluate(
                selectedParkId: 6,
                previous: intermediate.nextBaseline,
                current: makeSnapshot(sourceOffset: 3, ride: makeRide(status: .open))
            )
            XCTAssertEqual(open.alerts.map(\.kind), [.reopened])
        }
    }

    func testDateDecoderAcceptsFractionalZAndOffsetDates() throws {
        struct Dates: Decodable {
            let fractional: Date
            let offset: Date
        }
        let json = #"{"fractional":"2026-08-02T14:37:43.154Z","offset":"2026-08-02T14:25:00+00:00"}"#
        let dates = try PivotAPIClient.makeDecoder().decode(Dates.self, from: Data(json.utf8))

        XCTAssertEqual(dates.fractional.timeIntervalSince(dates.offset), 763.154, accuracy: 0.001)
    }

    func testSnapshotDecodesBourneAndItsFullDailyScheduleSource() throws {
        let snapshot = try makeShowSnapshot(
            shows: [Self.bourneShowJSON],
            sourceWarning: nil
        )
        let bourne = try XCTUnwrap(snapshot.showList.first)

        XCTAssertEqual(bourne.name, "The Bourne Stuntacular")
        XCTAssertEqual(bourne.showtimes.count, 3)
        XCTAssertEqual(bourne.showtimes.map(\.startTime), [
            Self.isoDate("2026-08-03T15:15:00.000Z"),
            Self.isoDate("2026-08-03T16:00:00.000Z"),
            Self.isoDate("2026-08-03T17:00:00.000Z")
        ])
        XCTAssertEqual(snapshot.nextShowName, "The Bourne Stuntacular")
        XCTAssertEqual(snapshot.nextShowAt, Self.isoDate("2026-08-03T15:15:00.000Z"))
        XCTAssertEqual(snapshot.showsSource?.name, "Universal Orlando Resort")
        XCTAssertEqual(snapshot.showsSource?.scheduleDate, "2026-08-03")
        XCTAssertEqual(snapshot.showsSource?.updateCadenceMinutes, 5)
        XCTAssertFalse(snapshot.showsSource?.stale ?? true)
        XCTAssertEqual(snapshot.showScheduleSourceLabel, "Schedule data from Universal Orlando Resort")
        XCTAssertTrue(bourne.dailyScheduleText.contains("11:15"))
        XCTAssertTrue(bourne.dailyScheduleText.contains("12:00"))
        XCTAssertTrue(bourne.dailyScheduleText.contains("1:00"))
        XCTAssertEqual(bourne.dailyScheduleText.filter { $0 == "·" }.count, 2)
    }

    func testShowSchedulePresentationDistinguishesUpcomingFinishedEmptyAndUnavailable() throws {
        let bourneSnapshot = try makeShowSnapshot(
            shows: [Self.bourneShowJSON],
            sourceWarning: nil
        )
        let upcoming = bourneSnapshot.showSchedulePresentation(
            referenceDate: Self.isoDate("2026-08-03T15:30:00.000Z")
        )
        let finished = bourneSnapshot.showSchedulePresentation(
            referenceDate: Self.isoDate("2026-08-03T18:00:00.000Z")
        )
        let noSchedule = try makeShowSnapshot(shows: [], sourceWarning: nil)
            .showSchedulePresentation(referenceDate: Self.isoDate("2026-08-03T15:30:00.000Z"))
        let unavailable = try makeShowSnapshot(
            shows: [],
            sourceWarning: "Daily schedule provider did not respond"
        ).showSchedulePresentation(referenceDate: Self.isoDate("2026-08-03T15:30:00.000Z"))

        XCTAssertEqual(upcoming.state, .upcoming)
        XCTAssertEqual(upcoming.headline, "The Bourne Stuntacular")
        XCTAssertEqual(upcoming.nextShowAt, Self.isoDate("2026-08-03T16:00:00.000Z"))
        XCTAssertEqual(upcoming.upcomingShowCount, 1)
        XCTAssertEqual(finished.state, .finishedForToday)
        XCTAssertEqual(finished.headline, "Finished for today")
        XCTAssertEqual(noSchedule.state, .noScheduledPerformances)
        XCTAssertEqual(noSchedule.headline, "No scheduled performances today")
        XCTAssertEqual(unavailable.state, .providerUnavailable)
        XCTAssertEqual(unavailable.detail, "Daily schedule provider did not respond")
    }

    func testShowScheduleRowPresentationMatchesCompactWebsiteLabels() throws {
        let snapshot = try makeShowSnapshot(
            shows: [Self.bourneShowJSON, Self.untimedShowJSON],
            sourceWarning: nil
        )
        let bourne = try XCTUnwrap(snapshot.showList.first)
        let upcoming = ShowScheduleRowFormatter.presentation(
            for: bourne,
            referenceDate: Self.isoDate("2026-08-03T15:30:00.000Z")
        )
        let finished = ShowScheduleRowFormatter.presentation(
            for: bourne,
            referenceDate: Self.isoDate("2026-08-03T18:00:00.000Z")
        )
        let untimed = ShowScheduleRowFormatter.presentation(
            for: try XCTUnwrap(snapshot.showList.last),
            referenceDate: Self.isoDate("2026-08-03T15:30:00.000Z")
        )
        let operating = LiveShowtime(
            type: "Operating",
            startTime: Self.isoDate("2026-08-03T15:00:00.000Z"),
            endTime: Self.isoDate("2026-08-03T16:00:00.000Z")
        )
        let meridiemSpace = "\u{202F}"

        XCTAssertEqual(upcoming.statusLabel, "Next 12:00\(meridiemSpace)PM")
        XCTAssertEqual(upcoming.countLabel, "3 times")
        XCTAssertEqual(finished.statusLabel, "Finished for today")
        XCTAssertEqual(untimed.statusLabel, "Time not posted today")
        XCTAssertEqual(untimed.countLabel, "Schedule")
        XCTAssertEqual(
            ShowScheduleRowFormatter.pillLabel(for: bourne.sortedShowtimes[0]),
            "11:15\(meridiemSpace)AM"
        )
        XCTAssertEqual(
            ShowScheduleRowFormatter.pillLabel(for: operating),
            "Available 11:00\(meridiemSpace)AM–12:00\(meridiemSpace)PM"
        )
        XCTAssertEqual(
            ShowScheduleRowFormatter.accessibilityLabel(for: operating),
            "Available from 11:00\(meridiemSpace)AM to 12:00\(meridiemSpace)PM"
        )
    }

    func testAllPublishedEntertainmentEntriesRemainAvailableForDisplay() throws {
        let snapshot = try makeShowSnapshot(
            shows: [
                Self.starlightShowJSON,
                Self.happilyEverAfterShowJSON,
                Self.untimedShowJSON
            ],
            sourceWarning: nil
        )

        XCTAssertEqual(snapshot.showList.map(\.name), [
            "Disney Starlight: Dream the Night Away",
            "Happily Ever After",
            "Untimed entertainment"
        ])
        XCTAssertEqual(snapshot.showList.last?.dailyScheduleText, "No timed performances published")
    }

    func testProductionV6SnapshotContractDecodesProviderAndLearningMetadata() throws {
        let data = Data(Self.productionV6SnapshotJSON.utf8)
        let snapshot = try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: data)
        let ride = try XCTUnwrap(snapshot.rides.first)
        let estimate = try XCTUnwrap(ride.estimate)
        let aggregatePrior = try XCTUnwrap(estimate.aggregateReliabilityPrior)

        XCTAssertEqual(snapshot.parkId, FloridaPark.magicKingdom.rawValue)
        XCTAssertEqual(snapshot.metrics.scheduledCount, 0)
        XCTAssertEqual(snapshot.queueTimesUpdatedAt, Self.isoDate("2026-08-03T01:55:23.000Z"))
        XCTAssertEqual(snapshot.themeParksWikiUpdatedAt, Self.isoDate("2026-08-03T01:56:14.012Z"))
        XCTAssertEqual(snapshot.waitStatusUpdatedAt, Self.isoDate("2026-08-03T01:56:14.012Z"))
        XCTAssertEqual(snapshot.themeParksWiki?.matchedRideCount, 1)
        XCTAssertEqual(ride.themeParksWikiStatus?.status, "DOWN")
        XCTAssertEqual(ride.statusAgreement, "AGREES")
        XCTAssertEqual(ride.statusProvenance, "QUEUE_TIMES_CONFIRMED_BY_THEMEPARKS_WIKI")
        XCTAssertEqual(ride.statusComparisonReason, "AGREEMENT")
        XCTAssertEqual(estimate.modelVersion, "PIVOT Ride Recovery v6")
        XCTAssertEqual(estimate.sameRideSampleSize, 4)
        XCTAssertEqual(estimate.sameRideCensoredSampleSize, 1)
        XCTAssertEqual(estimate.survivalEstimator, "weighted Kaplan-Meier with empirical-Bayes prior")
        XCTAssertEqual(estimate.calibration?.version, "PIVOT-ONLINE-CALIBRATION-v1")
        XCTAssertEqual(estimate.calibration?.basis, "same-ride residuals")
        XCTAssertEqual(estimate.historyProvenance?.confirmedTransitionCount, 18)
        XCTAssertEqual(estimate.historicalPrior?.basis, "none")
        XCTAssertTrue(aggregatePrior.applied)
        XCTAssertEqual(aggregatePrior.availabilityPercent, 96.5)
        XCTAssertFalse(aggregatePrior.eventLevel)
        XCTAssertEqual(aggregatePrior.evidenceCount, 0)
        XCTAssertFalse(aggregatePrior.evidenceAccounting.countsAsObservedOutage)
        XCTAssertEqual(aggregatePrior.evidenceAccounting.sampleSizeContribution, 0)
    }

    func testWindowMissedRevisionDecodesWithoutANewForecastPhase() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.productionV6SnapshotJSON.utf8)) as? [String: Any]
        )
        var rides = try XCTUnwrap(json["rides"] as? [[String: Any]])
        var ride = try XCTUnwrap(rides.first)
        var estimate = try XCTUnwrap(ride["estimate"] as? [String: Any])
        estimate["forecastPhase"] = "UPCOMING"
        estimate["revision"] = 1
        estimate["revisionReason"] = "WINDOW_MISSED"
        ride["estimate"] = estimate
        rides[0] = ride
        json["rides"] = rides

        let data = try JSONSerialization.data(withJSONObject: json)
        let snapshot = try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: data)
        let decoded = try XCTUnwrap(snapshot.rides.first?.estimate)

        XCTAssertEqual(decoded.forecastPhase, .upcoming)
        XCTAssertEqual(decoded.revision, 1)
        XCTAssertEqual(decoded.revisionReason, "WINDOW_MISSED")
        XCTAssertTrue(decoded.isMissedWindowRevision)
    }

    func testExpandedWeatherContractDecodesFiveMileClearanceAndRadar() throws {
        struct ExpandedWeatherContract: Decodable {
            let evidence: DelayEvidence
            let weather: WeatherSnapshot
        }

        let json = #"""
        {
          "evidence": {
            "label": "Five-mile NOAA lightning-density match",
            "phase": "ACTIVE",
            "closureTimingMatched": true,
            "correlatedClosureCount": 4,
            "minimumCorrelatedClosures": 2,
            "matchedLightningAt": "2026-08-03T18:00:00.000Z",
            "lastLightningDensityAt": "2026-08-03T18:00:00.000Z",
            "nearestPositiveSampleMiles": 5,
            "lightningPeriods30Minutes": 1,
            "observedThunderstorm": true,
            "forecastThunderstorm": true,
            "convectiveAlertLevel": null,
            "clearanceAt": "2026-08-03T18:30:00.000Z",
            "clearanceVerifiedAt": null,
            "clearanceState": "COUNTDOWN",
            "clearMinutes": 18,
            "requiredClearMinutes": 30,
            "radarTrend": "EXITING",
            "radarReflectivityDbz": 24.5,
            "radarProjectedClearAt": "2026-08-03T18:16:00.000Z"
          },
          "weather": {
            "location": { "parkId": 6, "parkName": "Magic Kingdom Park", "latitude": 28.4177, "longitude": -81.5812 },
            "fetchedAt": "2026-08-03T18:18:00.000Z",
            "condition": "Thunderstorm",
            "temperatureF": 86,
            "windMph": 12,
            "precipitationChance": 80,
            "observedThunderstorm": true,
            "forecastThunderstorm": true,
            "forecastThunderstormUntil": "2026-08-03T19:00:00.000Z",
            "convectiveAlertLevel": null,
            "activeAlerts": [],
            "nws": {
              "status": "LIVE", "observedAt": "2026-08-03T18:15:00.000Z", "forecastUpdatedAt": "2026-08-03T18:00:00.000Z",
              "alertsCheckedAt": "2026-08-03T18:18:00.000Z", "observationStatus": "LIVE", "forecastStatus": "LIVE",
              "alertsStatus": "LIVE", "stationName": "KMCO", "url": "https://api.weather.gov/"
            },
            "lightning": {
              "status": "LIVE", "checkedAt": "2026-08-03T18:18:00.000Z",
              "densityDetectedAt": ["2026-08-03T18:00:00.000Z"], "parkCoordinateDensityDetectedAt": [],
              "lastDensityDetectedAt": "2026-08-03T18:00:00.000Z", "nearestPositiveSampleMiles": 5,
              "sampleRadiusMiles": 5, "periodsDetected30Minutes": 1, "maximumStrikeDensity": 1.25,
              "coverageMinutes": 180, "sourceUpdatedAt": "2026-08-03T18:18:00.000Z", "url": "https://nowcoast.noaa.gov/",
              "clearSinceAt": "2026-08-03T18:00:00.000Z", "clearMinutes": 18, "requiredClearMinutes": 30,
              "clearanceAt": "2026-08-03T18:30:00.000Z", "clearanceVerifiedAt": null,
              "clearanceState": "COUNTDOWN", "completeFrames30Minutes": 2, "gridResolutionMiles": 5
            },
            "radar": {
              "status": "LIVE", "checkedAt": "2026-08-03T18:18:00.000Z", "sourceUpdatedAt": "2026-08-03T18:16:00.000Z",
              "sampleRadiusMiles": 5, "maximumReflectivityDbz": 24.5, "trend": "EXITING", "trendDbzPerMinute": -0.7,
              "projectedClearAt": "2026-08-03T18:16:00.000Z", "coverageMinutes": 28, "url": "https://nowcoast.noaa.gov/"
            }
          }
        }
        """#

        let contract = try PivotAPIClient.makeDecoder().decode(ExpandedWeatherContract.self, from: Data(json.utf8))

        XCTAssertEqual(contract.evidence.clearanceState, "COUNTDOWN")
        XCTAssertEqual(contract.evidence.clearMinutes, 18)
        XCTAssertEqual(contract.evidence.requiredClearMinutes, 30)
        XCTAssertEqual(contract.evidence.radarTrend, "EXITING")
        XCTAssertNil(contract.evidence.closureWaveUnknownRideCount)
        XCTAssertEqual(contract.weather.lightning.sampleRadiusMiles, 5)
        XCTAssertEqual(contract.weather.lightning.completeFrames30Minutes, 2)
        XCTAssertEqual(contract.weather.radar?.trend, "EXITING")
        XCTAssertEqual(contract.weather.radar?.maximumReflectivityDbz, 24.5)

        var hardenedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        var hardenedEvidence = try XCTUnwrap(hardenedJSON["evidence"] as? [String: Any])
        hardenedEvidence["closureWaveUnknownRideCount"] = 2
        hardenedJSON["evidence"] = hardenedEvidence
        let hardenedData = try JSONSerialization.data(withJSONObject: hardenedJSON)
        let hardenedContract = try PivotAPIClient.makeDecoder().decode(ExpandedWeatherContract.self, from: hardenedData)
        XCTAssertEqual(hardenedContract.evidence.closureWaveUnknownRideCount, 2)
    }

    func testLegacySnapshotStillDecodesWithoutSupplementaryOrV6Metadata() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.productionV6SnapshotJSON.utf8)) as? [String: Any]
        )
        json.removeValue(forKey: "sourceUpdatedAtByProvider")
        json.removeValue(forKey: "themeParksWiki")

        var metrics = try XCTUnwrap(json["metrics"] as? [String: Any])
        metrics.removeValue(forKey: "scheduledCount")
        json["metrics"] = metrics

        var rides = try XCTUnwrap(json["rides"] as? [[String: Any]])
        var ride = try XCTUnwrap(rides.first)
        for key in [
            "themeParksWikiStatus",
            "statusAgreement",
            "statusProvenance",
            "statusComparisonReason",
            "scheduledReason",
            "waitTimeSource",
            "scheduledClosure"
        ] {
            ride.removeValue(forKey: key)
        }
        var estimate = try XCTUnwrap(ride["estimate"] as? [String: Any])
        for key in [
            "sameRideSampleSize",
            "sameRideCensoredSampleSize",
            "survivalEstimator",
            "calibration",
            "historyProvenance",
            "historicalPrior",
            "aggregateReliabilityPrior"
        ] {
            estimate.removeValue(forKey: key)
        }
        ride["estimate"] = estimate
        rides[0] = ride
        json["rides"] = rides

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let snapshot = try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: legacyData)

        XCTAssertNil(snapshot.sourceUpdatedAtByProvider)
        XCTAssertEqual(snapshot.queueTimesUpdatedAt, snapshot.sourceUpdatedAt)
        XCTAssertEqual(snapshot.waitStatusUpdatedAt, snapshot.sourceUpdatedAt)
        XCTAssertNil(snapshot.themeParksWiki)
        XCTAssertNil(snapshot.metrics.scheduledCount)
        XCTAssertNil(snapshot.rides[0].statusAgreement)
        XCTAssertNil(snapshot.rides[0].estimate?.calibration)
        XCTAssertNil(snapshot.rides[0].estimate?.aggregateReliabilityPrior)
    }

    func testNewSnapshotFetchAllowsTransitionWhenProviderTimestampIsUnchanged() {
        let baseline = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: nil,
            current: makeSnapshot(
                sourceOffset: 1,
                waitStatusSourceOffset: 5,
                ride: makeRide(status: .open)
            )
        ).nextBaseline

        let newerSnapshot = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: baseline,
            current: makeSnapshot(
                sourceOffset: 20,
                waitStatusSourceOffset: 5,
                ride: makeRide(status: .down)
            )
        )

        XCTAssertEqual(newerSnapshot.alerts.map(\.kind), [.closed])
        XCTAssertEqual(newerSnapshot.nextBaseline?.fetchedAt, start.addingTimeInterval(20))
    }

    func testNewSnapshotFetchAllowsTransitionWhenProviderTimestampRegresses() {
        let baseline = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: nil,
            current: makeSnapshot(
                sourceOffset: 1,
                waitStatusSourceOffset: 10,
                ride: makeRide(status: .open)
            )
        ).nextBaseline

        let newerSnapshot = RideTransitionEngine.evaluate(
            selectedParkId: 6,
            previous: baseline,
            current: makeSnapshot(
                sourceOffset: 2,
                waitStatusSourceOffset: 5,
                ride: makeRide(status: .down)
            )
        )

        XCTAssertEqual(newerSnapshot.alerts.map(\.kind), [.closed])
        XCTAssertEqual(newerSnapshot.nextBaseline?.fetchedAt, start.addingTimeInterval(2))
    }

    func testLiveActivitySelectsTheHighestDemandCurrentClosure() {
        let weatherClosure = makeRide(
            id: 1,
            name: "Weather ride",
            status: .down,
            trend: [20, 25, 30]
        )
        let popularClosure = makeRide(
            id: 2,
            name: "Popular ride",
            status: .down,
            trend: [70, 80, 90]
        )
        let openRide = makeRide(
            id: 3,
            name: "Open ride",
            status: .open,
            trend: [100, 110, 120]
        )

        let selected = PIVOTLiveActivityRideSelector.mostPopularClosedRide(
            in: [weatherClosure, popularClosure, openRide]
        )

        XCTAssertEqual(selected?.id, popularClosure.id)
    }

    func testLiveActivityTargetKeepsClosureButWithholdsUnsupportedLegacyWindow() {
        let ride = makeRide(status: .down, downSince: start, elapsedDownMinutes: 42)
        let snapshot = makeSnapshot(sourceOffset: 42 * 60, ride: ride)
        let target = PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: snapshot,
            featuredRide: ride
        )

        XCTAssertEqual(target?.attributes.parkID, FloridaPark.magicKingdom.rawValue)
        XCTAssertEqual(target?.attributes.parkName, "Magic Kingdom Park")
        XCTAssertEqual(target?.state.rideID, ride.id)
        XCTAssertEqual(target?.state.animationKey, target?.episodeIdentifier)
        XCTAssertEqual(target?.state.closureStartedAt, start)
        XCTAssertEqual(target?.state.closureDurationIsMinimum, false)
        XCTAssertEqual(target?.state.closureDurationText, "Closed for 42 min")
        XCTAssertNil(target?.state.windowStart)
        XCTAssertNil(target?.state.bestGuess)
        XCTAssertNil(target?.state.windowEnd)
        XCTAssertEqual(target?.state.forecastPhase, "UPCOMING")
        XCTAssertEqual(target?.state.forecastRevision, 0)
        XCTAssertEqual(target?.state.forecastRevisionReason, "INITIAL")
        XCTAssertEqual(target?.state.lastUpdated, snapshot.fetchedAt)
        XCTAssertEqual(target?.staleDate, snapshot.fetchedAt.addingTimeInterval(15 * 60))
        XCTAssertEqual(
            target?.episodeIdentifier,
            "6:126:\(Int(start.addingTimeInterval(-1_200).timeIntervalSince1970))"
        )
    }

    func testLiveActivityCarriesSelectedAccentAndDecodesLegacyAttributes() throws {
        let ride = makeRide(status: .down)
        let snapshot = makeSnapshot(sourceOffset: 0, ride: ride)
        let palette: [String: UInt32] = ["mint": 0x78e3bf, "blue": 0x87c7ff, "purple": 0xc1a5ff,
                                        "pink": 0xff9fce, "orange": 0xffb477, "gold": 0xf2d369]
        for (name, rgb) in palette {
            let target = try XCTUnwrap(PIVOTLiveActivityTargetBuilder.makeTarget(
                selectedPark: .magicKingdom, snapshot: snapshot, featuredRide: ride, accentName: name
            ))
            XCTAssertEqual(target.attributes.accentRGB, rgb)
            let decoded = try JSONDecoder().decode(PIVOTLiveActivityAttributes.self,
                                                   from: JSONEncoder().encode(target.attributes))
            XCTAssertEqual(decoded.accentName, name)
        }
        let legacy = Data(#"{"parkID":6,"parkName":"Magic Kingdom","timeZoneIdentifier":"America/New_York"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PIVOTLiveActivityAttributes.self, from: legacy).accentRGB, 0x78e3bf)
    }

    func testLiveActivityFreshnessUsesFreshSnapshotForALongClosure() throws {
        let ride = makeRide(status: .down, elapsedDownMinutes: 45)
        let snapshot = makeSnapshot(sourceOffset: 20 * 60, ride: ride)
        let target = try XCTUnwrap(PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: snapshot,
            featuredRide: ride
        ))

        XCTAssertEqual(ride.lastUpdated, start)
        XCTAssertGreaterThan(snapshot.fetchedAt.timeIntervalSince(ride.lastUpdated ?? snapshot.fetchedAt), 15 * 60)
        XCTAssertEqual(target.state.lastUpdated, snapshot.fetchedAt)
        XCTAssertEqual(target.staleDate, snapshot.fetchedAt.addingTimeInterval(15 * 60))
    }

    func testLiveActivityUpdatesTheSameClosureForAMissedWindowRevision() throws {
        let initialRide = makeRide(status: .down)
        let revisedRide = makeRide(
            status: .down,
            forecastRevision: 1,
            forecastRevisionReason: "WINDOW_MISSED"
        )
        let snapshot = makeSnapshot(sourceOffset: 5, ride: revisedRide)
        let initialTarget = try XCTUnwrap(PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: makeSnapshot(sourceOffset: 4, ride: initialRide),
            featuredRide: initialRide
        ))
        let revisedTarget = try XCTUnwrap(PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: snapshot,
            featuredRide: revisedRide
        ))

        XCTAssertEqual(revisedTarget.episodeIdentifier, initialTarget.episodeIdentifier)
        XCTAssertEqual(revisedTarget.state.forecastRevision, 1)
        XCTAssertEqual(revisedTarget.state.forecastRevisionReason, "WINDOW_MISSED")
        XCTAssertTrue(revisedTarget.state.isMissedWindowRevision)
        XCTAssertTrue(revisedTarget.requiresActivityUpdate(
            currentState: initialTarget.state,
            currentStaleDate: initialTarget.staleDate
        ))
    }

    func testLegacyLiveActivityStateDecodesWithoutRevisionFields() throws {
        let json = #"""
        {
          "rideID": 126,
          "episodeIdentifier": "6:126:1775320800",
          "rideName": "Space Mountain",
          "landName": "Tomorrowland",
          "closureStartedAt": "2026-04-05T16:40:00.000Z",
          "closureDurationIsMinimum": false,
          "closureDurationText": "Closed for 20 min",
          "closureDurationAccessibilityLabel": "Closed for 20 min",
          "delayType": "RIDE",
          "statusSummary": "Ride delay",
          "forecastPhase": "UPCOMING",
          "windowStart": "2026-04-05T17:00:00.000Z",
          "bestGuess": "2026-04-05T17:15:00.000Z",
          "windowEnd": "2026-04-05T17:30:00.000Z",
          "evidenceStrength": "Moderate",
          "lastUpdated": "2026-04-05T16:55:00.000Z"
        }
        """#

        let state = try PivotAPIClient.makeDecoder().decode(
            PIVOTLiveActivityAttributes.ContentState.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(state.forecastRevision)
        XCTAssertNil(state.forecastRevisionReason)
        XCTAssertFalse(state.isMissedWindowRevision)
    }

    func testLiveActivityMinimumDurationUsesAContinuingTimerAnchor() {
        let ride = makeRide(status: .down, minimumDownMinutes: 8)
        let snapshot = makeSnapshot(sourceOffset: 30, ride: ride)
        let target = PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: snapshot,
            featuredRide: ride
        )

        XCTAssertEqual(target?.state.closureDurationIsMinimum, true)
        XCTAssertEqual(
            target?.state.closureStartedAt,
            ride.estimate?.episodeAnchorAt
        )
        XCTAssertEqual(target?.state.closureDurationText, "Closed for at least 8 min")

        let laterSnapshot = makeSnapshot(sourceOffset: 70, ride: ride)
        let laterTarget = PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: laterSnapshot,
            featuredRide: ride
        )
        XCTAssertEqual(laterTarget?.state.closureStartedAt, target?.state.closureStartedAt)
        XCTAssertEqual(laterTarget?.state.animationKey, target?.state.animationKey)
    }

    func testLiveActivityAnimationKeyChangesForAnotherFeaturedRide() {
        let firstRide = makeRide(id: 126, name: "Space Mountain", status: .down)
        let secondRide = makeRide(id: 999, name: "Seven Dwarfs Mine Train", status: .down)
        let firstTarget = PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: makeSnapshot(sourceOffset: 1, ride: firstRide),
            featuredRide: firstRide
        )
        let secondTarget = PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: makeSnapshot(sourceOffset: 2, ride: secondRide),
            featuredRide: secondRide
        )

        XCTAssertNotEqual(firstTarget?.state.animationKey, secondTarget?.state.animationKey)
    }

    func testLiveActivitySkipsAnIdenticalContentUpdate() {
        let ride = makeRide(status: .down, elapsedDownMinutes: 42)
        let target = PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: makeSnapshot(sourceOffset: 5, ride: ride),
            featuredRide: ride
        )!

        XCTAssertFalse(target.requiresActivityUpdate(
            currentState: target.state,
            currentStaleDate: target.staleDate
        ))
        XCTAssertTrue(target.requiresActivityUpdate(
            currentState: target.state,
            currentStaleDate: target.staleDate.addingTimeInterval(-1)
        ))
    }

    func testLiveActivityTargetEndsForPausedOrClearPark() {
        let closedRide = makeRide(status: .down, minimumDownMinutes: 8)
        let closedSnapshot = makeSnapshot(sourceOffset: 1, ride: closedRide)
        let openRide = makeRide(status: .open)
        let clearSnapshot = makeSnapshot(sourceOffset: 2, ride: openRide)

        XCTAssertNil(PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: nil,
            snapshot: closedSnapshot,
            featuredRide: closedRide
        ))
        XCTAssertNil(PIVOTLiveActivityTargetBuilder.makeTarget(
            selectedPark: .magicKingdom,
            snapshot: clearSnapshot,
            featuredRide: nil
        ))
    }

    @MainActor
    func testAppDrivenLiveActivityEndAllowsTheSameClosureToStartAgain() {
        let suiteName = "PIVOTTests.LiveActivity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("6:126:episode", forKey: "pivot.liveActivity.lastRequestedEpisode")

        let service = LiveActivityService(defaults: defaults)
        service.synchronize(nil)

        XCTAssertNil(defaults.string(forKey: "pivot.liveActivity.lastRequestedEpisode"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static var bourneShowJSON: [String: Any] {
        [
            "id": "uor.usf.shows.the_bourne_stuntacular",
            "name": "The Bourne Stuntacular",
            "status": "CLOSED",
            "showtimes": [
                [
                    "type": "Performance Time",
                    "startTime": "2026-08-03T15:15:00.000Z",
                    "endTime": NSNull()
                ],
                [
                    "type": "Performance Time",
                    "startTime": "2026-08-03T16:00:00.000Z",
                    "endTime": NSNull()
                ],
                [
                    "type": "Performance Time",
                    "startTime": "2026-08-03T17:00:00.000Z",
                    "endTime": NSNull()
                ]
            ],
            "nextShowAt": "2026-08-03T15:15:00.000Z",
            "nextShowEndAt": NSNull(),
            "nextShowType": "Performance Time",
            "sourceUpdatedAt": "2026-08-03T14:58:00.000Z"
        ]
    }

    private static func timedShowJSON(id: String, name: String, times: [String]) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "status": "OPERATING",
            "showtimes": times.map { time in
                [
                    "type": "Performance Time",
                    "startTime": time,
                    "endTime": NSNull()
                ]
            },
            "nextShowAt": times.first ?? NSNull(),
            "nextShowEndAt": NSNull(),
            "nextShowType": "Performance Time",
            "sourceUpdatedAt": "2026-08-03T14:58:00.000Z"
        ]
    }

    private static var starlightShowJSON: [String: Any] {
        timedShowJSON(
            id: "mk.starlight",
            name: "Disney Starlight: Dream the Night Away",
            times: ["2026-08-03T21:00:00.000Z", "2026-08-03T23:00:00.000Z"]
        )
    }

    private static var happilyEverAfterShowJSON: [String: Any] {
        timedShowJSON(
            id: "mk.happily-ever-after",
            name: "Happily Ever After",
            times: ["2026-08-03T22:00:00.000Z"]
        )
    }

    private static var untimedShowJSON: [String: Any] {
        timedShowJSON(id: "mk.untimed", name: "Untimed entertainment", times: [])
    }

    private func makeShowSnapshot(
        shows: [[String: Any]],
        sourceWarning: String?
    ) throws -> LiveParkSnapshot {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.productionV6SnapshotJSON.utf8)) as? [String: Any]
        )
        json["parkId"] = FloridaPark.universalStudiosFlorida.rawValue
        json["park"] = [
            "name": "Universal Studios Florida",
            "destination": "Universal Orlando Resort",
            "operator": "Universal",
            "country": "United States",
            "timezone": "America/New_York"
        ]
        json["shows"] = shows
        if shows.isEmpty {
            json["nextShowAt"] = NSNull()
            json["nextShowName"] = NSNull()
        } else {
            json["nextShowAt"] = "2026-08-03T15:15:00.000Z"
            json["nextShowName"] = "The Bourne Stuntacular"
        }
        json["showsSourceUpdatedAt"] = "2026-08-03T14:58:00.000Z"
        var showSource: [String: Any] = [
            "name": "Universal Orlando Resort",
            "label": "Schedule data from Universal Orlando Resort",
            "url": "https://www.universalorlando.com/web/en/us/things-to-do/entertainment",
            "fetchedAt": "2026-08-03T15:00:00.000Z",
            "sourceUpdatedAt": "2026-08-03T14:58:00.000Z",
            "scheduleDate": "2026-08-03",
            "stale": false,
            "updateCadenceMinutes": 5
        ]
        if let sourceWarning {
            showSource["warning"] = sourceWarning
        } else {
            showSource["warning"] = NSNull()
        }
        json["showsSource"] = showSource

        let data = try JSONSerialization.data(withJSONObject: json)
        return try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: data)
    }

    private func reopeningFixture(estimate changes: [String: Any] = [:], lightning: [String: Any]? = nil) throws -> LiveParkSnapshot {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Self.productionV6SnapshotJSON.utf8)) as? [String: Any])
        let now = Self.isoDate("2026-10-13T18:00:00.000Z")
        func iso(_ offset: TimeInterval) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(offset)) }
        json["fetchedAt"] = iso(0)
        json["sourceUpdatedAt"] = iso(0)
        var provider = try XCTUnwrap(json["themeParksWiki"] as? [String: Any])
        provider["fetchedAt"] = iso(0)
        provider["cacheStale"] = false
        provider["available"] = true
        json["themeParksWiki"] = provider
        var rows = try XCTUnwrap(json["rides"] as? [[String: Any]])
        var ride = rows[0]
        ride["status"] = "DOWN"
        ride["delayType"] = lightning == nil ? "RIDE" : "WEATHER"
        ride["weatherHoldActive"] = lightning != nil
        var estimate = try XCTUnwrap(ride["estimate"] as? [String: Any])
        estimate["issuedAt"] = iso(-30)
        estimate["windowStart"] = iso(300)
        estimate["historicalMedianAt"] = iso(1200)
        estimate["windowEnd"] = iso(2400)
        estimate["forecastPhase"] = "UPCOMING"
        estimate["sameRideSampleSize"] = 8
        estimate["effectiveSampleSize"] = 8
        estimate["recentSampleSize"] = 8
        estimate["distinctDayCount"] = 4
        estimate["startQuality"] = "observed"
        estimate["closureSignal"] = "confirmed"
        estimate["calibration"] = NSNull()
        var provenance = try XCTUnwrap(estimate["historyProvenance"] as? [String: Any])
        provenance["trainedThrough"] = iso(-86_400)
        estimate["historyProvenance"] = provenance
        if let lightning {
            var weather = try XCTUnwrap(json["weather"] as? [String: Any])
            var feed = try XCTUnwrap(weather["lightning"] as? [String: Any])
            feed["status"] = "LIVE"
            feed["sourceKind"] = "DENSITY"
            feed["checkedAt"] = iso(0)
            feed["sourceUpdatedAt"] = iso(-60)
            feed["completeFrames30Minutes"] = 3
            feed["clearanceState"] = "ACTIVE"
            feed["clearanceAt"] = iso(-120)
            feed["clearanceVerifiedAt"] = iso(-120)
            feed.merge(lightning) { _, new in new }
            weather["lightning"] = feed
            json["weather"] = weather
            estimate["estimateKind"] = "WEATHER"
            estimate["weatherClearanceAt"] = iso(-120)
            estimate["weatherRestartLagSampleSize"] = 8
        }
        estimate.merge(changes) { _, new in new }
        ride["estimate"] = estimate
        rows[0] = ride
        json["rides"] = rows
        return try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func reopeningGuidance(_ snapshot: LiveParkSnapshot, at date: Date? = nil, failed: Bool = false) -> ReopeningGuidance {
        let now = date ?? snapshot.fetchedAt
        return ReopeningGuidance.presentation(ride: snapshot.rides[0], snapshot: snapshot,
            feedHealth: DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot,
                isLoading: false, refreshFailed: failed, at: now), at: now, timeZone: FloridaPark.magicKingdom.timeZone)
    }

    func testSparseReopeningHistoryCannotShowAnExactGuess() throws {
        for count in [0, 1, 3] {
            let snapshot = try reopeningFixture(estimate: ["sameRideSampleSize": count])
            let result = reopeningGuidance(snapshot)
            XCTAssertNil(result.range)
            XCTAssertNil(result.bestGuess)
            XCTAssertTrue(result.detail.contains("Too few comparable closures"))
        }
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["startQuality": "unknown"])).range)
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["closureSignal": "first-seen"])).range)
    }

    func testReopeningRangeNeedsHistoryAndPointNeedsScoredSameRideSupport() throws {
        let supported = try reopeningFixture()
        XCTAssertNotNil(reopeningGuidance(supported).range)
        XCTAssertNil(reopeningGuidance(supported).bestGuess)
        let calibration: [String: Any] = ["version": "PIVOT-ONLINE-CALIBRATION-v4", "basis": "same-ride residuals", "sampleSize": 25,
            "effectiveSampleSize": 20, "distinctRideCount": 1, "distinctParkCount": 1, "historicalCoverage": 0.8,
            "medianAdjustmentMinutes": 0, "intervalPaddingMinutes": 0, "trainedThrough": "2026-10-12T18:00:00Z"]
        XCTAssertNotNil(reopeningGuidance(try reopeningFixture(estimate: ["calibration": calibration])).bestGuess)
        var poor = calibration
        poor["historicalCoverage"] = 0.3
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["calibration": poor])).range)
        poor = calibration
        poor["version"] = "PIVOT-ONLINE-CALIBRATION-v3"
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["calibration": poor])).bestGuess)
        poor = calibration
        poor["basis"] = "network residuals"
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["calibration": poor])).bestGuess)
    }

    func testExpiredReopeningWindowCannotRemainUpcomingBetweenRefreshes() throws {
        let snapshot = try reopeningFixture()
        let now = try XCTUnwrap(snapshot.rides[0].estimate).windowEnd.addingTimeInterval(1)
        // Keep the status observation current while retaining the issued window.
        let data = try JSONEncoder().encode(snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["fetchedAt"] = now.timeIntervalSinceReferenceDate
        var provider = try XCTUnwrap(json["themeParksWiki"] as? [String: Any])
        provider["fetchedAt"] = now.timeIntervalSinceReferenceDate
        json["themeParksWiki"] = provider
        let current = try JSONDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let result = reopeningGuidance(current, at: now)
        XCTAssertEqual(result.headline, "Window ended · waiting for a fresh ride update")
        XCTAssertNil(result.bestGuess)
        XCTAssertNil(result.range)
    }

    func testFailedExpiredAndFutureDataWithholdReopeningGuidance() throws {
        let snapshot = try reopeningFixture()
        XCTAssertNil(reopeningGuidance(snapshot, failed: true).range)
        XCTAssertNil(reopeningGuidance(snapshot, at: snapshot.fetchedAt.addingTimeInterval(16 * 60)).range)
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["issuedAt": "2026-10-14T18:00:00Z"])).range)
        XCTAssertNil(reopeningGuidance(try reopeningFixture(estimate: ["windowStart": "2026-10-14T18:00:00Z"])).range)
    }

    func testOctober17FigmentRevisionWaitsForSameEpisodeObservation() throws {
        let base = try reopeningFixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        let now = Self.isoDate("2026-10-17T20:45:15.564Z")
        let beforeEnd = Self.isoDate("2026-10-17T20:40:00.000Z")
        let anchor = Self.isoDate("2026-10-17T18:40:47.924Z")
        json["fetchedAt"] = beforeEnd.timeIntervalSinceReferenceDate
        var provider = try XCTUnwrap(json["themeParksWiki"] as? [String: Any])
        provider["fetchedAt"] = beforeEnd.timeIntervalSinceReferenceDate
        json["themeParksWiki"] = provider
        var rides = try XCTUnwrap(json["rides"] as? [[String: Any]])
        var estimate = try XCTUnwrap(rides[0]["estimate"] as? [String: Any])
        for (key, value) in ["issuedAt": "2026-10-17T19:54:46.625Z", "windowStart": "2026-10-17T19:54:46.625Z",
                             "historicalMedianAt": "2026-10-17T20:09:46.625Z", "windowEnd": "2026-10-17T20:44:46.625Z"] {
            estimate[key] = Self.isoDate(value).timeIntervalSinceReferenceDate
        }
        estimate["episodeAnchorAt"] = anchor.timeIntervalSinceReferenceDate
        estimate["revision"] = 1
        estimate["revisionReason"] = "WINDOW_MISSED"
        rides[0]["estimate"] = estimate
        rides[0]["statusObservedAt"] = beforeEnd.timeIntervalSinceReferenceDate
        rides[0]["statusEpisodeAnchorAt"] = anchor.timeIntervalSinceReferenceDate
        func result() throws -> ReopeningGuidance {
            json["rides"] = rides
            let snapshot = try JSONDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
            return reopeningGuidance(snapshot, at: now)
        }
        XCTAssertEqual(try result().headline, "Window ended · waiting for a fresh ride update")
        rides[0]["statusObservedAt"] = now.timeIntervalSinceReferenceDate
        XCTAssertEqual(try result().headline, "Still closed on the latest source update")
        XCTAssertTrue(try result().detail.contains("Result pending"))
        rides[0]["statusEpisodeAnchorAt"] = now.timeIntervalSinceReferenceDate
        XCTAssertEqual(try result().headline, "Window ended · waiting for a fresh ride update")
    }

    func testActiveAndUnobservedLightningCannotPromiseAReopening() throws {
        let active = try reopeningFixture(lightning: [:])
        XCTAssertEqual(reopeningGuidance(active).headline, "Weather timing uncertain")
        let cases: [[String: Any]] = [ ["status": "UNAVAILABLE"], ["completeFrames30Minutes": 0],
            ["sourceUpdatedAt": "2026-10-13T16:00:00Z"], ["checkedAt": "2026-10-14T18:00:00Z"], ["sourceKind": "GLM"] ]
        for override in cases {
            let result = reopeningGuidance(try reopeningFixture(lightning: override))
            XCTAssertEqual(result.headline, "Weather timing unavailable")
            XCTAssertNil(result.range)
        }
    }

    func testMappedClearanceNeedsCurrentSupportedRestartEvidence() throws {
        let clear: [String: Any] = ["clearanceState": "VERIFIED"]
        XCTAssertNil(reopeningGuidance(try reopeningFixture(lightning: clear)).range, "Legacy weather clocks are conditional, not reopening estimates")
        let reliability: [String: Any] = ["status": "HISTORICAL_RANGE", "showRange": true, "showBestGuess": false, "reason": "Observed restarts"]
        let supported = try reopeningFixture(estimate: ["reliability": reliability], lightning: clear)
        XCTAssertNotNil(reopeningGuidance(supported).range)
        XCTAssertNil(reopeningGuidance(supported).bestGuess)
        let changedStorm = try reopeningFixture(estimate: ["reliability": reliability], lightning: ["clearanceState": "VERIFIED", "clearanceAt": "2026-10-13T17:50:00Z"])
        XCTAssertNil(reopeningGuidance(changedStorm).range)
        let fewRestarts = try reopeningFixture(estimate: ["reliability": reliability, "weatherRestartLagSampleSize": 1], lightning: clear)
        XCTAssertNil(reopeningGuidance(fewRestarts).range)
    }

    func testLiveActivityRetainsRangeWithoutUnsupportedPointAndMarksItsContract() throws {
        let snapshot = try reopeningFixture()
        let target = try XCTUnwrap(PIVOTLiveActivityTargetBuilder.makeTarget(selectedPark: .magicKingdom,
            snapshot: snapshot, featuredRide: snapshot.rides[0]))
        XCTAssertNotNil(target.state.windowStart)
        XCTAssertNil(target.state.bestGuess)
        XCTAssertEqual(target.state.guidanceVersion, 1)
        let saved = try JSONDecoder().decode(PIVOTLiveActivityAttributes.ContentState.self, from: JSONEncoder().encode(target.state))
        XCTAssertEqual(saved.guidanceVersion, 1)
        let ending = try reopeningFixture(estimate: ["windowStart": "2026-10-13T18:01:00Z",
            "historicalMedianAt": "2026-10-13T18:03:00Z", "windowEnd": "2026-10-13T18:05:00Z"])
        let endingTarget = try XCTUnwrap(PIVOTLiveActivityTargetBuilder.makeTarget(selectedPark: .magicKingdom,
            snapshot: ending, featuredRide: ending.rides[0]))
        XCTAssertEqual(endingTarget.staleDate, ending.rides[0].estimate?.windowEnd,
                       "ActivityKit must expire the window without waiting for another push or view redraw")
    }

    private static let productionV6SnapshotJSON = #"""
    {
      "parkId": 6,
      "park": {
        "name": "Magic Kingdom Park",
        "destination": "Walt Disney World",
        "operator": "Disney",
        "country": "United States",
        "timezone": "America/New_York"
      },
      "parkActive": true,
      "feedHealthy": true,
      "fetchedAt": "2026-08-03T01:57:39.613Z",
      "sourceUpdatedAt": "2026-08-03T01:55:23.000Z",
      "sourceUpdatedAtByProvider": {
        "queueTimes": "2026-08-03T01:55:23.000Z",
        "themeParksWiki": "2026-08-03T01:56:14.012Z"
      },
      "cacheAgeSeconds": 136,
      "rides": [{
        "id": 126,
        "name": "Space Mountain",
        "land": "Tomorrowland",
        "status": "DOWN",
        "isOpen": false,
        "waitTime": null,
        "lastUpdated": "2026-08-03T01:55:23.000Z",
        "downSince": "2026-08-03T01:45:16.000Z",
        "elapsedDownMinutes": 12,
        "minimumDownMinutes": null,
        "estimate": {
          "modelVersion": "PIVOT Ride Recovery v6",
          "estimateKind": "OPERATIONAL",
          "windowStart": "2026-08-03T02:00:00.000Z",
          "historicalMedianAt": "2026-08-03T02:25:00.000Z",
          "windowEnd": "2026-08-03T03:25:00.000Z",
          "evidenceStrength": "Moderate",
          "sampleSize": 28,
          "effectiveSampleSize": 15.2,
          "distinctDayCount": 3,
          "recentSampleSize": 28,
          "distinctRideCount": 46,
          "distinctParkCount": 8,
          "censoredSampleSize": 74,
          "sameRideSampleSize": 4,
          "sameRideCensoredSampleSize": 1,
          "basis": "same-ride blend",
          "intervalCoverage": "hierarchical conditional range with source uncertainty",
          "method": "empirical-Bayes conditional ride recovery",
          "priorVersion": "PIVOT-FL-COLDSTART-2026-08-01",
          "startQuality": "observed",
          "closureSignal": "confirmed",
          "priorTrainedThrough": null,
          "survivalEstimator": "weighted Kaplan-Meier with empirical-Bayes prior",
          "calibration": {
            "version": "PIVOT-ONLINE-CALIBRATION-v1",
            "basis": "same-ride residuals",
            "sampleSize": 8,
            "effectiveSampleSize": 7.5,
            "distinctRideCount": 1,
            "distinctParkCount": 1,
            "historicalCoverage": 0.75,
            "medianAdjustmentMinutes": 5,
            "intervalPaddingMinutes": 10,
            "trainedThrough": "2026-08-02T23:20:23.000Z"
          },
          "historyProvenance": {
            "trainedThrough": "2026-08-02T23:20:23.000Z",
            "confirmedTransitionCount": 18,
            "forecastLifecycleCount": 84,
            "activeCensoredCount": 3,
            "legacyCount": 0
          },
          "historicalPrior": {
            "version": null,
            "trainedThrough": null,
            "basis": "none",
            "sourceName": null,
            "sourceReference": null,
            "license": null,
            "sampleSize": 0,
            "distinctDayCount": 0,
            "firstObserved": null,
            "lastObserved": null,
            "continuity": null,
            "continuityWeight": null,
            "intervalUncertaintyMinutes": 0.5
          },
          "aggregateReliabilityPrior": {
            "applied": true,
            "role": "aggregate-cold-start-only",
            "provenance": {
              "version": "ROPE-DROP-AGGREGATE-2026-08-03",
              "publisher": "Rope Drop News",
              "sourceUrl": "https://ropedropnews.com/reliability.csv",
              "reliabilityPageUrl": "https://ropedropnews.com/reliability",
              "documentationUrl": "https://github.com/RopeDropNews/theme-park-open-data",
              "repositoryCommit": "7ba382fb4e63f06e9be0446757ab7ee9e4117c88",
              "sourceSha256": "fixture",
              "license": "Creative Commons Attribution 4.0 International (CC BY 4.0)",
              "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
              "attribution": "Data from Rope Drop News, CC BY 4.0",
              "sourceFreshAsOf": "2026-08-02T23:06:29Z",
              "retrievedAt": "2026-08-02T23:41:11Z",
              "availableFrom": "2026-08-03T00:24:00Z",
              "documentedRollingWindowDays": 90,
              "role": "aggregate-cold-start-only",
              "eventLevelGroundTruth": false
            },
            "meanOutageMinutes": 32,
            "aggregateOutageCount": 52,
            "operatingDays": 53,
            "availabilityPercent": 96.5,
            "timeScale": 0.9125,
            "totalWeight": 0.175,
            "pointCount": 14,
            "matchKind": "normalized-exact",
            "sourceRideName": "Space Mountain",
            "exposure": "INDOOR",
            "eventLevel": false,
            "evidenceCount": 0,
            "evidenceAccounting": {
              "countsAsObservedOutage": false,
              "sampleSizeContribution": 0,
              "distinctDayCountContribution": 0,
              "distinctRideCountContribution": 0,
              "recentSampleSizeContribution": 0
            }
          },
          "weatherClearanceAt": null,
          "weatherRestartLagSampleSize": null,
          "weatherClosureSampleSize": null,
          "issuedAt": "2026-08-03T01:47:13.379Z",
          "anchorAt": "2026-08-03T01:47:13.379Z",
          "episodeAnchorAt": "2026-08-03T01:45:16.000Z",
          "forecastPhase": "IN_WINDOW",
          "lateMinutes": 0,
          "revision": 0,
          "revisionReason": "INITIAL",
          "lockedForOutage": true
        },
        "estimateReason": null,
        "delayType": "RIDE",
        "delayEvidence": null,
        "weatherExposure": "INDOOR",
        "radarEligible": true,
        "radarCategory": "RIDE",
        "reopenPending": false,
        "trend": [35, 45, 50],
        "themeParksWikiStatus": {
          "entityId": "fixture-entity",
          "entityName": "Space Mountain",
          "status": "DOWN",
          "sourceUpdatedAt": "2026-08-03T01:56:14.012Z",
          "matchedBy": "NORMALIZED_EXACT",
          "sourceAgeSeconds": 85
        },
        "statusAgreement": "AGREES",
        "statusProvenance": "QUEUE_TIMES_CONFIRMED_BY_THEMEPARKS_WIKI",
        "statusComparisonReason": "AGREEMENT",
        "scheduledReason": null
      }],
      "metrics": {
        "openCount": 0,
        "downCount": 1,
        "scheduledCount": 0,
        "averageWait": null,
        "reportingCount": 1
      },
      "source": {
        "name": "Queue-Times.com",
        "url": "https://queue-times.com/",
        "updateCadenceMinutes": 5
      },
      "themeParksWiki": {
        "available": true,
        "cacheStale": false,
        "fetchedAt": "2026-08-03T01:57:39.613Z",
        "sourceUpdatedAt": "2026-08-03T01:56:14.012Z",
        "cacheAgeSeconds": 85,
        "cacheHit": true,
        "matchedRideCount": 1,
        "unmatchedRides": [],
        "warning": null,
        "role": "SUPPLEMENTARY_STATUS",
        "statusSemantics": "RAW_PROVIDER_STATUS",
        "usedForWaitTimes": false,
        "usedForOperationalEligibility": true,
        "usedForOperationalTraining": false,
        "source": {
          "name": "ThemeParks.wiki",
          "label": "Powered by ThemeParks.wiki",
          "url": "https://www.themeparks.wiki/",
          "termsUrl": "https://www.themeparks.wiki/terms",
          "updateCadenceMinutes": 5
        }
      },
      "weather": {
        "location": {
          "parkId": 6,
          "parkName": "Magic Kingdom Park",
          "latitude": 28.4177,
          "longitude": -81.5812
        },
        "fetchedAt": "2026-08-03T01:57:39.613Z",
        "condition": "Partly Cloudy",
        "temperatureF": 84,
        "windMph": 8,
        "precipitationChance": 20,
        "observedThunderstorm": false,
        "forecastThunderstorm": false,
        "forecastThunderstormUntil": null,
        "convectiveAlertLevel": null,
        "activeAlerts": [],
        "nws": {
          "status": "LIVE",
          "observedAt": "2026-08-03T01:50:00.000Z",
          "forecastUpdatedAt": "2026-08-03T01:45:00.000Z",
          "alertsCheckedAt": "2026-08-03T01:57:39.613Z",
          "observationStatus": "LIVE",
          "forecastStatus": "LIVE",
          "alertsStatus": "LIVE",
          "stationName": "KMCO",
          "url": "https://weather.gov/"
        },
        "lightning": {
          "status": "LIVE",
          "checkedAt": "2026-08-03T01:57:39.613Z",
          "densityDetectedAt": [],
          "parkCoordinateDensityDetectedAt": [],
          "lastDensityDetectedAt": null,
          "nearestPositiveSampleMiles": null,
          "sampleRadiusMiles": 6.5,
          "periodsDetected30Minutes": 0,
          "maximumStrikeDensity": null,
          "coverageMinutes": 30,
          "sourceUpdatedAt": "2026-08-03T01:45:00.000Z",
          "url": "https://nowcoast.noaa.gov/"
        }
      }
    }
    """#

    private static func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }

    private func makeEstimate(
        phase: ForecastPhase,
        estimateKind: String = "OPERATIONAL",
        revision: Int = 0,
        revisionReason: String = "INITIAL"
    ) -> ReopeningEstimate {
        ReopeningEstimate(
            modelVersion: "PIVOT Ride Recovery v6",
            estimateKind: estimateKind,
            windowStart: start,
            historicalMedianAt: best,
            windowEnd: end,
            evidenceStrength: "Moderate",
            sampleSize: 12,
            effectiveSampleSize: 8.4,
            distinctDayCount: 5,
            recentSampleSize: 8,
            distinctRideCount: 3,
            distinctParkCount: 1,
            censoredSampleSize: 1,
            sameRideSampleSize: 4,
            sameRideCensoredSampleSize: 1,
            basis: "same-ride blend",
            intervalCoverage: "hierarchical conditional range with source uncertainty",
            method: "empirical-Bayes conditional ride recovery",
            priorVersion: "test",
            startQuality: "observed",
            closureSignal: "confirmed",
            priorTrainedThrough: nil,
            survivalEstimator: "weighted Kaplan-Meier with empirical-Bayes prior",
            calibration: nil,
            historyProvenance: nil,
            historicalPrior: nil,
            aggregateReliabilityPrior: nil,
            weatherClearanceEarliestAt: nil,
            weatherClearanceAt: nil,
            weatherClearanceVerifiedAt: nil,
            radarProjectedClearAt: nil,
            radarTrend: nil,
            weatherRestartLagSampleSize: nil,
            weatherClosureSampleSize: nil,
            issuedAt: start.addingTimeInterval(-600),
            anchorAt: start.addingTimeInterval(-600),
            episodeAnchorAt: start.addingTimeInterval(-1_200),
            forecastPhase: phase,
            lateMinutes: phase == .pastWindow ? 12 : 0,
            revision: revision,
            revisionReason: revisionReason,
            lockedForOutage: true
        )
    }

    private func makeDelayEvidence(
        weatherOriginSignal: String? = "LIGHTNING",
        closureTimingMatched: Bool = true,
        closureWaveUnknownRideCount: Int? = 0,
        clearanceState: String? = "ACTIVE"
    ) -> DelayEvidence {
        DelayEvidence(
            label: "Selected-park weather delay",
            phase: "ACTIVE",
            weatherOriginSignal: weatherOriginSignal,
            weatherOriginAt: start,
            closureTimingMatched: closureTimingMatched,
            correlatedClosureCount: 4,
            minimumCorrelatedClosures: 2,
            closureWaveExposedRideCount: 3,
            closureWaveRecentClosureCount: 2,
            closureWaveOpenRideCount: 1,
            closureWaveUnknownRideCount: closureWaveUnknownRideCount,
            closureWaveIgnoredOpenOutliers: 1,
            matchedLightningAt: weatherOriginSignal == "LIGHTNING" ? start : nil,
            lastLightningDensityAt: weatherOriginSignal == "LIGHTNING" ? start : nil,
            nearestPositiveSampleMiles: weatherOriginSignal == "LIGHTNING" ? 2 : nil,
            lightningPeriods30Minutes: weatherOriginSignal == "LIGHTNING" ? 2 : 0,
            observedThunderstorm: true,
            forecastThunderstorm: true,
            convectiveAlertLevel: nil,
            clearanceAt: weatherOriginSignal == "LIGHTNING" ? start.addingTimeInterval(30 * 60) : nil,
            clearanceVerifiedAt: nil,
            clearanceState: clearanceState,
            clearMinutes: 0,
            requiredClearMinutes: 30,
            radarTrend: "EXITING",
            radarReflectivityDbz: 28,
            radarProjectedClearAt: start.addingTimeInterval(10 * 60)
        )
    }

    @MainActor
    func testCrowdBrowsingDoesNotChangeSelectionAndFailureKeepsDataUnavailable() async throws {
        let suite = "crowd-browse-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(6, forKey: "pivot.selectedPark")
        let now = Date()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(makeSnapshot(sourceOffset: now.timeIntervalSince(start), ride: makeRide(status: .open)))) as? [String: Any])
        json["parkId"] = 5
        let payload = try JSONSerialization.data(withJSONObject: json)
        AuditURLProtocol.response = { request in
            XCTAssertTrue(request.url?.query?.contains("park=5") == true)
            return payload
        }
        defer { AuditURLProtocol.response = nil }
        let store = DashboardStore(apiClient: hhnTestClient(), defaults: defaults)
        await store.refreshCrowd(for: .epcot)
        XCTAssertEqual(store.selectedPark, .magicKingdom)
        XCTAssertEqual(defaults.integer(forKey: "pivot.selectedPark"), 6)
        XCTAssertEqual(store.crowdSnapshot(for: .epcot)?.parkId, 5)
        XCTAssertFalse(store.crowdRefreshFailed(for: .epcot))
        AuditURLProtocol.response = { _ in throw URLError(.notConnectedToInternet) }
        await store.refreshCrowd(for: .epcot)
        XCTAssertTrue(store.crowdRefreshFailed(for: .epcot))
        XCTAssertEqual(store.crowdSnapshot(for: .epcot)?.parkId, 5)
        XCTAssertFalse(store.crowdLoading.contains(5))
        store.selectPark(nil)
        XCTAssertNil(store.selectedPark)
        XCTAssertEqual(store.crowdSnapshot(for: .epcot)?.parkId, 5)
    }

    func testWaitLearningRecordsOnlyHealthyValidWaitsWithoutPollInflation() throws {
        let now = start.addingTimeInterval(300)
        let rides = (1...6).map { makeRide(id: $0, status: .open, waitTime: $0 * 10) }
        var observation = makeSnapshot(sourceOffset: 300, ride: rides[0])
        let helper = NativeWaitForecastTests()
        observation.parkHours = helper.hours(open: "2026-04-04T13:00:00Z", close: "2026-04-05T01:00:00Z", at: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(observation)) as? [String: Any])
        json["rides"] = try JSONSerialization.jsonObject(with: encoder.encode(rides))
        func decode() throws -> LiveParkSnapshot { try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json)) }
        observation = try decode()
        var history = WaitLearningHistory()
        XCTAssertTrue(history.record(observation, now: now))
        XCTAssertFalse(history.record(observation, now: now), "Repeated polls have one vote per quarter-hour")
        XCTAssertEqual(history.bins.count, 6)
        XCTAssertEqual(history.liveCrowd(park: .magicKingdom, snapshot: observation, failed: false, now: now)?.typicalWait, 35)
        XCTAssertNil(history.liveCrowd(park: .magicKingdom, snapshot: observation, failed: true, now: now))
        XCTAssertNil(history.liveCrowd(park: .magicKingdom, snapshot: observation, failed: false, now: now.addingTimeInterval(900)))
        for (field, value) in [("feedHealthy", false), ("parkActive", false)] {
            json[field] = value
            var empty = WaitLearningHistory()
            XCTAssertFalse(empty.record(try decode(), now: now))
            XCTAssertNil(empty.liveCrowd(park: .magicKingdom, snapshot: try decode(), failed: false, now: now))
            json[field] = true
        }
        for day in ["2026-04-03", "2026-04-02", "2026-04-01"] {
            for id in 1...6 {
                let bin = WaitLearningBin(parkID: 6, rideID: id, day: day, weekday: 7, hour: 12,
                    quarters: [0: Double(id * 5)], lastSeen: start.addingTimeInterval(-86400))
                history.bins["6:\(id):\(day):12"] = bin
                history.eligibleCounts["6:\(day):12"] = 6
            }
        }
        let adjusted = history.forecast(rideID: 1, park: .magicKingdom, hours: observation.parkHours,
            snapshot: observation, failed: false, now: now)
        XCTAssertEqual(adjusted.first?.minutes, 10, "Twice normal park waits scales the baseline")
        XCTAssertEqual(adjusted.first?.crowdAdjusted, true)
        let saved = history.forecast(rideID: 1, park: .magicKingdom, hours: observation.parkHours,
            snapshot: observation, failed: true, now: now)
        XCTAssertEqual(saved.first?.minutes, 5)
        XCTAssertEqual(saved.first?.crowdAdjusted, false, "Failed data never supplies the crowd adjustment")
        var rows = try XCTUnwrap(json["rides"] as? [[String: Any]])
        rows[0]["lastUpdated"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(121))
        rows[1]["waitTime"] = NSNull()
        rows[2]["status"] = "DOWN"; rows[2]["isOpen"] = false
        json["rides"] = rows
        json["fetchedAt"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(120))
        rows[0]["lastUpdated"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(220))
        json["rides"] = rows
        XCTAssertNil(WaitLearningHistory.currentWaits(try decode(), now: now)[1], "Fetch clock skew must not extend permitted source skew")
        json["fetchedAt"] = ISO8601DateFormatter().string(from: now)
        rows[0]["lastUpdated"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(121))
        json["rides"] = rows
        var invalid = WaitLearningHistory()
        XCTAssertTrue(invalid.record(try decode(), now: now))
        XCTAssertEqual(invalid.bins.count, 3)
        XCTAssertNil(invalid.liveCrowd(park: .magicKingdom, snapshot: try decode(), failed: false, now: now))
        XCTAssertNil(invalid.dailyCrowd(park: .magicKingdom, date: now, now: now))
    }

    func testWaitLearningRejectsConflictingDuplicateAndFutureSamples() throws {
        let now = start.addingTimeInterval(300)
        var ride = makeRide(status: .open)
        ride.waitHistory = [WaitHistorySample(observedAt: start, waitTime: 10), WaitHistorySample(observedAt: start, waitTime: 60),
            WaitHistorySample(observedAt: now.addingTimeInterval(1), waitTime: 0)]
        var observation = makeSnapshot(sourceOffset: 300, ride: ride)
        observation.parkHours = NativeWaitForecastTests().hours(open: "2026-04-04T13:00:00Z", close: "2026-04-05T01:00:00Z", at: now)
        var history = WaitLearningHistory()
        XCTAssertTrue(history.record(observation, now: now))
        XCTAssertEqual(history.bins.values.first?.mean, 35, "Only the valid current snapshot observation survives")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(observation)) as? [String: Any])
        json["rides"] = try JSONSerialization.jsonObject(with: encoder.encode([ride, ride]))
        let duplicate = try PivotAPIClient.makeDecoder().decode(LiveParkSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        var empty = WaitLearningHistory()
        XCTAssertFalse(empty.record(duplicate, now: now))
        XCTAssertTrue(WaitLearningHistory.currentWaits(duplicate).isEmpty)
    }

    private func makeRide(
        id: Int = 126,
        name: String = "Space Mountain",
        land: String = "Tomorrowland",
        status: RideStatus,
        waitTime: Int? = 35,
        reopenPending: Bool = false,
        radarEligible: Bool = true,
        downSince: Date? = nil,
        elapsedDownMinutes: Int? = nil,
        minimumDownMinutes: Int? = nil,
        trend: [Int] = [30, 35, 40],
        statusAgreement: String? = nil,
        scheduledReason: String? = nil,
        scheduledClosure: ScheduledClosure? = nil,
        operatingWindow: AttractionOperatingWindow? = nil,
        estimateKind: String = "OPERATIONAL",
        delayType: String? = nil,
        delayEvidence: DelayEvidence? = nil,
        weatherExposure: String = "INDOOR",
        forecastRevision: Int = 0,
        forecastRevisionReason: String = "INITIAL",
        location: AttractionLocation? = nil
    ) -> LiveRide {
        LiveRide(
            id: id,
            name: name,
            land: land,
            status: status,
            isOpen: status == .open,
            waitTime: status == .open ? waitTime : nil,
            lastUpdated: start,
            downSince: status == .down ? downSince : nil,
            elapsedDownMinutes: elapsedDownMinutes,
            minimumDownMinutes: minimumDownMinutes,
            estimate: status == .down
                ? makeEstimate(
                    phase: .upcoming,
                    estimateKind: estimateKind,
                    revision: forecastRevision,
                    revisionReason: forecastRevisionReason
                )
                : nil,
            estimateReason: nil,
            delayType: delayType ?? (status == .down ? "RIDE" : nil),
            delayEvidence: delayEvidence,
            weatherExposure: weatherExposure,
            radarEligible: radarEligible,
            radarCategory: "RIDE",
            reopenPending: reopenPending,
            trend: trend,
            location: location,
            themeParksWikiStatus: nil,
            waitTimeSource: status == .open ? "THEMEPARKS_WIKI" : nil,
            scheduledClosure: scheduledClosure,
            statusAgreement: statusAgreement,
            statusProvenance: nil,
            statusComparisonReason: nil,
            scheduledReason: scheduledReason,
            operatingWindow: operatingWindow
        )
    }

    private func makeThemeParksWikiSummary(
        available: Bool = true,
        cacheStale: Bool = false,
        fetchedAt: Date? = nil
    ) -> ThemeParksWikiSummary {
        ThemeParksWikiSummary(
            available: available,
            cacheStale: cacheStale,
            fetchedAt: fetchedAt ?? start,
            sourceUpdatedAt: start.addingTimeInterval(-3600),
            cacheAgeSeconds: 0,
            cacheHit: false,
            matchedRideCount: 1,
            unmatchedRides: [],
            showCount: nil,
            showsWithUpcomingTimes: nil,
            showSourceUpdatedAt: nil,
            warning: nil,
            role: "PRIMARY",
            statusSemantics: "Current provider status",
            usedForWaitTimes: true,
            usedForOperationalEligibility: true,
            usedForOperationalTraining: false,
            source: makeThemeParksWikiAttribution()
        )
    }

    private func makeThemeParksWikiAttribution() -> ThemeParksWikiAttribution {
        ThemeParksWikiAttribution(name: "ThemeParks.wiki", label: "ThemeParks.wiki", url: "https://www.themeparks.wiki/", termsUrl: "https://www.themeparks.wiki/", updateCadenceMinutes: 5)
    }

    private func makeParkHours(
        park: FloridaPark = .magicKingdom,
        date: String = "2026-09-30",
        fetchedAt: Date? = nil,
        stale: Bool = false
    ) -> ParkHoursSnapshot {
        ParkHoursSnapshot(
            parkId: park.rawValue,
            parkName: park.name,
            timezone: park.timeZoneIdentifier,
            date: date,
            fetchedAt: fetchedAt ?? start,
            sourceUpdatedAt: nil,
            cacheAgeSeconds: 0,
            cacheHit: true,
            stale: stale,
            warning: nil,
            regular: nil,
            earlyEntry: nil,
            source: makeThemeParksWikiAttribution()
        )
    }

    private func makeSnapshot(
        sourceOffset: TimeInterval,
        waitStatusSourceOffset: TimeInterval? = nil,
        feedHealthy: Bool = true,
        themeParksWiki: ThemeParksWikiSummary? = nil,
        ride: LiveRide
    ) -> LiveParkSnapshot {
        let sourceDate = start.addingTimeInterval(sourceOffset)
        let waitStatusSourceDate = start.addingTimeInterval(waitStatusSourceOffset ?? sourceOffset)
        return LiveParkSnapshot(
            parkId: 6,
            park: ParkMetadata(
                name: "Magic Kingdom Park",
                destination: "Walt Disney World",
                operatorName: "Disney",
                country: "United States",
                timezone: "America/New_York"
            ),
            parkActive: true,
            feedHealthy: feedHealthy,
            fetchedAt: sourceDate,
            sourceUpdatedAt: sourceDate,
            sourceUpdatedAtByProvider: ProviderSourceTimes(
                queueTimes: nil,
                themeParksWiki: waitStatusSourceDate
            ),
            cacheAgeSeconds: 0,
            rides: [ride],
            metrics: ParkMetrics(
                openCount: ride.status == .open ? 1 : 0,
                downCount: ride.status == .down ? 1 : 0,
                scheduledCount: ride.status == .scheduled ? 1 : 0,
                averageWait: ride.waitTime,
                reportingCount: 1
            ),
            source: SourceDetails(name: "ThemeParks.wiki", url: "https://www.themeparks.wiki/", updateCadenceMinutes: 5),
            themeParksWiki: themeParksWiki,
            weather: makeWeather(at: sourceDate)
        )
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

private final class AuditURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "audit.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let response = Self.response else { throw URLError(.badServerResponse) }
            let data = try response(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
