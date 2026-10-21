//
//  Reminders.swift
//  Starz
//

import Foundation
import SwiftData
import UserNotifications

/// Schedules two local notifications for a timed task: 1 hour and 10 minutes before.
enum Reminders {
    /// Minutes before the task time, with the text shown in the notification.
    typealias Offset = (minutes: Int, text: String)
    /// One pending notification: which task, which offset, and when it fires.
    typealias Reminder = (task: PlannerTask, offset: Offset, fireDate: Date)

    static let offsets: [Offset] = [
        (60, "In 1 hour"),
        (10, "In 10 minutes"),
    ]

    /// Reminder dates for a task at `time`, leaving out any that are already in the past.
    static func fireDates(for time: Date, now: Date = .now) -> [Date] {
        offsets
            .map { time.addingTimeInterval(TimeInterval(-$0.minutes * 60)) }
            .filter { $0 > now }
    }

    /// Asks for notification permission. Only prompts the first time.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Removes old reminders and schedules fresh ones. Call after any add, edit or completion change.
    static func update(for task: PlannerTask) {
        cancel(for: task)
        guard !task.isDone, let time = task.time else { return }

        let center = UNUserNotificationCenter.current()
        let fireDates = fireDates(for: time)
        for offset in offsets {
            let fireDate = time.addingTimeInterval(TimeInterval(-offset.minutes * 60))
            guard fireDates.contains(fireDate) else { continue }
            center.add(request(for: task, offset: offset, fireDate: fireDate))
        }
    }

    /// iOS keeps at most 64 pending local notifications per app.
    static let pendingLimit = 64

    /// The soonest reminders of all open timed tasks, at most `limit` of them.
    static func upcoming(
        for tasks: [PlannerTask], now: Date = .now, limit: Int = pendingLimit
    ) -> [Reminder] {
        var all: [Reminder] = []
        for task in tasks where !task.isDone {
            guard let time = task.time else { continue }
            for offset in offsets {
                let fireDate = time.addingTimeInterval(TimeInterval(-offset.minutes * 60))
                if fireDate > now { all.append((task, offset, fireDate)) }
            }
        }
        return Array(all.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Replaces all pending reminders with the soonest 64. Call on every app open,
    /// so reminders further out than the limit get scheduled once they move closer.
    static func rescheduleAll(in context: ModelContext, now: Date = .now) {
        let today = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<PlannerTask>(predicate: #Predicate { !$0.isDone && $0.day >= today })
        let tasks = (try? context.fetch(descriptor)) ?? []

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for reminder in upcoming(for: tasks, now: now) {
            center.add(request(for: reminder.task, offset: reminder.offset, fireDate: reminder.fireDate))
        }
    }

    private static func request(
        for task: PlannerTask, offset: Offset, fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = task.title
        if let time = task.time {
            content.body = "\(offset.text) · \(time.formatted(date: .omitted, time: .shortened))"
        }
        content.sound = .default

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(
            identifier: identifier(task.id, offset.minutes),
            content: content,
            trigger: trigger
        )
    }

    /// Removes any pending reminders for the task. Call before deleting it.
    static func cancel(for task: PlannerTask) {
        let ids = offsets.map { identifier(task.id, $0.minutes) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func identifier(_ id: UUID, _ minutes: Int) -> String {
        "\(id.uuidString)-\(minutes)"
    }
}

/// Shows reminders as banners even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
