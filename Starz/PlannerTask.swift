//
//  PlannerTask.swift
//  Starz
//
//  Created by Elen on 17.10.26.
//

import Foundation
import SwiftData

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
}

// MARK: - Actions that keep reminders in sync

extension PlannerTask {
    /// Marks the task done or open again, and cancels or restores its reminders.
    func toggleDone() {
        isDone.toggle()
        Reminders.update(for: self)
    }
}

extension ModelContext {
    /// Deletes a task together with its pending reminders.
    /// For a copy of a regular event this is "Only this event": the day is remembered so it isn't recreated.
    func deleteTask(_ task: PlannerTask) {
        series(of: task)?.deletedDates.append(task.day.dayKey)
        Reminders.cancel(for: task)
        delete(task)
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
