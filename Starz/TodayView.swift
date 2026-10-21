//
//  TodayView.swift
//  Starz
//
//  Created by Elen on 17.10.26.
//

import SwiftUI
import SwiftData

/// What the root screen shows: the day list, with or without the calendar pushed on top.
struct DayNavigation {
    /// Re-set when the date changes so the screen rolls over at midnight.
    var day = Date.now
    var showCalendar = false

    /// "This current tide": closes the calendar and shows today's list.
    mutating func showToday(now: Date = .now) {
        day = now
        showCalendar = false
    }
}

/// Root screen: today's tasks.
struct TodayView: View {
    @State private var navigation = DayNavigation()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TodayContent(day: navigation.day)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Calendar", systemImage: "calendar") {
                            navigation.showCalendar = true
                        }
                    }
                }
                .navigationDestination(isPresented: $navigation.showCalendar) {
                    CalendarView { navigation.showToday() }
                }
        }
        .tint(.white)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { navigation.day = .now }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            navigation.day = .now
        }
    }
}

/// Header, task card and "New task" button for one day.
private struct TodayContent: View {
    let day: Date
    @Query private var tasks: [PlannerTask]
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
                    TaskCard(tasks: tasks, onEdit: { editor = .edit($0) })
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

/// Dark rounded card listing tasks, used by Today and Calendar.
struct TaskCard: View {
    let tasks: [PlannerTask]
    let onEdit: (PlannerTask) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                EventRow(task: task, onEdit: { onEdit(task) })
                if task.id != tasks.last?.id {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

/// Long-press actions shared by Today and Calendar: "Make regular" and delete.
/// A copy of a regular event offers two ways to delete instead of one.
struct RegularEventMenuItems: View {
    let task: PlannerTask
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if task.seriesID == nil {
            Menu("Make regular", systemImage: "repeat") {
                Button("Every day") { modelContext.makeRegular(task, .daily) }
                Button("Every year") { modelContext.makeRegular(task, .yearly) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { modelContext.deleteTask(task) }
            }
        } else {
            Menu("Delete", systemImage: "trash") {
                Button("Only this event", role: .destructive) {
                    withAnimation { modelContext.deleteTask(task) }
                }
                Button("This regular event", role: .destructive) {
                    withAnimation { modelContext.deleteSeries(of: task) }
                }
            }
        }
    }
}

/// One task, shared by Today and Calendar: checkbox, title, optional description and time,
/// and the long-press menu. Tapping the checkbox or "Done"/"Undone" ticks and unticks it.
struct EventRow: View {
    let task: PlannerTask
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                CheckStar(isOn: task.isDone)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark as not done" : "Mark as done")

            Button(action: onEdit) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(task.title)
                                .strikethrough(task.isDone)
                                .foregroundStyle(task.isDone ? .secondary : .primary)
                            if task.seriesID != nil {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(task.recurrence == .yearly ? "Repeats every year" : "Repeats")
                            }
                        }
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
        .contextMenu {
            Button(Self.doneActionTitle(isDone: task.isDone), systemImage: task.isDone ? "star" : "star.fill", action: toggle)
            Button("Edit", systemImage: "pencil", action: onEdit)
            RegularEventMenuItems(task: task)
        }
    }

    func toggle() {
        withAnimation(.snappy) {
            task.toggleDone()
        }
    }

    /// Long-press action: "Done" for unticked items, "Undone" for ticked ones.
    static func doneActionTitle(isDone: Bool) -> String {
        isDone ? "Undone" : "Done"
    }
}

/// Purple outlined star when open; mint-filled star when done.
struct CheckStar: View {
    let isOn: Bool

    var body: some View {
        RoundedStar()
            .fill(isOn ? Color.mint : .clear)
            .overlay {
                RoundedStar()
                    .stroke(Color.accentPurple, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
        .frame(width: 32, height: 32)
    }
}

struct RoundedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.46
        let vertices = (0..<10).map { index -> CGPoint in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        let cornerRadius = outerRadius * 0.11
        let before = vertices.indices.map { index in
            point(from: vertices[index], toward: vertices[(index + 9) % 10], distance: cornerRadius)
        }
        let after = vertices.indices.map { index in
            point(from: vertices[index], toward: vertices[(index + 1) % 10], distance: cornerRadius)
        }

        var path = Path()
        path.move(to: before[0])
        for index in vertices.indices {
            path.addQuadCurve(to: after[index], control: vertices[index])
            path.addLine(to: before[(index + 1) % vertices.count])
        }
        path.closeSubpath()
        return path
    }

    private func point(from start: CGPoint, toward end: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let fraction = min(distance / length, 0.5)
        return CGPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
    }
}

#Preview {
    TodayView()
        .preferredColorScheme(.dark)
        .modelContainer(for: PlannerTask.self, inMemory: true)
}
