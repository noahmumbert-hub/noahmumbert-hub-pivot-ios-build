import XCTest

final class PIVOTUITests: XCTestCase {
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
        XCTAssertTrue(app.staticTexts["PIVOT 1.9.1"].exists)
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
