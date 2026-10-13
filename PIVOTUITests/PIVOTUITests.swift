import XCTest

final class PIVOTUITests: XCTestCase {
    func testWaitForecastShowsHourlyPlanCrowdAndLearningState() {
        let app = XCUIApplication()
        app.launchArguments = ["--wait-forecast-ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Crowds & waits"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5/10"].exists)
        XCTAssertTrue(app.staticTexts["Lowest estimated wait"].exists)
        XCTAssertTrue(app.staticTexts["Hourly estimates"].exists)
        app.staticTexts["Hourly estimates"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "same weekday")).count > 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Wait forecasts and park crowd meter"; screenshot.lifetime = .keepAlways
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

    private func hhnApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--hhn-ui-test", "--reset-hhn-ui-test"] + extraArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Halloween Horror Nights"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.minY < app.frame.minY {
                app.swipeDown()
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
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
        XCTAssertTrue(app.staticTexts["PIVOT 1.14.4"].exists)
        app.buttons["accent-mint"].tap()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDashboardUsesTheNativeTabBarAndDestinations() {
        let app = XCUIApplication()
        app.launchArguments = ["-pivot.selectedPark", "-1"]
        app.launch()

        XCTAssertTrue(app.staticTexts["PIVOT"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Change park'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Refresh ride data now"].exists)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 5)

        let today = tabBar.buttons["Plan"]
        let waits = tabBar.buttons["Waits"]
        let shows = tabBar.buttons["Shows"]
        let radar = tabBar.buttons["Radar"]
        let data = tabBar.buttons["More"]

        XCTAssertTrue(today.exists)
        XCTAssertTrue(waits.exists)
        XCTAssertTrue(shows.exists)
        XCTAssertTrue(radar.exists)
        XCTAssertTrue(data.exists)
        XCTAssertTrue(waits.isSelected)
        XCTAssertTrue(app.staticTexts["Wait times"].exists)
        today.tap()
        XCTAssertTrue(app.staticTexts["Your day"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Today’s entertainment, all in one place."].exists)

        waits.tap()
        XCTAssertTrue(waits.isSelected)
        XCTAssertTrue(app.staticTexts["Wait times"].waitForExistence(timeout: 3))

        shows.tap()
        XCTAssertTrue(shows.isSelected)
        XCTAssertTrue(app.staticTexts["Today’s entertainment, all in one place."].waitForExistence(timeout: 3))

        radar.tap()
        XCTAssertTrue(radar.isSelected)
        XCTAssertTrue(app.staticTexts["Reopen Radar"].waitForExistence(timeout: 3))

        data.tap()
        XCTAssertTrue(data.isSelected)
        XCTAssertTrue(app.staticTexts["Manage your park, alerts, and app."].waitForExistence(timeout: 3))

        for item in [today, waits, shows, radar, data] {
            XCTAssertGreaterThanOrEqual(item.frame.width, 44)
            XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        }
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
