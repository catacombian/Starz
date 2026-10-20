//
//  StarzTests.swift
//  StarzTests
//
//  Created by Elen on 17.10.26.
//

import XCTest
@testable import Starz

final class StarzTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testBothRemindersWhenTaskIsFarAway() {
        let now = date(10, 0)
        let fireDates = Reminders.fireDates(for: date(14, 0), now: now)
        XCTAssertEqual(fireDates, [date(13, 0), date(13, 50)])
    }

    func testPastRemindersAreSkipped() {
        let now = date(13, 30)
        XCTAssertEqual(Reminders.fireDates(for: date(14, 0), now: now), [date(13, 50)])
        XCTAssertEqual(Reminders.fireDates(for: date(14, 0), now: date(13, 55)), [])
    }

    func testOnDayKeepsTimeAndMovesDay() {
        let time = date(18, 30)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertEqual(time.onDay(tomorrow), date(18, 30, dayOffset: 1))
    }

    func testDayRangeCoversWholeDay() {
        let range = date(15, 45).dayRange
        XCTAssertEqual(range.lowerBound, date(0, 0))
        XCTAssertEqual(range.upperBound, date(0, 0, dayOffset: 1))
        XCTAssertTrue(range.contains(date(23, 59)))
    }

    func testNewTaskIsStoredOnStartOfDay() {
        let task = PlannerTask(title: "Gym", day: date(18, 30))
        XCTAssertEqual(task.day, date(0, 0))
        XCTAssertFalse(task.isDone)
    }
}
