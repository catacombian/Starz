//
//  Series.swift
//  Starz
//

import Foundation
import SwiftData

/// How often a regular event repeats.
enum Recurrence: String, Codable {
    case daily
    case yearly
}

/// Template for a regular event. `topUp` turns it into ordinary tasks (copies) a week ahead.
@Model
final class Series {
    var id: UUID
    var title: String
    var details: String
    /// Wall-clock time of the copies, or nil for events without a time.
    /// Kept as hour and minute so copies stay at the same local time across daylight saving changes.
    var hour: Int?
    var minute: Int?
    var recurrence: Recurrence
    /// Day key ("yyyy-MM-dd") of the first occurrence. No copies are made before it.
    var startKey: String
    /// Day keys of copies deleted with "Only this event", so `topUp` doesn't bring them back.
    var deletedDates: [String]

    /// Builds the template from an existing task, which becomes the first copy.
    init(from task: PlannerTask, recurrence: Recurrence) {
        self.id = UUID()
        self.title = task.title
        self.details = task.details
        if let time = task.time {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            self.hour = parts.hour
            self.minute = parts.minute
        }
        self.recurrence = recurrence
        self.startKey = task.day.dayKey
        self.deletedDates = []
    }

    /// Whether this event should have a copy on `day`.
    func occurs(on day: Date) -> Bool {
        let key = day.dayKey
        guard key >= startKey, !deletedDates.contains(key) else { return false }

        switch recurrence {
        case .daily:
            return true
        case .yearly:
            let start = startKey.split(separator: "-").compactMap { Int($0) }
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
            guard start.count == 3, let year = parts.year else { return false }
            if parts.month == start[1] && parts.day == start[2] { return true }
            // Feb 29 birthdays show up on Feb 28 in non-leap years.
            let isFeb29Event = start[1] == 2 && start[2] == 29
            return isFeb29Event && parts.month == 2 && parts.day == 28 && !Self.isLeapYear(year)
        }
    }

    /// A new task for `day` with the template's title, details and time.
    func makeCopy(on day: Date) -> PlannerTask {
        var time: Date?
        if let hour {
            // `.nextTime` moves a time that doesn't exist (skipped by daylight saving) to the next valid one.
            time = Calendar.current.date(
                bySettingHour: hour, minute: minute ?? 0, second: 0, of: day,
                matchingPolicy: .nextTime
            )
        }
        let copy = PlannerTask(title: title, details: details, day: day, time: time)
        copy.seriesID = id
        copy.recurrence = recurrence
        return copy
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

// MARK: - Top-up

extension Series {
    /// Copies are kept this many days ahead, counting today.
    static let windowDays = 7

    /// Creates the missing copies of every regular event for today and the next 6 days.
    /// Safe to call any number of times: a day that already has a copy is skipped,
    /// and so is a full day (20 tasks). Returns the new copies.
    @discardableResult
    static func topUp(in context: ModelContext, now: Date = .now) -> [PlannerTask] {
        let allSeries = (try? context.fetch(FetchDescriptor<Series>())) ?? []
        guard !allSeries.isEmpty else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: today)!
        let existing = (try? context.fetch(PlannerTask.descriptor(in: today..<end))) ?? []

        var created: [PlannerTask] = []
        for offset in 0..<windowDays {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let range = day.dayRange
            var dayTasks = existing.filter { range.contains($0.day) }

            for series in allSeries where series.occurs(on: day) {
                guard !dayTasks.contains(where: { $0.seriesID == series.id }) else { continue }
                guard dayTasks.count < PlannerTask.maxPerDay else { break }
                let copy = series.makeCopy(on: day)
                context.insert(copy)
                dayTasks.append(copy)
                created.append(copy)
            }
        }
        if !created.isEmpty { try? context.save() }
        return created
    }
}

// MARK: - Yearly copies

extension Series {
    /// "Every year" creates copies this many years ahead right away.
    static let yearsAhead = 3

    /// Creates the copies of a yearly event on the same day and month in each of the next 3 years
    /// after `day`. Feb 29 falls on Feb 28 in non-leap years. A year that already has a copy,
    /// was deleted with "Only this event" or is full is skipped. Returns the new copies.
    @discardableResult
    func fillComingYears(after day: Date, in context: ModelContext) -> [PlannerTask] {
        guard recurrence == .yearly else { return [] }
        var created: [PlannerTask] = []
        for offset in 1...Self.yearsAhead {
            // Adding years to Feb 29 lands on Feb 28 when the target year isn't a leap year.
            guard let target = Calendar.current.date(byAdding: .year, value: offset, to: day),
                  occurs(on: target) else { continue }
            let dayTasks = (try? context.fetch(PlannerTask.descriptor(for: target))) ?? []
            guard !dayTasks.contains(where: { $0.seriesID == id }),
                  dayTasks.count < PlannerTask.maxPerDay else { continue }
            let copy = makeCopy(on: target)
            context.insert(copy)
            created.append(copy)
        }
        return created
    }
}

// MARK: - Actions

extension ModelContext {
    /// The regular event a copy belongs to, if any.
    func series(of task: PlannerTask) -> Series? {
        guard let id = task.seriesID else { return nil }
        var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    /// Turns a task into a regular event and fills the coming week with copies.
    /// A yearly event also gets its copies for the next 3 years right away.
    /// A task that is already a regular event is left alone, so this never makes duplicates.
    func makeRegular(_ task: PlannerTask, _ recurrence: Recurrence) {
        guard task.seriesID == nil else { return }
        let series = Series(from: task, recurrence: recurrence)
        insert(series)
        task.seriesID = series.id
        task.recurrence = recurrence
        series.fillComingYears(after: task.day, in: self)
        Series.topUp(in: self)
        try? save()
        Reminders.rescheduleAll(in: self)
    }

    /// "This regular event": deletes the template and its copies from today on.
    /// Earlier copies stay as history and become ordinary tasks.
    func deleteSeries(of task: PlannerTask, now: Date = .now) {
        let id: UUID? = task.seriesID
        guard id != nil else { return }
        let today = Calendar.current.startOfDay(for: now)
        let copies = (try? fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.seriesID == id }))) ?? []
        for copy in copies {
            if copy.day >= today {
                Reminders.cancel(for: copy)
                delete(copy)
            } else {
                copy.seriesID = nil
                copy.recurrence = nil
            }
        }
        if let series = series(of: task) { delete(series) }
    }
}

extension Date {
    /// Calendar day as "yyyy-MM-dd" in the current time zone.
    var dayKey: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
