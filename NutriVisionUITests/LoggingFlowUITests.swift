//
//  LoggingFlowUITests.swift
//  NutriVisionUITests
//

import XCTest

/// Logs a food end to end through search. Launches with `-uiTesting`, which
/// gives an empty in-memory store and skips onboarding.
final class LoggingFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSearchAndQuickLogAppearsOnDashboard() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        app.buttons["Add food"].firstMatch.tap()

        let search = app.searchFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("banana")

        let quickLog = app.buttons["Log Banana now"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 5))
        quickLog.tap()

        app.buttons["Close"].tap()
        // Meal rows expose one combined accessibility element ("Banana, 8:00 AM, 105 kcal").
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Banana'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testOpenSettingsAndChangeUnits() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Insights"].exists)
    }
}
