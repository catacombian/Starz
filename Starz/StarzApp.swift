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

    /// SwiftData store kept in the App Group so the widget can read the same tasks.
    let container: ModelContainer = {
        let config = ModelConfiguration(
            groupContainer: .identifier("group.com.manhutava.Starz")
        )
        return try! ModelContainer(for: PlannerTask.self, configurations: config)
    }()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
