//
//  StarzTests.swift
//  StarzTests
//
//  Created by Elen on 17.10.26.
//

import XCTest
import SwiftData
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

    // MARK: - Regular events

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PlannerTask.self, Series.self, configurations: config).mainContext
    }

    @MainActor
    private func makeRegular(_ title: String, day: Date, time: Date?, _ recurrence: Recurrence, in context: ModelContext) -> Series {
        let task = PlannerTask(title: title, day: day, time: time)
        context.insert(task)
        let series = Series(from: task, recurrence: recurrence)
        context.insert(series)
        task.seriesID = series.id
        return series
    }

    @MainActor
    private func copies(of series: Series, in context: ModelContext) throws -> [PlannerTask] {
        let id: UUID? = series.id
        return try context.fetch(FetchDescriptor<PlannerTask>(
            predicate: #Predicate { $0.seriesID == id },
            sortBy: [SortDescriptor(\.day)]
        ))
    }

    @MainActor
    func testTopUpFillsSevenDaysAndRunningTwiceAddsNothing() throws {
        let context = try makeContext()
        let now = date(8, 0)
        let series = makeRegular("Stretch", day: now, time: date(18, 30), .daily, in: context)

        XCTAssertEqual(Series.topUp(in: context, now: now).count, 6, "today already has the original")
        XCTAssertEqual(Series.topUp(in: context, now: now).count, 0)

        let all = try copies(of: series, in: context)
        XCTAssertEqual(all.map(\.day), (0..<7).map { date(0, 0, dayOffset: $0) })
        for (offset, copy) in all.enumerated() {
            XCTAssertEqual(copy.time, date(18, 30, dayOffset: offset))
            // Both reminders (1 hour and 10 minutes before) are due for every copy.
            XCTAssertEqual(Reminders.fireDates(for: copy.time!, now: now).count, 2)
        }
    }

    @MainActor
    func testDeletedCopyIsNotRecreated() throws {
        let context = try makeContext()
        let now = date(8, 0)
        let series = makeRegular("Stretch", day: now, time: nil, .daily, in: context)
        Series.topUp(in: context, now: now)

        let tomorrow = try copies(of: series, in: context)[1]
        context.deleteTask(tomorrow)
        XCTAssertEqual(Series.topUp(in: context, now: now).count, 0)
        XCTAssertEqual(try copies(of: series, in: context).count, 6)
    }

    @MainActor
    func testDeleteSeriesKeepsPastCopies() throws {
        let context = try makeContext()
        let series = makeRegular("Stretch", day: date(8, 0, dayOffset: -2), time: nil, .daily, in: context)
        Series.topUp(in: context, now: date(8, 0, dayOffset: -2))
        Series.topUp(in: context, now: date(8, 0))

        let today = try copies(of: series, in: context).first { $0.day == date(0, 0) }!
        context.deleteSeries(of: today, now: date(8, 0))

        let left = try context.fetch(FetchDescriptor<PlannerTask>())
        XCTAssertEqual(left.map(\.day).sorted(), [date(0, 0, dayOffset: -2), date(0, 0, dayOffset: -1)])
        XCTAssertTrue(left.allSatisfy { $0.seriesID == nil })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Series>()), 0)
    }

    @MainActor
    func testTopUpRespectsDailyLimit() throws {
        let context = try makeContext()
        let now = date(8, 0)
        let tomorrow = date(0, 0, dayOffset: 1)
        for i in 0..<PlannerTask.maxPerDay {
            context.insert(PlannerTask(title: "Task \(i)", day: tomorrow))
        }
        _ = makeRegular("Stretch", day: now, time: nil, .daily, in: context)
        Series.topUp(in: context, now: now)
        XCTAssertEqual(try context.fetchCount(PlannerTask.descriptor(for: tomorrow)), PlannerTask.maxPerDay)
    }

    func testYearlyEventOccursOnItsDate() {
        let birthday = PlannerTask(title: "Mum", day: day(2026, 5, 14))
        let series = Series(from: birthday, recurrence: .yearly)
        XCTAssertTrue(series.occurs(on: day(2027, 5, 14)))
        XCTAssertFalse(series.occurs(on: day(2027, 5, 15)))
        XCTAssertFalse(series.occurs(on: day(2025, 5, 14)), "nothing before the start")
    }

    func testFeb29BirthdayFallsOnFeb28InOtherYears() {
        let birthday = PlannerTask(title: "Leap", day: day(2028, 2, 29))
        let series = Series(from: birthday, recurrence: .yearly)
        XCTAssertTrue(series.occurs(on: day(2029, 2, 28)))
        XCTAssertFalse(series.occurs(on: day(2029, 3, 1)))
        XCTAssertTrue(series.occurs(on: day(2032, 2, 29)))
        XCTAssertFalse(series.occurs(on: day(2032, 2, 28)), "leap years use the real date")
    }

    func testRemindersAreCappedToTheSoonest() {
        let now = date(6, 0)
        let tasks = (0..<40).map { PlannerTask(title: "\($0)", day: date(0, 0, dayOffset: $0), time: date(12, 0, dayOffset: $0)) }
        let upcoming = Reminders.upcoming(for: tasks, now: now)
        XCTAssertEqual(upcoming.count, Reminders.pendingLimit)
        XCTAssertEqual(upcoming.first?.fireDate, date(11, 0))
        XCTAssertEqual(upcoming.last?.fireDate, date(11, 50, dayOffset: 31))
    }

    // MARK: - Shared event row

    func testLongPressActionIsDoneOrUndone() {
        XCTAssertEqual(EventRow.doneActionTitle(isDone: false), "Done")
        XCTAssertEqual(EventRow.doneActionTitle(isDone: true), "Undone")
    }

    /// The checkbox and the "Done"/"Undone" menu item both call `toggle`.
    @MainActor
    func testRowTicksAndUnticks() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Gym", day: date(0, 0))
        context.insert(task)
        let row = EventRow(task: task, onEdit: {})

        row.toggle()
        XCTAssertTrue(task.isDone)
        XCTAssertEqual(EventRow.doneActionTitle(isDone: task.isDone), "Undone")
        row.toggle()
        XCTAssertFalse(task.isDone)
        XCTAssertEqual(EventRow.doneActionTitle(isDone: task.isDone), "Done")
    }

    // MARK: - "This current tide"

    func testThisCurrentTideClosesCalendarAndShowsToday() {
        let now = date(9, 0)
        for start in [date(12, 0, dayOffset: -40), date(12, 0, dayOffset: 75), now] {
            var navigation = DayNavigation(day: start, showCalendar: true)
            navigation.showToday(now: now)
            XCTAssertFalse(navigation.showCalendar)
            XCTAssertTrue(calendar.isDate(navigation.day, inSameDayAs: now))
        }
    }

    // MARK: - Make yearly

    @MainActor
    private func yearlyCopies(of task: PlannerTask, in context: ModelContext) throws -> [PlannerTask] {
        let id = task.seriesID
        XCTAssertNotNil(id)
        return try context.fetch(FetchDescriptor<PlannerTask>(
            predicate: #Predicate { $0.seriesID == id },
            sortBy: [SortDescriptor(\.day)]
        ))
    }

    @MainActor
    func testMakeYearlyCreatesNextThreeYears() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Anniversary", day: day(2026, 10, 21))
        context.insert(task)
        context.makeRegular(task, .yearly)

        let all = try yearlyCopies(of: task, in: context)
        XCTAssertEqual(all.map(\.day), [day(2026, 10, 21), day(2027, 10, 21), day(2028, 10, 21), day(2029, 10, 21)])
        XCTAssertTrue(all.allSatisfy { $0.recurrence == .yearly })
        // The calendar finds them when browsing those dates.
        XCTAssertEqual(try context.fetch(PlannerTask.descriptor(for: day(2028, 10, 21))).map(\.title), ["Anniversary"])
    }

    @MainActor
    func testMakeYearlyTwiceMakesNoDuplicates() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Anniversary", day: day(2026, 10, 21))
        context.insert(task)
        context.makeRegular(task, .yearly)
        context.makeRegular(task, .yearly)

        XCTAssertEqual(try yearlyCopies(of: task, in: context).count, 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Series>()), 1)
    }

    @MainActor
    func testMakeYearlyOnFeb29UsesFeb28InOtherYears() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Leap", day: day(2028, 2, 29))
        context.insert(task)
        context.makeRegular(task, .yearly)

        XCTAssertEqual(try yearlyCopies(of: task, in: context).map(\.day),
                       [day(2028, 2, 29), day(2029, 2, 28), day(2030, 2, 28), day(2031, 2, 28)])
    }

    @MainActor
    func testDeletingYearlyCopies() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Anniversary", day: day(2026, 10, 21))
        context.insert(task)
        context.makeRegular(task, .yearly)

        // "Only this event" leaves the other years.
        let copy2028 = try yearlyCopies(of: task, in: context).first { $0.day == day(2028, 10, 21) }!
        context.deleteTask(copy2028)
        XCTAssertEqual(try yearlyCopies(of: task, in: context).map(\.day), [day(2026, 10, 21), day(2027, 10, 21), day(2029, 10, 21)])

        // "This regular event" removes them all.
        context.deleteSeries(of: task, now: day(2026, 10, 21))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannerTask>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Series>()), 0)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
