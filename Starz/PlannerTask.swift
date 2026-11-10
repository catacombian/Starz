//
//  PlannerTask.swift
//  Starz
//
//  Created by Elen on 17.10.26.
//

import Foundation
import SwiftData
import WidgetKit

/// What the app and the widget share: one SwiftData store in the App Group, and the widget's kind.
enum SharedStore {
    static let widgetKind = "PlannerWidgetExtension"

    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(groupContainer: .identifier("group.com.manhutava.Starz"))
        return try ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
    }

    /// Runs `body` on a brand-new container and context, so it always reads what is on disk now.
    /// The container must outlive the context, hence `withExtendedLifetime`.
    static func withFreshContext<T>(_ body: (ModelContext) throws -> T) throws -> T {
        let container = try makeContainer()
        return try withExtendedLifetime(container) { try body(ModelContext(container)) }
    }

    static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

/// A single to-do item. Named `PlannerTask` to avoid clashing with Swift's `Task`.
@Model
final class PlannerTask {
    /// Stable identifier, also used for notification request IDs.
    var id: UUID
    var title: String
    /// Optional description. Empty string means "no description".
    var details: String
    /// Start of the day this task belongs to.
    var day: Date
    /// Full date and time of the task, or nil if the task has no time.
    var time: Date?
    var isDone: Bool
    var createdAt: Date
    /// The regular event (`Series`) this task is a copy of, or nil for a one-off task.
    var seriesID: UUID?
    /// How the regular event repeats (daily or yearly), or nil for a one-off task.
    var recurrence: Recurrence?

    init(title: String, details: String = "", day: Date, time: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.day = Calendar.current.startOfDay(for: day)
        self.time = time
        self.isDone = false
        self.createdAt = .now
    }

    /// Limit: a day can hold at most this many tasks.
    static let maxPerDay = 20
    static let dayFullMessage = "You've reached the limit of \(maxPerDay) tasks for this day."
    static let moveTargetFullMessage = "That day already has \(maxPerDay) tasks."

    /// Limit: a description can hold at most this many characters.
    static let maxDetailsLength = 200
    /// The character counter appears from this length on.
    static let detailsCounterStart = 150

    /// The most characters `text` may grow to: the limit, or its own length if it is an old
    /// description already over the limit. Pass the `current` cap so it only ever comes down.
    static func detailsCap(for text: String, current: Int = .max) -> Int {
        max(maxDetailsLength, min(current, text.count))
    }

    /// Applies `cap` to a change of the description field. A field already at the cap
    /// ignores the change, so text inserted mid-way can't push characters off the end.
    /// Otherwise longer input, such as a paste, is trimmed.
    static func limitedDetails(_ new: String, previous: String, cap: Int) -> String {
        guard new.count > cap else { return new }
        return previous.count == cap ? previous : String(new.prefix(cap))
    }

    /// Fetches the tasks of one day, in the order they were added.
    static func descriptor(for day: Date) -> FetchDescriptor<PlannerTask> {
        descriptor(in: day.dayRange)
    }

    /// Fetches the tasks whose day falls in `range`, in the order they were added.
    static func descriptor(in range: Range<Date>) -> FetchDescriptor<PlannerTask> {
        let start = range.lowerBound
        let end = range.upperBound
        return FetchDescriptor(
            predicate: #Predicate { $0.day >= start && $0.day < end },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }

    /// What the widget lists for `day`: tasks not done yet, timed ones first, earliest first.
    static func openTasks(on day: Date, in context: ModelContext) -> [PlannerTask] {
        let tasks = (try? context.fetch(descriptor(for: day))) ?? []
        return tasks
            .filter { !$0.isDone }
            .sorted { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
    }
}

// MARK: - Actions that keep reminders and the widget in sync

extension PlannerTask {
    /// Marks the task done or open again, and cancels or restores its reminders.
    func toggleDone() {
        isDone.toggle()
        Reminders.update(for: self)
        modelContext?.commit()
    }
}

extension ModelContext {
    /// The one place changes are written. Saves first, so the widget reads the new data when it reloads.
    /// Every action that changes tasks ends here.
    func commit() {
        try? save()
        SharedStore.reloadWidget()
    }

    /// Whether `day` can take one more task, counting completed ones.
    /// A `task` already on that day doesn't need a new place, so it always fits.
    func hasRoom(on day: Date, for task: PlannerTask? = nil) -> Bool {
        if let task, Calendar.current.isDate(task.day, inSameDayAs: day) { return true }
        let count = (try? fetchCount(PlannerTask.descriptor(for: day))) ?? 0
        return count < PlannerTask.maxPerDay
    }

    /// Adds a new task and schedules its reminders. Refuses it and returns false when the day is full.
    @discardableResult
    func addTask(_ task: PlannerTask) -> Bool {
        guard hasRoom(on: task.day) else { return false }
        insert(task)
        Reminders.update(for: task)
        commit()
        return true
    }

    /// Applies edits from the editor. `day` can move the task to another date.
    /// Changes nothing and returns false when that day is full.
    @discardableResult
    func updateTask(_ task: PlannerTask, title: String, details: String, day: Date, time: Date?) -> Bool {
        guard hasRoom(on: day, for: task) else { return false }
        task.title = title
        task.details = details
        task.day = Calendar.current.startOfDay(for: day)
        task.time = time
        Reminders.update(for: task)
        commit()
        return true
    }

    /// Deletes a task together with its pending reminders.
    /// For a copy of a regular event this is "Only this event": the day is remembered so it isn't recreated.
    func deleteTask(_ task: PlannerTask) {
        series(of: task)?.deletedDates.append(task.day.dayKey)
        Reminders.cancel(for: task)
        delete(task)
        commit()
    }
}

extension Date {
    /// From the start of this day up to (not including) the start of the next day.
    var dayRange: Range<Date> {
        let start = Calendar.current.startOfDay(for: self)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return start..<end
    }

    /// Combines the day of `day` with the hour and minute of `self`.
    func onDay(_ day: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: self)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }
}
