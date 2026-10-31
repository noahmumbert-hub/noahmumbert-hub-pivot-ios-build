import XCTest

final class PIVOTUITests: XCTestCase {
    private func mapFixtureApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--park-map-ui-test"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Full screen map"].waitForExistence(timeout: 10))
        return app
    }

    private func chooseMapCategory(_ category: String, app: XCUIApplication) {
        app.buttons["Filter map places"].tap()
        let choice = app.buttons[category].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
    }

    private func rootFixture(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--apple-ui-test", "--apple-ui-fixtures", "--ui-light"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].waitForExistence(timeout: 10))
        return app
    }

    private func camera(_ app: XCUIApplication) -> [Double] {
        let probe = app.staticTexts["Map camera state"]
        guard probe.exists else { return [.nan, .nan, .nan] }
        let values = probe.label.split(separator: ",").compactMap { Double($0) }
        return values.count == 3 ? values : [.nan, .nan, .nan]
    }

    private func waitForCamera(_ app: XCUIApplication, _ condition: @escaping ([Double]) -> Bool,
                               timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in
            let values = self.camera(app)
            return values.count == 3 && condition(values)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout)
        if result != .completed {
            XCTFail("Last measured camera: \(camera(app)); events: \(mapEvents(app))", file: file, line: line)
        }
    }

    private func mapEvents(_ app: XCUIApplication) -> String {
        let trace = app.staticTexts["Map event trace"]
        return trace.exists ? trace.label : "No map events available"
    }

    func testReferenceEPCOTCardsSearchFiltersAndPhotoCredits() {
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark"])
        let header = app.descendants(matching: .any)["PIVOT header"]
        let park = app.buttons["Change park. Current park: EPCOT"]
        XCTAssertTrue(park.waitForExistence(timeout: 5))
        XCTAssertLessThan(header.frame.maxY, park.frame.minY)
        XCTAssertLessThan(header.frame.minX, app.frame.width / 2)
        XCTAssertTrue(app.buttons["Refresh ride data now"].isHittable)
        screenshot("Reference EPCOT dark overview", app: app)
        app.buttons["Photo credit"].tap()
        XCTAssertTrue(app.navigationBars["Photo credit"].waitForExistence(timeout: 5))
        // SwiftUI Link inside a native List is exposed as a Button on iOS 26.
        let source = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Original photo'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.isHittable)
        app.buttons["Done"].tap()
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        let keyboardGone = NSPredicate { _, _ in !app.keyboards.firstMatch.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardGone, object: nil)], timeout: 5), .completed,
                       "Submitting a ride search must dismiss the keyboard so results remain reachable on compact phones")
        let guardians = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guardians of the Galaxy'")).firstMatch
        reveal(guardians, in: app)
        XCTAssertTrue(guardians.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remy'")).firstMatch.exists)
        reveal(app.buttons["Clear ride search"], in: app)
        app.buttons["Clear ride search"].tap()
        let filters = app.segmentedControls["ride-status-filter"]
        reveal(filters, in: app); filters.buttons["Down"].tap()
        let down = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Spaceship Earth'")).firstMatch
        reveal(down, in: app)
        XCTAssertTrue(down.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guardians of the Galaxy'")).firstMatch.exists)
        screenshot("Reference EPCOT down filter", app: app)
    }

    func testRideSearchKeepsHistoricalSizeAndCurrentWaits() {
        for expired in [false, true] {
            let app = rootFixture(["--reference-ui-park=5", "--ui-dark"] + (expired ? ["--ride-search-expired"] : []))
            let control = app.descendants(matching: .any)["ride-search-control"].firstMatch
            reveal(control, in: app)
            XCTAssertEqual(control.frame.height, 46, accuracy: 1)
            XCTAssertEqual(app.buttons["ride-sort-menu"].frame.height, 46, accuracy: 1)
            let search = app.textFields["Ride search"]
            search.tap(); search.typeText("Guardians\n")
            let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guardians of the Galaxy'")).firstMatch
            reveal(result, in: app)
            XCTAssertTrue(result.isHittable)
            XCTAssertTrue(result.label.contains(expired ? "Wait unavailable" : "45 minute wait"))
            if expired { XCTAssertFalse(result.label.contains("45 minute wait")) }
            screenshot(expired ? "Search expired wait withheld" : "Search historical size and live wait", app: app)
            result.tap()
            let status = app.staticTexts[expired ? "Wait unavailable" : "45 min wait"].firstMatch
            reveal(status, in: app); XCTAssertTrue(status.isHittable)
            app.buttons["Done"].tap()
            reveal(app.buttons["Clear ride search"], in: app); app.buttons["Clear ride search"].tap()
            reveal(search, in: app); search.tap(); search.typeText("Spaceship\n")
            let closed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Spaceship Earth'")).firstMatch
            reveal(closed, in: app)
            XCTAssertTrue(closed.label.contains(expired ? "Wait unavailable" : "Temporarily closed"))
            XCTAssertFalse(closed.label.contains("0 minute wait"))
            app.terminate()
        }
    }

    func testObservedWaitDotsKeepEveryValueAndOpenLowestWaitForecast() {
        let app = rootFixture(["--reference-ui-park=5", "--ride-history-ui-test", "--ride-history-supported"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
        reveal(history, in: app); history.tap()
        let chart = app.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
        reveal(chart, in: app); XCTAssertTrue(chart.isHittable)
        screenshot("Every observed wait dot labeled latest samples", app: app)
        chart.swipeRight()
        screenshot("Every observed wait dot labeled earlier samples", app: app)
        let sampleTimes = app.staticTexts["Sample times"].firstMatch
        reveal(sampleTimes, in: app); sampleTimes.tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'wait-sample-row-10916-'")).count, 12)
        XCTAssertTrue(app.staticTexts["wait-sample-row-10916-4"].label.contains("0 min"), "A supplied zero is preserved")
        let lowest = app.staticTexts["ride-lowest-wait-window"]
        reveal(lowest, in: app); XCTAssertTrue(lowest.label.contains("about 10 min"))
        screenshot("Supported lowest wait prediction beside observed history", app: app)
        let hourly = app.buttons["ride-history-hourly-estimates"]
        reveal(hourly, in: app); hourly.tap()
        XCTAssertTrue(app.staticTexts["Lowest estimated wait"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testHistoryLowestWaitPredictionWithholdsMissingAndStaleEvidence() {
        for expired in [false, true] {
            let args = ["--reference-ui-park=5", "--ride-history-ui-test"] + (expired ? ["--ride-history-supported", "--ride-search-expired"] : [])
            let app = rootFixture(args)
            let search = app.textFields["Ride search"]
            reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
            let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
            reveal(history, in: app); history.tap()
            let unavailable = app.staticTexts["Prediction unavailable"].firstMatch
            reveal(unavailable, in: app); XCTAssertTrue(unavailable.isHittable)
            XCTAssertFalse(app.staticTexts["ride-lowest-wait-window"].exists)
            screenshot(expired ? "Stale source withholds lowest wait prediction" : "Insufficient history has no invented prediction", app: app)
            app.terminate()
        }
    }

    func testReopeningWindowShowsSupportedBestPredictionAndUnavailableStates() {
        for mode in ["supported", "uncalibrated", "expired"] {
            let extra = mode == "uncalibrated" ? ["--reopening-unsupported"] : mode == "expired" ? ["--ride-search-expired"] : []
            let app = rootFixture(["--reference-ui-park=5", "--reopening-ui-test"] + extra)
            let search = app.textFields["Ride search"]
            reveal(search, in: app); search.tap(); search.typeText("Spaceship\n")
            let best = mode == "supported"
                ? app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Best prediction ·'")).firstMatch
                : app.staticTexts["Best prediction unavailable"].firstMatch
            reveal(best, in: app); XCTAssertTrue(best.isHittable)
            if mode != "expired" { XCTAssertTrue(app.staticTexts["Historical reopening range"].exists) }
            else { XCTAssertFalse(app.staticTexts["Historical reopening range"].exists) }
            screenshot("Reopening best prediction \(mode)", app: app)
            let ride = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Spaceship Earth'")).firstMatch
            reveal(ride, in: app); ride.tap()
            reveal(best, in: app); XCTAssertTrue(best.isHittable)
            app.buttons["Done"].tap(); app.terminate()
        }
    }

    func testFavoriteRideSearchConnectsWaitsAndSupportsLargeText() {
        for mode in ["default", "large", "expired"] {
            let extra = mode == "large" ? ["--ui-large-type"] : mode == "expired" ? ["--ride-search-expired"] : []
            let app = rootFixture(["--reference-ui-park=5", "--ui-dark"] + extra)
            app.tabBars.buttons["Plan"].tap()
            let choose = app.buttons["native-day-favorites"]
            reveal(choose, in: app); choose.tap()
            if mode == "large" {
                let bodySize = app.staticTexts["Favorite search body size"]
                XCTAssertTrue(bodySize.waitForExistence(timeout: 5))
                XCTAssertGreaterThanOrEqual(bodySize.frame.height, 35, "The favorite sheet must actually render accessibility-size body text")
            }
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText("World Discovery\n")
            let guardians = app.switches["favorite-ride-10916"]
            reveal(guardians, in: app)
            XCTAssertTrue(guardians.isHittable)
            XCTAssertTrue(guardians.label.contains(mode == "expired" ? "Wait unavailable" : "45 min wait"))
            XCTAssertFalse(app.switches["favorite-ride-10914"].exists, "Land search must exclude World Showcase")
            let closed = app.switches["favorite-ride-159"]
            reveal(closed, in: app)
            XCTAssertTrue(closed.isHittable)
            XCTAssertTrue(closed.label.contains(mode == "expired" ? "Wait unavailable" : "Temporarily closed"))
            XCTAssertGreaterThanOrEqual(closed.frame.height, 44)
            screenshot("Favorite search \(mode) waits and status", app: app)
            let endSearch = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "close"])).firstMatch
            XCTAssertTrue(endSearch.waitForExistence(timeout: 5)); endSearch.tap()
            app.buttons["Done"].tap(); app.terminate()
        }
    }

    func testGeneratedRideIllustrationLoadsWithCreditsAndPreservesWaits() {
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        let guardians = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guardians of the Galaxy'")).firstMatch
        reveal(guardians, in: app)
        screenshot("Illustration Guardians ride card", app: app)
        guardians.tap()
        let artwork = app.descendants(matching: .any)["ride-illustration-5-10916"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let loaded = NSPredicate { _, _ in artwork.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
        screenshot("Illustration Guardians detail artwork", app: app)
        let credit = app.descendants(matching: .any)["ride-illustration-credit"].firstMatch
        reveal(credit, in: app)
        XCTAssertTrue(credit.isHittable)
        XCTAssertTrue(app.staticTexts["AI-generated illustration"].exists)
        let reference = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Reference photo: Jedi94'")).firstMatch
        reveal(reference, in: app)
        XCTAssertTrue(reference.isHittable)
        let wait = app.staticTexts["45 min wait"]
        reveal(wait, in: app)
        XCTAssertTrue(wait.isHittable)
        screenshot("Illustration credits and current wait", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Plan"].tap()
        reveal(app.buttons["native-day-favorites"], in: app)
        XCTAssertTrue(app.buttons["native-day-favorites"].isHittable)
    }

    func testGeneratedRideWithReservedPhotoRightsKeepsAccurateCredits() {
        let app = rootFixture(["--reference-ui-park=60", "--reference-ui-ride=9600564880643", "--ui-dark"])
        let ride = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'K.I. & Miami Valley Railroad'")).firstMatch
        reveal(ride, in: app)
        XCTAssertTrue(ride.isHittable)
        screenshot("Illustration Kings Island railroad card", app: app)
        ride.tap()
        let artwork = app.descendants(matching: .any)["ride-illustration-60-9600564880643"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let loaded = NSPredicate { _, _ in artwork.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
        screenshot("Illustration Kings Island railroad detail", app: app)
        let rights = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Reference rights: Copyright Six Flags; source rights retained'")).firstMatch
        reveal(rights, in: app)
        XCTAssertTrue(rights.isHittable)
        XCTAssertTrue(app.staticTexts["AI-generated illustration"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Illustration adaptation:'")).firstMatch.exists)
        screenshot("Illustration reserved reference rights", app: app)
        let wait = app.staticTexts["45 min wait"]
        reveal(wait, in: app)
        XCTAssertTrue(wait.isHittable)
    }

    func testReferenceCardsKeepEachParksIdentityAndNativeTabs() {
        // Photo, fallback, water park, Canadian park, and long-name coverage.
        for (id, name) in [(65, "Universal Studios Florida"), (50, "Cedar Point"),
                           (58, "Canada’s Wonderland"), (41, "Hurricane Harbor Los Angeles")] {
            let app = rootFixture(["--reference-ui-park=\(id)", "--ui-dark"])
            let park = app.buttons["Change park. Current park: \(name)"]
            XCTAssertTrue(park.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Current rides"].exists)
            XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 5)
            returnToTop(app)
            XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].isHittable)
            screenshot("Reference park \(id) overview", app: app)
            app.tabBars.buttons["Plan"].tap()
            XCTAssertTrue(park.waitForExistence(timeout: 5))
            reveal(app.buttons["native-day-favorites"], in: app)
            XCTAssertTrue(app.buttons["native-day-favorites"].isHittable)
            app.terminate()
        }
    }

    func testNativeMapFillsWindowAndSupportsPinchPanZoomWithoutCameraReset() {
        let app = rootFixture(["--map-gesture-test"])
        app.tabBars.buttons["Map"].tap()
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertEqual(app.maps.count, 1, "Measure the actual native Map accessibility element")
        XCTAssertEqual(map.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(map.frame.minY, app.frame.minY, accuracy: 1)
        XCTAssertEqual(map.frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(map.frame.height, app.frame.height, accuracy: 1)
        waitForCamera(app) { abs($0[0] - 28.419) < 0.006 && abs($0[1] + 81.581) < 0.006 && $0[2] > 0 && $0[2] < 10_000 }
        let initial = camera(app)
        XCTAssertEqual(initial[0], 28.419, accuracy: 0.006)
        XCTAssertEqual(initial[1], -81.581, accuracy: 0.006)
        XCTAssertLessThan(initial[2], 10_000, "Whole-park fit must frame the park, not the surrounding region")
        // Real two-finger gestures begin inside native map pixels, clear of the
        // search/Browse overlays that occupy the whole Map element's outer edges.
        let gestureArea = app.descendants(matching: .any)["Map gesture area"]
        XCTAssertTrue(gestureArea.waitForExistence(timeout: 5))
        XCTAssertTrue(map.frame.contains(gestureArea.frame))
        XCTAssertFalse(gestureArea.frame.intersects(app.textFields["Search park places"].frame))
        XCTAssertFalse(gestureArea.frame.intersects(app.buttons["Browse map places"].frame))
        XCTAssertFalse(gestureArea.frame.intersects(app.buttons["Zoom in"].frame))
        let initialPins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map-pin-' OR identifier == 'Map place cluster'"))
        XCTAssertGreaterThan(initialPins.count, 0, "The initial park fit must contain its loaded annotations")
        let pinchTouchBounds = gestureArea.frame.insetBy(dx: 24, dy: 24)
        XCTAssertFalse(initialPins.allElementsBoundByIndex.contains { $0.frame.intersects(pinchTouchBounds) },
                       "Both physical fingers must begin and move through empty map pixels")
        // A substantial physical span avoids a tiny14pt→28pt gesture entirely
        // inside a marker's44pt touch target. The actual native camera must zoom.
        gestureArea.pinch(withScale: 6, velocity: 1)
        waitForCamera(app) { $0[2] < initial[2] * 0.85 }
        let pinched = camera(app)
        XCTAssertTrue(gestureArea.waitForExistence(timeout: 5))
        gestureArea.pinch(withScale: 0.5, velocity: -1)
        waitForCamera(app) { $0[2] > pinched[2] * 1.15 }
        let beforeDoubleTap = camera(app)
        // A marker consumes a double-tap as selection. Measure empty native map
        // pixels rather than assuming a fixed coordinate stays empty after zooming.
        let occupied = app.buttons.allElementsBoundByIndex.map { $0.frame.insetBy(dx: -24, dy: -24) }
            + app.links.allElementsBoundByIndex.map { $0.frame.insetBy(dx: -12, dy: -12) }
        let top = app.textFields["Search park places"].frame.maxY + 24
        let bottom = app.buttons["Browse map places"].frame.minY - 24
        let area = CGRect(x: map.frame.minX + 24, y: top, width: map.frame.width - 48, height: bottom - top)
        XCTAssertGreaterThan(area.height, 0)
        let fractions: [CGFloat] = (1...19).map { CGFloat($0) / 20 }
        let candidates = fractions.flatMap { y in
            fractions.map { x in CGPoint(x: area.minX + area.width * x, y: area.minY + area.height * y) }
        }
        guard let empty = candidates.first(where: { point in !occupied.contains { $0.contains(point) } }) else {
            XCTFail("No clear map pixels available for the native double-tap gesture"); return
        }
        map.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: empty.x - map.frame.minX, dy: empty.y - map.frame.minY)).doubleTap()
        waitForCamera(app) { $0[2] < beforeDoubleTap[2] * 0.85 }
        let doubled = camera(app)
        app.buttons["Zoom out"].tap()
        waitForCamera(app) { abs($0[2] - doubled[2] * 2) < doubled[2] * 0.2 }
        app.buttons["Zoom in"].tap()
        waitForCamera(app) { abs($0[2] - doubled[2]) < doubled[2] * 0.1 }
        let beforePan = camera(app)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)))
        waitForCamera(app) { abs($0[0] - beforePan[0]) + abs($0[1] - beforePan[1]) > 0.0002 }
        let panned = camera(app)
        // Wait through the visible map's 15-second status refresh; camera must remain user-owned.
        let tick = expectation(description: "Map freshness tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { tick.fulfill() }
        wait(for: [tick], timeout: 18)
        XCTAssertEqual(camera(app)[0], panned[0], accuracy: 0.0001)
        XCTAssertEqual(camera(app)[1], panned[1], accuracy: 0.0001)
        XCTAssertEqual(camera(app)[2], panned[2], accuracy: panned[2] * 0.05)
        screenshot("Native edge-to-edge map after pinch and pan", app: app)
        app.buttons["Close full screen map"].tap()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 5))
        waitForCamera(app) { abs($0[0] - panned[0]) < 0.0002 && abs($0[1] - panned[1]) < 0.0002 && abs($0[2] - panned[2]) < panned[2] * 0.05 }
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        waitForCamera(app) { abs($0[0] - panned[0]) < 0.0002 && abs($0[1] - panned[1]) < 0.0002 && abs($0[2] - panned[2]) < panned[2] * 0.05 }
        app.buttons["Zoom out"].tap()
        waitForCamera(app) { $0[2] > panned[2] * 1.3 }
        app.buttons["Show whole park"].tap()
        waitForCamera(app) { abs($0[0] - initial[0]) < 0.0002 && abs($0[1] - initial[1]) < 0.0002 }
        let beforeFilter = camera(app)
        chooseMapCategory("Food", app: app)
        XCTAssertEqual(camera(app)[0], beforeFilter[0], accuracy: 0.0001)
        XCTAssertEqual(camera(app)[1], beforeFilter[1], accuracy: 0.0001)
        XCTAssertEqual(camera(app)[2], beforeFilter[2], accuracy: beforeFilter[2] * 0.05)
        app.buttons["Show whole park"].tap()
        XCTAssertFalse(app.buttons["map-pin-b2260923-9315-40fd-9c6b-44dd811dbe64"].exists)
        screenshot("Native full-screen food map and Apple attribution", app: app)
    }

    func testNativeClustersZoomAndCoLocatedPlacesRemainSelectable() {
        let app = mapFixtureApp()
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        chooseMapCategory("Rides", app: app)
        waitForCamera(app) { $0[2] > 0 && $0[2] < 10_000 }
        let initialAltitude = camera(app)[2]
        app.buttons["Zoom out"].tap()
        app.buttons["Zoom out"].tap()
        // The loaded simulator took13.8s to finish this consecutive MapKit
        // animation. Require its actual settled camera, with the same scale gate.
        waitForCamera(app, { $0[2] > initialAltitude * 3 }, timeout: 20)
        XCTAssertEqual(camera(app)[2], initialAltitude * 4, accuracy: initialAltitude * 0.4,
                       "Two zoom-out presses must settle near four times the original altitude")
        let cluster = app.buttons["Map place cluster"].firstMatch
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        let before = camera(app)
        cluster.tap()
        waitForCamera(app) { $0[2] < before[2] * 0.85 }
        chooseMapCategory("Food", app: app)
        app.buttons["Show whole park"].tap()
        XCTAssertTrue(cluster.waitForExistence(timeout: 5)); cluster.tap()
        let member = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'North counter'")).firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'South counter'")).firstMatch.exists)
        screenshot("Co-located map places native member list", app: app)
        member.tap()
        XCTAssertTrue(app.staticTexts["North counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dining location · hours unavailable"].exists)
    }

    func testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent() {
        let app = rootFixture()
        app.tabBars.buttons["Map"].tap()
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        let map = app.maps.firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let search = app.textFields["Search park places"]
        search.tap(); search.typeText("Space Mountain\n")
        app.buttons["Browse map places"].tap()
        let ride = app.buttons["map-place-row-b2260923-9315-40fd-9c6b-44dd811dbe64"]
        XCTAssertTrue(ride.waitForExistence(timeout: 5)); ride.tap()
        XCTAssertTrue(app.staticTexts["Selected ride wait"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "45 min")
        XCTAssertTrue(app.staticTexts["Selected ride wait"].isHittable)
        XCTAssertTrue(app.buttons["map-pin-b2260923-9315-40fd-9c6b-44dd811dbe64"].isHittable)
        let legal = app.links["Legal"]
        XCTAssertTrue(legal.exists)
        XCTAssertTrue(map.frame.contains(legal.frame), "Native Apple attribution must remain inside the map window")
        XCTAssertLessThan(legal.frame.maxY, app.staticTexts["Selected place name"].frame.minY)
        screenshot("Native production full-screen selected current ride", app: app)
        // MapKit's virtual Legal accessibility element reports isHittable=false
        // even though its real link opens Safari. Verify the actual user journey.
        legal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        let openStreetMapCredit = safari.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "openstreetmap.org/copyright")).firstMatch
        XCTAssertTrue(openStreetMapCredit.waitForExistence(timeout: 20), "The native Legal link must open the actual map-data attribution page")
        XCTAssertTrue(safari.links["Apple Inc."].exists)
        screenshot("Native Apple map attribution reached from the map", app: safari)
        app.activate()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["Selected place name"].label, "Space Mountain")
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "45 min")
        XCTAssertTrue(app.staticTexts["Selected ride wait"].isHittable)
        app.buttons["Close place details"].tap()
        let pin = app.buttons["map-pin-b2260923-9315-40fd-9c6b-44dd811dbe64"]
        XCTAssertGreaterThanOrEqual(pin.frame.width, 44)
        XCTAssertGreaterThanOrEqual(pin.frame.height, 44)
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Selected ride wait"].waitForExistence(timeout: 3), "The edge of the native marker’s 44-point target must select the ride")
        app.buttons["Ride details"].tap()
        XCTAssertTrue(app.staticTexts["Current wait"].waitForExistence(timeout: 5))
        screenshot("Native ride detail sheet", app: app)
    }

    func testNativeSurfacesPreserveHoursShowsAlertsAndPlanProgress() {
        let app = rootFixture()
        screenshot("Native Waits light", app: app)
        app.tabBars.buttons["Shows"].tap()
        let show = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Castle afternoon performance'")).firstMatch
        reveal(show, in: app); XCTAssertTrue(show.waitForExistence(timeout: 5)); show.tap()
        screenshot("Native Shows light", app: app)
        app.tabBars.buttons["Plan"].tap()
        let favorites = app.buttons["native-day-favorites"]
        reveal(favorites, in: app); favorites.tap()
        let toggle = app.switches["favorite-ride-138"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "The actual favorite switch must be on before leaving the editor")
        app.buttons["Done"].tap()
        let progress = app.buttons["All favorites & progress"]
        reveal(progress, in: app); progress.tap()
        let undo = app.buttons["progress-undo-138"]
        if undo.exists { reveal(undo, in: app); undo.tap() }
        let done = app.buttons["progress-done-138"]
        reveal(done, in: app); done.tap()
        reveal(undo, in: app); undo.tap()
        let skip = app.buttons["progress-skip-138"]
        reveal(skip, in: app); skip.tap()
        reveal(undo, in: app); undo.tap()
        screenshot("Native Plan light with retained progress controls", app: app)
        app.tabBars.buttons["More"].tap()
        reveal(app.buttons["Park hours & early entry"], in: app)
        app.buttons["Park hours & early entry"].tap()
        XCTAssertTrue(app.staticTexts["Early entry"].waitForExistence(timeout: 5))
        screenshot("Native park hours and early entry", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["Ride alerts & Live Activity"], in: app)
        app.buttons["Ride alerts & Live Activity"].tap()
        XCTAssertTrue(app.switches["Alerts favorites only"].waitForExistence(timeout: 5))
        screenshot("Native alert settings Form", app: app)
    }

    func testNativeDarkAndLargeTextSurfacesRemainReachable() {
        let app = rootFixture(["--ui-dark", "--ui-large-type"])
        screenshot("Native Waits dark accessibility text", app: app)
        app.tabBars.buttons["More"].tap()
        screenshot("Native More dark accessibility text", app: app)
        reveal(app.buttons["Settings"], in: app)
        app.buttons["Settings"].tap()
        let settingsBody = app.staticTexts["Settings body size"]
        XCTAssertTrue(settingsBody.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(settingsBody.frame.height, 35, "Settings must actually render accessibility-size body text")
        reveal(app.buttons["accent-mint"], in: app)
        app.buttons["accent-mint"].tap()
        screenshot("Native Settings dark accessibility text", app: app)
        app.buttons["Done"].tap()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["Full screen map"].waitForExistence(timeout: 5))
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        let mapBody = app.staticTexts["Map body size"]
        XCTAssertTrue(mapBody.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(mapBody.frame.height, 35, "The fullscreen map must actually render accessibility-size body text")
        XCTAssertTrue(app.buttons["Zoom in"].isHittable)
        XCTAssertTrue(app.buttons["Browse map places"].isHittable)
        let legal = app.links["Legal"]
        XCTAssertTrue(legal.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(legal.frame.maxY, app.buttons["Browse map places"].frame.minY - 4,
                                 "Large-text Browse must leave the native attribution completely visible")
        screenshot("Native map dark accessibility text", app: app)
    }

    private func selectMapFixture(_ name: String, id: Int, app: XCUIApplication) {
        if app.buttons["Clear place search"].exists { app.buttons["Clear place search"].tap() }
        let search = app.textFields["Search park places"]
        search.tap()
        search.typeText(name + "\n")
        // The fixture's stable identifier is separate from the displayed ride name.
        let fixturePin = app.buttons["map-pin-fixture-\(id)"]
        XCTAssertTrue(fixturePin.waitForExistence(timeout: 5))
        // Dismissing the keyboard and the previous ride card changes map insets.
        // Give keyboard dismissal its own condition; repeatedly querying the
        // keyboard's AX tree must not consume the pin's stability interval.
        let keyboardGone = NSPredicate { _, _ in !app.keyboards.firstMatch.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardGone, object: nil)], timeout: 5), .completed,
                       "The search keyboard must dismiss before selecting the map pin")
        // Wait for the visible pin to stop moving, then perform one real tap.
        let windowFrame = app.frame
        var previousFrame = fixturePin.exists ? fixturePin.frame : CGRect.null
        var stableSince = Date()
        let stablePin = NSPredicate { _, _ in
            guard fixturePin.exists else {
                previousFrame = .null; stableSince = Date(); return false
            }
            let frame = fixturePin.frame
            guard !frame.isEmpty, windowFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
                previousFrame = .null; stableSince = Date(); return false
            }
            if previousFrame.isNull || abs(frame.midX - previousFrame.midX) > 1 || abs(frame.midY - previousFrame.midY) > 1 {
                previousFrame = frame; stableSince = Date(); return false
            }
            return Date().timeIntervalSince(stableSince) >= 1 && fixturePin.isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stablePin, object: nil)], timeout: 5), .completed,
                       "The native pin must settle after keyboard/card layout changes before the physical tap")
        fixturePin.tap()
        XCTAssertTrue(app.staticTexts["Selected ride wait"].waitForExistence(timeout: 3), mapEvents(app))
    }

    func testMapFullScreenPreservesSelectionFiltersAndCurrentWait() {
        let app = mapFixtureApp()
        chooseMapCategory("Rides", app: app)
        selectMapFixture("Current wait ride", id: 1, app: app)
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "35 min")
        screenshot("Map current ride wait", app: app)
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Search park places"].value as? String, "Current wait ride")
        XCTAssertEqual(app.buttons["Filter map places"].value as? String, "Rides")
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "35 min")
        XCTAssertTrue(app.staticTexts["Selected ride wait"].isHittable)
        app.buttons["Show whole park"].tap()
        screenshot("Full screen map current ride wait", app: app)
        app.buttons["Close full screen map"].tap()
        XCTAssertTrue(app.buttons["Full screen map"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Search park places"].value as? String, "Current wait ride")
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "35 min")
        XCTAssertEqual(app.buttons["Filter map places"].value as? String, "Rides")
    }

    func testMapFullScreenRideStatesDoNotInventWaits() {
        let app = mapFixtureApp()
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        let cases: [(String, Int, String)] = [
            ("Walk-on ride", 2, "0 min · walk-on"), ("Unposted wait ride", 3, "Open · wait not posted"),
            ("Closed ride", 4, "Temporarily closed"), ("Scheduled ride", 5, "Not operating now"),
            ("Inactive ride", 6, "Park inactive"), ("Old wait ride", 7, "Open · wait unavailable"),
            ("Stale ride", 8, "Wait unavailable"), ("Unknown ride", 9, "Wait unavailable"),
            ("Unmapped ride", 10, "Wait unavailable")
        ]
        for (name, id, expected) in cases {
            selectMapFixture(name, id: id, app: app)
            XCTAssertEqual(app.staticTexts["Selected ride wait"].label, expected)
            XCTAssertTrue(app.staticTexts["Selected ride wait"].isHittable)
            if id == 4 { screenshot("Full screen map closed ride", app: app) }
        }
        screenshot("Full screen map unavailable ride", app: app)
    }

    func testMapWaitExpiresWhileFullScreenStaysOpen() {
        let app = mapFixtureApp(["--map-wait-expiring"])
        selectMapFixture("Current wait ride", id: 1, app: app)
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "35 min")
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        let expired = NSPredicate(format: "label == %@", "Open · wait unavailable")
        let expectation = XCTNSPredicateExpectation(predicate: expired, object: app.staticTexts["Selected ride wait"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 40), .completed)
        XCTAssertFalse(app.staticTexts["35 min"].exists)
        screenshot("Full screen map wait expires", app: app)
    }

    func testMapFailedRefreshDoesNotPresentCachedWaitAsCurrent() {
        let app = mapFixtureApp(["--map-refresh-failed"])
        selectMapFixture("Current wait ride", id: 1, app: app)
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "Wait unavailable")
        XCTAssertTrue(app.staticTexts["Refresh failed · waiting for a current update"].exists)
        XCTAssertFalse(app.staticTexts["35 min"].exists)
        screenshot("Map refresh failure", app: app)
    }

    func testWaitForecastShowsHourlyPlanCrowdAndLearningState() {
        let app = XCUIApplication()
        app.launchArguments = ["--wait-forecast-ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Crowds & waits"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "5/10")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Lowest estimated wait"].exists)
        XCTAssertTrue(app.staticTexts["Hourly estimates"].exists)
        app.staticTexts["Hourly estimates"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "same weekday")).count > 0)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "Wait forecasts and park crowd meter"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSavedForecastDoesNotSuggestRidingNow() {
        let app = XCUIApplication()
        app.launchArguments = ["--wait-forecast-ui-test", "--forecast-saved"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Crowds & waits"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lowest estimated wait"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "History only")).firstMatch.exists)
    }

    func testPlanOwnsCrowdAndPredictedWaitControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "6"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["park-crowd-meter"].exists)
        XCTAssertFalse(app.buttons["plan-predicted-waits"].exists)
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Your day"].waitForExistence(timeout: 5))
        let forecastSection = app.buttons["Crowds & predicted waits"]
        reveal(forecastSection, in: app)
        forecastSection.tap()
        let forecasts = app.buttons["plan-predicted-waits"]
        reveal(forecasts, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["park-crowd-meter"].exists)
        XCTAssertTrue(app.buttons["browse-park-crowds"].exists)
        screenshot("Crowd meter and predicted waits on Plan", app: app)
        app.tabBars.buttons["Waits"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plan-predicted-waits"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["park-crowd-meter"].exists)
    }

    private func hhnApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--hhn-ui-test", "--reset-hhn-ui-test"] + extraArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Halloween Horror Nights"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists {
                let frame = element.frame
                if frame.isEmpty { app.swipeUp(); continue }
                let viewport = app.frame.insetBy(dx: 1, dy: 1)
                // XCTest can throw instead of returning false for an offscreen
                // accessibility frame. Scroll it into the viewport before hit-testing.
                let center = CGPoint(x: frame.midX, y: frame.midY)
                if !frame.isEmpty && viewport.contains(center) && element.isHittable { return }
                // A real hittable control near the bottom is valid. If occluded,
                // move it toward the actual window center rather than excluding
                // a fixed80pt band that makes compact-phone scrolling oscillate.
                if center.y < viewport.midY { app.swipeDown() } else { app.swipeUp() }
            } else {
                app.swipeUp()
            }
        }
        XCTFail("Could not reveal \(element.identifier)")
    }

    private func returnToTop(_ app: XCUIApplication) {
        for _ in 0..<5 { app.swipeDown() }
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHHNFavoritesCompletionUndoAndRelaunch() {
        let app = hhnApp()
        XCTAssertEqual(app.descendants(matching: .any)["hhn-feed-status"].label, "Live house updates")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == '0 minute wait'")).firstMatch.exists,
                      "A freshly observed unchanged house wait must remain visible")
        let headerSpan = app.descendants(matching: .any)["hhn-feed-status"].frame.maxY - app.staticTexts["hhn-event-title"].frame.minY
        XCTAssertLessThan(headerSpan, 150, "The normal-text HHN event header should leave room for houses")
        screenshot("HHN live overview", app: app)
        let favorite = app.buttons["hhn-favorite-test-charlie"]
        reveal(favorite, in: app)
        XCTAssertGreaterThanOrEqual(favorite.frame.width, 44)
        XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "Favorited")
        let done = app.buttons["hhn-done-test-charlie"]
        done.tap()
        XCTAssertEqual(done.value as? String, "Done")
        XCTAssertEqual(app.staticTexts["hhn-progress-description"].label, "1 of 1 favorites done")
        returnToTop(app)
        let remaining = app.buttons["hhn-filter-remaining"]
        reveal(remaining, in: app)
        remaining.tap()
        XCTAssertTrue(app.staticTexts["All favorites done"].exists)
        app.terminate()
        app.launchArguments = ["--hhn-ui-test"]
        app.launch()
        reveal(app.buttons["hhn-filter-favorites"], in: app)
        app.buttons["hhn-filter-favorites"].tap()
        reveal(app.buttons["hhn-done-test-charlie"], in: app)
        XCTAssertEqual(app.buttons["hhn-favorite-test-charlie"].value as? String, "Favorited")
        XCTAssertEqual(app.buttons["hhn-done-test-charlie"].value as? String, "Done")
        app.buttons["hhn-done-test-charlie"].tap()
        XCTAssertEqual(app.staticTexts["hhn-progress-description"].label, "0 of 1 favorites done")
        screenshot("HHN favorite house", app: app)
    }

    func testHHNSearchAndFilterEmptyStates() {
        let app = hhnApp()
        let search = app.textFields["hhn-house-search"]
        reveal(search, in: app)
        search.tap()
        search.typeText("no matching house")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["No matching houses"].exists)
        app.buttons["Clear house search"].tap()
        app.buttons["hhn-filter-favorites"].tap()
        XCTAssertTrue(app.staticTexts["No favorites yet"].exists)
        app.buttons["hhn-filter-all"].tap()
        search.tap()
        search.typeText("Lanterns")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Midnight Lanterns"].exists)
        XCTAssertFalse(app.staticTexts["The Haunted Conservatory"].exists)
    }

    func testHHNSavedAndEmptyFeedsNeverShowLiveWaits() {
        let app = hhnApp(["--hhn-ui-test-stale"])
        XCTAssertEqual(app.descendants(matching: .any)["hhn-feed-status"].label, "Saved · waits unknown")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == '15 minute wait'")).firstMatch.exists)
        reveal(app.buttons["hhn-favorite-test-alpha"], in: app)
        app.buttons["hhn-favorite-test-alpha"].tap()
        XCTAssertEqual(app.buttons["hhn-favorite-test-alpha"].value as? String, "Favorited")
        screenshot("HHN saved house data", app: app)
        app.terminate()
        app.launchArguments = ["--hhn-ui-test", "--hhn-ui-test-empty"]
        app.launch()
        XCTAssertEqual(app.descendants(matching: .any)["hhn-feed-status"].label, "Updates unavailable")
        XCTAssertTrue(app.staticTexts["House listings unavailable"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'still saved'")).firstMatch.exists)
    }

    func testHHNPreviewExpandsWithoutPretendingWaitsAreLive() {
        let app = hhnApp(["--hhn-ui-test-preview"])
        let preview = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tonight’s preview' AND label CONTAINS 'Halloween Horror Nights'")).firstMatch
        XCTAssertTrue(preview.label.contains("Tonight’s preview"))
        XCTAssertFalse(app.textFields["hhn-house-search"].exists)
        preview.tap()
        XCTAssertTrue(app.textFields["hhn-house-search"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == '15 minute wait'")).firstMatch.exists)
        reveal(app.buttons["hhn-favorite-test-charlie"], in: app)
        app.buttons["hhn-favorite-test-charlie"].tap()
        XCTAssertEqual(app.buttons["hhn-favorite-test-charlie"].value as? String, "Favorited")
        screenshot("HHN tonight preview", app: app)
    }

    func testHHNLargeTextKeepsControlsAccessible() {
        let app = hhnApp(["--hhn-ui-test-large-type"])
        screenshot("HHN accessibility text header", app: app)
        for id in ["hhn-filter-all", "hhn-filter-favorites", "hhn-filter-remaining"] {
            let button = app.buttons[id]
            reveal(button, in: app)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minX, 0)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        reveal(app.buttons["hhn-filter-all"], in: app)
        app.buttons["hhn-filter-all"].tap()
        reveal(app.buttons["hhn-favorite-test-charlie"], in: app)
        app.buttons["hhn-favorite-test-charlie"].tap()
        XCTAssertEqual(app.buttons["hhn-favorite-test-charlie"].value as? String, "Favorited")
        screenshot("HHN accessibility house card", app: app)
    }

    func testSortPreferenceSurvivesNavigationAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "6"]
        app.launch()
        for choice in ["Longest", "Shortest"] {
            XCTAssertTrue(app.buttons["ride-sort-menu"].waitForExistence(timeout: 10))
            app.buttons["ride-sort-menu"].tap()
            app.buttons[choice].firstMatch.tap()
            XCTAssertTrue(app.buttons["ride-sort-menu"].label.contains(choice))
            app.tabBars.buttons["More"].tap()
            app.tabBars.buttons["Waits"].tap()
            XCTAssertTrue(app.buttons["ride-sort-menu"].label.contains(choice))
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["ride-sort-menu"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["ride-sort-menu"].label.contains(choice))
        }
    }

    func testAccentSettingsPersistAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "-1"]
        app.launch()
        app.tabBars.buttons["More"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings'")).firstMatch.tap()
        for id in ["mint", "blue", "purple", "pink", "orange", "gold"] {
            XCTAssertTrue(app.buttons["accent-\(id)"].waitForExistence(timeout: 5))
        }
        app.buttons["accent-purple"].tap()
        XCTAssertEqual(app.buttons["accent-purple"].value as? String, "Selected")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["More"].isSelected)
        app.terminate()
        app.launch()
        app.tabBars.buttons["More"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings'")).firstMatch.tap()
        XCTAssertEqual(app.buttons["accent-purple"].value as? String, "Selected")
        reveal(app.staticTexts["PIVOT 1.17.1"], in: app)
        XCTAssertTrue(app.staticTexts["PIVOT 1.17.1"].exists)
        let build = app.staticTexts["PIVOT build number"]
        reveal(build, in: app)
        XCTAssertNotNil(build.label.range(of: #"^Build \d+(?:\.\d+){0,2}$"#, options: .regularExpression))
        screenshot("Installed PIVOT version and build", app: app)
        reveal(app.buttons["accent-mint"], in: app)
        app.buttons["accent-mint"].tap()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDashboardUsesTheNativeTabBarAndDestinations() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "-1"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Change park'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Refresh ride data now"].exists)
        // Clear persisted selection through the same control a person uses.
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Change park'")).firstMatch.tap()
        let noPark = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'No park'")).firstMatch
        XCTAssertTrue(noPark.waitForExistence(timeout: 5))
        noPark.tap()
        XCTAssertTrue(app.buttons["Change park. Current park: none"].waitForExistence(timeout: 5))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 5)

        let today = tabBar.buttons["Plan"]
        let waits = tabBar.buttons["Waits"]
        let shows = tabBar.buttons["Shows"]
        let map = tabBar.buttons["Map"]
        let data = tabBar.buttons["More"]

        XCTAssertTrue(today.exists)
        XCTAssertTrue(waits.exists)
        XCTAssertTrue(shows.exists)
        XCTAssertTrue(map.exists)
        XCTAssertTrue(data.exists)
        XCTAssertTrue(waits.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].exists)
        today.tap()
        XCTAssertTrue(app.staticTexts["Your day"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Today’s entertainment, all in one place."].exists)

        waits.tap()
        XCTAssertTrue(waits.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["PIVOT header"].waitForExistence(timeout: 3))

        shows.tap()
        XCTAssertTrue(shows.isSelected)
        XCTAssertTrue(app.staticTexts["Today’s entertainment, all in one place."].waitForExistence(timeout: 3))

        map.tap()
        XCTAssertTrue(map.isSelected)
        XCTAssertTrue(app.staticTexts["Choose a park to see rides, food, and shows."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Choose park"].exists)

        data.tap()
        XCTAssertTrue(data.isSelected)
        XCTAssertTrue(app.staticTexts["Manage your park, alerts, and app."].waitForExistence(timeout: 3))

        for item in [today, waits, shows, map, data] {
            XCTAssertGreaterThanOrEqual(item.frame.width, 44)
            XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        }
    }

    func testMapSearchAndCategoryWorkWithBundledLocations() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "6"]
        app.launch()
        let map = app.tabBars.firstMatch.buttons["Map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tap()
        let search = app.textFields["Search park places"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        chooseMapCategory("Food", app: app)
        XCTAssertTrue(app.buttons["Browse map places"].exists)
        search.tap()
        search.typeText("zz-no-such-place")
        XCTAssertTrue(app.staticTexts["No matching places."].waitForExistence(timeout: 3))
        screenshot("Map search empty state", app: app)
        app.buttons["Clear place search"].tap()
        screenshot("Map food category", app: app)
        app.buttons["Browse map places"].tap()
        XCTAssertTrue(app.staticTexts["Map coverage & sources"].exists || app.buttons["Done"].exists)
        app.buttons["Done"].tap()
        chooseMapCategory("Rides", app: app)
        search.tap()
        search.typeText("Space Mountain\n")
        let pin = app.buttons["map-pin-b2260923-9315-40fd-9c6b-44dd811dbe64"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(pin.frame.width, 44)
        XCTAssertGreaterThanOrEqual(pin.frame.height, 44)
        pin.tap()
        let status = app.staticTexts["Selected ride wait"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.isHittable)
        XCTAssertFalse(status.label.isEmpty)
        XCTAssertTrue(app.buttons["Full screen map"].isHittable)
        XCTAssertTrue(app.buttons["Browse map places"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Map"].isSelected)
        screenshot("Production map selected ride with tab bar", app: app)
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        XCTAssertTrue(status.isHittable)
        screenshot("Production full screen map selected ride", app: app)
        app.buttons["Close full screen map"].tap()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 5))
        XCTAssertTrue(status.isHittable)
    }

    func testNativeTabBarStaysFixedWhileContentScrolls() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "-1"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Plan"].tap()
        let originalMinY = tabBar.frame.minY

        app.swipeUp()
        app.swipeUp()

        XCTAssertTrue(tabBar.exists)
        XCTAssertTrue(tabBar.isHittable)
        XCTAssertEqual(tabBar.frame.minY, originalMinY, accuracy: 2)
    }

    func testExpandedParkCanBeFoundAndSelected() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "-1"]
        app.launch()

        let parkButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Change park'")
        ).firstMatch
        XCTAssertTrue(parkButton.waitForExistence(timeout: 5))
        parkButton.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Cedar Point")

        let cedarPoint = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Cedar Point'")
        ).firstMatch
        XCTAssertTrue(cedarPoint.waitForExistence(timeout: 5))
        cedarPoint.tap()

        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Current park: Cedar Point'")
            ).firstMatch.waitForExistence(timeout: 5)
        )
    }
}
