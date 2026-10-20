//
//  TodayView.swift
//  Starz
//
//  Created by Elen on 17.10.26.
//

import SwiftUI
import SwiftData

/// Root screen: today's tasks.
struct TodayView: View {
    /// Re-set when the date changes so the screen rolls over at midnight.
    @State private var today = Date.now
    @State private var showCalendar = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TodayContent(day: today)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Calendar", systemImage: "calendar") {
                            showCalendar = true
                        }
                    }
                }
                .navigationDestination(isPresented: $showCalendar) {
                    CalendarView()
                }
        }
        .tint(.white)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = .now }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            today = .now
        }
    }
}

/// Header, task card and "New task" button for one day.
private struct TodayContent: View {
    let day: Date
    @Query private var tasks: [PlannerTask]
    @Environment(\.modelContext) private var modelContext
    @State private var editor: EditorTarget?

    init(day: Date) {
        self.day = day
        _tasks = Query(PlannerTask.descriptor(for: day))
    }

    private var doneCount: Int { tasks.filter(\.isDone).count }
    private var isFull: Bool { tasks.count >= PlannerTask.maxPerDay }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if tasks.isEmpty {
                    emptyState
                } else {
                    TaskCard(tasks: tasks, onToggle: toggle, onEdit: { editor = .edit($0) }, onDelete: delete)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(GlowBackground())
        .safeAreaInset(edge: .bottom) {
            NewTaskButton(isFull: isFull) { editor = .new(day: day) }
        }
        .sheet(item: $editor) { target in
            TaskEditorSheet(target: target)
        }
        .sensoryFeedback(.success, trigger: doneCount) { old, new in new > old }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.subheadline.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(day.formatted(.dateTime.day().month(.wide)))
                .font(.system(size: 40, weight: .bold))
            Text(tasks.isEmpty ? "Nothing planned" : "\(doneCount) of \(tasks.count) done")
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(Color.accentPurpleLight)
            Text("A clear day")
                .font(.headline)
            Text("Tap New task to plan something.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func toggle(_ task: PlannerTask) {
        withAnimation(.snappy) {
            task.toggleDone()
        }
    }

    private func delete(_ task: PlannerTask) {
        withAnimation {
            modelContext.deleteTask(task)
        }
    }
}

/// Floating glass "New task" button. Disabled once the day is full.
struct NewTaskButton: View {
    let isFull: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isFull {
                Text("Daily limit of \(PlannerTask.maxPerDay) tasks reached")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: action) {
                Label("New task", systemImage: "plus")
                    .font(.headline)
                    .labelStyle(NewTaskLabelStyle())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .floatingGlass(in: Capsule())
            .disabled(isFull)
            .opacity(isFull ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Purple plus icon followed by white text.
private struct NewTaskLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(Color.accentPurpleLight)
            configuration.title.foregroundStyle(.white)
        }
    }
}

/// Dark rounded card listing tasks with checkboxes.
struct TaskCard: View {
    let tasks: [PlannerTask]
    let onToggle: (PlannerTask) -> Void
    let onEdit: (PlannerTask) -> Void
    let onDelete: (PlannerTask) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TaskRow(task: task, onToggle: { onToggle(task) }, onEdit: { onEdit(task) })
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { onEdit(task) }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(task) }
                    }
                if task.id != tasks.last?.id {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

/// One task: checkbox, title, optional description and optional time.
struct TaskRow: View {
    let task: PlannerTask
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                CheckCircle(isOn: task.isDone)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark as not done" : "Mark as done")

            Button(action: onEdit) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                        if !task.details.isEmpty {
                            Text(task.details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let time = task.time {
                        Text(time, format: .dateTime.hour().minute())
                            .monospacedDigit()
                            .foregroundStyle(task.isDone ? Color.secondary : Color.accentPurpleLight)
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(.vertical, 14)
                .padding(.trailing, 18)
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit task")
        }
        .padding(.leading, 4)
    }
}

/// Empty ring when open; filled white circle with a checkmark when done.
struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(.white)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .opacity(isOn ? 1 : 0)
                .scaleEffect(isOn ? 1 : 0.5)
        }
        .frame(width: 28, height: 28)
    }
}

#Preview {
    TodayView()
        .preferredColorScheme(.dark)
        .modelContainer(for: PlannerTask.self, inMemory: true)
}
