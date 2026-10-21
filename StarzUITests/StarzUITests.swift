//
//  StarzUITests.swift
//  StarzUITests
//
//  Created by Elen on 17.10.26.
//

import XCTest

final class StarzUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// Calendar rows match Today (checkbox, no dash, same long-press menu),
    /// and "This current tide" goes back to today's list from another month and day.
    func testCalendarRowsAndThisCurrentTide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["New task"].tap()
        let title = app.textFields["What do you need to do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Water plants")
        app.buttons["Add"].tap()

        assertTicksAndUnticks(in: app)

        app.buttons["Calendar"].tap()
        let tide = app.buttons["This current tide"]
        XCTAssertTrue(tide.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["–"].exists, "no dash before titles")
        assertTicksAndUnticks(in: app)

        // Browse to another month and select a day there.
        app.buttons["Next month"].tap()
        app.buttons["Next month"].tap()
        var parts = Calendar.current.dateComponents([.year, .month], from: Calendar.current.date(byAdding: .month, value: 2, to: .now)!)
        parts.day = 15
        let otherDay = Calendar.current.date(from: parts)!.formatted(date: .complete, time: .omitted)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", otherDay)).firstMatch.tap()

        tide.tap()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 5))
        let todayHeader = Date.now.formatted(.dateTime.day().month(.wide))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", todayHeader)).firstMatch.exists)
        XCTAssertTrue(app.buttons["Water plants"].exists)
    }

    /// Ticks and unticks the only task, first with the checkbox, then with the long-press menu.
    private func assertTicksAndUnticks(in app: XCUIApplication) {
        let open = app.buttons["Mark as done"]
        let done = app.buttons["Mark as not done"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))

        open.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))

        app.buttons["Water plants"].press(forDuration: 1)
        app.buttons["Done"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.buttons["Water plants"].press(forDuration: 1)
        app.buttons["Undone"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
