//
//  StarzApp.swift
//  Starz
//
//  Created by Elen on 17.10.26.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct StarzApp: App {
    private static let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: PlannerTask.self)
    }
}
