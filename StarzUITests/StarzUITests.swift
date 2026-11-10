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
    /// and "This current tide" opens the list for the day selected in the calendar.
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
        let otherDate = Calendar.current.date(from: parts)!
        let otherDay = otherDate.formatted(date: .complete, time: .omitted)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", otherDay)).firstMatch.tap()

        // An empty day in another month shows its own (empty) list, not today's.
        tide.tap()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 5))
        let otherHeader = otherDate.formatted(.dateTime.day().month(.wide))
        let emptyHeader = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", otherHeader, "Nothing planned")
        XCTAssertTrue(app.staticTexts.matching(emptyHeader).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Water plants"].exists)

        // With today selected again it shows today's list.
        app.buttons["Calendar"].tap()
        XCTAssertTrue(tide.waitForExistence(timeout: 5))
        tide.tap()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Water plants"].waitForExistence(timeout: 5))
    }

    /// Saving immediately must not break the sheet: delete a task from the editor while it closes.
    func testDeleteFromEditor() throws {
        let app = launchWithTask("Water plants")
        app.buttons["Water plants"].tap()
        let delete = app.buttons["Delete task"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.staticTexts["A clear day"].waitForExistence(timeout: 5))
    }

    /// Changing the date in the editor moves the task off today's list.
    func testMoveTaskToAnotherDate() throws {
        let app = launchWithTask("Water plants")
        app.buttons["Water plants"].tap()
        let picker = app.datePickers.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // A neighbouring day in this month, so the calendar doesn't have to page.
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let target = calendar.isDate(tomorrow, equalTo: .now, toGranularity: .month)
            ? tomorrow
            : calendar.date(byAdding: .day, value: -1, to: .now)!
        let label = target.formatted(.dateTime.month(.wide).day())
        let dayButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(dayButton.waitForExistence(timeout: 5))
        dayButton.tap()
        app.staticTexts["Edit task"].tap()
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["A clear day"].waitForExistence(timeout: 5))
    }

    /// With the keyboard up on the description, Save stays reachable and saves the text.
    func testSaveIsReachableWhileTypingDescription() throws {
        let app = launchWithTask("Water plants")
        typeDescription("Use rainwater", in: app)
        XCTAssertTrue(app.buttons["Save"].isHittable, "Save is pushed off screen")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Use rainwater"].waitForExistence(timeout: 5))
    }

    /// Swiping the sheet away, keyboard still up, keeps everything typed so far.
    func testSwipeDownKeepsDescription() throws {
        let app = launchWithTask("Water plants")
        typeDescription("Use rainwater", in: app)
        swipeSheetAway(in: app)
        XCTAssertTrue(app.staticTexts["Use rainwater"].waitForExistence(timeout: 5))
    }

    /// Swiping away with an empty title keeps the old title, but still saves the description.
    func testSwipeDownWithEmptyTitleKeepsOldTitle() throws {
        let app = launchWithTask("Water plants")
        app.buttons["Water plants"].tap()
        let title = app.textFields["What do you need to do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save is off while the title is empty")
        swipeSheetAway(in: app)
        XCTAssertTrue(app.buttons["Water plants"].waitForExistence(timeout: 5))
    }

    /// Cancel is the one way out that throws edits away.
    func testCancelDiscardsEdits() throws {
        let app = launchWithTask("Water plants")
        typeDescription("Use rainwater", in: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Use rainwater"].waitForExistence(timeout: 2))
    }

    /// Typing stops at the limit, and the counter shows from 150 characters on.
    func testDescriptionLimitAndCounter() throws {
        let app = launchWithTask("Water plants")
        typeDescription(String(repeating: "a", count: 149), in: app)
        // Second field: the description can't be found by its placeholder once it has text.
        let details = app.textFields.element(boundBy: 1)
        XCTAssertFalse(app.staticTexts["149 of 200 characters"].exists)

        details.typeText("a")
        XCTAssertTrue(app.staticTexts["150 of 200 characters"].waitForExistence(timeout: 5))

        details.typeText(String(repeating: "a", count: 60))
        XCTAssertTrue(app.staticTexts["200 of 200 characters"].waitForExistence(timeout: 5))
        XCTAssertEqual((details.value as? String)?.count, 200)
    }

    /// A full day: dimmed button, message instead of the sheet, and back to normal after a delete.
    func testFullDayShowsMessageInsteadOfSheet() throws {
        let app = launchWithTask("Task 1")
        for number in 2...20 {
            app.buttons["New task"].tap()
            let title = app.textFields["What do you need to do?"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.typeText("Task \(number)")
            app.buttons["Add"].tap()
            XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 5))
        }

        let message = app.staticTexts["You've reached the limit of 20 tasks for this day."]
        app.buttons["New task"].tap()
        XCTAssertTrue(message.waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["What do you need to do?"].exists, "no sheet")
        XCTAssertFalse(app.staticTexts["Edit task"].exists, "the tap doesn't reach the row behind the button")
        // It goes away by itself after about 2.5 seconds.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: message)
        wait(for: [gone], timeout: 6)

        app.buttons["Task 1"].tap()
        app.buttons["Delete task"].tap()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 5))
        app.buttons["New task"].tap()
        XCTAssertTrue(app.textFields["What do you need to do?"].waitForExistence(timeout: 5), "active again")
    }

    /// Opens the task and types into its description, leaving the keyboard up.
    private func typeDescription(_ text: String, in app: XCUIApplication) {
        app.buttons["Water plants"].tap()
        let details = app.textFields["Add details"].exists ? app.textFields["Add details"] : app.textViews.firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        details.typeText(text)
    }

    /// Drags the sheet down by its top edge, the way a finger does.
    private func swipeSheetAway(in app: XCUIApplication) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    }

    private func launchWithTask(_ name: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["New task"].tap()
        let title = app.textFields["What do you need to do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(name)
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
        return app
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
