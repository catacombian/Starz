//
//  PlannerWidgetExtension.swift
//  PlannerWidgetExtension
//
//  Created by Elen on 20/10/2026.
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

struct TaskRow: Identifiable {
    let id: UUID
    let title: String
    let time: Date?
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let rows: [TaskRow]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: .now, rows: [
            TaskRow(id: UUID(), title: "Finish project report", time: nil),
            TaskRow(id: UUID(), title: "Gym", time: nil)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: .now, rows: loadRows(on: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        // The second entry already holds tomorrow's list, so the rollover happens exactly at
        // midnight even if iOS runs the next refresh late.
        let now = Date.now
        let midnight = now.dayRange.upperBound
        let entries = [
            TaskEntry(date: now, rows: loadRows(on: now)),
            TaskEntry(date: midnight, rows: loadRows(on: midnight)),
        ]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    private func loadRows(on day: Date) -> [TaskRow] {
        let rows = try? SharedStore.withFreshContext { context in
            PlannerTask.openTasks(on: day, in: context)
                .prefix(5)
                .map { TaskRow(id: $0.id, title: $0.title, time: $0.time) }
        }
        return rows ?? []
    }
}

/// The star in a widget row: marks the task done in the shared store.
/// Sets it done rather than toggling, so a double tap can't undo it.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete task"
    static let isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        try SharedStore.withFreshContext { context in
            var descriptor = FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let task = try context.fetch(descriptor).first, !task.isDone {
                task.toggleDone()
            }
        }
        return .result()
    }
}

struct PlannerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskEntry

    var limit: Int { family == .systemSmall ? 3 : 5 }

    var body: some View {
        // Uses the most rows that fit, so nothing gets cropped at any widget or text size.
        ViewThatFits(in: .vertical) {
            ForEach((1...limit).reversed(), id: \.self) { list(rowCount: $0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }

    private func list(rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today").font(.headline)
            if entry.rows.isEmpty {
                Text("Nothing left to do").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(entry.rows.prefix(rowCount)) { row in
                HStack(spacing: 8) {
                    Button(intent: CompleteTaskIntent(taskID: row.id)) {
                        Image(systemName: "star")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 124.0 / 255, green: 77.0 / 255, blue: 1))
                    }
                    .buttonStyle(.plain)
                    Text(row.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if let t = row.time {
                        Text(t, style: .time)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.65, green: 0.55, blue: 0.98))
                    }
                }
            }
        }
    }
}

@main
struct PlannerWidgetExtension: Widget {
    let kind: String = "PlannerWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PlannerWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("The first tasks on your to-do list for today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    PlannerWidgetExtension()
} timeline: {
    TaskEntry(date: .now, rows: [
        TaskRow(id: UUID(), title: "Sample Task", time: .now)
    ])
}
