import XCTest
import UIKit

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

    func testObservedWaitDotsKeepEveryValueAndOpenLowestWaitForecast() {
        let app = rootFixture(["--reference-ui-park=5", "--ride-history-ui-test", "--ride-history-supported"])
        let search = app.textFields["Ride search"]
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recent observed waits'")).firstMatch
        reveal(history, in: app); history.tap()
        let chart = app.descendants(matching: .any)["observed-wait-chart-10916"].firstMatch
        centerFullyVisible(chart, in: app)
        screenshot("Every observed wait dot labeled latest samples", app: app)
        centerHorizontally(chart.staticTexts["wait-sample-time-10916-0"].firstMatch, in: chart, app: app)
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

    private func assertObservedChartSamples(_ waits: [String], chart: XCUIElement) {
        let points = chart.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Observation '"))
        XCTAssertEqual(points.count, waits.count, "Every distinct dot must remain readable to VoiceOver")
        for (index, wait) in waits.enumerated() {
            let point = points.matching(NSPredicate(format: "label BEGINSWITH %@", "Observation \(index + 1),")).firstMatch
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
            var frames: [CGRect] = []
            for element in elements {
                guard Date() < deadline else { break }
                frames.append(element.frame)
            }
            let sampledAt = Date()
            trace.append("t=\(sampledAt.timeIntervalSince(started)): \(frames)")
            guard frames.count == elements.count else { break }
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
    private func centerFullyVisible(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let viewport = safeContentViewport(in: app)
        let appFrame = app.frame
        for _ in 0..<22 {
            var movement: CGFloat = min(420, viewport.height * 0.8)
            let frame = element.exists ? element.frame : .zero
            if !frame.isEmpty {
                guard frame.height <= viewport.height + 1, frame.width <= viewport.width + 1 else {
                    XCTFail("Target cannot fit the visible content area. Frame \(frame); viewport \(viewport)", file: file, line: line)
                    return
                }
                if viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                    waitForSettledFrames([element], file: file, line: line)
                    assertContained(element.frame, in: safeContentViewport(in: app), "The complete target must remain visible", file: file, line: line)
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
        XCTFail("Could not place the complete target inside the visible content area. Frame \(element.frame); viewport \(safeContentViewport(in: app))", file: file, line: line)
    }

    private func assertCompleteClock(_ label: XCUIElement, category: UIContentSizeCategory,
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

    private func centerHorizontally(_ label: XCUIElement, in scrollView: XCUIElement, app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(label.waitForExistence(timeout: 5), "A genuine displayed time label must exist", file: file, line: line)
        let contentViewport = safeContentViewport(in: app)
        let appFrame = app.frame
        var trace: [String] = []
        // Measure once more after the final permitted pan. Largest observation
        // columns can begin several viewports away from the requested quarter.
        for attempt in 0...24 {
            let viewport = scrollView.frame.intersection(contentViewport).insetBy(dx: 4, dy: 0)
            let frame = label.frame
            let offset = frame.minX < viewport.minX
                ? viewport.minX - frame.minX + 12 : viewport.maxX - frame.maxX - 12
            trace.append("attempt \(attempt): label=\(frame), viewport=\(viewport), horizontalOffset=\(offset)")
            guard !frame.isEmpty, frame.width <= viewport.width + 1 else {
                XCTFail("A complete time label must fit its scroll viewport. Frame \(frame); viewport \(viewport)", file: file, line: line)
                return
            }
            let fullyVisible = viewport.insetBy(dx: -1, dy: -1).contains(frame)
            if fullyVisible {
                waitForSettledFrames([scrollView, label], file: file, line: line)
                // The inset above is a positioning margin. After scrolling settles,
                // require the full glyph frame to fit the actual visible clip.
                let currentViewport = scrollView.frame.intersection(safeContentViewport(in: app))
                assertContained(label.frame, in: currentViewport, "The entire time label must be inside the horizontal viewport", file: file, line: line)
                return
            }
            guard attempt < 24 else { break }
            let movement = min(viewport.width * 0.85, max(20, abs(offset))) * (offset < 0 ? -1 : 1)
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX - movement / 2 - appFrame.minX, dy: viewport.midY - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: movement, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not bring the complete time label into its horizontal viewport. Actual pan trace: \(trace.joined(separator: "; "))",
                file: file, line: line)
    }

    private func assertHistoryHeaderLayout(_ header: XCUIElement, chart: XCUIElement, app: XCUIApplication,
                                           category: UIContentSizeCategory, capture: String) {
        centerFullyVisible(header, in: app)
        let viewport = safeContentViewport(in: app)
        let movement = min(viewport.height * 0.8, max(0, header.frame.minY - viewport.minY - 12))
        if movement > 2 {
            // Put the title near the upper edge so that the adjacent plot also
            // has a real visible frame, even when both are taller than SE.
            let appFrame = app.frame
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: verticalPanX(in: viewport) - appFrame.minX, dy: viewport.midY + movement / 2 - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -movement)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
            waitForSettledFrames([header, chart])
        }
        let headerFrame = header.frame
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
    }

    private func assertHistoryColumns(_ waits: [String], chart: XCUIElement, app: XCUIApplication,
                                      category: UIContentSizeCategory = .accessibilityExtraExtraExtraLarge,
                                      observations: Range<Int>? = nil, header: XCUIElement? = nil, capture: String) {
        if let header { assertHistoryHeaderLayout(header, chart: chart, app: app, category: category, capture: capture) }
        centerFullyVisible(chart, in: app)
        assertObservedChartSamples(waits, chart: chart)
        let times = chart.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'wait-sample-time-10916-'"))
        XCTAssertEqual(times.count, waits.count, "Every dot must have a genuine displayed local-time label")
        for index in (observations ?? waits.indices).reversed() {
            let time = chart.staticTexts["wait-sample-time-10916-\(index)"].firstMatch
            centerHorizontally(time, in: chart, app: app)
            assertCompleteClock(time, category: category)
            let point = chart.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Observation \(index + 1),")).firstMatch
            XCTAssertEqual(point.value as? String, "\(waits[index]) minutes")
            let annotation = chart.staticTexts["wait-sample-value-10916-\(index)"].firstMatch
            if annotation.exists {
                XCTAssertEqual(annotation.label, "\(waits[index]) min")
                assertContained(annotation.frame, in: chart.frame.intersection(safeContentViewport(in: app)), "The complete wait annotation must remain visible")
            }
            // Charts may expose annotations through the semantic Observation
            // element instead of a Text node. The real time label positions the
            // same column; each attachment also records that dot's visible glyphs.
            assertContained(chart.frame, in: safeContentViewport(in: app), "The entire chart must be visible for every captured observation")
            screenshot("\(capture) observation \(index + 1) value and full local time", app: app)
        }
    }

    private func assertForecastTimeLabels(in forecast: XCUIElement, app: XCUIApplication,
                                         quarter: Int, capture: String) {
        let chart = forecast.descendants(matching: .any)["wait-forecast-chart"].firstMatch
        centerFullyVisible(chart, in: app)
        let times = chart.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'wait-forecast-time-'"))
        let count = times.count
        XCTAssertGreaterThan(count, 1, "A multi-hour forecast must display its actual time labels")
        XCTAssertLessThanOrEqual(count, 25)
        XCTAssertEqual(count, 8, "The supported fixture must retain all eight ordinary forecast clocks")
        XCTAssertTrue((0..<4).contains(quarter))
        // Two clocks per case leave room for a cold native app launch while
        // preserving every clock, font, and whole-viewport assertion.
        let indices = (quarter * 2)..<(quarter * 2 + 2)
        for index in indices.reversed() {
            let time = chart.staticTexts["wait-forecast-time-\(index)"].firstMatch
            centerHorizontally(time, in: chart, app: app)
            assertCompleteClock(time, category: .accessibilityLarge)
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
        centerHorizontally(chart.staticTexts["wait-sample-time-10916-0"].firstMatch, in: chart, app: app)
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
        centerFullyVisible(hourly, in: app); hourly.tap()
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
        reveal(search, in: app); search.tap(); search.typeText("Guardians\n")
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
            XCTAssertGreaterThan(parkTime.frame.height, 40, "Park time and zone must wrap at accessibility size")
            let variation = summary.staticTexts["lowest-wait-variation"]
            centerFullyVisible(variation, in: app)
            XCTAssertGreaterThan(variation.frame.height, 40, "The complete uncertainty label must wrap")
            let source = summary.staticTexts["lowest-wait-source-time"]
            centerFullyVisible(source, in: app)
            XCTAssertTrue(source.label.contains("Wait source checked"))
            let observed = summary.staticTexts["lowest-wait-history-time"]
            centerFullyVisible(observed, in: app)
            XCTAssertTrue(observed.label.contains("History last observed"))
        }
        screenshot(expired ? "Lowest wait unavailable at accessibility size" : "Lowest wait evidence at accessibility size", app: app)
        let hourly = summary.buttons["ride-history-hourly-estimates"]
        centerFullyVisible(hourly, in: app); hourly.tap()
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
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: nil)], timeout: 5), .completed)
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
        let app = rootFixture(["--reference-ui-park=334", "--reference-ui-ride=14691", "--ui-dark"])
        let ride = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fyre Drill'")).firstMatch
        reveal(ride, in: app)
        XCTAssertTrue(ride.isHittable)
        screenshot("Accepted Florida Fyre Drill illustration card", app: app)
        ride.tap()
        let artwork = app.descendants(matching: .any)["ride-illustration-334-14691"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let loaded = NSPredicate { _, _ in artwork.value as? String == "Loaded" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
        screenshot("Accepted Florida Fyre Drill illustration detail", app: app)
        let rights = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Reference rights: Copyright Universal Studios; source rights retained'")).firstMatch
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
        reveal(app.staticTexts["PIVOT 1.18.2"], in: app)
        XCTAssertTrue(app.staticTexts["PIVOT 1.18.2"].exists)
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
