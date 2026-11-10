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
    @Environment(\.scenePhase) private var scenePhase

    /// SwiftData store kept in the App Group so the widget can read the same tasks.
    let container: ModelContainer = {
        // UI tests start from an empty, throwaway store.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: PlannerTask.self, Series.self, configurations: config)
        }
        return try! SharedStore.makeContainer()
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { refresh() }
            // Safety net: nothing unsaved is left behind, and the widget gets one last look.
            if phase == .background { container.mainContext.commit() }
        }
    }

    /// On launch and every return to the app: add the coming week's copies of regular events,
    /// then schedule the soonest reminders (iOS keeps only 64).
    @MainActor
    private func refresh() {
        Series.topUp(in: container.mainContext)
        Reminders.rescheduleAll(in: container.mainContext)
    }
}
