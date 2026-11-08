import XCTest
import UIKit
import Vision

final class PIVOTUITests: XCTestCase {
    private func artworkFixtureApp(mode: String = "originals", directory: String = UUID().uuidString,
                                   smallBatch: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PIVOT_ARTWORK_FIXTURE"] = mode
        app.launchEnvironment["PIVOT_ARTWORK_DIRECTORY"] = directory
        if smallBatch { app.launchEnvironment["PIVOT_ARTWORK_SMALL_BATCH"] = "1" }
        return app
    }

    private func mapFixtureApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = artworkFixtureApp()
        app.launchArguments = ["--park-map-ui-test"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Full screen map"].waitForExistence(timeout: 10))
        return app
    }

    private func chooseMapCategory(_ category: String, app: XCUIApplication) {
        let filter = app.buttons["Filter map places"]
        let available = NSPredicate { _, _ in filter.exists && filter.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: available, object: nil)], timeout: 5), .completed)
        filter.tap()
        let chooserBar = app.navigationBars["Place categories"]
        XCTAssertTrue(chooserBar.waitForExistence(timeout: 5))
        waitForSettledFrames([chooserBar])
        let window = app.frame
        if chooserBar.frame.minY > window.minY + window.height * 0.25 {
            // On SE the medium detent leaves lower rows at the sheet's edge.
            // Expand it with one real native drag before locating a whole row.
            chooserBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            waitForSettledFrames([chooserBar])
            XCTAssertLessThan(chooserBar.frame.minY, window.minY + window.height * 0.25,
                              "The native category sheet must expand before selecting a lower row")
        }
        let choice = app.buttons[category].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        waitForSettledFrames([choice])
        let readinessStartedAt = ProcessInfo.processInfo.systemUptime
        var readinessTrace: [String] = []
        let ready = NSPredicate { _, _ in
            let startedAt = ProcessInfo.processInfo.systemUptime
            let exists = choice.exists
            let hittable = exists && choice.isHittable
            let finishedAt = ProcessInfo.processInfo.systemUptime
            if readinessTrace.count < 12 {
                readinessTrace.append("atMs=\(Int((startedAt - readinessStartedAt) * 1_000)) readMs=\(Int((finishedAt - startedAt) * 1_000)) exists=\(exists) hittable=\(hittable)")
            }
            return exists && hittable
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5)
        if result != .completed {
            recordMapCategoryRowFailure(category, result: result, startedAt: readinessStartedAt,
                trace: readinessTrace, app: app)
        }
        XCTAssertEqual(result, .completed)
        assertParkBannerTouchTarget(choice.frame)
        print("MAP_CATEGORY_ROW_READY title=\(category) frame=\(choice.frame)")
        choice.tap()
        waitForMapCategory(category, app: app)
    }

    private func recordMapCategoryRowFailure(_ category: String, result: XCTWaiter.Result,
                                             startedAt: TimeInterval, trace: [String], app: XCUIApplication) {
        // The original waiter has already failed. These observations send no
        // input and cannot replace its result with a later passing state.
        let originalElapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let original = "category=\(category) originalResult=\(result.rawValue) originalElapsedMs=\(Int(originalElapsed * 1_000))"
        print("MAP_CATEGORY_ROW_FAILURE_ORIGINAL \(original) \(trace.joined(separator: " | "))")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Map category row after failed original five-second readiness"
        capture.lifetime = .keepAlways
        add(capture)
        let snapshotStartedAt = ProcessInfo.processInfo.systemUptime
        let root = try? app.snapshot()
        let snapshotElapsed = ProcessInfo.processInfo.systemUptime - snapshotStartedAt
        let nodes = root.map { nativeSnapshotNodes($0) } ?? []
        let names = [category, "Place categories", "Cancel map categories", "Filter map places", "Search park places"]
        let relevant = nodes.filter { node in
            names.contains(node.identifier) || names.contains(node.label)
                || node.elementType == .sheet || node.elementType == .alert
                || node.elementType == .table || node.elementType == .scrollView
        }
        func bounded(_ value: Any?) -> String {
            String(String(describing: value ?? "<nil>").replacingOccurrences(of: "\n", with: " ").prefix(160))
        }
        let rows = relevant.prefix(32).map { node in
            "type=\(node.elementType.rawValue) id=\(bounded(node.identifier)) label=\(bounded(node.label)) value=\(bounded(node.value)) enabled=\(node.isEnabled) selected=\(node.isSelected) frame=\(node.frame) children=\(node.children.count)"
        }
        let rootFrame = root.map { String(describing: $0.frame) } ?? "unavailable"
        let matches = nodes.filter { $0.elementType == .button && ($0.identifier == category || $0.label == category) }.count
        let details = (["\(original) snapshotReadMs=\(Int(snapshotElapsed * 1_000)) rootFrame=\(rootFrame) nativeNodes=\(nodes.count) matchingButtons=\(matches) relevantNodes=\(relevant.count)"] + trace + rows).joined(separator: "\n")
        print("MAP_CATEGORY_ROW_FAILURE \(details.replacingOccurrences(of: "\n", with: " | "))")
        let attachment = XCTAttachment(string: details)
        attachment.name = "Map category original row-readiness failure and native snapshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func recordMapRefreshRequestDiagnostic(_ phase: String, app: XCUIApplication) {
        print("MAP_REFRESH_REQUEST_DIAGNOSTIC_BEGIN phase=\(phase)")
        let startedAt = ProcessInfo.processInfo.systemUptime
        let probe = app.staticTexts["Map refresh request diagnostic"]
        let value = probe.exists ? (probe.value as? String ?? "<value unavailable>") : "<probe absent>"
        let details = "phase=\(phase) readMs=\(Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)) \(value)"
        print("MAP_REFRESH_REQUEST_DIAGNOSTIC \(details)")
        let attachment = XCTAttachment(string: details)
        attachment.name = "Actual map refresh request metadata"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForMapCategory(_ category: String, app: XCUIApplication) {
        // Selection and sheet dismissal must finish before a search-field tap.
        // Keep the real foreground controls reachable before sending input.
        let ready = NSPredicate { _, _ in
            let filter = app.buttons["Filter map places"]
            let search = app.textFields["Search park places"]
            // An absent row's live query can retry for several seconds even
            // after the recorded sheet has gone. Read all structural conditions
            // from one native snapshot, then check both real hit targets.
            guard let snapshot = try? app.snapshot() else { return false }
            var pending = [snapshot]
            var applied = false
            var chooserExists = false
            var rowExists = false
            while let element = pending.popLast() {
                pending.append(contentsOf: element.children)
                if element.elementType == .button {
                    if element.identifier == "Filter map places" {
                        applied = element.value as? String == category
                    }
                    if element.identifier == category || element.label == category {
                        rowExists = true
                    }
                }
                if element.elementType == .navigationBar
                    && (element.identifier == "Place categories" || element.label == "Place categories") {
                    chooserExists = true
                }
            }
            return applied && !chooserExists && !rowExists
                && search.isHittable && filter.isHittable
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5)
        if result != .completed {
            // Preserve the five-second assertion. Observe a failed interaction
            // without another tap so bounded evidence distinguishes a late UI
            // update from a selection that never committed.
            screenshot("Map category failed original five-second postcondition", app: app)
            let filter = app.buttons["Filter map places"]
            let chooserExists = app.navigationBars["Place categories"].exists
            let rowExists = app.buttons[category].firstMatch.exists
            let filterValue = filter.exists ? String(describing: filter.value) : "<absent>"
            let initial = "category=\(category); filter=\(filterValue); chooser=\(chooserExists); row=\(rowExists)"
            let later = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
            screenshot("Map category after observation without another input", app: app)
            let details = "Original result: \(result.rawValue)\n\(initial)\nLater result: \(later.rawValue)\n\(app.debugDescription)"
            print("MAP_CATEGORY_FAILURE_DIAGNOSTIC \(initial); later=\(later.rawValue)")
            let attachment = XCTAttachment(string: details)
            attachment.name = "Map category original failure and later native state"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(result, .completed,
                       "The chosen category must be applied and its native chooser dismissed before searching")
    }

    private func focusMapSearch(_ app: XCUIApplication) {
        let search = app.textFields["Search park places"]
        XCTAssertTrue(search.isHittable)
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "One real search-field tap must open the keyboard")
        let submit = app.keyboards.buttons["Search"]
        if !submit.isHittable {
            // A fresh simulator can present the system slide-to-type tutorial
            // after returning from Home. It replaces the keyboard's normal keys.
            let tutorial = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                "Speed up your typing by sliding your finger")).firstMatch
            if tutorial.waitForExistence(timeout: 2) {
                let proceed = app.buttons["Continue"].firstMatch
                XCTAssertTrue(proceed.isHittable, "The identified system keyboard tutorial must expose Continue")
                proceed.tap()
                print("MAP_KEYBOARD_SYSTEM_TUTORIAL_DISMISSED nativeContinueTap=true")
            }
        }
        let keyReady = NSPredicate { _, _ in submit.isHittable }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyReady, object: nil)], timeout: 5)
        if result != .completed {
            screenshot("Map keyboard preparation did not expose native Search", app: app)
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Map native keyboard preparation failure state"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertEqual(result, .completed, "The actual keyboard Search key must be hittable before its one submit tap")
    }

    private func visibleMapCluster(in app: XCUIApplication, memberCount: Int? = nil) -> XCUIElement? {
        let clusters: XCUIElementQuery
        if let memberCount {
            clusters = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                "Map place cluster", "\(memberCount) places. Zoom in"))
        } else {
            clusters = app.buttons.matching(identifier: "Map place cluster")
        }
        XCTAssertTrue(clusters.firstMatch.waitForExistence(timeout: 5))
        var visible: XCUIElement?
        let minimum: CGFloat = 44
        let ready = NSPredicate { _, _ in
            let viewport = app.frame
            visible = clusters.allElementsBoundByIndex.first { element in
                guard element.exists && element.isHittable else { return false }
                let frame = element.frame
                return viewport.contains(frame)
                    && frame.width >= minimum - minimum.ulp * 8
                    && frame.height >= minimum - minimum.ulp * 8
            }
            return visible != nil
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
        guard result == .completed, let visible else {
            screenshot("No visible native cluster matching the requested members", app: app)
            XCTFail("A hittable full-size native cluster must be visible before its one physical tap")
            return nil
        }
        waitForSettledFrames([visible])
        XCTAssertTrue(visible.isHittable)
        assertParkBannerTouchTarget(visible.frame)
        print("MAP_CLUSTER_NATIVE_TARGET label=\(visible.label) frame=\(visible.frame)")
        return visible
    }

    private func rootFixture(_ extra: [String] = [], artworkMode: String = "originals",
                             artworkDirectory: String = UUID().uuidString, smallArtworkBatch: Bool = false) -> XCUIApplication {
        let app = artworkFixtureApp(mode: artworkMode, directory: artworkDirectory, smallBatch: smallArtworkBatch)
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
            screenshot("Native map camera failed its original postcondition", app: app)
            let hierarchy = XCTAttachment(string: "Camera: \(camera(app))\nEvents: \(mapEvents(app))\n\(app.debugDescription)")
            hierarchy.name = "Native map camera failure state"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
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
        reveal(search, in: app); search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Guardians")
        let submit = app.keyboards.buttons["Search"]
        XCTAssertTrue(submit.isHittable)
        submit.tap()
        let keyboardGone = NSPredicate { _, _ in !app.keyboards.firstMatch.exists }
        let submitted = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardGone, object: nil)], timeout: 5)
        if submitted != .completed {
            screenshot("Reference ride search failed keyboard dismissal", app: app)
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Reference ride search submission failure state"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertEqual(submitted, .completed,
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
            XCTAssertTrue(result.label.contains(expired ? "Wait stale" : "45 minute wait"))
            if expired { XCTAssertFalse(result.label.contains("45 minute wait")) }
            screenshot(expired ? "Search expired wait withheld" : "Search historical size and live wait", app: app)
            result.tap()
            let status = app.staticTexts[expired ? "Wait stale" : "45 min wait"].firstMatch
            reveal(status, in: app); XCTAssertTrue(status.isHittable)
            app.buttons["Done"].tap()
            reveal(app.buttons["Clear ride search"], in: app); app.buttons["Clear ride search"].tap()
            reveal(search, in: app); search.tap(); search.typeText("Spaceship\n")
            let closed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Spaceship Earth'")).firstMatch
            reveal(closed, in: app)
            XCTAssertTrue(closed.label.contains(expired ? "Wait stale" : "Temporarily closed"))
            XCTAssertFalse(closed.label.contains("0 minute wait"))
            if expired { XCTAssertFalse(closed.label.contains("Closed for")) }
            app.terminate()
        }
    }

    private func assertWaitsControlsJoinedToResult(_ app: XCUIApplication, rideID: Int,
                                                  file: StaticString = #filePath, line: UInt = #line) {
        let search = app.descendants(matching: .any)["ride-search-control"].firstMatch
        let result = app.buttons["ride-row-action-\(rideID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), file: file, line: line)
        let viewport = safeContentViewport(in: app)
        // Fit the real search and result together without assuming a scroll
        // offset or a fixed height for the native List or its large-text rows.
        var visible = false
        var trace: [String] = []
        for _ in 0..<8 {
            let searchFrame = search.frame
            let resultFrame = result.frame
            let joined = searchFrame.union(resultFrame)
            trace.append("search \(searchFrame); result \(resultFrame)")
            guard !searchFrame.isEmpty, !resultFrame.isEmpty, joined.height <= viewport.height + 1 else { break }
            if viewport.insetBy(dx: -1, dy: -1).contains(joined) { visible = true; break }
            let offset = joined.minY < viewport.minY ? joined.minY - viewport.minY - 8 : joined.maxY - viewport.maxY + 8
            let movement = min(viewport.height * 0.8, max(20, abs(offset))) * (offset < 0 ? -1 : 1)
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: verticalPanX(in: viewport), dy: viewport.midY + movement / 2))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: -movement)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(visible, "Search and its result must fit together. \(trace.joined(separator: "; "))", file: file, line: line)
        guard visible else { return }
        waitForSettledFrames([search, result], file: file, line: line)
        for element in [search, app.buttons["ride-sort-menu"], app.segmentedControls["ride-status-filter"], result] {
            assertContained(element.frame, in: safeContentViewport(in: app),
                            "Search, sort, filters and the matching ride must be fully visible together", file: file, line: line)
        }
        let controlsCell = app.cells.containing(.textField, identifier: "Ride search").firstMatch
        let resultCell = app.cells.containing(.button, identifier: "ride-row-action-\(rideID)").firstMatch
        XCTAssertTrue(controlsCell.exists, "Controls must be a real native List cell", file: file, line: line)
        XCTAssertTrue(resultCell.exists, "The ride must remain a real native List cell", file: file, line: line)
        guard controlsCell.exists, resultCell.exists else { return }
        let controlsFrame = controlsCell.frame
        let resultFrame = resultCell.frame
        XCTAssertEqual(controlsFrame.maxY, resultFrame.minY, accuracy: 2,
                       "Controls and results must touch within one inset-grouped section, without a separate card gap", file: file, line: line)
        XCTAssertEqual(controlsFrame.minX, resultFrame.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(controlsFrame.width, resultFrame.width, accuracy: 1, file: file, line: line)
    }

    func testWaitsSearchAndResultsShareOneNativeGroup() {
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        assertWaitsControlsJoinedToResult(app, rideID: 10916)
        XCTAssertTrue(app.buttons["ride-row-action-10916"].label.contains("45 minute wait"))
        XCTAssertEqual(app.descendants(matching: .any)["ride-search-control"].firstMatch.frame.height, 46, accuracy: 1)
        screenshot("Waits shared group search current wait", app: app)
        app.buttons["ride-sort-menu"].tap()
        app.buttons["Name"].tap()
        XCTAssertTrue(app.buttons["ride-sort-menu"].label.contains("Name"))
        app.buttons["Clear ride search"].tap()
        app.segmentedControls["ride-status-filter"].buttons["Down"].tap()
        search.tap(); search.typeText("Spaceship\n")
        assertWaitsControlsJoinedToResult(app, rideID: 159)
        let closed = app.buttons["ride-row-action-159"]
        XCTAssertTrue(closed.label.contains("Temporarily closed"))
        XCTAssertFalse(closed.label.contains("0 minute wait"))
        XCTAssertFalse(app.buttons["ride-row-action-10916"].exists)
        screenshot("Waits shared group filtered down status", app: app)
    }

    func testBannerColdLaunchShowsParkAndSchedule() {
        let app = rootFixture(["--reference-ui-park=64", "--ui-dark"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Change park. Current park: Islands of Adventure"].isHittable)
        for identifier in ["park-hours-value", "park-early-entry-value"] {
            let value = app.staticTexts[identifier]
            let complete = NSPredicate { _, _ in value.exists && value.label.contains(" – ") }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: nil)], timeout: 10), .completed,
                           "The first Waits screen must display both complete schedule endpoints")
        }
        XCTAssertTrue(app.buttons["park-photo-credit-64"].isHittable)
        screenshot("Park banner cold launch park and complete schedule", app: app)
        // Validate the painted title and initialize the existing native text
        // recognizer in this short readiness case, before longer UI journeys.
        let titleCapture = app.buttons["Change park. Current park: Islands of Adventure"].screenshot()
        guard let pixels = titleCapture.image.cgImage else {
            XCTFail("The cold-launch park title must supply native pixels")
            return
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request]) }
        catch { XCTFail("Cold-launch title recognition failed: \(error)"); return }
        let words = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        let visible = words.contains { $0.range(of: "Islands", options: .caseInsensitive) != nil }
        if !visible {
            let attachment = XCTAttachment(screenshot: titleCapture)
            attachment.name = "Unresolved cold-launch native park title"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(visible, "The native cold-launch park title must be painted and readable: \(words)")
    }

    private func assertParkBannerTouchTarget(_ frame: CGRect,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let minimum: CGFloat = 44
        for dimension in [frame.width, frame.height] {
            // Native CGRect subtraction produced43.99999999999997 for44pt.
            // Normalize at most8 floating-point ULPs, far below one pixel;
            // a genuinely undersized dimension still fails the44pt assertion.
            let normalized = abs(dimension - minimum) <= minimum.ulp * 8 ? minimum : dimension
            XCTAssertTrue(dimension.isFinite, file: file, line: line)
            XCTAssertGreaterThanOrEqual(normalized, minimum,
                                        "The control needs a full44-point target; raw dimension \(dimension)", file: file, line: line)
        }
    }

    func testCompactParkBannerIslandsIsSmallerAndKeepsScheduleAndActions() {
        checkParkBanner(parkID: 64, name: "Islands of Adventure", category: .large,
                        extra: ["--ui-dark"], capture: "Islands standard")
    }

    func testCompactParkBannerEPCOTIsSmallerAndKeepsScheduleAndActions() {
        checkParkBanner(parkID: 5, name: "EPCOT", category: .large,
                        extra: ["--ui-light"], capture: "EPCOT standard light")
    }

    func testCompactParkBannerIslandsKeepsAccessibilityScheduleAndActions() {
        checkParkBanner(parkID: 64, name: "Islands of Adventure", category: .accessibilityLarge,
                        extra: ["--ui-dark", "--ui-large-type"], capture: "Islands accessibility large")
    }

    func testCompactParkBannerEPCOTKeepsAccessibilityScheduleAndActions() {
        checkParkBanner(parkID: 5, name: "EPCOT", category: .accessibilityLarge,
                        extra: ["--ui-dark", "--ui-large-type"], capture: "EPCOT accessibility large")
    }

    func testCompactParkBannerIslandsKeepsLargestScheduleAndActions() {
        checkParkBanner(parkID: 64, name: "Islands of Adventure", category: .accessibilityExtraExtraExtraLarge,
                        extra: ["--ui-dark", "--ui-largest-type"], capture: "Islands accessibility largest")
    }

    func testCompactParkBannerEPCOTKeepsLargestScheduleAndActions() {
        checkParkBanner(parkID: 5, name: "EPCOT", category: .accessibilityExtraExtraExtraLarge,
                        extra: ["--ui-dark", "--ui-largest-type"], capture: "EPCOT accessibility largest")
    }

    private func checkParkBanner(parkID: Int, name: String, category: UIContentSizeCategory,
                                 extra: [String], capture: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let app = rootFixture(["--reference-ui-park=\(parkID)"] + extra)
        defer { app.terminate() }
        let bounds = app.descendants(matching: .any)["park-banner-layout-bounds-\(parkID)"].firstMatch
        let choose = app.buttons["Change park. Current park: \(name)"].firstMatch
        XCTAssertTrue(bounds.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(choose.waitForExistence(timeout: 5), file: file, line: line)
        waitForSettledFrames([bounds, choose], file: file, line: line)
        let height = bounds.frame.height
        if category == .large {
            // Released native cards measure176–177pt on these devices. Keep a
            // meaningful reduction while allowing font rounding and wrapping.
            XCTAssertLessThanOrEqual(height, 160, "The park banner must be visibly smaller than the released card", file: file, line: line)
        } else {
            XCTAssertGreaterThan(height, 160, "Schedule text must grow naturally at accessibility sizes", file: file, line: line)
        }
        print("PARK_BANNER_METRICS \(capture) category=\(category.rawValue) card=\(bounds.frame) parkAction=\(choose.frame)")
        screenshot("Park banner \(capture) overview", app: app)

        centerFullyVisible(choose, in: app, file: file, line: line)
        assertContained(choose.frame, in: bounds.frame, "The park action and its wrapped name must remain inside the banner", file: file, line: line)
        assertParkBannerTouchTarget(choose.frame, file: file, line: line)
        XCTAssertTrue(choose.isHittable, file: file, line: line)
        screenshot("Park banner \(capture) park action", app: app)

        for identifier in ["park-hours-title", "park-hours-value", "park-early-entry-title", "park-early-entry-value"] {
            let elements = app.descendants(matching: .any).matching(identifier: identifier)
            let text = app.staticTexts[identifier].firstMatch
            XCTAssertEqual(elements.count, 1, "Each schedule child must retain its own accessibility identity", file: file, line: line)
            centerFullyVisible(text, in: app, file: file, line: line)
            assertFullTextLayout(text, category: category, file: file, line: line)
            assertContained(text.frame, in: bounds.frame, "The full schedule child must stay inside the banner", file: file, line: line)
            if identifier.hasSuffix("value") {
                XCTAssertTrue(text.label.contains(" – "), "Both schedule endpoints must remain available", file: file, line: line)
            }
            screenshot("Park banner \(capture) \(identifier)", app: app)
        }
        XCTAssertEqual(app.staticTexts["park-hours-title"].label, "Park hours", file: file, line: line)
        XCTAssertEqual(app.staticTexts["park-early-entry-title"].label, "Early entry", file: file, line: line)
        XCTAssertGreaterThanOrEqual(app.staticTexts["park-hours-title"].frame.minY, choose.frame.maxY,
                                    "The schedule must not overlap the park name", file: file, line: line)
        XCTAssertGreaterThanOrEqual(app.staticTexts["park-early-entry-title"].frame.minY,
                                    app.staticTexts["park-hours-value"].frame.maxY,
                                    "The two schedule rows must not overlap", file: file, line: line)

        let credit = app.buttons["park-photo-credit-\(parkID)"].firstMatch
        centerFullyVisible(credit, in: app, file: file, line: line)
        XCTAssertEqual(app.buttons.matching(identifier: "park-photo-credit-\(parkID)").count, 1, file: file, line: line)
        XCTAssertEqual(credit.label, "Photo credit", file: file, line: line)
        assertParkBannerTouchTarget(credit.frame, file: file, line: line)
        assertContained(credit.frame, in: bounds.frame, "The information target must remain inside the banner", file: file, line: line)
        XCTAssertTrue(credit.isHittable, file: file, line: line)
        screenshot("Park banner \(capture) information target", app: app)
        // Exercise the44pt rectangle outside the17pt glyph. Start with the
        // original corner, then check every remaining corner in this same case.
        let edge: CGVector
        if category == .large {
            edge = parkID == 5 ? CGVector(dx: 0.1, dy: 0.1) : CGVector(dx: 0.9, dy: 0.9)
        } else {
            edge = parkID == 5 ? CGVector(dx: 0.9, dy: 0.1) : CGVector(dx: 0.1, dy: 0.9)
        }
        print("PARK_BANNER_INFORMATION_TARGET \(capture) frame=\(credit.frame) edge=\(edge)")
        credit.coordinate(withNormalizedOffset: edge).tap()
        XCTAssertTrue(app.navigationBars["Photo credit"].waitForExistence(timeout: 5), file: file, line: line)
        print("PARK_BANNER_CORNER_VERIFIED \(capture) edge=\(edge)")
        if category != .large {
            let probe = app.staticTexts["park-photo-credit-type-probe"]
            XCTAssertTrue(probe.waitForExistence(timeout: 5), "The presented sheet must receive the requested native text-size fixture", file: file, line: line)
            let font = UIFont.preferredFont(forTextStyle: .body,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            XCTAssertGreaterThanOrEqual(probe.frame.height, font.lineHeight - 3,
                                        "The photo-credit sheet must use the actual requested accessibility category", file: file, line: line)
        }
        let source = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Original photo'")).firstMatch
        centerFullyVisible(source, in: app, file: file, line: line)
        screenshot("Park banner \(capture) original photo link", app: app)
        assertFullTextLayout(source, style: .body, category: category, file: file, line: line)
        XCTAssertTrue(source.isHittable, file: file, line: line)
        dismissParkPhotoCredit(app, returningTo: credit, file: file, line: line)

        let remainingCorners = [CGVector(dx: 0.1, dy: 0.1), CGVector(dx: 0.9, dy: 0.1),
                                CGVector(dx: 0.1, dy: 0.9), CGVector(dx: 0.9, dy: 0.9)]
            .filter { $0.dx != edge.dx || $0.dy != edge.dy }
        for corner in remainingCorners {
            centerFullyVisible(credit, in: app, file: file, line: line)
            waitForSettledFrames([bounds, credit], file: file, line: line)
            assertParkBannerTouchTarget(credit.frame, file: file, line: line)
            assertContained(credit.frame, in: bounds.frame,
                            "Every information-target corner must remain inside the banner", file: file, line: line)
            XCTAssertTrue(credit.isHittable, file: file, line: line)
            print("PARK_BANNER_INFORMATION_TARGET \(capture) frame=\(credit.frame) edge=\(corner)")
            credit.coordinate(withNormalizedOffset: corner).tap()
            XCTAssertTrue(app.navigationBars["Photo credit"].waitForExistence(timeout: 5),
                          "Each corner of the44pt information control must open its credit sheet", file: file, line: line)
            print("PARK_BANNER_CORNER_VERIFIED \(capture) edge=\(corner)")
            dismissParkPhotoCredit(app, returningTo: credit, file: file, line: line)
        }

        centerFullyVisible(choose, in: app, file: file, line: line)
        choose.tap()
        XCTAssertTrue(app.navigationBars["Choose a park"].waitForExistence(timeout: 5), file: file, line: line)
        screenshot("Park banner \(capture) native park picker", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Change park. Current park: \(name)"].waitForExistence(timeout: 5), file: file, line: line)
        print("PARK_BANNER_VERIFIED park=\(parkID) category=\(category.rawValue) height=\(height) schedule=complete informationTarget=44 parkAction=working")
    }

    private func dismissParkPhotoCredit(_ app: XCUIApplication, returningTo credit: XCUIElement,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), file: file, line: line)
        waitForSettledFrames([done], file: file, line: line)
        XCTAssertTrue(done.isHittable, "The credit sheet must expose a usable Done control", file: file, line: line)
        done.tap()
        let dismissed = NSPredicate { _, _ in !app.navigationBars["Photo credit"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: nil)], timeout: 10), .completed,
                       "One Done tap must dismiss credits before the next corner is exercised", file: file, line: line)
        let ready = NSPredicate { _, _ in credit.exists && credit.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10), .completed,
                       "The banner information control must become usable again after dismissal", file: file, line: line)
        print("PARK_BANNER_CREDIT_DISMISSED frame=\(credit.frame)")
    }

    func testWaitsCompactLayoutKeepsParkHoursAndHistoryTouchTarget() {
        checkCompactWaitsLayout(parkID: 5, rideID: 10916, extra: [],
                               category: .large, capture: "standard EPCOT")
    }

    func testWaitsCompactLayoutKeepsTwelveSampleControlSmall() {
        checkCompactWaitsLayout(parkID: 64, rideID: 5985,
                               extra: ["--reference-ui-ride=5985", "--ride-history-ui-test"],
                               category: .large, capture: "standard Islands of Adventure")
    }

    func testWaitsCompactLayoutAllowsAccessibilityTextToWrap() {
        checkCompactWaitsLayout(parkID: 5, rideID: 10916,
                               extra: ["--ride-history-ui-test", "--ui-large-type"],
                               category: .accessibilityLarge, capture: "accessibility large")
    }

    func testWaitsCompactLayoutAllowsLargestAccessibilityTextToWrap() {
        checkCompactWaitsLayout(parkID: 5, rideID: 10916,
                               extra: ["--ride-history-ui-test", "--ui-largest-type"],
                               category: .accessibilityExtraExtraExtraLarge, capture: "accessibility largest")
    }

    private func checkCompactWaitsLayout(parkID: Int, rideID: Int, extra: [String],
                                         category: UIContentSizeCategory, capture: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let app = rootFixture(["--reference-ui-park=\(parkID)", "--ui-dark"] + extra)
        let banner = app.descendants(matching: .any)["park-banner-\(parkID)"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), file: file, line: line)
        waitForSettledFrames([banner], file: file, line: line)
        screenshot("Compact Waits \(capture) overview", app: app)
        for identifier in ["park-hours-value", "park-early-entry-value"] {
            let matches = app.descendants(matching: .any).matching(identifier: identifier)
            let value = app.staticTexts[identifier].firstMatch
            if !value.exists { print("COMPACT_WAITS_INITIAL_ACCESSIBILITY \(capture) \(identifier)\n" + app.debugDescription) }
            centerFullyVisible(value, in: app, file: file, line: line)
            XCTAssertEqual(matches.count, 1, "The schedule value must have a unique accessibility identity", file: file, line: line)
            XCTAssertTrue(value.label.contains(" – "), "Both complete schedule endpoints must remain available", file: file, line: line)
            assertFullTextLayout(value, category: category, file: file, line: line)
            screenshot("Compact Waits \(capture) \(identifier)", app: app)
        }

        let heading = app.staticTexts["Current rides"].firstMatch
        centerFullyVisible(heading, in: app, file: file, line: line)
        let controls = app.cells.containing(.textField, identifier: "Ride search").firstMatch
        XCTAssertTrue(banner.exists && controls.exists, file: file, line: line)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "park-banner-\(parkID)").count, 1,
                       "The park card must expose one container rather than overriding its schedule children", file: file, line: line)
        let bounds = app.descendants(matching: .any)["park-banner-layout-bounds-\(parkID)"].firstMatch
        XCTAssertTrue(bounds.waitForExistence(timeout: 5), "Measure the actual card rectangle, rather than the union of its accessibility children", file: file, line: line)
        waitForSettledFrames([bounds, controls], file: file, line: line)
        let parkGap = controls.frame.minY - bounds.frame.maxY
        print("COMPACT_WAITS_PARK_FRAMES \(capture) container=\(banner.frame) card=\(bounds.frame) controls=\(controls.frame) gap=\(parkGap)")
        XCTAssertGreaterThanOrEqual(parkGap, 0, "Park and rides cards must not overlap", file: file, line: line)
        XCTAssertLessThanOrEqual(parkGap, 12, "A healthy feed must not reserve an empty warning row or a large section gap", file: file, line: line)
        screenshot("Compact Waits \(capture) park to rides junction", app: app)

        let toggle = app.buttons["wait-history-toggle-\(rideID)"]
        centerFullyVisible(toggle, in: app, file: file, line: line)
        let action = app.buttons["ride-row-action-\(rideID)"]
        let cell = app.cells.containing(.button, identifier: "ride-row-action-\(rideID)").firstMatch
        waitForSettledFrames([toggle, action, cell], file: file, line: line)
        XCTAssertTrue(toggle.isHittable, "The smaller history control must remain independently tappable", file: file, line: line)
        XCTAssertEqual(toggle.value as? String, "Collapsed", file: file, line: line)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44, "Compaction must retain the minimum history touch target", file: file, line: line)
        XCTAssertTrue(toggle.label.hasPrefix("Recent observed waits"), file: file, line: line)
        assertFullTextLayout(toggle, category: category, file: file, line: line)
        let title = toggle.staticTexts["wait-history-title-\(rideID)"].firstMatch
        if title.exists {
            assertFullTextLayout(title, category: category, file: file, line: line)
            assertContained(title.frame, in: toggle.frame, "The title must fit the compact control", file: file, line: line)
        }
        let historyGap = toggle.frame.minY - action.frame.maxY
        let bottomPadding = cell.frame.maxY - toggle.frame.maxY
        XCTAssertGreaterThanOrEqual(historyGap, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(historyGap, 8, "Remove excess space above the history control", file: file, line: line)
        XCTAssertGreaterThanOrEqual(bottomPadding, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(bottomPadding, 12, "Remove the history control's extra vertical card padding", file: file, line: line)
        if category == .large {
            XCTAssertLessThanOrEqual(toggle.frame.height, 46, "A one-line history control needs only its accessible touch height", file: file, line: line)
        } else {
            let font = UIFont.preferredFont(forTextStyle: .caption1,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            XCTAssertGreaterThanOrEqual(toggle.frame.height, font.lineHeight - 2,
                                        "The control must grow with the actual caption size", file: file, line: line)
        }
        let metrics: [String: Any] = ["capture": capture, "category": category.rawValue,
            "parkGap": parkGap, "historyTouchHeight": toggle.frame.height,
            "historyTopGap": historyGap, "rowBottomPadding": bottomPadding,
            "historyLabel": toggle.label]
        if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) { print("COMPACT_WAITS_LAYOUT_METRICS " + json) }
        screenshot("Compact Waits \(capture) collapsed history touch target", app: app)

        toggle.tap()
        let chart = app.descendants(matching: .any)["observed-wait-chart-\(rideID)"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "The smaller control must still open its chart", file: file, line: line)
        centerFullyVisible(toggle, in: app, file: file, line: line)
        XCTAssertEqual(toggle.value as? String, "Expanded", file: file, line: line)
        screenshot("Compact Waits \(capture) expanded history", app: app)
        toggle.tap()
        // Check both outcomes independently: a missing-element AX snapshot can take
        // several seconds on the runner even after the recording shows collapse.
        // Sharing five seconds between both queries made a correct collapse time out.
        let collapsed = NSPredicate { _, _ in toggle.value as? String == "Collapsed" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: collapsed, object: nil)], timeout: 10), .completed,
                       "The history control must report its collapsed state", file: file, line: line)
        let removed = NSPredicate { _, _ in !chart.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: removed, object: nil)], timeout: 10), .completed,
                       "Toggling history must not intercept the ride action or leave a chart mounted", file: file, line: line)
    }

    func testWaitsSearchAndResultsStayJoinedAtAccessibilitySize() {
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark", "--ui-large-type"])
        let heading = app.staticTexts["Current rides"]
        centerFullyVisible(heading, in: app)
        XCTAssertGreaterThanOrEqual(heading.frame.height, 35, "The actual controls heading must render enlarged type")
        screenshot("Waits shared group enlarged heading", app: app)
        let search = app.textFields["Ride search"]
        centerFullyVisible(search, in: app)
        XCTAssertTrue(search.isHittable, "The fully visible large-text search field must accept input")
        search.tap(); search.typeText("Guardians\n")
        let freshness = app.staticTexts["waits-feed-freshness"].firstMatch
        centerFullyVisible(freshness, in: app)
        screenshot("Waits shared group enlarged full freshness", app: app)
        assertFullTextLayout(freshness, style: .caption2, category: .accessibilityLarge)
        assertWaitsControlsJoinedToResult(app, rideID: 10916)
        XCTAssertTrue(app.buttons["ride-row-action-10916"].label.contains("45 minute wait"))
        XCTAssertGreaterThanOrEqual(search.frame.height, 35)
        screenshot("Waits shared group enlarged search and current wait", app: app)
    }

    func testWaitsSharedGroupKeepsUnchangedWaitFromFreshProvider() {
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark", "--ride-search-unchanged-provider"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        assertWaitsControlsJoinedToResult(app, rideID: 10916)
        screenshot("Waits shared group fresh provider unchanged current wait", app: app)
        let state = waitsFeedAccessibilityState(app, rideID: 10916)
        XCTAssertEqual(state.matches, 1, state.diagnostic)
        XCTAssertEqual(state.badge, "Live", state.diagnostic)
        XCTAssertTrue(state.freshness.hasPrefix("Live · auto 5s"), state.diagnostic)
        XCTAssertTrue(state.ride.contains("45 minute wait"), state.diagnostic)
        XCTAssertFalse(state.ride.contains("Wait stale"), state.diagnostic)
        XCTAssertFalse(state.ride.contains("0 minute wait"), state.diagnostic)
    }

    func testWaitsSharedGroupWithholdsWaitFromExpiredProviderFetch() {
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark", "--ride-search-unchanged-provider", "--ride-search-provider-fetch-expired"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        assertWaitsControlsJoinedToResult(app, rideID: 10916)
        screenshot("Waits shared group expired provider wait withheld", app: app)
        let state = waitsFeedAccessibilityState(app, rideID: 10916)
        XCTAssertEqual(state.matches, 1, state.diagnostic)
        XCTAssertEqual(state.badge, "Saved", state.diagnostic)
        XCTAssertTrue(state.freshness.contains("Source too old"), state.diagnostic)
        XCTAssertTrue(state.ride.contains("Wait stale"), state.diagnostic)
        XCTAssertFalse(state.ride.contains("45 minute wait"), state.diagnostic)
        XCTAssertFalse(state.ride.contains("0 minute wait"), state.diagnostic)
    }

    private func waitsFeedAccessibilityState(_ app: XCUIApplication, rideID: Int)
        -> (matches: Int, badge: String, freshness: String, ride: String, diagnostic: String) {
        let health = app.descendants(matching: .any).matching(identifier: "waits-feed-health")
        let exists = health.firstMatch.waitForExistence(timeout: 5)
        let count = health.count
        let badge = exists && count == 1 ? health.firstMatch.label : "<missing or ambiguous>"
        let freshness = app.staticTexts["waits-feed-freshness"].firstMatch
        let ride = app.buttons["ride-row-action-\(rideID)"]
        let freshnessExists = freshness.exists
        let rideExists = ride.exists
        let freshnessValue = freshnessExists ? freshness.label : "<missing>"
        let rideValue = rideExists ? ride.label : "<missing>"
        let badgeFrame = exists ? String(describing: health.firstMatch.frame) : "<missing>"
        let freshnessFrame = freshnessExists ? String(describing: freshness.frame) : "<missing>"
        let rideFrame = rideExists ? String(describing: ride.frame) : "<missing>"
        let diagnostic = "badge matches=\(count), label=\(badge), frame=\(badgeFrame); freshness=\(freshnessValue), frame=\(freshnessFrame); ride=\(rideValue), frame=\(rideFrame)"
        print("Waits feed accessibility state: \(diagnostic)")
        return (count, badge, freshnessValue, rideValue, diagnostic)
    }

    func testObservedWaitDotsKeepEveryValueAndOpenLowestWaitForecast() {
        let app = rootFixture(["--reference-ui-park=5", "--ride-history-ui-test", "--ride-history-supported"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
        reveal(history, in: app); history.tap()
        let chart = app.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
        centerFullyVisible(chart, in: app)
        screenshot("Every observed wait dot labeled latest samples", app: app)
        centerHorizontally("wait-sample-time-10916-0", in: "observed-wait-chart-10916", app: app)
        screenshot("Every observed wait dot labeled earlier samples", app: app)
        let sampleTimes = app.buttons["Sample times"].firstMatch
        reveal(sampleTimes, in: app); sampleTimes.tap()
        XCTAssertEqual(history.value as? String, "Expanded", "A child disclosure must keep ride history open")
        XCTAssertTrue(app.staticTexts["wait-sample-row-10916-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'wait-sample-row-10916-'")).count, 12)
        XCTAssertTrue(app.staticTexts["wait-sample-row-10916-4"].label.contains("0 min"), "A supplied zero is preserved")
        let lowest = app.staticTexts["ride-lowest-wait-window"]
        reveal(lowest, in: app); XCTAssertTrue(lowest.label.contains("about 10 min"))
        screenshot("Supported lowest wait prediction beside observed history", app: app)
        let hourly = app.buttons["ride-history-hourly-estimates"]
        reveal(hourly, in: app); hourly.tap()
        XCTAssertTrue(app.staticTexts["Lowest estimated wait"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertEqual(history.value as? String, "Expanded", "Opening hourly estimates must keep observed history expanded")
        XCTAssertTrue(chart.exists)
    }

    private func observedHistoryFixture(_ extra: [String] = []) -> XCUIApplication {
        let app = rootFixture(["--reference-ui-park=5", "--reference-ui-ride=10916", "--ride-history-ui-test"] + extra)
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
        reveal(history, in: app)
        history.tap()
        return app
    }

    private func nativeSnapshotNodes(_ snapshot: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        var nodes = [snapshot]
        var pending = snapshot.children
        while let node = pending.popLast() {
            nodes.append(node)
            pending.append(contentsOf: node.children)
        }
        return nodes
    }

    private func nativeElementSnapshot(_ identifier: String, in app: XCUIApplication) -> XCUIElementSnapshot? {
        // Snapshot the application itself before looking up an identity. Asking
        // an identifier-filtered XCUIElement for a snapshot first resolves its
        // query remotely. The retained timeout stacks are in that resolution.
        guard let root = try? app.snapshot() else { return nil }
        let matches = nativeSnapshotNodes(root).filter { $0.identifier == identifier }
        return matches.count == 1 ? matches[0] : nil
    }

    private struct NativeChartColumnSnapshot {
        let chart: XCUIElementSnapshot
        let clock: XCUIElementSnapshot
        let nodes: [XCUIElementSnapshot]
        let contentViewport: CGRect
    }

    private func assertObservedChartSamples(_ waits: [String], chart: XCUIElement) {
        // Read every real semantic dot from one native snapshot. Resolving a
        // separate live query for every value repeatedly snapshots this large
        // Swift Charts subtree and can exhaust an SE case before its gestures.
        guard let snapshot = try? chart.snapshot() else {
            XCTFail("The presented chart must supply its native accessibility snapshot")
            return
        }
        assertObservedChartSamples(waits, nodes: nativeSnapshotNodes(snapshot))
    }

    private func assertObservedChartSamples(_ waits: [String], nodes: [XCUIElementSnapshot]) {
        let points = nodes.filter { $0.label.hasPrefix("Observation ") }
        XCTAssertEqual(points.count, waits.count, "Every distinct dot must remain readable to VoiceOver")
        for (index, wait) in waits.enumerated() {
            let matches = points.filter { $0.label.hasPrefix("Observation \(index + 1),") }
            XCTAssertEqual(matches.count, 1, "Each observation must have exactly one genuine semantic dot")
            guard let point = matches.first else { continue }
            XCTAssertEqual(point.value as? String, "\(wait) minutes", "Each dot must announce its own recorded wait")
        }
    }

    private func safeContentViewport(in app: XCUIApplication) -> CGRect {
        let window = app.frame
        var top = window.minY + 24
        var bottom = window.maxY - 8
        for bar in app.statusBars.allElementsBoundByIndex {
            let frame = bar.frame
            if !frame.isEmpty, frame.intersects(window), frame.maxY < window.midY {
                top = max(top, frame.maxY + 8)
            }
        }
        // UIKit can retain the underlying page in the accessibility tree of a
        // sheet. Only foreground native controls reserve content space.
        for bar in app.navigationBars.allElementsBoundByIndex where bar.isHittable {
            let frame = bar.frame
            if !frame.isEmpty, frame.intersects(window), frame.maxY < window.midY {
                top = max(top, frame.maxY + 8)
            }
        }
        for bar in app.tabBars.allElementsBoundByIndex + app.keyboards.allElementsBoundByIndex where bar.isHittable {
            let frame = bar.frame
            if !frame.isEmpty, frame.intersects(window), frame.minY > window.midY {
                bottom = min(bottom, frame.minY - 8)
            }
        }
        return CGRect(x: window.minX + 8, y: top, width: window.width - 16, height: max(1, bottom - top))
    }

    private func assertContained(_ frame: CGRect, in viewport: CGRect, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(frame.isEmpty, message, file: file, line: line)
        XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame),
                      "\(message). Frame \(frame); visible area \(viewport)", file: file, line: line)
    }

    private func waitForSettledFrames(_ elements: [XCUIElement],
                                      sampleFrames: (() -> [CGRect])? = nil,
                                      file: StaticString = #filePath, line: UInt = #line) {
        waitForSettledFrames(count: elements.count, sampleFrames: { deadline in
            if let sampleFrames { return sampleFrames() }
            var frames: [CGRect] = []
            for element in elements {
                guard Date() < deadline else { break }
                frames.append(element.frame)
            }
            return frames
        }, file: file, line: line)
    }

    private func waitForSettledFrames(count: Int, sampleFrames: (Date) -> [CGRect],
                                      file: StaticString = #filePath, line: UInt = #line) {
        let started = Date()
        let deadline = started.addingTimeInterval(15)
        var previous: [CGRect] = []
        var previousSampleAt: Date?
        var trace: [String] = []
        while Date() < deadline {
            if let previousSampleAt {
                let delay = 0.25 - Date().timeIntervalSince(previousSampleAt)
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            }
            // An AX read cannot be interrupted. Check before each read so only
            // the in-flight frame lookup may finish after the deadline.
            guard Date() < deadline else { break }
            let frames = sampleFrames(deadline)
            let sampledAt = Date()
            trace.append("t=\(sampledAt.timeIntervalSince(started)): \(frames)")
            guard frames.count == count else { break }
            let valid = frames.allSatisfy { frame in
                !frame.isEmpty && !frame.isNull
                    && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            }
            let stable = valid && frames.count == previous.count && zip(frames, previous).allSatisfy { lhs, rhs in
                abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
                    && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
            }
            if stable, let previousSampleAt, sampledAt.timeIntervalSince(previousSampleAt) >= 0.25 { return }
            previous = valid ? frames : []
            previousSampleAt = sampledAt
        }
        XCTFail("Displayed glyph frames must settle before measuring or capturing them. Actual sample trace: \(trace.joined(separator: "; "))",
                file: file, line: line)
    }

    private func verticalPanX(in viewport: CGRect) -> CGFloat {
        // Clear the native scroll indicator's expanded drag area.
        viewport.maxX - min(48, viewport.width / 4)
    }

    /// Move by the measured missing edge, using longer drags only while far
    /// away. The entire target must fit clear of foreground native bars.
    private func centerFullyVisible(_ element: XCUIElement, in app: XCUIApplication, snapshotIdentifier: String? = nil,
                                     file: StaticString = #filePath, line: UInt = #line) {
        func currentFrame() -> CGRect {
            if let snapshotIdentifier {
                return nativeElementSnapshot(snapshotIdentifier, in: app)?.frame ?? .zero
            }
            return element.exists ? element.frame : .zero
        }
        let viewport = safeContentViewport(in: app)
        let appFrame = app.frame
        for _ in 0..<22 {
            var movement: CGFloat = min(420, viewport.height * 0.8)
            let frame = currentFrame()
            if !frame.isEmpty {
                guard frame.height <= viewport.height + 1, frame.width <= viewport.width + 1 else {
                    XCTFail("Target cannot fit the visible content area. Frame \(frame); viewport \(viewport)", file: file, line: line)
                    return
                }
                if viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                    if snapshotIdentifier != nil {
                        waitForSettledFrames(count: 1, sampleFrames: { _ in [currentFrame()] }, file: file, line: line)
                    } else {
                        waitForSettledFrames([element], file: file, line: line)
                    }
                    let finalViewport = safeContentViewport(in: app)
                    let finalFrame = snapshotIdentifier == nil ? element.frame : currentFrame()
                    assertContained(finalFrame, in: finalViewport, "The complete target must remain visible", file: file, line: line)
                    return
                }
                let offset = frame.minY < viewport.minY
                    ? frame.minY - viewport.minY - 12 : frame.maxY - viewport.maxY + 12
                movement = min(movement, max(20, abs(offset))) * (offset < 0 ? -1 : 1)
            }
            let x = verticalPanX(in: viewport)
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x - appFrame.minX, dy: viewport.midY + movement / 2 - appFrame.minY))
            let end = start.withOffset(CGVector(dx: 0, dy: -movement))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        screenshot("Complete target could not fit the content viewport", app: app)
        XCTFail("Could not place the complete target inside the visible content area. Frame \(currentFrame()); viewport \(safeContentViewport(in: app))", file: file, line: line)
    }

    private func assertCompleteClock(_ label: XCUIElementSnapshot, category: UIContentSizeCategory,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let text = label.label
        let clock = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertNotNil(clock.range(of: #"\d{1,2}:\d{2}\s?[AP]M"#, options: .regularExpression), file: file, line: line)
        XCTAssertFalse(clock.contains("…") || clock.contains("..."), "Clocks must retain their complete hour, minute and AM/PM", file: file, line: line)
        // Accessibility labels can retain characters that were visually
        // ellipsized. Independently require enough space for their actual
        // caption glyphs at the requested native content-size category.
        let font = UIFont.preferredFont(forTextStyle: .caption2,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        let glyphs = (text as NSString).size(withAttributes: [.font: font])
        let frame = label.frame
        XCTAssertGreaterThanOrEqual(frame.width, ceil(glyphs.width) - 2,
                                    "The displayed time must have room for every glyph", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, font.lineHeight - 2,
                                    "The displayed time must have a complete caption line", file: file, line: line)
    }

    private func expectedTextHeight(_ text: String, width: CGFloat, style: UIFont.TextStyle,
                                    category: UIContentSizeCategory) -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        let bounds = (text as NSString).boundingRect(with: CGSize(width: max(1, width), height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return ceil(bounds.height)
    }

    private func assertFullTextLayout(_ text: XCUIElement, style: UIFont.TextStyle = .caption1,
                                      category: UIContentSizeCategory = .accessibilityLarge,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let wording = text.label
        let frame = text.frame
        XCTAssertFalse(wording.contains("…") || wording.contains("..."),
                       "Supporting text must retain its full wording", file: file, line: line)
        let required = expectedTextHeight(wording, width: frame.width, style: style, category: category)
        XCTAssertGreaterThanOrEqual(frame.height, required - 3,
                                    "The visible text frame must accommodate its entire wrapped wording", file: file, line: line)
    }

    @discardableResult
    private func centerHorizontally(_ identifier: String, in chartIdentifier: String, app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) -> NativeChartColumnSnapshot? {
        XCTAssertFalse(identifier.isEmpty, "The displayed clock needs its genuine accessibility identity", file: file, line: line)
        func readColumn() -> (chart: XCUIElementSnapshot, clock: XCUIElementSnapshot, nodes: [XCUIElementSnapshot])? {
            guard let chart = nativeElementSnapshot(chartIdentifier, in: app) else { return nil }
            let nodes = nativeSnapshotNodes(chart)
            let clocks = nodes.filter { $0.elementType == .staticText && $0.identifier == identifier }
            guard clocks.count == 1 else { return nil }
            return (chart, clocks[0], nodes)
        }
        let exists = NSPredicate { _, _ in readColumn() != nil }
        let existence = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: exists, object: nil)], timeout: 5)
        XCTAssertEqual(existence, .completed, "A genuine displayed time label must exist exactly once", file: file, line: line)
        guard existence == .completed else { return nil }
        func currentFrames() -> [CGRect] {
            guard let state = readColumn() else { return [.zero, .zero] }
            return [state.chart.frame, state.clock.frame]
        }
        let contentViewport = safeContentViewport(in: app)
        let appFrame = app.frame
        var trace: [String] = []
        // Measure once more after the final permitted pan. Largest observation
        // columns can begin several viewports away from the requested quarter.
        for attempt in 0...24 {
            let frames = currentFrames()
            let viewport = frames[0].intersection(contentViewport).insetBy(dx: 4, dy: 0)
            let frame = frames[1]
            let offset = frame.minX < viewport.minX
                ? viewport.minX - frame.minX + 12 : viewport.maxX - frame.maxX - 12
            trace.append("attempt \(attempt): label=\(frame), viewport=\(viewport), horizontalOffset=\(offset)")
            guard !frame.isEmpty, frame.width <= viewport.width + 1 else {
                XCTFail("A complete time label must fit its scroll viewport. Frame \(frame); viewport \(viewport)", file: file, line: line)
                return nil
            }
            let fullyVisible = viewport.insetBy(dx: -1, dy: -1).contains(frame)
            if fullyVisible {
                waitForSettledFrames(count: 2, sampleFrames: { _ in currentFrames() }, file: file, line: line)
                // The inset above is a positioning margin. After scrolling settles,
                // require the full glyph frame to fit the actual visible clip.
                let contentViewport = safeContentViewport(in: app)
                guard let settled = readColumn() else {
                    XCTFail("The settled chart and its unique displayed clock must retain their native identities", file: file, line: line)
                    return nil
                }
                let currentViewport = settled.chart.frame.intersection(contentViewport)
                assertContained(settled.clock.frame, in: currentViewport, "The entire time label must be inside the horizontal viewport", file: file, line: line)
                print("HORIZONTAL_CLOCK_VERIFIED identifier=\(identifier) pans=\(attempt) frame=\(settled.clock.frame) viewport=\(currentViewport)")
                // These are attributes of the actual post-pan state, obtained
                // together. Re-reading label/value/frame as live queries here
                // was the next blocking remote lookup in the timeout trace.
                return NativeChartColumnSnapshot(chart: settled.chart, clock: settled.clock,
                    nodes: settled.nodes, contentViewport: contentViewport)
            }
            guard attempt < 24 else { break }
            let movement = min(viewport.width * 0.85, max(20, abs(offset))) * (offset < 0 ? -1 : 1)
            print("HORIZONTAL_CLOCK_PAN identifier=\(identifier) attempt=\(attempt) frame=\(frame) viewport=\(viewport) movement=\(movement)")
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX - movement / 2 - appFrame.minX, dy: viewport.midY - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: movement, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not bring the complete time label into its horizontal viewport. Actual pan trace: \(trace.joined(separator: "; "))",
                file: file, line: line)
        return nil
    }

    private func assertHistoryHeaderLayout(_ header: XCUIElement, chart: XCUIElement, app: XCUIApplication,
                                           category: UIContentSizeCategory, capture: String) -> Bool {
        func requireExpandedHistory(_ stage: String) -> Bool {
            let value = header.value as? String
            let observation = "HISTORY_DISCLOSURE_STATE stage=\(stage) value=\(value ?? "missing") header=\(header.frame) chartExists=\(chart.exists)"
            print(observation)
            guard value == "Expanded" else {
                screenshot("\(capture) unexpected disclosure state \(stage)", app: app)
                let evidence = XCTAttachment(string: "\(observation)\n\(app.debugDescription)")
                evidence.name = "History disclosure state \(stage)"
                evidence.lifetime = .keepAlways
                add(evidence)
                XCTFail("Positioning the history header must preserve its expanded disclosure: \(observation)")
                return false
            }
            return true
        }
        if header.exists { guard requireExpandedHistory("before positioning") else { return false } }
        centerFullyVisible(header, in: app, snapshotIdentifier: "wait-history-toggle-10916")
        guard requireExpandedHistory("after complete header positioning") else { return false }
        let viewport = safeContentViewport(in: app)
        let positionedHeader = header.frame
        // A narrow horizontal gutter beside a SwiftUI Button can still be in
        // its effective touch region. Start above the disclosure instead, and
        // keep the whole upward pan clear of the control's expanded hit area.
        let clearance: CGFloat = 44
        let point = CGPoint(x: viewport.midX, y: positionedHeader.minY - clearance)
        let movement = min(viewport.height * 0.8,
                           max(0, point.y - viewport.minY - 12))
        if movement > 2 {
            // Put the title near the upper edge so that the adjacent plot also
            // has a real visible frame, even when both are taller than SE.
            // This is a scroll-positioning gesture through the preceding
            // content, rather than the disclosure's adjacent touch padding.
            let appFrame = app.frame
            XCTAssertTrue(viewport.contains(point), "The positioning gesture must begin inside visible content")
            XCTAssertFalse(positionedHeader.insetBy(dx: -32, dy: -32).contains(point),
                           "The positioning pan must begin beyond the disclosure's adjacent touch padding")
            XCTAssertLessThanOrEqual(point.y, positionedHeader.minY - clearance,
                                     "The positioning pan must stay clear of the disclosure's touch padding")
            print("HISTORY_POSITIONING_GESTURE start=\(point) movement=\(movement) header=\(positionedHeader) viewport=\(viewport)")
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: point.x - appFrame.minX, dy: point.y - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -movement)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
            guard requireExpandedHistory("after upper-edge positioning drag") else { return false }
            waitForSettledFrames([header, chart])
            XCTAssertLessThan(header.frame.minY, positionedHeader.minY - min(10, movement / 2),
                              "The real positioning drag must move the presented history content")
        }
        let headerFrame = header.frame
        assertContained(headerFrame, in: safeContentViewport(in: app), "The complete history header must stay visible after positioning")
        let wording = header.label
        XCTAssertTrue(wording.hasPrefix("Recent observed waits"))
        // The complete control must be at least as tall as its wording would
        // need with no icon at all. A collapsed 44pt control cannot satisfy this
        // bound while painting a four-line title over the chart.
        let minimum = expectedTextHeight(wording, width: headerFrame.width, style: .caption1, category: category)
        XCTAssertGreaterThanOrEqual(headerFrame.height, minimum - 3,
                                    "The disclosure must reserve the full height of its multiline title")
        let title = header.staticTexts["wait-history-title-10916"].firstMatch
        if title.exists {
            assertFullTextLayout(title, style: .caption1, category: category)
            assertContained(title.frame, in: headerFrame, "The genuine title glyphs must fit inside the disclosure control")
        }
        let chartFrame = chart.frame
        XCTAssertFalse(chartFrame.isEmpty || chartFrame.isInfinite || chartFrame.isNull)
        XCTAssertLessThanOrEqual(headerFrame.maxY + 8, chartFrame.minY,
                                 "The full disclosure header must end before the plotted wait labels begin")
        screenshot("\(capture) complete history header clear of chart", app: app)
        return true
    }

    private func assertHistoryColumns(_ waits: [String], chart: XCUIElement, app: XCUIApplication,
                                      category: UIContentSizeCategory = .accessibilityExtraExtraExtraLarge,
                                      observations: Range<Int>? = nil, header: XCUIElement? = nil, capture: String) {
        if let header {
            guard assertHistoryHeaderLayout(header, chart: chart, app: app, category: category, capture: capture) else { return }
        }
        centerFullyVisible(chart, in: app, snapshotIdentifier: "observed-wait-chart-10916")
        guard let initial = nativeElementSnapshot("observed-wait-chart-10916", in: app) else {
            XCTFail("The presented history chart must have one genuine native accessibility identity")
            return
        }
        let initialNodes = nativeSnapshotNodes(initial)
        assertObservedChartSamples(waits, nodes: initialNodes)
        let times = initialNodes.filter { $0.elementType == .staticText && $0.identifier.hasPrefix("wait-sample-time-10916-") }
        XCTAssertEqual(times.count, waits.count, "Every dot must have a genuine displayed local-time label")
        for index in (observations ?? waits.indices).reversed() {
            guard let column = centerHorizontally("wait-sample-time-10916-\(index)",
                in: "observed-wait-chart-10916", app: app) else { return }
            assertCompleteClock(column.clock, category: category)
            let points = column.nodes.filter { $0.label.hasPrefix("Observation \(index + 1),") }
            XCTAssertEqual(points.count, 1, "The visible column must retain its unique semantic observation")
            guard let point = points.first else { return }
            XCTAssertEqual(point.value as? String, "\(waits[index]) minutes")
            let annotations = column.nodes.filter {
                $0.elementType == .staticText && $0.identifier == "wait-sample-value-10916-\(index)"
            }
            XCTAssertLessThanOrEqual(annotations.count, 1, "An ordinary wait annotation must have one native identity")
            if let annotation = annotations.first {
                XCTAssertEqual(annotation.label, "\(waits[index]) min")
                assertContained(annotation.frame, in: column.chart.frame.intersection(column.contentViewport), "The complete wait annotation must remain visible")
            }
            // Charts may expose annotations through the semantic Observation
            // element instead of a Text node. The real time label positions the
            // same column; each attachment also records that dot's visible glyphs.
            assertContained(column.chart.frame, in: column.contentViewport, "The entire chart must be visible for every captured observation")
            screenshot("\(capture) observation \(index + 1) value and full local time", app: app)
        }
    }

    private func assertForecastTimeLabels(in forecast: XCUIElement, app: XCUIApplication,
                                         quarter: Int, capture: String) {
        let chart = forecast.descendants(matching: .any)["wait-forecast-chart"].firstMatch
        centerFullyVisible(chart, in: app, snapshotIdentifier: "wait-forecast-chart")
        guard let initial = nativeElementSnapshot("wait-forecast-chart", in: app) else {
            XCTFail("The presented forecast chart must have one genuine native accessibility identity")
            return
        }
        let times = nativeSnapshotNodes(initial).filter {
            $0.elementType == .staticText && $0.identifier.hasPrefix("wait-forecast-time-")
        }
        let count = times.count
        XCTAssertGreaterThan(count, 1, "A multi-hour forecast must display its actual time labels")
        XCTAssertLessThanOrEqual(count, 25)
        XCTAssertEqual(count, 8, "The supported fixture must retain all eight ordinary forecast clocks")
        XCTAssertTrue((0..<4).contains(quarter))
        // Two clocks per case leave room for a cold native app launch while
        // preserving every clock, font, and whole-viewport assertion.
        let indices = (quarter * 2)..<(quarter * 2 + 2)
        for index in indices.reversed() {
            guard let column = centerHorizontally("wait-forecast-time-\(index)", in: "wait-forecast-chart", app: app) else { return }
            assertCompleteClock(column.clock, category: .accessibilityLarge)
            screenshot("\(capture) full forecast time \(index + 1)", app: app)
        }
    }

    private func assertObservedSampleRows(_ waits: [String], app: XCUIApplication) {
        let disclosure = app.buttons["Sample times"].firstMatch
        centerFullyVisible(disclosure, in: app)
        disclosure.tap()
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
        XCTAssertEqual(history.value as? String, "Expanded", "Opening sample times must not toggle the parent disclosure")
        XCTAssertTrue(app.staticTexts["wait-sample-row-10916-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'wait-sample-row-10916-'")).count, waits.count)
        for (index, wait) in waits.enumerated() {
            let row = app.staticTexts["wait-sample-row-10916-\(index)"]
            centerFullyVisible(row, in: app)
            XCTAssertTrue(row.label.hasSuffix("· \(wait) min"), "Observation \(index + 1) must retain its own wait")
            XCTAssertGreaterThanOrEqual(row.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        }
    }

    func testObservedHistoryLabelsKeepTwelveRepeatedDotsInLightAppearance() {
        checkRepeatedHistory(appearance: "--ui-light")
    }

    func testObservedHistoryLabelsKeepTwelveRepeatedDotsInDarkAppearance() {
        checkRepeatedHistory(appearance: "--ui-dark")
    }

    private func checkRepeatedHistory(appearance: String) {
        let app = observedHistoryFixture(["--ride-history-case=equal", appearance])
        let chart = app.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
        centerFullyVisible(chart, in: app)
        assertObservedChartSamples(Array(repeating: "15", count: 12), chart: chart)
        screenshot("Observed history repeated waits latest \(appearance)", app: app)
        centerHorizontally("wait-sample-time-10916-0", in: "observed-wait-chart-10916", app: app)
        screenshot("Observed history repeated waits earlier \(appearance)", app: app)
        assertObservedSampleRows(Array(repeating: "15", count: 12), app: app)
        app.terminate()
    }

    func testObservedHistoryHandlesSingleSample() {
        checkObservedHistoryCases(["single"])
    }

    func testObservedHistoryHandlesSparseSamples() {
        checkObservedHistoryCases(["sparse"])
    }

    func testObservedHistoryWithholdsUnavailableSamples() {
        checkObservedHistoryCases(["empty", "invalid"])
    }

    private func checkObservedHistoryCases(_ modes: [String]) {
        for mode in modes {
            let app = observedHistoryFixture(["--ride-history-case=\(mode)"])
            let chart = app.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
            if mode == "empty" || mode == "invalid" {
                let empty = app.staticTexts["wait-history-empty-10916"]
                reveal(empty, in: app)
                XCTAssertTrue(empty.isHittable)
                XCTAssertFalse(chart.exists, "Unavailable observations must not become zero-minute dots")
                XCTAssertFalse(app.buttons["Sample times"].exists)
            } else {
                let maximum = Double(1440).formatted(.number.precision(.fractionLength(0...1)))
                let waits = mode == "single" ? ["12.5"] : ["0", "12.5", maximum]
                assertHistoryColumns(waits, chart: chart, app: app, category: .large, capture: "Observed history \(mode)")
                assertObservedSampleRows(waits, app: app)
            }
            screenshot("Observed history \(mode)", app: app)
            app.terminate()
        }
    }

    func testObservedHistoryLargestRowsKeepFirstThreeLabelsReadable() {
        checkLargestHistoryRows(observations: 0..<3)
    }

    func testObservedHistoryLargestRowsKeepSecondThreeLabelsReadable() {
        checkLargestHistoryRows(observations: 3..<6)
    }

    func testObservedHistoryLargestRowsKeepThirdThreeLabelsReadable() {
        checkLargestHistoryRows(observations: 6..<9)
    }

    func testObservedHistoryLargestRowsKeepLastThreeLabelsReadable() {
        checkLargestHistoryRows(observations: 9..<12)
    }

    private func checkLargestHistoryRows(observations: Range<Int>) {
        let app = observedHistoryFixture(["--ui-largest-type", "--ui-dark"])
        let chart = app.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
        let waits = ["20", "20", "15", "15", "0", "15", "25", "20", "15", "10", "15", "15"]
        assertHistoryColumns(waits, chart: chart, app: app, observations: observations,
            header: app.buttons["wait-history-toggle-10916"], capture: "Largest observed history row")
        app.terminate()
    }

    func testObservedSampleTimesRemainReadableAtLargestAccessibilitySize() {
        let app = observedHistoryFixture(["--ui-largest-type", "--ui-dark"])
        let waits = ["20", "20", "15", "15", "0", "15", "25", "20", "15", "10", "15", "15"]
        assertObservedSampleRows(waits, app: app)
        XCTAssertGreaterThan(app.staticTexts["wait-sample-row-10916-11"].frame.height, 60,
                             "Measure the real wrapping sample text to verify the largest size was applied")
        screenshot("Largest observed history sample times", app: app)
        app.terminate()
    }

    func testObservedHistoryLargestDetailsKeepFirstThreeLabelsReadable() {
        checkLargestHistoryDetails(observations: 0..<3)
    }

    func testObservedHistoryLargestDetailsKeepSecondThreeLabelsReadable() {
        checkLargestHistoryDetails(observations: 3..<6)
    }

    func testObservedHistoryLargestDetailsKeepThirdThreeLabelsReadable() {
        checkLargestHistoryDetails(observations: 6..<9)
    }

    func testObservedHistoryLargestDetailsKeepLastThreeLabelsReadable() {
        checkLargestHistoryDetails(observations: 9..<12)
    }

    private func checkLargestHistoryDetails(observations: Range<Int>) {
        let app = rootFixture(["--reference-ui-park=5", "--reference-ui-ride=10916", "--ride-history-ui-test", "--ui-largest-type", "--ui-dark"])
        let ride = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guardians of the Galaxy'")).firstMatch
        reveal(ride, in: app); ride.tap()
        XCTAssertTrue(app.navigationBars["Ride information"].waitForExistence(timeout: 5))
        let bodySize = app.staticTexts["Ride information body size"]
        XCTAssertTrue(bodySize.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bodySize.frame.height, 50, "Ride details must actually render the largest accessibility text size")
        let details = app.scrollViews["ride-information-content"]
        XCTAssertTrue(details.waitForExistence(timeout: 5), "Chart assertions must inspect the presented ride information")
        let chart = details.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
        let waits = ["20", "20", "15", "15", "0", "15", "25", "20", "15", "10", "15", "15"]
        assertHistoryColumns(waits, chart: chart, app: app, observations: observations,
            header: details.buttons["wait-history-toggle-10916"], capture: "Largest observed history ride detail")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        app.terminate()
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

    func testLowestWaitEvidenceAndHourlySheetStayConsistentAtAccessibilityTextSize() {
        checkLowestWaitEvidenceAndHourlySheet(expired: false)
    }

    func testStaleLowestWaitHourlySheetWithholdsRecommendationAtAccessibilityTextSize() {
        checkLowestWaitEvidenceAndHourlySheet(expired: true)
    }

    func testHourlyForecastShowsFirstTwoCompleteTimesAtAccessibilityTextSize() {
        checkHourlyForecastTimesAtAccessibilityTextSize(quarter: 0)
    }

    func testHourlyForecastShowsSecondTwoCompleteTimesAtAccessibilityTextSize() {
        checkHourlyForecastTimesAtAccessibilityTextSize(quarter: 1)
    }

    func testHourlyForecastShowsThirdTwoCompleteTimesAtAccessibilityTextSize() {
        checkHourlyForecastTimesAtAccessibilityTextSize(quarter: 2)
    }

    func testHourlyForecastShowsLastTwoCompleteTimesAtAccessibilityTextSize() {
        checkHourlyForecastTimesAtAccessibilityTextSize(quarter: 3)
    }

    private func checkHourlyForecastTimesAtAccessibilityTextSize(quarter: Int) {
        let app = observedHistoryFixture(["--ride-history-supported", "--ui-large-type"])
        let summary = app.otherElements["ride-lowest-wait-summary"].firstMatch
        let hourly = summary.buttons["ride-history-hourly-estimates"]
        centerFullyVisible(hourly, in: app, snapshotIdentifier: "ride-history-hourly-estimates"); hourly.tap()
        XCTAssertTrue(app.navigationBars["Predicted waits"].waitForExistence(timeout: 5))
        let forecast = app.otherElements["ride-wait-forecast"].firstMatch
        XCTAssertTrue(forecast.waitForExistence(timeout: 5))
        let bodySize = app.staticTexts["Hourly forecast body size"]
        XCTAssertTrue(bodySize.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bodySize.frame.height, 35,
                                    "Clock glyphs must be reviewed in the genuinely enlarged modal")
        assertForecastTimeLabels(in: forecast, app: app, quarter: quarter, capture: "Accessibility hourly sheet")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.isHittable)
        done.tap(); app.terminate()
    }

    private func checkLowestWaitEvidenceAndHourlySheet(expired: Bool) {
        let app = rootFixture(["--reference-ui-park=5", "--ride-history-ui-test", "--ride-history-supported", "--ui-large-type"]
            + (expired ? ["--ride-search-expired"] : []))
        let search = app.textFields["Ride search"]
        centerFullyVisible(search, in: app)
        XCTAssertTrue(search.isHittable)
        search.tap(); search.typeText("Guardians\n")
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
        reveal(history, in: app); history.tap()
        let summary = app.otherElements["ride-lowest-wait-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        if expired {
            let unavailable = summary.staticTexts["Prediction unavailable"].firstMatch
            centerFullyVisible(unavailable, in: app)
            XCTAssertFalse(summary.staticTexts["ride-lowest-wait-window"].exists)
            XCTAssertFalse(summary.staticTexts["lowest-wait-source-time"].exists)
        } else {
            let lowest = summary.staticTexts["ride-lowest-wait-window"]
            centerFullyVisible(lowest, in: app)
            XCTAssertTrue(lowest.label.contains("about 10 min"))
            let parkTime = summary.staticTexts["lowest-wait-park-time"]
            centerFullyVisible(parkTime, in: app)
            screenshot("Lowest wait complete park-local date and zone", app: app)
            let parkWording = parkTime.label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertNotNil(parkWording.range(of:
                #"^Park time · (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([1-9]|[12][0-9]|3[01]),?(?: at)? (1[0-2]|0?[1-9]):[0-5][0-9] ?[AP]M (EDT|EST)$"#,
                options: .regularExpression), "Retain the complete park-local date, clock and zone: \(parkTime.label)")
            assertFullTextLayout(parkTime, style: .caption1, category: .accessibilityLarge)
            let variation = summary.staticTexts["lowest-wait-variation"]
            centerFullyVisible(variation, in: app)
            screenshot("Lowest wait complete observed variation", app: app)
            XCTAssertNotNil(variation.label.range(of:
                #"^Observed variation [0-9]+–[0-9]+ min; not a guaranteed interval\.$"#,
                options: .regularExpression), "Retain the complete range and uncertainty wording: \(variation.label)")
            assertFullTextLayout(variation, style: .caption1, category: .accessibilityLarge)
            let source = summary.staticTexts["lowest-wait-source-time"]
            centerFullyVisible(source, in: app)
            XCTAssertTrue(source.label.contains("Wait source checked"))
            let observed = summary.staticTexts["lowest-wait-history-time"]
            centerFullyVisible(observed, in: app)
            XCTAssertTrue(observed.label.contains("History last observed"))
        }
        screenshot(expired ? "Lowest wait unavailable at accessibility size" : "Lowest wait evidence at accessibility size", app: app)
        let hourly = summary.buttons["ride-history-hourly-estimates"]
        centerFullyVisible(hourly, in: app, snapshotIdentifier: "ride-history-hourly-estimates"); hourly.tap()
        XCTAssertTrue(app.navigationBars["Predicted waits"].waitForExistence(timeout: 5))
        let forecast = app.otherElements["ride-wait-forecast"].firstMatch
        XCTAssertTrue(forecast.waitForExistence(timeout: 5), "Assertions must inspect the presented forecast, whose source evidence also appears on the underlying page")
        let bodySize = app.staticTexts["Hourly forecast body size"]
        XCTAssertTrue(bodySize.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bodySize.frame.height, 35,
                                    "The actual presented hourly sheet must render accessibility-size body text")
        if expired {
            XCTAssertFalse(forecast.staticTexts["lowest-predicted-wait"].exists)
            XCTAssertFalse(forecast.staticTexts["lowest-wait-source-time"].exists)
            let saved = forecast.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'History only'")).firstMatch
            centerFullyVisible(saved, in: app)
            screenshot("Hourly sheet withholds stale lowest wait at measured accessibility size", app: app)
        } else {
            let lowest = forecast.staticTexts["lowest-predicted-wait"]
            centerFullyVisible(lowest, in: app)
            XCTAssertTrue(lowest.label.contains("about 10 min"))
            XCTAssertGreaterThan(lowest.frame.height, 40, "The complete hourly-window text must really wrap at accessibility size")
            let source = forecast.staticTexts["lowest-wait-source-time"]
            centerFullyVisible(source, in: app)
            XCTAssertTrue(source.label.contains("Wait source checked"))
            screenshot("Hourly sheet retains supported lowest wait at measured accessibility size", app: app)
        }
        let done = app.buttons["Done"]
        XCTAssertTrue(done.isHittable)
        done.tap(); app.terminate()
    }

    func testReopeningWindowShowsSupportedBestPredictionAndUnavailableStates() {
        checkReopeningPredictions(in: ["supported", "v3", "uncalibrated"])
    }

    func testReopeningWindowWithholdsRangeOnlyStaleAndMissingPoints() {
        checkReopeningPredictions(in: ["range-only", "stale", "missing"])
    }

    func testReopeningWindowDistinguishesEndedFailedAndPassedPredictions() {
        checkReopeningPredictions(in: ["ended", "failed", "passed"])
    }

    private func checkReopeningPredictions(in modes: [String]) {
        for mode in modes {
            let extra: [String]
            switch mode {
            case "uncalibrated": extra = ["--reopening-unsupported"]
            case "v3": extra = ["--reopening-v3"]
            case "range-only": extra = ["--reopening-range-only"]
            case "stale": extra = ["--ride-search-expired"]
            case "missing": extra = ["--reopening-missing"]
            case "ended": extra = ["--reopening-window-ended"]
            case "failed": extra = ["--reopening-refresh-failed"]
            case "passed": extra = ["--reopening-point-passed"]
            default: extra = []
            }
            let app = rootFixture(["--reference-ui-park=5", "--reopening-ui-test", "--ui-dark"] + extra)
            selectDownRides(in: app)
            let prediction = app.staticTexts["reopening-best-prediction-159"].firstMatch
            let window = app.staticTexts["reopening-window-159"].firstMatch
            let hasPrediction = ["supported", "v3", "uncalibrated", "passed"].contains(mode)
            func checkPrediction() {
                reveal(prediction, in: app)
                XCTAssertTrue(prediction.isHittable)
                if hasPrediction {
                    XCTAssertTrue(prediction.label.hasPrefix(mode == "passed" ? "Earlier best prediction ·" : "Best prediction ·"))
                    XCTAssertTrue(prediction.label.hasSuffix("(estimate)"))
                } else {
                    XCTAssertEqual(prediction.label, "Best prediction unavailable")
                }
                XCTAssertEqual(window.exists, hasPrediction || mode == "range-only")
            }
            checkPrediction()
            screenshot("Reopening best prediction \(mode) row", app: app)
            let ride = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Spaceship Earth'")).firstMatch
            reveal(ride, in: app); ride.tap()
            XCTAssertTrue(app.navigationBars["Ride information"].waitForExistence(timeout: 5))
            checkPrediction()
            if mode == "supported" || mode == "stale" { screenshot("Reopening best prediction \(mode) detail", app: app) }
            app.buttons["Done"].tap(); app.terminate()
        }
    }

    func testReopeningPredictionRemainsReadableAtAccessibilitySizeInRows() {
        let app = rootFixture(["--reference-ui-park=5", "--reopening-ui-test", "--ui-large-type", "--ui-dark"])
        selectDownRides(in: app)
        let headline = app.staticTexts["reopening-headline-159"].firstMatch
        centerFullyVisible(headline, in: app)
        XCTAssertEqual(headline.label, "Historical reopening range")
        assertFullTextLayout(headline)
        let window = app.staticTexts["reopening-window-159"].firstMatch
        centerFullyVisible(window, in: app)
        assertFullTextLayout(window)
        let prediction = app.staticTexts["reopening-best-prediction-159"].firstMatch
        centerFullyVisible(prediction, in: app)
        XCTAssertTrue(prediction.label.hasPrefix("Best prediction ·"))
        XCTAssertTrue(prediction.label.hasSuffix("(estimate)"))
        assertFullTextLayout(prediction)
        let detail = app.staticTexts["reopening-detail-159"].firstMatch
        centerFullyVisible(detail, in: app)
        XCTAssertEqual(detail.label, "Based on comparable observed closures. The park has not announced a reopening time.")
        assertFullTextLayout(detail)
        screenshot("Reopening best prediction accessibility row", app: app)
        app.terminate()
    }

    func testReopeningPredictionRemainsReadableAtAccessibilitySizeInRadar() {
        let app = rootFixture(["--reference-ui-park=5", "--reopening-ui-test", "--ui-large-type", "--ui-dark"])
        app.tabBars.buttons["More"].tap()
        let closures = app.buttons["Closures & park weather"]
        centerFullyVisible(closures, in: app); closures.tap()
        checkRadarSelectionAtAccessibilitySize(in: app)
        let headline = app.staticTexts["reopening-headline-159"].firstMatch
        centerFullyVisible(headline, in: app)
        XCTAssertEqual(headline.label, "Historical reopening range")
        assertFullTextLayout(headline, style: .headline)
        let prediction = app.staticTexts["reopening-best-prediction-159"].firstMatch
        centerFullyVisible(prediction, in: app)
        XCTAssertTrue(prediction.label.hasPrefix("Best prediction ·"))
        XCTAssertTrue(prediction.label.hasSuffix("(estimate)"))
        assertFullTextLayout(prediction, style: .subheadline)
        let window = app.staticTexts["reopening-window-159"].firstMatch
        centerFullyVisible(window, in: app)
        assertFullTextLayout(window, style: .title2)
        screenshot("Reopening best prediction accessibility radar", app: app)
        let detail = app.staticTexts["reopening-detail-159"].firstMatch
        centerFullyVisible(detail, in: app)
        XCTAssertEqual(detail.label, "Based on comparable observed closures. The park has not announced a reopening time.")
        assertFullTextLayout(detail, style: .subheadline)
        screenshot("Complete reopening supporting copy in accessibility Radar", app: app)
        app.terminate()
    }

    private func checkRadarSelectionAtAccessibilitySize(in app: XCUIApplication) {
        let picker = app.buttons["radar-featured-ride-picker"].firstMatch
        centerFullyVisible(picker, in: app)
        let automaticTitle = "Automatic · highest recent demand"
        func choose(_ title: String) {
            picker.tap()
            let option = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let updated = NSPredicate { _, _ in picker.value as? String == title }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: nil)], timeout: 5)
            if result != .completed {
                screenshot("Radar selection failed after one native menu tap", app: app)
                let state = XCTAttachment(string: "Requested: \(title)\nActual: \(String(describing: picker.value))\n\(app.debugDescription)")
                state.name = "Radar native selection failure state"
                state.lifetime = .keepAlways
                add(state)
            }
            XCTAssertEqual(result, .completed)
        }
        if picker.value as? String != automaticTitle { choose(automaticTitle) }
        centerFullyVisible(picker, in: app)
        XCTAssertEqual(picker.label, "Featured ride")
        XCTAssertEqual(picker.value as? String, automaticTitle)
        let selection = app.staticTexts["radar-featured-ride-selection"].firstMatch
        if selection.exists {
            waitForSettledFrames([picker, selection])
            XCTAssertEqual(selection.label, automaticTitle)
            assertContained(selection.frame, in: picker.frame, "The selected ride's full two-line label must fit its control")
            assertFullTextLayout(selection, style: .body)
        } else {
            // Native Menu may combine its label into the button. Check the
            // actual control's natural height against independently measured
            // body glyphs, without substituting a hidden layout probe.
            let required = expectedTextHeight(automaticTitle, width: picker.frame.width - 40,
                style: .body, category: .accessibilityLarge)
            XCTAssertGreaterThanOrEqual(picker.frame.height, max(44, required) - 3,
                                        "The Menu must grow enough to contain its complete wrapped title")
        }
        screenshot("Radar automatic selection full accessibility label", app: app)
        choose("Spaceship Earth")
        XCTAssertEqual(picker.value as? String, "Spaceship Earth", "The flexible label must preserve the original pin binding")
        choose(automaticTitle)
        XCTAssertEqual(picker.value as? String, automaticTitle, "Automatic selection must remain available after pinning")
    }

    private func selectDownRides(in app: XCUIApplication) {
        // Full-screen swipes can jump between either side of this compact
        // control on SE at accessibility size. Move it toward the actual
        // content center with short drags and tap the segment itself.
        let down = app.segmentedControls["ride-status-filter"].buttons["Down"]
        var lastFrame = CGRect.zero
        for _ in 0..<16 {
            let window = app.frame
            let bottom = app.tabBars.firstMatch.frame.minY
            let viewport = CGRect(x: window.minX, y: window.minY + 24,
                width: window.width, height: bottom - window.minY - 24)
            var movement: CGFloat = 110
            if down.exists {
                lastFrame = down.frame
                if !lastFrame.isEmpty, viewport.contains(lastFrame), down.isHittable {
                    down.tap()
                    return
                }
                if !lastFrame.isEmpty {
                    let offset = lastFrame.midY - viewport.midY
                    movement = min(110, max(30, abs(offset))) * (offset < 0 ? -1 : 1)
                }
            }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX, dy: viewport.midY))
            let end = start.withOffset(CGVector(dx: 0, dy: -movement))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        screenshot("Down filter could not be reached", app: app)
        XCTFail("Could not reveal Down segment. Last frame: \(lastFrame)")
    }

    func testFavoriteRideSearchConnectsWaitsAndSupportsLargeText() {
        for mode in ["default", "large", "expired", "unavailable"] {
            let extra = mode == "large" ? ["--ui-large-type"] : mode == "expired" ? ["--ride-search-expired"] : mode == "unavailable" ? ["--ride-search-unavailable"] : []
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
            XCTAssertTrue(guardians.label.contains(mode == "expired" ? "Wait stale" : mode == "unavailable" ? "Wait unavailable" : "45 min wait"))
            XCTAssertFalse(app.switches["favorite-ride-10914"].exists, "Land search must exclude World Showcase")
            let closed = app.switches["favorite-ride-159"]
            reveal(closed, in: app)
            XCTAssertTrue(closed.isHittable)
            XCTAssertTrue(closed.label.contains(mode == "expired" ? "Wait stale" : mode == "unavailable" ? "Wait unavailable" : "Temporarily closed"))
            XCTAssertGreaterThanOrEqual(closed.frame.height, 44)
            screenshot("Favorite search \(mode) waits and status", app: app)
            let endSearch = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "close"])).firstMatch
            XCTAssertTrue(endSearch.waitForExistence(timeout: 5)); endSearch.tap()
            app.buttons["Done"].tap(); app.terminate()
        }
    }

    private func assertNoVisibleThumbnailBadge(_ rideAction: XCUIElement, in app: XCUIApplication,
                                              file: StaticString = #filePath, line: UInt = #line) throws {
        centerFullyVisible(rideAction, in: app, file: file, line: line)
        let capture = rideAction.screenshot()
        let nativeImage = capture.image
        let nativePixels = try XCTUnwrap(nativeImage.cgImage, file: file, line: line)
        func recognizedText(in image: UIImage) throws -> [String] {
            let pixels = try XCTUnwrap(image.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.customWords = ["AI art"]
            request.minimumTextHeight = 0.005
            try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request])
            return request.results?.flatMap { $0.topCandidates(3).map(\.string) } ?? []
        }
        func containsBadge(_ strings: [String]) -> Bool {
            strings.contains { $0.range(of: #"\b(?:AI|Al)\s*art\b"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil }
        }
        // The old overlay was accessibility-hidden, so AX text absence alone
        // cannot catch it. Calibrate OCR on the same native pixels/scale with
        // an explicitly synthetic 9pt old badge. Never attach/export this control
        // as a native UI capture or change production rendering to assist OCR.
        let size = rideAction.frame.size
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            XCTFail("The native ride action must have a finite nonempty screenshot frame", file: file, line: line)
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(nativePixels.width) / size.width
        let control = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            nativeImage.draw(in: CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.white
            ]
            let text = "AI art" as NSString
            let measured = text.size(withAttributes: attributes)
            let badge = CGRect(x: 4, y: size.height - ceil(measured.height) - 10,
                               width: ceil(measured.width) + 10, height: ceil(measured.height) + 6)
            UIColor.black.withAlphaComponent(0.78).setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: badge.height / 2).fill()
            text.draw(at: CGPoint(x: badge.minX + 5, y: badge.minY + 3), withAttributes: attributes)
        }
        let calibration = try recognizedText(in: control)
        XCTAssertTrue(containsBadge(calibration), "OCR must detect the synthetic old badge before testing its absence: \(calibration)", file: file, line: line)
        let actual = try recognizedText(in: nativeImage)
        XCTAssertFalse(containsBadge(actual), "The actual ride thumbnail must have no visible AI art badge: \(actual)", file: file, line: line)
        let attachment = XCTAttachment(screenshot: capture)
        attachment.name = "Native ride action without thumbnail badge \(rideAction.identifier)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct ArtworkDeliveryCase {
        let parkID: Int
        let rideID: Int
        let parkName: String
        let rideName: String
        let references: [(credit: String, rights: String)]
        let adaptation: String?
        var key: String { "\(parkID)-\(rideID)" }
    }

    private var artworkDeliveryCases: [ArtworkDeliveryCase] {
        [
            .init(parkID: 5, rideID: 10916, parkName: "EPCOT", rideName: "Guardians of the Galaxy: Cosmic Rewind", references: [(credit: "Jedi94", rights: "CC BY-SA 4.0")], adaptation: "CC BY-SA 4.0"),
            .init(parkID: 6, rideID: 129, parkName: "Magic Kingdom Park", rideName: "Seven Dwarfs Mine Train", references: [(credit: "Carter Johnson", rights: "CC BY 2.0")], adaptation: "CC BY 2.0"),
            .init(parkID: 7, rideID: 5476, parkName: "Disney’s Hollywood Studios", rideName: "Slinky Dog Dash", references: [(credit: "Freddo", rights: "CC BY-SA 4.0")], adaptation: "CC BY-SA 4.0"),
            .init(parkID: 8, rideID: 110, parkName: "Disney’s Animal Kingdom", rideName: "Expedition Everest - Legend of the Forbidden Mountain", references: [(credit: "Benjamin D. Esham (bdesham)", rights: "CC BY-SA 4.0")], adaptation: "CC BY-SA 4.0"),
            .init(parkID: 21, rideID: 67702520791477, parkName: "SeaWorld Orlando", rideName: "SEAQuest: Legends of the Deep", references: [(credit: "Vekoma Rides Manufacturing B.V., official November 30 2025 IAAPA release; individual photographer not stated", rights: "Vekoma retains original-photo rights; photographic reference only, no permission to redistribute original asserted.")], adaptation: nil),
            .init(parkID: 24, rideID: 62020843059756, parkName: "Busch Gardens Tampa Bay", rideName: "Cheetah Hunt", references: [(credit: "Busch Gardens / United Parks & Resorts (reference publisher)", rights: "Copyright United Parks & Resorts; source rights retained")], adaptation: nil),
            .init(parkID: 32, rideID: 6173967272242, parkName: "Six Flags Magic Mountain", rideName: "WONDER WOMAN™ Flight of Courage", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 33, rideID: 108157577665976, parkName: "Six Flags Discovery Kingdom", rideName: "Medusa", references: [(credit: "Six Flags / Discovery Kingdom (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 34, rideID: 6240016210695, parkName: "Six Flags Over Texas", rideName: "Runaway Mine Train", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 35, rideID: 355690524725, parkName: "Six Flags Over Georgia", rideName: "Twisted Cyclone", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 37, rideID: 10024564956838, parkName: "Six Flags Great Adventure", rideName: "Jersey Devil Coaster", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 38, rideID: 94405110155494, parkName: "Six Flags Great America", rideName: "Goliath", references: [(credit: "Six Flags / Great America (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 39, rideID: 1502550413799, parkName: "Six Flags Fiesta Texas", rideName: "JOKER™: Carnival of Chaos", references: [(credit: "Six Flags / Fiesta Texas (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 41, rideID: 66829960275970, parkName: "Hurricane Harbor Los Angeles", rideName: "Tornado", references: [(credit: "Six Flags / Hurricane Harbor Los Angeles (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 43, rideID: 263165555937179, parkName: "Six Flags New England", rideName: "SUPERMAN™ The Ride", references: [(credit: "Six Flags / New England (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 44, rideID: 3285667514807, parkName: "Hurricane Harbor New Jersey", rideName: "Hurricane Mountain", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 50, rideID: 146600727393618, parkName: "Cedar Point", rideName: "Millennium Force", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 57, rideID: 187367662225851, parkName: "California’s Great America", rideName: "Gold Striker", references: [(credit: "Six Flags / California's Great America (reference publisher)", rights: "Copyright source photographer/operator; rights retained")], adaptation: nil),
            .init(parkID: 58, rideID: 3561804630704, parkName: "Canada’s Wonderland", rideName: "Behemoth", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 59, rideID: 255684283139198, parkName: "Carowinds", rideName: "Fury 325", references: [(credit: "Paul B. Drabek / Negative-G (original photographer and publisher)", rights: "Copyright Paul B. Drabek; rights retained")], adaptation: nil),
            .init(parkID: 60, rideID: 217175995369859, parkName: "Kings Island", rideName: "The Beast", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 61, rideID: 52035568535322, parkName: "Knott’s Berry Farm", rideName: "GhostRider", references: [(credit: "Six Flags / Knott's Berry Farm (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 62, rideID: 2757390716801, parkName: "Kings Dominion", rideName: "Rapterra", references: [(credit: "Six Flags (reference publisher)", rights: "Copyright Six Flags; source rights retained")], adaptation: nil),
            .init(parkID: 64, rideID: 6682, parkName: "Islands of Adventure", rideName: "Hagrid's Magical Creatures Motorbike Adventure™", references: [(credit: "Universal Orlando Resort own-attraction photography", rights: "Copyright Universal; photographic reference only, rights retained")], adaptation: nil),
            .init(parkID: 65, rideID: 5996, parkName: "Universal Studios Florida", rideName: "MEN IN BLACK™ Alien Attack!™", references: [(credit: "Orlando Informer attraction photography; individual photographer not stated", rights: "Reference only; copyright Orlando Informer/photographer retained")], adaptation: nil),
            .init(parkID: 67, rideID: 16595, parkName: "Volcano Bay", rideName: "Krakatau™ Aqua Coaster", references: [(credit: "Universal Orlando Resort (reference publisher)", rights: "Copyright Universal Studios; source rights retained")], adaptation: nil),
            .init(parkID: 69, rideID: 264332998053273, parkName: "Dorney Park & Wildwater Kingdom", rideName: "Talon", references: [(credit: "Six Flags / Dorney Park (reference publisher)", rights: "Copyright source photographer/operator; rights retained")], adaptation: nil),
            .init(parkID: 281, rideID: 122687607356381, parkName: "Six Flags Darien Lake", rideName: "Ride of Steel", references: [(credit: "Six Flags / Darien Lake (reference publisher)", rights: "Copyright source photographer/operator; rights retained")], adaptation: nil),
            .init(parkID: 282, rideID: 37680069812368, parkName: "Frontier City", rideName: "Silver Bullet", references: [(credit: "Six Flags / Frontier City (reference publisher)", rights: "Copyright source photographer/operator; rights retained")], adaptation: nil),
            .init(parkID: 295, rideID: 15992860430486, parkName: "Hurricane Harbor Phoenix", rideName: "Bahama Blaster", references: [(credit: "Six Flags / Hurricane Harbor Phoenix (reference publisher)", rights: "Copyright source photographer/operator; rights retained")], adaptation: nil),
            .init(parkID: 334, rideID: 14691, parkName: "Epic Universe", rideName: "Fyre Drill", references: [(credit: "Universal Orlando Resort (reference publisher)", rights: "Copyright Universal Studios; source rights retained")], adaptation: nil),
            .init(parkID: 339, rideID: 7461499888841, parkName: "Schlitterbahn New Braunfels", rideName: "Deluge", references: [(credit: "Six Flags / Schlitterbahn New Braunfels (reference publisher)", rights: "Copyright source photographer/operator; rights retained")], adaptation: nil),
        ]
    }

    private func revealArtworkDetail(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let navigation = app.navigationBars["Ride information"].firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let window = app.frame
        let scroll = app.scrollViews.allElementsBoundByIndex.first { candidate in
            candidate.exists && !candidate.frame.isEmpty && candidate.frame.intersects(window) && candidate.isHittable
        }
        guard let scroll else {
            XCTFail("Artwork details must expose a foreground scroll view", file: file, line: line)
            return
        }
        func visibleBody() -> CGRect {
            var area = scroll.frame.intersection(window).insetBy(dx: 2, dy: 4)
            let bottom = min(area.maxY, window.maxY - 12)
            area.origin.y = max(area.minY, navigation.frame.maxY + 8)
            area.size.height = max(0, bottom - area.minY)
            return area
        }
        for attempt in 0..<10 {
            waitForSettledFrames([scroll, element], file: file, line: line)
            let area = visibleBody()
            let frame = element.frame
            print("ARTWORK_DETAIL_VISIBLE attempt=\(attempt) label=\(element.label) viewport=\(area) target=\(frame)")
            guard area.width > 0, area.height > 44, !frame.isEmpty else {
                XCTFail("Artwork detail text needs a measured visible scroll region and nonempty frame", file: file, line: line)
                return
            }
            if area.contains(frame) && element.isHittable { return }
            // A full-window flick overshot these short rights links in run178.
            // Move at most120pt toward the measured target, holding at the end
            // so the next poll observes its resting position, not a fly-by.
            let offset = frame.midY - area.midY
            guard abs(offset) >= 1, frame.height <= area.height else {
                XCTFail("The complete artwork text must fit inside the foreground detail viewport", file: file, line: line)
                return
            }
            let movement = min(120, min(area.height * 0.25, max(20, abs(offset)))) * (offset < 0 ? -1 : 1)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: area.midX - window.minX, dy: area.midY + movement / 2 - window.minY))
            let end = start.withOffset(CGVector(dx: 0, dy: -movement))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        waitForSettledFrames([scroll, element], file: file, line: line)
        assertContained(element.frame, in: visibleBody(), "Complete artwork text must remain clear of navigation and screen edges", file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func assertArtworkDelivery(_ item: ArtworkDeliveryCase, largestText: Bool = false,
                                       overview: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let suffix = largestText ? " largest text" : ""
        let app = rootFixture(["--reference-ui-park=\(item.parkID)", "--reference-ui-ride=\(item.rideID)",
                               "--ui-dark"] + (largestText ? ["--ui-largest-type"] : []))
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Change park. Current park: \(item.parkName)"].waitForExistence(timeout: 5), file: file, line: line)
        let action = app.buttons["ride-row-action-\(item.rideID)"]
        reveal(action, in: app)
        XCTAssertTrue(action.isHittable, file: file, line: line)
        XCTAssertTrue(action.label.contains(item.rideName), file: file, line: line)
        XCTAssertTrue(action.label.contains("45 minute wait"), file: file, line: line)
        if overview { screenshot("Artwork delivery \(item.key) list\(suffix)", app: app) }
        // Thumbnail is deliberately hidden from VoiceOver. Preserve that behavior:
        // inspect its actual native button pixels; do not invent a Loaded AX value.
        let listCapture = XCTAttachment(screenshot: action.screenshot())
        listCapture.name = "Artwork delivery \(item.key) native ride action\(suffix)"
        listCapture.lifetime = .keepAlways
        add(listCapture)
        action.tap()
        let artwork = app.descendants(matching: .any)["ride-illustration-\(item.key)"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5), file: file, line: line)
        let loaded = NSPredicate { _, _ in artwork.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed, file: file, line: line)
        XCTAssertTrue(artwork.label.hasPrefix("AI illustration:"), file: file, line: line)
        screenshot("Artwork delivery \(item.key) detail\(suffix)", app: app)
        let credit = app.descendants(matching: .any)["ride-illustration-credit"].firstMatch
        revealArtworkDetail(credit, in: app, file: file, line: line)
        XCTAssertTrue(credit.isHittable, file: file, line: line)
        XCTAssertTrue(app.staticTexts["AI-generated illustration"].exists, file: file, line: line)
        let composition = app.staticTexts["Inspired by real ride photography. Composition and lighting are illustrated."]
        revealArtworkDetail(composition, in: app, file: file, line: line)
        XCTAssertTrue(composition.isHittable, file: file, line: line)
        for reference in item.references {
            let source = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Reference photo: " + reference.credit)).firstMatch
            revealArtworkDetail(source, in: app, file: file, line: line)
            XCTAssertTrue(source.isHittable, file: file, line: line)
            let rights = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Reference rights: " + reference.rights)).firstMatch
            revealArtworkDetail(rights, in: app, file: file, line: line)
            XCTAssertTrue(rights.isHittable, file: file, line: line)
        }
        if let license = item.adaptation {
            let adaptation = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Illustration adaptation: " + license)).firstMatch
            revealArtworkDetail(adaptation, in: app, file: file, line: line)
            XCTAssertTrue(adaptation.isHittable, file: file, line: line)
        } else {
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Illustration adaptation:'")).firstMatch.exists, file: file, line: line)
        }
        screenshot("Artwork delivery \(item.key) rights\(suffix)", app: app)
        let wait = app.staticTexts["45 min wait"]
        revealArtworkDetail(wait, in: app, file: file, line: line)
        XCTAssertTrue(wait.isHittable, file: file, line: line)
        print("ARTWORK_DELIVERY_VERIFIED key=\(item.key) detail=Loaded syntheticWait=45 largest=\(largestText)")
    }

    func testArtworkDeliveryLoadsParkGroup1() {
        for (offset, item) in artworkDeliveryCases[0..<2].enumerated() {
            assertArtworkDelivery(item, overview: (0 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup2() {
        for (offset, item) in artworkDeliveryCases[2..<4].enumerated() {
            assertArtworkDelivery(item, overview: (2 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup3() {
        for (offset, item) in artworkDeliveryCases[4..<6].enumerated() {
            assertArtworkDelivery(item, overview: (4 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup4() {
        for (offset, item) in artworkDeliveryCases[6..<8].enumerated() {
            assertArtworkDelivery(item, overview: (6 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup5() {
        for (offset, item) in artworkDeliveryCases[8..<10].enumerated() {
            assertArtworkDelivery(item, overview: (8 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup6() {
        for (offset, item) in artworkDeliveryCases[10..<12].enumerated() {
            assertArtworkDelivery(item, overview: (10 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup7() {
        for (offset, item) in artworkDeliveryCases[12..<14].enumerated() {
            assertArtworkDelivery(item, overview: (12 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup8() {
        for (offset, item) in artworkDeliveryCases[14..<16].enumerated() {
            assertArtworkDelivery(item, overview: (14 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup9() {
        for (offset, item) in artworkDeliveryCases[16..<18].enumerated() {
            assertArtworkDelivery(item, overview: (16 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup10() {
        for (offset, item) in artworkDeliveryCases[18..<20].enumerated() {
            assertArtworkDelivery(item, overview: (18 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup11() {
        for (offset, item) in artworkDeliveryCases[20..<22].enumerated() {
            assertArtworkDelivery(item, overview: (20 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup12() {
        for (offset, item) in artworkDeliveryCases[22..<24].enumerated() {
            assertArtworkDelivery(item, overview: (22 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup13() {
        for (offset, item) in artworkDeliveryCases[24..<26].enumerated() {
            assertArtworkDelivery(item, overview: (24 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup14() {
        for (offset, item) in artworkDeliveryCases[26..<28].enumerated() {
            assertArtworkDelivery(item, overview: (26 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup15() {
        for (offset, item) in artworkDeliveryCases[28..<30].enumerated() {
            assertArtworkDelivery(item, overview: (28 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryLoadsParkGroup16() {
        for (offset, item) in artworkDeliveryCases[30..<32].enumerated() {
            assertArtworkDelivery(item, overview: (30 + offset) % 4 == 0)
        }
    }

    func testArtworkDeliveryCreditsRemainReadableAtLargestAccessibilitySize() {
        let item = artworkDeliveryCases.first { $0.parkID == 32 && $0.rideID == 6173967272242 }!
        assertArtworkDelivery(item, largestText: true, overview: true)
    }

    func testArtworkDeliveryKeepsExcludedDraftAndPhotoFallbackTruthful() {
        for (rideID, name, hasPhoto) in [(2679, "Frozen Ever After", false),
                                       (10914, "Remy's Ratatouille Adventure", true)] {
            let app = rootFixture(["--reference-ui-park=5", "--reference-ui-ride=\(rideID)", "--ui-dark"])
            let action = app.buttons["ride-row-action-\(rideID)"]
            reveal(action, in: app)
            XCTAssertTrue(action.isHittable)
            XCTAssertTrue(action.label.contains(name))
            XCTAssertTrue(action.label.contains("45 minute wait"))
            screenshot("Artwork delivery excluded \(rideID) list", app: app)
            action.tap()
            XCTAssertFalse(app.descendants(matching: .any)["ride-illustration-5-\(rideID)"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["ride-illustration-credit"].exists)
            if hasPhoto {
                let photoCredit = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Photo: Jeremy Thompson'")).firstMatch
                reveal(photoCredit, in: app)
                XCTAssertTrue(photoCredit.isHittable)
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'CC BY 2.0'")).firstMatch.exists)
            } else {
                let fallback = app.staticTexts["A verified ride photo isn’t available yet."]
                reveal(fallback, in: app)
                XCTAssertTrue(fallback.isHittable)
            }
            screenshot("Artwork delivery excluded \(rideID) detail fallback", app: app)
            let wait = app.staticTexts["45 min wait"]
            // A full-screen flick can jump across this short status card on
            // SE, oscillating between the photograph and the history chart.
            // Use the measured missing edge and require the entire label.
            centerFullyVisible(wait, in: app)
            XCTAssertTrue(wait.isHittable)
            print("ARTWORK_FALLBACK_WAIT_VERIFIED ride=\(rideID) text=\(wait.label) frame=\(wait.frame)")
            app.terminate()
        }
    }

    func testGeneratedRideIllustrationLoadsWithCreditsAndPreservesWaits() throws {
#if PIVOT_COLD_SEARCH_CONTROL
        // This branch is compiled only for the non-qualifying diagnostic scope.
        // It must be the first text interaction on a fresh simulator; the
        // normal artwork/credit/wait journey below is untouched in every gate.
        let app = XCUIApplication()
        app.launchArguments = ["--apple-ui-test", "--apple-ui-fixtures", "--ui-light", "--ui-dark", "--ride-search-cold-control"]
        app.launch()
        let search = app.textFields["Ride search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        reveal(search, in: app)
        XCTAssertTrue(search.isHittable)
        waitForSettledFrames([search])
        let searchFrame = search.frame
        assertContained(searchFrame, in: safeContentViewport(in: app),
                        "The entire Ride search field must be visible before its tap")
        let firstTapAt = ProcessInfo.processInfo.systemUptime
        let focusDeadline = firstTapAt + 5
        search.tap()
        let tapCompletedAt = ProcessInfo.processInfo.systemUptime
        // Tap the visible keyboard key in this diagnostic control. The
        // field-targeted typeText action in run 313 re-queried the field and
        // coincided with a second keyboard presentation after editing began.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: max(0, focusDeadline - ProcessInfo.processInfo.systemUptime)))
        let gKey = keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", "g")).firstMatch
        XCTAssertTrue(gKey.exists, "The visible keyboard must expose its G key")
        let needsShift = gKey.label == "g"
        if needsShift {
            let shiftKey = keyboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label ==[c] %@", "shift")).firstMatch
            XCTAssertTrue(shiftKey.exists, "The visible keyboard must expose Shift for uppercase G")
            shiftKey.tap()
        }
        gKey.tap()
        let inputCompletedAt = ProcessInfo.processInfo.systemUptime
        let typedPrefix = search.value as? String
        let readbackCompletedAt = ProcessInfo.processInfo.systemUptime
        print("RIDE_SEARCH_CONTROL_ACTION firstTapUptimeMs=\(Int(firstTapAt * 1_000)) tapCompletedUptimeMs=\(Int(tapCompletedAt * 1_000)) inputCompletedUptimeMs=\(Int(inputCompletedAt * 1_000)) readbackCompletedUptimeMs=\(Int(readbackCompletedAt * 1_000)) visibleKey=true shiftUsed=\(needsShift) exactPrefixReceived=\(typedPrefix == "G")")
        if typedPrefix != "G" || inputCompletedAt > focusDeadline {
            print("RIDE_SEARCH_CONTROL_INPUT_FAILURE tapMs=\(Int((tapCompletedAt - firstTapAt) * 1_000)) inputMs=\(Int((inputCompletedAt - tapCompletedAt) * 1_000)) actionMs=\(Int((inputCompletedAt - firstTapAt) * 1_000)) exactPrefixReceived=\(typedPrefix == "G") preparedFrame=\(searchFrame) keyboard=\(app.keyboards.firstMatch.exists) searchHittable=\(search.isHittable)")
            screenshot("Cold Ride search control missed five seconds", app: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Cold Ride search control failure state"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(typedPrefix, "G", "The exact Ride search field must receive the keyboard input")
        XCTAssertLessThanOrEqual(inputCompletedAt, focusDeadline, "Ride search must accept input within five seconds of the first tap")
        search.typeText("uardians")
        XCTAssertEqual(search.value as? String, "Guardians")
        search.typeText("\n")
#else
        let app = rootFixture(["--reference-ui-park=5", "--ui-dark"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app)
        XCTAssertTrue(search.isHittable)
        // A virtualized List can report a hittable field while its frame is
        // still moving. Finish that preparation before measuring interaction.
        waitForSettledFrames([search])
        let searchFrame = search.frame
        assertContained(searchFrame, in: safeContentViewport(in: app),
                        "The entire Ride search field must be visible before its tap")
        // Target the native TextField itself; an app-relative coordinate missed
        // focus on SE. Tap the visible keyboard key for the first character,
        // then verify that this exact field received it.
        let firstTapAt = ProcessInfo.processInfo.systemUptime
        let oldEndToEndDeadline = firstTapAt + 5
        search.tap()
        let tapCompletedAt = ProcessInfo.processInfo.systemUptime
        let keyboard = app.keyboards.firstMatch
        // XCTest may wait for idle after the tap. The fixture's native editing
        // and keyboard event timestamps are gated against firstTapAt by the
        // post-test validator, independent of this query's return time.
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let keyboardVisibleAt = ProcessInfo.processInfo.systemUptime
        let gKey = keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", "g")).firstMatch
        XCTAssertTrue(gKey.exists, "The visible keyboard must expose its G key")
        let needsShift = gKey.label == "g"
        if needsShift {
            let shiftKey = keyboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label ==[c] %@", "shift")).firstMatch
            XCTAssertTrue(shiftKey.exists, "The visible keyboard must expose Shift for uppercase G")
            shiftKey.tap()
        }
        gKey.tap()
        let inputCompletedAt = ProcessInfo.processInfo.systemUptime
        let typedPrefix = search.value as? String
        let readbackCompletedAt = ProcessInfo.processInfo.systemUptime
        print("ARTWORK_RIDE_SEARCH_ACTION firstTapUptimeMs=\(Int(firstTapAt * 1_000)) tapCompletedUptimeMs=\(Int(tapCompletedAt * 1_000)) keyboardObservedUptimeMs=\(Int(keyboardVisibleAt * 1_000)) inputCompletedUptimeMs=\(Int(inputCompletedAt * 1_000)) readbackCompletedUptimeMs=\(Int(readbackCompletedAt * 1_000)) visibleKey=true shiftUsed=\(needsShift) exactPrefixReceived=\(typedPrefix == "G") oldFiveSecondBreached=\(inputCompletedAt > oldEndToEndDeadline)")
        if typedPrefix != "G" {
            print("ARTWORK_RIDE_SEARCH_INPUT_FAILURE tapMs=\(Int((tapCompletedAt - firstTapAt) * 1_000)) inputMs=\(Int((inputCompletedAt - tapCompletedAt) * 1_000)) actionMs=\(Int((inputCompletedAt - firstTapAt) * 1_000)) readbackMs=\(Int((ProcessInfo.processInfo.systemUptime - firstTapAt) * 1_000)) typedPrefix=\(typedPrefix ?? "<absent>") preparedFrame=\(searchFrame) keyboard=\(app.keyboards.firstMatch.exists) searchHittable=\(search.isHittable)")
            screenshot("Artwork ride search did not receive exact native input", app: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Artwork ride search input failure state"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(typedPrefix, "G", "The exact Ride search field must receive the keyboard input")
        search.typeText("uardians")
        XCTAssertEqual(search.value as? String, "Guardians")
        search.typeText("\n")
        let guardians = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guardians of the Galaxy'")).firstMatch
        reveal(guardians, in: app)
        XCTAssertTrue(guardians.label.contains("45 minute wait"))
        try assertNoVisibleThumbnailBadge(app.buttons["ride-row-action-10916"], in: app)
        screenshot("Illustration Guardians ride card", app: app)
        guardians.tap()
        let artwork = app.descendants(matching: .any)["ride-illustration-5-10916"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let loaded = NSPredicate { _, _ in artwork.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
        screenshot("Illustration Guardians detail artwork", app: app)
        let credit = app.descendants(matching: .any)["ride-illustration-credit"].firstMatch
        revealArtworkDetail(credit, in: app)
        XCTAssertTrue(credit.isHittable)
        XCTAssertTrue(app.staticTexts["AI-generated illustration"].exists)
        let reference = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Reference photo: Jedi94'")).firstMatch
        revealArtworkDetail(reference, in: app)
        XCTAssertTrue(reference.isHittable)
        let wait = app.staticTexts["45 min wait"]
        revealArtworkDetail(wait, in: app)
        XCTAssertTrue(wait.isHittable)
        screenshot("Illustration credits and current wait", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Plan"].tap()
        reveal(app.buttons["native-day-favorites"], in: app)
        XCTAssertTrue(app.buttons["native-day-favorites"].isHittable)
#endif
    }

    func testGeneratedRideWithReservedPhotoRightsKeepsAccurateCredits() throws {
        let app = rootFixture(["--reference-ui-park=334", "--reference-ui-ride=14691", "--ui-dark"])
        let ride = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fyre Drill'")).firstMatch
        reveal(ride, in: app)
        XCTAssertTrue(ride.isHittable)
        XCTAssertTrue(ride.label.contains("45 minute wait"))
        try assertNoVisibleThumbnailBadge(app.buttons["ride-row-action-14691"], in: app)
        screenshot("Accepted Florida Fyre Drill illustration card", app: app)
        ride.tap()
        let artwork = app.descendants(matching: .any)["ride-illustration-334-14691"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let loaded = NSPredicate { _, _ in artwork.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
        screenshot("Accepted Florida Fyre Drill illustration detail", app: app)
        let rights = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Reference rights: Copyright Universal Studios; source rights retained'")).firstMatch
        revealArtworkDetail(rights, in: app)
        XCTAssertTrue(rights.isHittable)
        XCTAssertTrue(app.staticTexts["AI-generated illustration"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Illustration adaptation:'")).firstMatch.exists)
        screenshot("Illustration reserved reference rights", app: app)
        let wait = app.staticTexts["45 min wait"]
        revealArtworkDetail(wait, in: app)
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
            // This is a fresh launch at the top. Assert the real header is
            // visible instead of five unconditional positioning swipes per park.
            let header = app.descendants(matching: .any)["PIVOT header"]
            XCTAssertTrue(header.isHittable)
            XCTAssertTrue(app.frame.contains(header.frame))
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
        let zoomOut = app.buttons["Zoom out"]
        waitForSettledFrames([zoomOut])
        XCTAssertTrue(zoomOut.isHittable)
        assertParkBannerTouchTarget(zoomOut.frame)
        XCTAssertTrue(app.frame.contains(zoomOut.frame))
        let physicalCenter = zoomOut.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        print("MAP_RAPID_ZOOM_NATIVE_TARGET frame=\(zoomOut.frame) initialAltitude=\(initialAltitude)")
        // Keep both rapid presses and the original 4x outcome; send each real
        // touch to the measured control centre, without an intervening wait.
        physicalCenter.tap()
        physicalCenter.tap()
        // The loaded simulator took13.8s to finish this consecutive MapKit
        // animation. Require its actual settled camera, with the same scale gate.
        waitForCamera(app, { $0[2] > initialAltitude * 3 }, timeout: 20)
        XCTAssertEqual(camera(app)[2], initialAltitude * 4, accuracy: initialAltitude * 0.4,
                       "Two zoom-out presses must settle near four times the original altitude")
        guard let cluster = visibleMapCluster(in: app) else { return }
        let before = camera(app)
        cluster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Native SE evidence recorded this valid cluster-fit animation taking
        // 8.1 seconds. Keep the same zoom requirement while awaiting its finish.
        waitForCamera(app, { $0[2] < before[2] * 0.85 }, timeout: 20)
        chooseMapCategory("Food", app: app)
        app.buttons["Show whole park"].tap()
        // MapKit retains non-hittable AX clusters and member pins from earlier
        // regions. Select the visible two-place Food cluster, not their first AX match.
        guard let foodCluster = visibleMapCluster(in: app, memberCount: 2) else { return }
        foodCluster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let member = app.buttons["map-place-row-fixture-food-a"]
        let otherMember = app.buttons["map-place-row-fixture-food-b"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        XCTAssertTrue(otherMember.exists)
        let done = app.buttons["Done"]
        let listReady = NSPredicate { _, _ in member.isHittable && otherMember.isHittable && done.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: listReady, object: nil)], timeout: 10), .completed)
        waitForSettledFrames([member, otherMember, done])
        // AX existence can precede the sheet's painted frame. Keep the exact
        // native frame that visibly contains both names as the required capture.
        let captureDeadline = Date().addingTimeInterval(10)
        var paintedCapture: XCUIScreenshot?
        var paintedWords: [String] = []
        repeat {
            let capture = XCUIScreen.main.screenshot()
            guard let pixels = capture.image.cgImage else {
                XCTFail("The native member list must supply screen pixels"); return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            do { try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request]) }
            catch { XCTFail("Native member-list recognition failed: \(error)"); return }
            paintedWords = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = paintedWords.joined(separator: " ")
            if ["North counter", "South counter"].allSatisfy({ text.range(of: $0, options: .caseInsensitive) != nil }) {
                paintedCapture = capture
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < captureDeadline
        guard let paintedCapture else {
            screenshot("Unresolved native co-located member list", app: app)
            XCTFail("Both native member names must be painted: \(paintedWords)"); return
        }
        let memberCapture = XCTAttachment(screenshot: paintedCapture)
        memberCapture.name = "Co-located map places native member list"
        memberCapture.lifetime = .keepAlways
        add(memberCapture)
        member.tap()
        XCTAssertTrue(app.staticTexts["North counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dining location · hours unavailable"].exists)
        let selectedName = app.staticTexts["Selected place name"]
        let selected = NSPredicate { _, _ in
            selectedName.exists && selectedName.label == "North counter" && selectedName.isHittable
                && !member.exists && !otherMember.exists && !done.exists
                && app.buttons["Close place details"].isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: nil)], timeout: 10), .completed,
                       "One native member-row tap must dismiss the list and select the actual place card")
    }

    private func mapAttributionCredit(in safari: XCUIApplication) -> XCUIElement {
        safari.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "openstreetmap.org/copyright")).firstMatch
    }

    private func recordSafariAttributionFailure(_ phase: String, safari: XCUIApplication) {
        screenshot("Native map attribution failure · \(phase)", app: safari)
        let hierarchy = XCTAttachment(string: "Safari state: \(safari.state.rawValue)\n\(safari.debugDescription)")
        hierarchy.name = "Safari attribution hierarchy · \(phase)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func prepareSafariForMapAttribution() -> XCUIApplication {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTContext.runActivity(named: "Prepare Safari startup before the native Legal journey") { _ in
            // Full-suite SE evidence showed an unloaded Start Page and a lost
            // WebKit process; Pro Max also stalled on Safari's launch screen.
            // Initialize browser chrome without opening or priming any credits.
            safari.launch()
            let foreground = safari.wait(for: .runningForeground, timeout: 45)
            if !foreground { recordSafariAttributionFailure("startup foreground", safari: safari) }
            XCTAssertTrue(foreground, "Safari must finish starting before testing the map's Legal handoff")
            let address = safari.textFields.matching(NSPredicate(
                format: "identifier == 'TabBarItemTitle' OR identifier == 'URL' OR label == 'Address'")).firstMatch
            let chromeReady = address.waitForExistence(timeout: 15)
            if !chromeReady { recordSafariAttributionFailure("startup chrome", safari: safari) }
            XCTAssertTrue(chromeReady, "Safari's address control must be ready, beyond its launch screen")
            if mapAttributionCredit(in: safari).exists {
                // Repeated journeys must clear the document left by the prior
                // real Legal tap; do not let restored content satisfy the next.
                XCTAssertTrue(address.isHittable)
                address.tap()
                address.typeText("about:blank\n")
                let cleared = NSPredicate { _, _ in !self.mapAttributionCredit(in: safari).exists }
                let reset = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: nil)], timeout: 10) == .completed
                if !reset { recordSafariAttributionFailure("clear prior attribution document", safari: safari) }
                XCTAssertTrue(reset, "The prior journey's attribution document must close before the next Legal tap")
                print("MAP_ATTRIBUTION_BROWSER_RESET priorDocumentCleared=\(reset)")
            }
            XCTAssertFalse(mapAttributionCredit(in: safari).exists,
                           "The Legal journey must not start with an already loaded attribution document")
            // Closing it makes a fresh foreground transition part of the actual
            // Legal tap. Browser startup readiness cannot stand in for that tap.
            safari.terminate()
            XCTAssertTrue(safari.wait(for: .notRunning, timeout: 10))
        }
        return safari
    }

    func testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent() {
        // The external browser/document phases have separate bounded waits;
        // retain the suite's existing hard maximum for this complete journey.
        executionTimeAllowance = 240
        let safari = prepareSafariForMapAttribution()
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
        XCTContext.runActivity(named: "Open real Apple map-data attribution through native Legal") { _ in
            let foreground = safari.wait(for: .runningForeground, timeout: 45)
            if !foreground { recordSafariAttributionFailure("Legal foreground handoff", safari: safari) }
            XCTAssertTrue(foreground, "The native Legal tap must bring Safari to the foreground")
            let documentReady = mapAttributionCredit(in: safari).waitForExistence(timeout: 90)
            if !documentReady { recordSafariAttributionFailure("Apple attribution document", safari: safari) }
            XCTAssertTrue(documentReady, "The native Legal link must open the actual map-data attribution page")
            XCTAssertTrue(safari.links["Apple Inc."].waitForExistence(timeout: 10),
                          "The loaded document must retain the actual Apple attribution")
        }
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
        // The map behind this sheet also says Current wait. Require the actual
        // detail content before starting its artwork checks.
        let detailContent = app.scrollViews["ride-information-content"]
        XCTAssertTrue(detailContent.staticTexts["Current wait"].waitForExistence(timeout: 5))
        // The wait card can appear before the bundled image finishes decoding.
        // Require the real image state before recording this visual gate.
        let artworkID = "ride-illustration-6-138"
        let artwork = app.descendants(matching: .any)[artworkID].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let artworkTimeout: TimeInterval = 5
        let observationStarted = ProcessInfo.processInfo.systemUptime
        var artworkSamples: [String] = []
        let loaded = NSPredicate { _, _ in
            // Run276 spent most of this deadline resolving one live element
            // query, then retained a rendered image with Loaded in its later
            // hierarchy. Resolve the current identity in one native snapshot;
            // record query time separately from the image's actual state.
            let sampleStarted = ProcessInfo.processInfo.systemUptime
            let snapshot = try? app.snapshot()
            let matches = snapshot.map { self.nativeSnapshotNodes($0).filter { $0.identifier == artworkID } } ?? []
            let current = matches.count == 1 ? matches[0] : nil
            let sampledAt = ProcessInfo.processInfo.systemUptime
            let elapsed = sampledAt - observationStarted
            let value = current?.value as? String ?? "<unavailable>"
            let timing = String(format: "elapsed=%.3fs snapshot=%.3fs", elapsed, sampledAt - sampleStarted)
            let state = "available=\(snapshot != nil) matches=\(matches.count) value=\(value) type=\(String(describing: current?.elementType))"
            artworkSamples.append("\(timing) \(state) frame=\(String(describing: current?.frame))")
            // A slow snapshot returning Loaded after the original five-second
            // deadline must still fail. Later diagnostics cannot qualify it.
            return elapsed <= artworkTimeout && current != nil && value == "Loaded"
        }
        let imageReady = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: artworkTimeout) == .completed
        let artworkObservations = artworkSamples.isEmpty ? "<no native samples>" : artworkSamples.joined(separator: "\n")
        print("MAP_RIDE_DETAIL_ARTWORK_OBSERVATIONS\n\(artworkObservations)")
        if !imageReady {
            screenshot("Native ride detail artwork did not load", app: app)
            let hierarchy = XCTAttachment(string: "Original five-second result: failed\n\(artworkObservations)\n\nLater diagnostic hierarchy (not a passing observation):\n\(app.debugDescription)")
            hierarchy.name = "Native ride detail artwork loading failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(imageReady, "The bundled Space Mountain illustration must load after returning from Safari")
        guard imageReady else { return }
        print("MAP_RIDE_DETAIL_ARTWORK_VERIFIED key=6-138 state=Loaded")
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
            return Date().timeIntervalSince(stableSince) >= 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stablePin, object: nil)], timeout: 5), .completed,
                       "The native pin must settle after keyboard/card layout changes before the physical tap")
        // MapKit can report a visible, settled annotation as not hittable in
        // its virtual AX tree. Exercise the actual pin at its measured center;
        // the selected-ride assertions below must prove that the tap worked.
        let pinFrame = fixturePin.frame
        let pinCenter = CGPoint(x: pinFrame.midX, y: pinFrame.midY)
        XCTAssertFalse(pinFrame.isEmpty)
        XCTAssertTrue(windowFrame.contains(pinCenter))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: pinCenter.x - windowFrame.minX, dy: pinCenter.y - windowFrame.minY)).tap()
        XCTAssertTrue(app.staticTexts["Selected ride wait"].waitForExistence(timeout: 3), mapEvents(app))
    }

    private func selectRootMapRide(_ name: String, app: XCUIApplication) {
        let search = app.textFields["Search park places"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let reachable = NSPredicate { _, _ in search.exists && search.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reachable, object: nil)], timeout: 10), .completed,
                       "The active park's map search must be reachable before typing")
        search.tap(); search.typeText(name + "\n")
        app.buttons["Browse map places"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map-place-row-' AND label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.staticTexts["Selected ride wait"].waitForExistence(timeout: 10))
    }

    func testMapRefreshKeepsUnchangedProviderWaitOnActualMap() {
        let app = rootFixture(["--reference-ui-park=5", "--ride-search-unchanged-provider"])
        app.tabBars.buttons["Map"].tap()
        selectRootMapRide("Guardians", app: app)
        screenshot("Map unchanged provider wait baseline", app: app)
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "45 min")
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["Selected ride wait"].label, "45 min")
    }

    private func waitForMapWait(_ text: String, app: XCUIApplication, timeout: TimeInterval = 10) {
        let label = app.staticTexts["Selected ride wait"]
        let predicate = NSPredicate { _, _ in label.exists && label.label == text }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout), .completed,
            "Map wait expected \(text); got \(label.exists ? label.label : "missing")")
    }

    private func refreshMapWait(_ text: String, app: XCUIApplication) {
        let refresh = app.buttons["Refresh map waits"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10)); XCTAssertTrue(refresh.isEnabled)
        refresh.tap()
        waitForMapWait(text, app: app)
    }

    /// Tap one real park result only after its entire row clears the native
    /// search and keyboard overlays. No internal selection or tap retry.
    private func tapVisibleParkPickerRow(_ name: String, in app: XCUIApplication,
                                         parkSearch: XCUIElement, captureTitle: String,
                                         timeout: TimeInterval = 5,
                                         file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let pickerList = app.collectionViews.containing(.staticText, identifier: name).firstMatch
        guard pickerList.waitForExistence(timeout: timeout) else {
            XCTFail("The native park List must contain the exact \(name) title", file: file, line: line)
            return false
        }
        let choices = pickerList.buttons.containing(.staticText, identifier: name)
        let choice = choices.firstMatch
        guard choice.waitForExistence(timeout: timeout), choices.count == 1 else {
            XCTFail("The native park List must expose one exact \(name) result", file: file, line: line)
            return false
        }
        // A List AX frame can cover the full sheet behind the keyboard/search.
        // Both the target and native drag must stay in the visible list region.
        func pickerViewport() -> CGRect {
            let window = app.frame
            var viewport = pickerList.frame.intersection(safeContentViewport(in: app))
            for keyboard in app.keyboards.allElementsBoundByIndex {
                let frame = keyboard.frame
                if !frame.isEmpty, frame.intersects(viewport) {
                    viewport.size.height = max(0, min(viewport.maxY, frame.minY - 8) - viewport.minY)
                }
            }
            if parkSearch.exists {
                let frame = parkSearch.frame
                if frame.intersects(viewport) {
                    if frame.midY > viewport.midY {
                        // Clear the outer search capsule and its toolbar inset too.
                        viewport.size.height = max(0, min(viewport.maxY, frame.minY - 16) - viewport.minY)
                    } else {
                        let bottom = viewport.maxY
                        viewport.origin.y = max(viewport.minY, frame.maxY + 8)
                        viewport.size.height = max(0, bottom - viewport.minY)
                    }
                }
            }
            return viewport.intersection(window)
        }
        let window = app.frame
        for attempt in 0..<6 {
            let viewport = pickerViewport()
            let row = choice.frame
            print("PARK_PICKER_VISIBLE_VIEWPORT park=\(name) attempt=\(attempt) viewport=\(viewport) row=\(row)")
            guard viewport.width > 0, viewport.height > 44 else {
                XCTFail("The park picker must expose a visible list region clear of search and keyboard", file: file, line: line)
                return false
            }
            if viewport.insetBy(dx: -1, dy: -1).contains(row) && choice.isHittable { break }
            let offset = row.minY < viewport.minY
                ? row.minY - viewport.minY - 12 : row.maxY - viewport.maxY + 12
            let movement = min(viewport.height * 0.75, max(30, abs(offset))) * (offset < 0 ? -1 : 1)
            let origin = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: verticalPanX(in: viewport) - window.minX,
                dy: viewport.midY + movement / 2 - window.minY))
            let destination = origin.withOffset(CGVector(dx: 0, dy: -movement))
            origin.press(forDuration: 0.05, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        waitForSettledFrames([pickerList, choice], file: file, line: line)
        assertContained(choice.frame, in: pickerViewport(),
                        "The complete park row must be clear of the foreground search and keyboard", file: file, line: line)
        let hittable = choice.isHittable
        XCTAssertTrue(hittable, file: file, line: line)
        guard hittable else { return false }
        screenshot(captureTitle, app: app)
        let finalFrame = choice.frame
        guard !finalFrame.isEmpty, pickerViewport().insetBy(dx: -1, dy: -1).contains(finalFrame), choice.isHittable else {
            XCTFail("The complete \(name) row must remain visible and hittable at the single tap", file: file, line: line)
            return false
        }
        choice.tap()
        return true
    }

    func testMapNetworkRefreshRepeatFullScreenFailureRecoveryAndNavigation() {
        let app = artworkFixtureApp()
        app.launchArguments = ["--apple-ui-test", "--map-refresh-network-test", "--map-refresh-manual-test", "-pivot.selectedPark", "6"]
        app.launch()
        app.tabBars.buttons["Map"].tap()
        selectRootMapRide("Space Mountain", app: app)
        waitForMapWait("35 min", app: app)
        refreshMapWait("5 min", app: app)
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        refreshMapWait("Wait unavailable", app: app) // Real HTTP 503 handling.
        XCTAssertTrue(app.staticTexts["Map feed status"].label.contains("Refresh failed"))
        screenshot("Map HTTP failure retains location and withholds wait", app: app)
        refreshMapWait("0 min · walk-on", app: app)
        XCTAssertFalse(app.staticTexts["Map feed status"].label.contains("failed"))
        refreshMapWait("Wait unavailable", app: app) // HTTP 200 with an expired provider fetch.
        XCTAssertTrue(app.staticTexts["Map feed status"].label.contains("too old"))
        refreshMapWait("15 min", app: app)
        refreshMapWait("Wait unavailable", app: app) // Malformed HTTP 200 JSON.
        XCTAssertTrue(app.staticTexts["Map feed status"].label.contains("Refresh failed"))
        refreshMapWait("15 min", app: app)
        screenshot("Map current wait recovers in full screen", app: app)
        app.buttons["Close full screen map"].tap()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Waits"].tap()
        app.tabBars.buttons["Map"].tap()
        waitForMapWait("15 min", app: app)
        XCTAssertEqual(app.textFields["Search park places"].value as? String, "Space Mountain")
        refreshMapWait("15 min", app: app)
        app.buttons["Change park. Current park: Magic Kingdom Park"].tap()
        let parkSearch = app.searchFields.firstMatch
        XCTAssertTrue(parkSearch.waitForExistence(timeout: 5)); parkSearch.tap(); parkSearch.typeText("EPCOT")
        guard tapVisibleParkPickerRow("EPCOT", in: app, parkSearch: parkSearch,
            captureTitle: "Map EPCOT row clear of search and keyboard", timeout: 10) else { return }
        let selectedPark = app.buttons["Change park. Current park: EPCOT"]
        let switched = NSPredicate { _, _ in
            !parkSearch.exists && selectedPark.exists && selectedPark.isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: switched, object: nil)], timeout: 10), .completed,
                       "The picker must dismiss and the Map must select EPCOT before a new ride search")
        screenshot("Map park switch selects EPCOT before ride search", app: app)
        selectRootMapRide("Guardians", app: app)
        refreshMapWait("15 min", app: app)
        XCTAssertTrue(app.buttons["Change park. Current park: EPCOT"].exists)
    }

    func testMapNetworkAutoRefreshContinuesInFullScreenAndAfterForegroundReturn() {
        let app = artworkFixtureApp()
        app.launchArguments = ["--apple-ui-test", "--map-refresh-network-test", "-pivot.selectedPark", "6"]
        app.launch()
        app.tabBars.buttons["Map"].tap()
        selectRootMapRide("Space Mountain", app: app)
        let embedded = app.staticTexts["Selected ride wait"]
        let initialLive = NSPredicate { _, _ in embedded.exists && embedded.label.hasSuffix(" min") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: initialLive, object: nil)], timeout: 15), .completed,
            "Foreground polling must survive asynchronous bootstrap before entering full screen; source: \(app.staticTexts["Map feed status"].label)")
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        let label = app.staticTexts["Selected ride wait"]
        let initial = label.label
        let updated = NSPredicate { _, _ in label.exists && label.label != initial && label.label.hasSuffix(" min") }
        let updateResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: nil)], timeout: 15)
        screenshot("Map automatic HTTP refresh in full screen", app: app)
        XCTAssertEqual(updateResult, .completed,
            "Full-screen polling: initial=\(initial), current=\(label.label), source=\(app.staticTexts["Map feed status"].label)")
        let beforeBackground = label.label
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 10))
        let resumed = NSPredicate { _, _ in label.exists && label.label != beforeBackground && label.label.hasSuffix(" min") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: nil)], timeout: 15), .completed)
        app.buttons["Close full screen map"].tap()
        app.tabBars.buttons["Plan"].tap()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertTrue(label.label.hasSuffix(" min"))
    }

    func testLiveMapRefreshReportsRealProviderStatus() {
        let app = artworkFixtureApp()
        // Keep scheduled polling from racing this manual button check and tap.
        // The separate automatic HTTP test retains the production polling loop;
        // omitting --map-refresh-network-test keeps this request on the real API.
        app.launchArguments = ["--map-refresh-manual-test", "--map-refresh-diagnostics", "-pivot.selectedPark", "6"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Map"].tap()
        selectRootMapRide("Prince Charming", app: app)
        let refresh = app.buttons["Refresh map waits"]
        let ready = NSPredicate { _, _ in refresh.exists && refresh.isEnabled }
        let readyBeforeTap = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 30)
        if readyBeforeTap != .completed { recordMapRefreshRequestDiagnostic("before-tap-wait-failed", app: app) }
        XCTAssertEqual(readyBeforeTap, .completed)
        refresh.tap()
        let readyAfterTap = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 30)
        if readyAfterTap != .completed { recordMapRefreshRequestDiagnostic("after-tap-wait-failed", app: app) }
        XCTAssertEqual(readyAfterTap, .completed)
        let status = app.staticTexts["Map feed status"]
        let observation = "LIVE MAP OBSERVATION: \(status.label); selected ride: \(app.staticTexts["Selected ride wait"].label)"
        print(observation)
        let evidence = XCTAttachment(string: observation); evidence.lifetime = .keepAlways; add(evidence)
        screenshot("Live provider map refresh observation", app: app)
        recordMapRefreshRequestDiagnostic("after-manual-refresh", app: app)
        XCTAssertTrue(status.label.hasPrefix("Live"), observation)
        // Real service failures remain failures; no synthetic fallback is used.
        app.buttons["Full screen map"].tap()
        XCTAssertTrue(app.buttons["Close full screen map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Map feed status"].label.hasPrefix("Live"))
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
        let app = artworkFixtureApp()
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
        let app = artworkFixtureApp()
        app.launchArguments = ["--wait-forecast-ui-test", "--forecast-saved"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Crowds & waits"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lowest estimated wait"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "History only")).firstMatch.exists)
    }

    func testPlanOwnsCrowdAndPredictedWaitControls() {
        let app = artworkFixtureApp()
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
        let app = artworkFixtureApp()
        app.launchArguments = ["--hhn-ui-test", "--reset-hhn-ui-test"] + extraArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Halloween Horror Nights"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
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
        XCTFail("Could not reveal the requested element", file: file, line: line)
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
        let app = artworkFixtureApp()
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
        let app = artworkFixtureApp()
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
        reveal(app.staticTexts["PIVOT 1.18.6"], in: app)
        XCTAssertTrue(app.staticTexts["PIVOT 1.18.6"].exists)
        let build = app.staticTexts["PIVOT build number"]
        reveal(build, in: app)
        XCTAssertNotNil(build.label.range(of: #"^Build \d+(?:\.\d+){0,2}$"#, options: .regularExpression))
        screenshot("Installed PIVOT version and build", app: app)
        // The About rows are below the accent choices. On compact phones the
        // offscreen Mint row is absent from XCTest's tree, so scroll toward it.
        let mint = app.buttons["accent-mint"]
        var mintVisible = false
        for _ in 0..<5 {
            if mint.exists {
                let frame = mint.frame
                let viewport = app.frame.insetBy(dx: 1, dy: 1)
                let center = CGPoint(x: frame.midX, y: frame.midY)
                if !frame.isEmpty && viewport.contains(center) && mint.isHittable {
                    mintVisible = true
                    break
                }
            }
            app.swipeDown()
        }
        guard mintVisible else {
            XCTFail("Could not reveal Mint accent above the About section")
            return
        }
        mint.tap()
    }

    private func openDownloadedSpaceMountain(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["ride-row-action-138"]
        reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("Space Mountain"))
        row.tap()
        XCTAssertTrue(app.navigationBars["Ride information"].waitForExistence(timeout: 5))
        return app.descendants(matching: .any)["ride-illustration-6-138"].firstMatch
    }

    private func assertDownloadedImageLoaded(_ image: XCUIElement) {
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let loaded = NSPredicate { _, _ in image.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
        XCTAssertTrue(image.label.hasPrefix("AI illustration:"))
    }

    private func openArtworkDownloadSettings(_ app: XCUIApplication) {
        app.tabBars.buttons["More"].tap()
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings'")).firstMatch
        reveal(settings, in: app)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let link = app.buttons["artwork-download-settings"]
        reveal(link, in: app)
        XCTAssertTrue(link.isHittable)
        link.tap()
        XCTAssertTrue(app.navigationBars["Artwork downloads"].waitForExistence(timeout: 5))
        let count = app.staticTexts["artwork-download-count"]
        let contentReady = count.waitForExistence(timeout: 5)
        if !contentReady {
            screenshot("Artwork downloads content missing after navigation", app: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Artwork downloads navigation failure state"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(contentReady, "The artwork download screen must show its saved-original count")
    }

    private func findArtworkDownloadAction(in app: XCUIApplication) -> XCUIElement {
        let action = app.buttons["download-all-artwork"]
        // A fresh largest-text Form only exposes its visible rows to XCTest.
        // Scroll the foreground form before asking for the download row.
        for _ in 0..<10 {
            if action.exists { break }
            app.swipeUp()
        }
        return action
    }

    /// Leave the download control high enough that the progress row and pause
    /// message can appear below it at largest type. Do this before starting a
    /// slow batch, so status observation needs no full-height flick afterward.
    private func positionArtworkDownloadActionForPause(_ action: XCUIElement, in app: XCUIApplication) {
        let viewport = safeContentViewport(in: app)
        let appFrame = app.frame
        let desiredTop = viewport.minY + 24
        for _ in 0..<4 {
            guard action.exists else { XCTFail("The download action disappeared before the batch started"); return }
            let frame = action.frame
            if frame.minY >= viewport.minY + 4,
               frame.minY <= viewport.minY + 72,
               action.isHittable { return }
            let displacement = frame.minY - desiredTop
            let movement = min(viewport.height * 0.55, max(20, abs(displacement)))
                * (displacement >= 0 ? 1 : -1)
            let x = verticalPanX(in: viewport)
            let startY = viewport.midY + movement / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: x - appFrame.minX, dy: startY - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -movement)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let finalFrame = action.frame
        XCTAssertTrue(action.isHittable && finalFrame.minY >= viewport.minY + 4
                      && finalFrame.minY <= viewport.minY + 72,
                      "The download action must sit near the top of the visible Form before the timed pause. Frame \(finalFrame), viewport \(viewport)")
    }

    func testArtworkDownloadsFreshOfflineUpgradeAndPersistentReuse() {
        let directory = UUID().uuidString
        let app = rootFixture(artworkMode: "offline", artworkDirectory: directory)
        let missing = openDownloadedSpaceMountain(app)
        let retry = app.buttons["retry-artwork-6-138"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(missing.exists)
        XCTAssertFalse(app.descendants(matching: .any)["ride-illustration-credit"].exists)
        XCTAssertTrue(app.staticTexts["The illustration is unavailable. Connect to the internet and retry."].waitForExistence(timeout: 5))
        screenshot("Downloaded artwork direct upgrade offline fallback", app: app)
        app.terminate()
        app.launchEnvironment["PIVOT_ARTWORK_FIXTURE"] = "originals"
        app.launch()
        let downloaded = openDownloadedSpaceMountain(app)
        assertDownloadedImageLoaded(downloaded)
        XCTAssertTrue(app.descendants(matching: .any)["ride-illustration-credit"].exists)
        screenshot("Downloaded artwork verified original and attribution", app: app)
        app.terminate()
        app.launchEnvironment["PIVOT_ARTWORK_FIXTURE"] = "offline"
        app.launch()
        assertDownloadedImageLoaded(openDownloadedSpaceMountain(app))
        XCTAssertTrue(app.descendants(matching: .any)["ride-illustration-credit"].exists)
        screenshot("Downloaded artwork survives offline relaunch", app: app)
    }

    func testArtworkDownloadsCorruptOriginalRequiresExplicitRetry() {
        let app = rootFixture(artworkMode: "corrupt-once")
        let image = openDownloadedSpaceMountain(app)
        let message = app.staticTexts["The illustration couldn’t be verified. Retry to download the original."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertFalse(image.exists)
        XCTAssertFalse(app.descendants(matching: .any)["ride-illustration-credit"].exists)
        let retry = app.buttons["retry-artwork-6-138"]
        revealArtworkDetail(retry, in: app)
        assertParkBannerTouchTarget(retry.frame)
        screenshot("Downloaded artwork corrupt bytes rejected", app: app)
        retry.tap()
        assertDownloadedImageLoaded(app.descendants(matching: .any)["ride-illustration-6-138"].firstMatch)
        XCTAssertTrue(app.descendants(matching: .any)["ride-illustration-credit"].exists)
        screenshot("Downloaded artwork explicit retry preserves identity", app: app)
    }

    func testArtworkDownloadsLowStorageKeepsLargestTextAndLiveDetailsUsable() {
        let app = rootFixture(["--ui-largest-type"], artworkMode: "low-storage")
        let image = openDownloadedSpaceMountain(app)
        let message = app.staticTexts["More free space is needed. Saved artwork stays available."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertFalse(image.exists)
        let retry = app.buttons["retry-artwork-6-138"]
        revealArtworkDetail(retry, in: app)
        assertParkBannerTouchTarget(retry.frame)
        screenshot("Downloaded artwork low storage largest text retry", app: app)
        let wait = app.scrollViews["ride-information-content"].staticTexts["45 min wait"].firstMatch
        revealArtworkDetail(wait, in: app)
        XCTAssertTrue(wait.isHittable)
        screenshot("Downloaded artwork low storage retains live wait details", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Map"].isHittable)
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["Full screen map"].waitForExistence(timeout: 5))
        screenshot("Downloaded artwork storage error leaves Map usable", app: app)
    }

    func testArtworkDownloadsPauseResumeAndSettingsOfflineInventory() {
        let directory = UUID().uuidString
        let app = rootFixture(["--ui-largest-type"], artworkMode: "slow", artworkDirectory: directory, smallArtworkBatch: true)
        openArtworkDownloadSettings(app)
        let download = app.buttons["download-all-artwork"]
        reveal(download, in: app)
        positionArtworkDownloadActionForPause(download, in: app)
        print("ARTWORK_PAUSE_PREP downloadFrame=\(download.frame) viewport=\(safeContentViewport(in: app))")
        download.tap()
        let pause = app.buttons["pause-artwork-downloads"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(pause.isHittable, "The pause action must stay visible after the batch starts")
        print("ARTWORK_PAUSE_PREP pauseFrame=\(pause.frame)")
        let pauseStartedAt = ProcessInfo.processInfo.systemUptime
        pause.tap()
        let pauseDeadline = pauseStartedAt + 5
        let message = app.staticTexts["artwork-download-message"]
        let paused = NSPredicate { _, _ in
            message.exists && message.label == "Download paused. Saved artwork stays available."
        }
        let remaining = pauseDeadline - ProcessInfo.processInfo.systemUptime
        let pauseResult: XCTWaiter.Result = remaining > 0
            ? XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: paused, object: nil)], timeout: remaining)
            : .timedOut
        if pauseResult != .completed {
            let laterMessage = message.exists ? message.label : "<absent>"
            print("ARTWORK_PAUSE_STATUS_FAILURE originalFiveSecondResult=\(pauseResult.rawValue) elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - pauseStartedAt) * 1_000)) laterMessage=\(laterMessage) downloadAction=\(app.buttons["download-all-artwork"].exists) pauseAction=\(pause.exists)")
            screenshot("Artwork pause status missing at original deadline", app: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Artwork pause status failure state"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(pauseResult, .completed)
        let downloadsScreen = app.navigationBars["Artwork downloads"]
        XCTAssertTrue(downloadsScreen.exists, "The artwork download sheet must stay open after revealing pause status")
        screenshot("Downloaded artwork batch paused without removing originals", app: app)
        app.terminate()
        app.launchEnvironment["PIVOT_ARTWORK_FIXTURE"] = "originals"
        app.launch()
        openArtworkDownloadSettings(app)
        let resume = findArtworkDownloadAction(in: app)
        let resumeReady = resume.waitForExistence(timeout: 5)
        if !resumeReady {
            let inventory = app.staticTexts["artwork-download-count"]
            let inventoryLabel = inventory.exists ? inventory.label : "missing"
            print("ARTWORK_RESUME_UI_STATE download=false pause=\(app.buttons["pause-artwork-downloads"].exists) count=\(inventoryLabel)")
            screenshot("Downloaded artwork resume control missing", app: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Artwork downloads resume failure state"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(resumeReady, "The paused batch must offer a resume action after relaunch")
        reveal(resume, in: app)
        XCTAssertTrue(resume.isHittable)
        resume.tap()
        // The count row is above the action in the largest-text Form.
        let count = app.staticTexts["artwork-download-count"]
        let resumedDownloadsScreen = app.navigationBars["Artwork downloads"]
        let viewport = app.frame.insetBy(dx: 1, dy: 1)
        func countIsVisible() -> Bool {
            guard count.exists else { return false }
            let frame = count.frame
            return !frame.isEmpty && viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        for _ in 0..<5 {
            XCTAssertTrue(resumedDownloadsScreen.exists, "The artwork download sheet must remain open while scrolling to the saved count")
            if countIsVisible() { break }
            app.swipeDown()
        }
        XCTAssertTrue(resumedDownloadsScreen.exists, "The artwork download sheet must remain open for the saved-count check")
        XCTAssertTrue(countIsVisible(), "The saved-count row must be visible after scrolling")
        let complete = NSPredicate { _, _ in count.exists && count.label == "2 of 2 illustrations saved" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: nil)], timeout: 15), .completed)
        screenshot("Downloaded artwork batch resumes original files", app: app)
        app.terminate()
        app.launchEnvironment["PIVOT_ARTWORK_FIXTURE"] = "offline"
        app.launch()
        openArtworkDownloadSettings(app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: nil)], timeout: 5), .completed)
        let completedAction = findArtworkDownloadAction(in: app)
        XCTAssertTrue(completedAction.exists)
        XCTAssertFalse(completedAction.isEnabled)
        screenshot("Downloaded artwork offline inventory survives update style relaunch", app: app)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTopBrandAndParkSelectorAlignAcrossRepeatedTabNavigation() {
        checkTopBrandAndParkSelector(extra: ["--ui-dark"], repeated: true)
    }

    func testTopBrandAndParkSelectorFitAtLargestTextSize() {
        checkTopBrandAndParkSelector(extra: ["--ui-largest-type"], repeated: false)
    }

    private func checkTopBrandAndParkSelector(extra: [String], repeated: Bool,
                                               file: StaticString = #filePath, line: UInt = #line) {
        let name = "Hurricane Harbor Los Angeles"
        let app = rootFixture(["--reference-ui-park=41"] + extra)
        defer { app.terminate() }
        let tabs = app.tabBars.firstMatch
        let route = repeated
            ? ["Waits", "Plan", "Shows", "Map", "More", "Map", "Shows", "Plan", "Waits"]
            : ["Waits", "Plan", "Shows", "Map", "More"]
        var firstHeaderY: CGFloat?
        var firstParkY: CGFloat?
        for tab in route {
            if tab != "Waits" || firstHeaderY != nil { tabs.buttons[tab].tap() }
            let headerQuery = app.descendants(matching: .any).matching(identifier: "PIVOT header")
            let header = headerQuery.allElementsBoundByIndex.first { $0.isHittable }
            let refreshQuery = app.buttons.matching(NSPredicate(format: "label == %@", "Refresh ride data now"))
            let refresh = refreshQuery.allElementsBoundByIndex.first { $0.exists && app.frame.intersects($0.frame) }
            let parkQuery = app.buttons.matching(NSPredicate(format: "label == %@", "Change park. Current park: \(name)"))
            let park = parkQuery.allElementsBoundByIndex.first { $0.isHittable }
            guard let header, let refresh, let park else {
                screenshot("Missing top controls on \(tab)", app: app)
                XCTFail("\(tab) must expose the PIVOT logo, refresh and selected park", file: file, line: line)
                return
            }
            let viewport = safeContentViewport(in: app)
            assertContained(header.frame, in: viewport, "\(tab) logo must not clip", file: file, line: line)
            assertContained(refresh.frame, in: viewport, "\(tab) refresh circle must not clip", file: file, line: line)
            assertContained(park.frame, in: viewport, "\(tab) park selector must not clip", file: file, line: line)
            assertParkBannerTouchTarget(refresh.frame, file: file, line: line)
            assertParkBannerTouchTarget(park.frame, file: file, line: line)
            XCTAssertLessThan(header.frame.maxX, refresh.frame.minX,
                              "The logo and refresh circle must not overlap on \(tab)", file: file, line: line)
            XCTAssertLessThan(header.frame.maxY, park.frame.minY,
                              "The park selector must remain below the logo on \(tab)", file: file, line: line)
            if let firstHeaderY {
                XCTAssertEqual(header.frame.minY, firstHeaderY, accuracy: 8,
                               "Logo position must stay aligned across tabs", file: file, line: line)
            } else { firstHeaderY = header.frame.minY }
            if let firstParkY {
                XCTAssertEqual(park.frame.minY, firstParkY, accuracy: 18,
                               "Park selector must start in the same header band", file: file, line: line)
            } else { firstParkY = park.frame.minY }
            screenshot("Top controls \(tab) \(repeated ? "standard" : "largest")", app: app)
            if tab == "Map" && !repeated {
                let search = app.textFields["Search park places"]
                let filter = app.buttons["Filter map places"]
                let fullScreen = app.buttons["Full screen map"]
                let zoom = app.buttons["Zoom in"]
                let browse = app.buttons["Browse map places"]
                for control in [search, filter, fullScreen, zoom, browse] {
                    XCTAssertTrue(control.waitForExistence(timeout: 5),
                                  "The largest-text Map must expose \(control.identifier)", file: file, line: line)
                    XCTAssertTrue(control.isHittable,
                                  "The largest-text Map control \(control.identifier) must remain usable", file: file, line: line)
                    assertContained(control.frame, in: viewport,
                                    "The largest-text Map control \(control.identifier) must stay visible", file: file, line: line)
                }
                XCTAssertLessThan(park.frame.height, viewport.height * 0.3,
                                  "The park selector must leave room for Map controls", file: file, line: line)
                XCTAssertGreaterThan(browse.frame.minY - search.frame.maxY, 88,
                                     "The map must retain a usable viewport between search and Browse", file: file, line: line)
                XCTAssertFalse(filter.frame.intersects(fullScreen.frame),
                               "Map toolbar actions must not overlap", file: file, line: line)
                XCTAssertFalse(zoom.frame.intersects(search.frame) || zoom.frame.intersects(browse.frame),
                               "Map zoom must remain clear of the search and Browse controls", file: file, line: line)
            }
        }
        if repeated {
            tabs.buttons["Map"].tap()
            let park = app.buttons["Change park. Current park: \(name)"]
            XCTAssertTrue(park.isHittable, file: file, line: line)
            park.tap()
            XCTAssertTrue(app.navigationBars["Choose a park"].waitForExistence(timeout: 5), file: file, line: line)
            app.buttons["Done"].tap()
            XCTAssertTrue(park.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(park.isHittable, file: file, line: line)
        }
    }

    func testDashboardUsesTheNativeTabBarAndDestinations() {
        let app = artworkFixtureApp()
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
        let app = artworkFixtureApp()
        app.launchArguments = ["-pivot.selectedPark", "6"]
        app.launch()
        let map = app.tabBars.firstMatch.buttons["Map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tap()
        let search = app.textFields["Search park places"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        chooseMapCategory("Food", app: app)
        XCTAssertTrue(app.buttons["Browse map places"].exists)
        focusMapSearch(app)
        screenshot("Map search keyboard after category selection", app: app)
        search.typeText("zz-no-such-place")
        XCTAssertEqual(search.value as? String, "zz-no-such-place")
        XCTAssertTrue(app.staticTexts["No matching places."].waitForExistence(timeout: 3))
        screenshot("Map search empty state", app: app)
        app.buttons["Clear place search"].tap()
        screenshot("Map food category", app: app)
        app.buttons["Browse map places"].tap()
        XCTAssertTrue(app.staticTexts["Map coverage & sources"].exists || app.buttons["Done"].exists)
        app.buttons["Done"].tap()

        chooseMapCategory("Rides", app: app)
        focusMapSearch(app)
        search.typeText("Space Mountain")
        let submit = app.keyboards.buttons["Search"]
        XCTAssertTrue(submit.isHittable)
        submit.tap()
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

    func testMapCategoryChangesAndInterruptedSearchRemainUsable() {
        let app = artworkFixtureApp()
        app.launchArguments = ["-pivot.selectedPark", "6"]
        app.launch()
        let map = app.tabBars.firstMatch.buttons["Map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tap()
        let search = app.textFields["Search park places"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        chooseMapCategory("Food", app: app)
        // Alternate real categories so every repeated action has an observable
        // value change; every selection must commit and dismiss the chooser.
        // Then cancel another menu and interrupt an active search. Each return
        // must leave the real field usable by one tap.
        chooseMapCategory("Rides", app: app)
        chooseMapCategory("Food", app: app)
        app.buttons["Filter map places"].tap()
        XCTAssertTrue(app.navigationBars["Place categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Rides"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Food"].firstMatch.value as? String, "Selected")
        screenshot("Map category chooser with current Food selection", app: app)
        app.buttons["Cancel map categories"].tap()
        waitForMapCategory("Food", app: app)
        screenshot("Map category chooser cancelled without changing Food", app: app)
        focusMapSearch(app)
        search.typeText("zz-no-such-place")
        XCTAssertTrue(app.staticTexts["No matching places."].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "zz-no-such-place")
        focusMapSearch(app)
        let submit = app.keyboards.buttons["Search"]
        XCTAssertTrue(submit.isHittable)
        submit.tap()
        // The interrupted-journey recording shows the keyboard gone while the
        // generic predicate waiter times out. Use XCTest's native disappearance
        // API for the same actual element and unchanged five-second deadline.
        let submitted: Bool
        if #available(iOS 18.0, *) {
            submitted = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        } else {
            let gone = NSPredicate { _, _ in !app.keyboards.firstMatch.exists }
            submitted = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 5) == .completed
        }
        if !submitted {
            screenshot("Interrupted map search failed native submission", app: app)
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Interrupted map native submission failure state"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertTrue(submitted, "The native Search submission must remove the keyboard within five seconds")
        print("MAP_INTERRUPTED_KEYBOARD_DISMISSED nativeNonExistence=\(submitted)")
        screenshot("Map search restored after foreground interruption", app: app)
        app.buttons["Clear place search"].tap()
        XCTAssertFalse(app.buttons["Clear place search"].exists)
    }

    func testNativeTabBarStaysFixedWhileContentScrolls() {
        let app = artworkFixtureApp()
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
        let app = artworkFixtureApp()
        app.launchArguments = ["-pivot.selectedPark", "6"]
        app.launch()

        guard app.wait(for: .runningForeground, timeout: 5),
              app.descendants(matching: .any)["PIVOT header"].waitForExistence(timeout: 10) else {
            XCTFail("The app must finish its foreground launch before selecting a park")
            return
        }
        // Establish the unselected state through the real picker. A fresh install
        // must not depend on a negative launch-default value or an earlier test.
        let initialPark = app.buttons["Change park. Current park: Magic Kingdom Park"]
        guard initialPark.waitForExistence(timeout: 5), initialPark.isHittable else {
            XCTFail("The initial Magic Kingdom park control must be ready for picker setup")
            return
        }
        waitForSettledFrames([initialPark])
        assertContained(initialPark.frame, in: safeContentViewport(in: app),
                        "The initial park control must be wholly visible before setup")
        initialPark.tap()
        let picker = app.navigationBars["Choose a park"]
        let noPark = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "No park")).firstMatch
        guard picker.waitForExistence(timeout: 5), noPark.waitForExistence(timeout: 5), noPark.isHittable else {
            XCTFail("The actual picker must offer No park for unselected-state setup")
            return
        }
        waitForSettledFrames([noPark])
        assertContained(noPark.frame, in: safeContentViewport(in: app),
                        "The No park setup row must be wholly visible before selection")
        noPark.tap()
        let setupFinished = NSPredicate { _, _ in
            !picker.exists && app.buttons["Change park. Current park: none"].exists
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: setupFinished, object: nil)], timeout: 5) == .completed else {
            XCTFail("Choosing No park must dismiss the picker and establish the unselected state")
            return
        }
        // Select the unique visible control without assuming its AX parent type.
        let choices = app.buttons.matching(NSPredicate(format: "label == %@", "Change park. Current park: none"))
        let parkButton = choices.firstMatch
        guard parkButton.waitForExistence(timeout: 5), choices.count == 1 else {
            XCTFail("The unselected Waits screen must have one exact park-selection control")
            return
        }
        waitForSettledFrames([parkButton])
        let controlFrame = parkButton.frame
        assertContained(controlFrame, in: safeContentViewport(in: app),
                        "The park-selection control must be wholly visible before the single tap")
        guard !controlFrame.isEmpty,
              safeContentViewport(in: app).insetBy(dx: -1, dy: -1).contains(controlFrame), parkButton.isHittable else {
            XCTFail("The park-selection control must be visible and hittable before its single tap")
            return
        }
        screenshot("Expanded park selector ready before single tap", app: app)
        parkButton.tap()

        let search = app.searchFields.firstMatch
        let searchAppeared = search.waitForExistence(timeout: 5)
        screenshot("Expanded park picker after single tap", app: app)
        guard searchAppeared, app.navigationBars["Choose a park"].exists, search.isHittable else {
            XCTFail("The single tap must present the native Choose a park search. App state \(app.state.rawValue); park control still exists \(parkButton.exists)")
            return
        }
        search.tap()
        search.typeText("Cedar Point")

        guard tapVisibleParkPickerRow("Cedar Point", in: app, parkSearch: search,
            captureTitle: "Expanded Cedar Point row clear of search and keyboard") else { return }
        let selectedPark = app.buttons["Change park. Current park: Cedar Point"]
        let switched = NSPredicate { _, _ in
            !search.exists && selectedPark.exists && selectedPark.isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: switched, object: nil)], timeout: 5), .completed,
                       "The picker must dismiss and the app must select Cedar Point after the single result tap")
        screenshot("Expanded park selects Cedar Point after picker dismisses", app: app)
    }

}
