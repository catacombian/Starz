//
//  PlannerWidgetExtension.swift
//  PlannerWidgetExtension
//
//  Created by Elen on 20/10/2026.
//

import WidgetKit
import SwiftUI
import SwiftData

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
        completion(TaskEntry(date: .now, rows: loadRows()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = TaskEntry(date: .now, rows: loadRows())
        let tomorrow = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)
        ) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }

    private func loadRows() -> [TaskRow] {
        let config = ModelConfiguration(
            groupContainer: .identifier("group.com.manhutava.Starz")
        )
        guard let container = try? ModelContainer(for: PlannerTask.self, configurations: config) else {
            return []
        }
        let context = ModelContext(container)
        let start = Calendar.current.startOfDay(for: .now)
        
        // Fetch tasks using an explicit predicate descriptor
        let descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { (task: PlannerTask) in
                task.day == start && task.isDone == false
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        let tasks = (try? context.fetch(descriptor)) ?? []
        return tasks
            .sorted { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
            .prefix(5)
            .map { TaskRow(id: $0.id, title: $0.title, time: $0.time) }
    }
}

struct PlannerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TaskEntry

    var limit: Int { family == .systemSmall ? 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today").font(.headline)
            if entry.rows.isEmpty {
                Text("Nothing left to do").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(entry.rows.prefix(limit)) { row in
                HStack(spacing: 8) {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                    Text(row.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if let t = row.time {
                        Text(t, style: .time)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.65, green: 0.55, blue: 0.98))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.black, for: .widget)
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
