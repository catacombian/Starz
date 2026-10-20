//
//  Reminders.swift
//  Starz
//

import Foundation
import UserNotifications

/// Schedules two local notifications for a timed task: 1 hour and 10 minutes before.
enum Reminders {
    /// Minutes before the task time, with the text shown in the notification.
    static let offsets: [(minutes: Int, text: String)] = [
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
        let now = Date.now
        for offset in offsets {
            let fireDate = time.addingTimeInterval(TimeInterval(-offset.minutes * 60))
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = "\(offset.text) · \(time.formatted(date: .omitted, time: .shortened))"
            content.sound = .default

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(task.id, offset.minutes),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
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
