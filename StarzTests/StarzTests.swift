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
    /// `mainContext` doesn't keep its container alive, so the tests have to.
    private var containers: [ModelContainer] = []

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
        let container = try ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
        containers.append(container)
        return container.mainContext
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

    /// Taps "This current tide" with `selected` picked in the calendar and returns
    /// the titles the day view loads for the day it ends up showing.
    @MainActor
    private func tide(selected: Date, in context: ModelContext) throws -> [String] {
        var navigation = DayNavigation(day: date(9, 0), showCalendar: true)
        navigation.show(day: selected)
        XCTAssertFalse(navigation.showCalendar)
        XCTAssertTrue(calendar.isDate(navigation.day, inSameDayAs: selected))
        return try context.fetch(PlannerTask.descriptor(for: navigation.day)).map(\.title)
    }

    @MainActor
    private func contextWithTodayAndTomorrow() throws -> ModelContext {
        let context = try makeContext()
        context.insert(PlannerTask(title: "Today task", day: date(0, 0)))
        context.insert(PlannerTask(title: "Tomorrow task", day: date(0, 0, dayOffset: 1)))
        return context
    }

    @MainActor
    func testThisCurrentTideWithTodaySelected() throws {
        let context = try contextWithTodayAndTomorrow()
        XCTAssertEqual(try tide(selected: date(0, 0), in: context), ["Today task"])
    }

    @MainActor
    func testThisCurrentTideWithAnotherDayWithEvents() throws {
        let context = try contextWithTodayAndTomorrow()
        XCTAssertEqual(try tide(selected: date(0, 0, dayOffset: 1), in: context), ["Tomorrow task"])
    }

    @MainActor
    func testThisCurrentTideWithAnEmptyDayShowsNothing() throws {
        let context = try contextWithTodayAndTomorrow()
        XCTAssertEqual(try tide(selected: date(0, 0, dayOffset: 3), in: context), [], "not today's tasks")
    }

    @MainActor
    func testThisCurrentTideWithADayInAnotherMonth() throws {
        let context = try contextWithTodayAndTomorrow()
        let otherMonth = calendar.date(byAdding: .month, value: 2, to: date(0, 0))!
        context.insert(PlannerTask(title: "Later task", day: otherMonth))
        XCTAssertEqual(try tide(selected: otherMonth, in: context), ["Later task"])
    }

    func testThisCurrentTideDefaultsToToday() {
        var navigation = DayNavigation(day: date(12, 0, dayOffset: 40), showCalendar: true)
        navigation.show()
        XCTAssertTrue(calendar.isDateInToday(navigation.day))
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

    // MARK: - Widget: today's list

    private func titles(on day: Date, in context: ModelContext) -> [String] {
        PlannerTask.openTasks(on: day, in: context).map(\.title)
    }

    @MainActor
    func testWidgetListsOnlyTodaysOpenTasks() throws {
        let context = try makeContext()
        context.insert(PlannerTask(title: "Yesterday", day: date(0, 0, dayOffset: -1)))
        context.insert(PlannerTask(title: "Today", day: date(0, 0)))
        context.insert(PlannerTask(title: "Tomorrow", day: date(0, 0, dayOffset: 1)))
        let done = PlannerTask(title: "Done", day: date(0, 0))
        context.insert(done)
        done.toggleDone()

        XCTAssertEqual(titles(on: date(12, 0), in: context), ["Today"])
    }

    @MainActor
    func testWidgetShowsTimedTasksFirstInTimeOrder() throws {
        let context = try makeContext()
        context.insert(PlannerTask(title: "No time", day: date(0, 0)))
        context.insert(PlannerTask(title: "Late", day: date(0, 0), time: date(18, 0)))
        context.insert(PlannerTask(title: "Early", day: date(0, 0), time: date(9, 0)))

        XCTAssertEqual(titles(on: date(12, 0), in: context), ["Early", "Late", "No time"])
    }

    @MainActor
    func testWidgetFollowsADateMovedOutOfAndIntoToday() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Gym", day: date(0, 0), time: date(18, 0))
        context.addTask(task)

        context.updateTask(task, title: "Gym", details: "", day: date(9, 0, dayOffset: 1), time: date(18, 0, dayOffset: 1))
        XCTAssertEqual(titles(on: date(12, 0), in: context), [])
        XCTAssertEqual(titles(on: date(12, 0, dayOffset: 1), in: context), ["Gym"])
        XCTAssertEqual(task.day, date(0, 0, dayOffset: 1), "stored on the start of the new day")

        context.updateTask(task, title: "Gym", details: "", day: date(0, 0), time: nil)
        XCTAssertEqual(titles(on: date(12, 0), in: context), ["Gym"])
    }

    @MainActor
    func testWidgetRollsOverExactlyAtMidnight() throws {
        let context = try makeContext()
        context.insert(PlannerTask(title: "Today", day: date(0, 0)))
        context.insert(PlannerTask(title: "Tomorrow", day: date(0, 0, dayOffset: 1)))

        let lastMinute = date(23, 59)
        let midnight = lastMinute.dayRange.upperBound
        XCTAssertEqual(midnight, date(0, 0, dayOffset: 1))
        XCTAssertEqual(titles(on: lastMinute, in: context), ["Today"])
        XCTAssertEqual(titles(on: midnight, in: context), ["Tomorrow"])
    }

    /// A task made in another time zone isn't stored on this zone's midnight. The widget used to miss it.
    @MainActor
    func testWidgetMatchesTheAppForATaskFromAnotherTimeZone() throws {
        let context = try makeContext()
        let task = PlannerTask(title: "Flight", day: date(0, 0))
        task.day = date(3, 0)
        context.insert(task)

        XCTAssertEqual(titles(on: date(12, 0), in: context), ["Flight"])
        XCTAssertEqual(try context.fetch(PlannerTask.descriptor(for: date(12, 0))).map(\.title), ["Flight"])
    }

    // MARK: - Widget: changes reach the shared store right away

    /// Two containers on one file, like the app and the widget. The widget's side is opened anew
    /// for each read and autosave is off, so a change only shows if the action really saved it.
    @MainActor
    func testEveryActionIsOnDiskBeforeItReturns() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
        containers.append(container)
        let app = container.mainContext
        app.autosaveEnabled = false

        func widget() throws -> [String] {
            let other = try ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
            return withExtendedLifetime(other) { titles(on: date(12, 0), in: ModelContext(other)) }
        }

        let task = PlannerTask(title: "Gym", day: date(0, 0))
        app.addTask(task)
        XCTAssertEqual(try widget(), ["Gym"], "add")

        app.updateTask(task, title: "Run", details: "", day: date(0, 0), time: nil)
        XCTAssertEqual(try widget(), ["Run"], "edit title")

        app.updateTask(task, title: "Run", details: "", day: date(0, 0, dayOffset: 1), time: nil)
        XCTAssertEqual(try widget(), [], "moved to tomorrow")
        app.updateTask(task, title: "Run", details: "", day: date(0, 0), time: nil)
        XCTAssertEqual(try widget(), ["Run"], "moved back to today")

        task.toggleDone()
        XCTAssertEqual(try widget(), [], "completed")
        task.toggleDone()
        XCTAssertEqual(try widget(), ["Run"], "uncompleted")

        app.makeRegular(task, .daily)
        XCTAssertFalse(app.hasChanges, "make regular")
        app.deleteSeries(of: task)
        XCTAssertEqual(try widget(), [], "delete regular event")

        let other = PlannerTask(title: "Read", day: date(0, 0))
        app.addTask(other)
        app.deleteTask(other)
        XCTAssertEqual(try widget(), [], "delete")
    }

    /// What the widget's star does: a separate container writes, and the app reads the result.
    @MainActor
    func testCompletingFromTheWidgetReachesTheApp() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
        containers.append(container)
        let app = container.mainContext
        app.addTask(PlannerTask(title: "Gym", day: date(0, 0)))

        let widgetContainer = try ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
        try withExtendedLifetime(widgetContainer) {
            try ModelContext(widgetContainer).fetch(FetchDescriptor<PlannerTask>()).first?.toggleDone()
        }

        XCTAssertEqual(try app.fetch(FetchDescriptor<PlannerTask>()).map(\.isDone), [true])
    }

    // MARK: - Description limit

    private func text(_ count: Int) -> String { String(repeating: "a", count: count) }

    private let limit = PlannerTask.maxDetailsLength

    func testDescriptionWithinLimitIsUntouched() {
        XCTAssertEqual(PlannerTask.limitedDetails(text(200), previous: text(199), cap: limit), text(200))
    }

    func testTypingStopsAtLimitAndPasteIsTrimmed() {
        XCTAssertEqual(PlannerTask.limitedDetails(text(201), previous: text(200), cap: limit), text(200))
        XCTAssertEqual(PlannerTask.limitedDetails(text(500), previous: text(10), cap: limit), text(200))
    }

    /// Fast typing can deliver 201 and then 202 before the first trim lands. It must not get stuck over the limit.
    func testFastTypingCannotGetStuckOverTheLimit() {
        XCTAssertEqual(PlannerTask.limitedDetails(text(202), previous: text(201), cap: limit), text(200))
    }

    func testInsertingIntoAFullDescriptionKeepsItsEnd() {
        let full = text(199) + "z"
        XCTAssertEqual(PlannerTask.limitedDetails("b" + full, previous: full, cap: limit), full)
    }

    func testOldLongDescriptionCanOnlyShrink() {
        var cap = PlannerTask.detailsCap(for: text(250))
        XCTAssertEqual(cap, 250, "stored text stays as it is")
        XCTAssertEqual(PlannerTask.limitedDetails(text(251), previous: text(250), cap: cap), text(250), "can't add")

        // Deleting lowers the cap, so the room can't be used again.
        XCTAssertEqual(PlannerTask.limitedDetails(text(240), previous: text(250), cap: cap), text(240))
        cap = PlannerTask.detailsCap(for: text(240), current: cap)
        XCTAssertEqual(PlannerTask.limitedDetails(text(241), previous: text(240), cap: cap), text(240))

        // Under the limit it behaves like any other description.
        cap = PlannerTask.detailsCap(for: text(190), current: cap)
        XCTAssertEqual(cap, 200)
        XCTAssertEqual(PlannerTask.limitedDetails(text(195), previous: text(190), cap: cap), text(195))
    }

    // MARK: - Daily task limit

    /// Fills the day, leaving one of the tasks done, since done tasks count too.
    @MainActor
    private func fill(_ day: Date, in context: ModelContext) {
        for i in 0..<PlannerTask.maxPerDay {
            XCTAssertTrue(context.addTask(PlannerTask(title: "Task \(i)", day: day)))
        }
        try? context.fetch(PlannerTask.descriptor(for: day)).first?.toggleDone()
    }

    @MainActor
    func testAddTaskRefusesThe21stTask() throws {
        let context = try makeContext()
        fill(date(0, 0), in: context)

        XCTAssertFalse(context.addTask(PlannerTask(title: "One too many", day: date(0, 0))))
        XCTAssertEqual(try context.fetchCount(PlannerTask.descriptor(for: date(0, 0))), PlannerTask.maxPerDay)
        XCTAssertTrue(context.addTask(PlannerTask(title: "Tomorrow", day: date(0, 0, dayOffset: 1))), "other days aren't affected")
    }

    @MainActor
    func testDeletingAndMovingAwayFreeAPlace() throws {
        let context = try makeContext()
        fill(date(0, 0), in: context)
        let tasks = try context.fetch(PlannerTask.descriptor(for: date(0, 0)))

        context.deleteTask(tasks[0])
        XCTAssertTrue(context.hasRoom(on: date(0, 0)))
        XCTAssertTrue(context.addTask(PlannerTask(title: "Back to 20", day: date(0, 0))))
        XCTAssertFalse(context.hasRoom(on: date(0, 0)))

        XCTAssertTrue(context.updateTask(tasks[1], title: "Moved", details: "", day: date(0, 0, dayOffset: 1), time: nil))
        XCTAssertTrue(context.hasRoom(on: date(0, 0)))
    }

    @MainActor
    func testMovingToAFullDayChangesNothing() throws {
        let context = try makeContext()
        fill(date(0, 0, dayOffset: 1), in: context)
        let task = PlannerTask(title: "Gym", day: date(0, 0))
        context.addTask(task)

        XCTAssertFalse(context.updateTask(task, title: "Run", details: "", day: date(0, 0, dayOffset: 1), time: nil))
        XCTAssertEqual(task.day, date(0, 0))
        XCTAssertEqual(task.title, "Gym")
    }

    @MainActor
    func testEditingATaskOnAFullDayStillWorks() throws {
        let context = try makeContext()
        fill(date(0, 0), in: context)
        let task = try XCTUnwrap(context.fetch(PlannerTask.descriptor(for: date(0, 0))).first)

        XCTAssertTrue(context.updateTask(task, title: "Renamed", details: "", day: date(0, 0), time: nil))
        XCTAssertEqual(task.title, "Renamed")
    }

    /// Several regular events on a nearly full day: only the ones that fit get a copy.
    @MainActor
    func testTopUpStopsAtTheLimitAndFillsInLater() throws {
        let context = try makeContext()
        let now = date(8, 0)
        let tomorrow = date(0, 0, dayOffset: 1)
        for i in 0..<(PlannerTask.maxPerDay - 1) {
            context.addTask(PlannerTask(title: "Task \(i)", day: tomorrow))
        }
        _ = makeRegular("Stretch", day: now, time: nil, .daily, in: context)
        _ = makeRegular("Read", day: now, time: nil, .daily, in: context)
        Series.topUp(in: context, now: now)
        XCTAssertEqual(try context.fetchCount(PlannerTask.descriptor(for: tomorrow)), PlannerTask.maxPerDay)

        // A place opens up: the skipped copy arrives with the next top-up.
        let open = try XCTUnwrap(context.fetch(PlannerTask.descriptor(for: tomorrow)).first { $0.seriesID == nil })
        context.deleteTask(open)
        XCTAssertEqual(Series.topUp(in: context, now: now).count, 1)
        XCTAssertEqual(try context.fetchCount(PlannerTask.descriptor(for: tomorrow)), PlannerTask.maxPerDay)
    }

    @MainActor
    func testYearlyCopySkipsAFullYear() throws {
        let context = try makeContext()
        fill(day(2027, 10, 21), in: context)
        let task = PlannerTask(title: "Anniversary", day: day(2026, 10, 21))
        context.insert(task)
        context.makeRegular(task, .yearly)

        XCTAssertEqual(try context.fetchCount(PlannerTask.descriptor(for: day(2027, 10, 21))), PlannerTask.maxPerDay)
        XCTAssertEqual(try yearlyCopies(of: task, in: context).map(\.day), [day(2026, 10, 21), day(2028, 10, 21), day(2029, 10, 21)])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
