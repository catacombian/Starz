//
//  CalendarView.swift
//  Starz
//

import SwiftUI
import SwiftData

/// Month calendar: browse months and tap a day to see its tasks.
struct CalendarView: View {
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    /// First day of the month being shown.
    @State private var month = Date.now.startOfMonth
    @State private var editor: EditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                monthHeader
                MonthGrid(month: month, selectedDay: $selectedDay)
                    .simultaneousGesture(swipeBetweenMonths)
                    .sensoryFeedback(.selection, trigger: selectedDay)
                DayTasks(day: selectedDay, onEdit: { editor = .edit($0) })
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(GlowBackground())
        .safeAreaInset(edge: .bottom) {
            if selectedDay >= Calendar.current.startOfDay(for: .now) {
                DayNewTaskButton(day: selectedDay) { editor = .new(day: selectedDay) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { goToToday() }
                    .font(.headline)
            }
        }
        .sheet(item: $editor) { target in
            TaskEditorSheet(target: target)
        }
        .onChange(of: selectedDay) { _, day in
            // Tapping a grey day from a neighbouring month jumps to that month.
            withAnimation(.snappy) { month = day.startOfMonth }
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 34, weight: .bold))
                .contentTransition(.numericText())
            Spacer()
            HStack(spacing: 12) {
                GlassIconButton(systemImage: "chevron.left", label: "Previous month") { showMonth(offset: -1) }
                GlassIconButton(systemImage: "chevron.right", label: "Next month") { showMonth(offset: 1) }
            }
        }
        .padding(.leading, 8)
    }

    private var swipeBetweenMonths: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let width = value.translation.width
            // Only react to mostly-horizontal swipes so vertical scrolling still works.
            guard abs(width) > 50, abs(width) > abs(value.translation.height) * 2 else { return }
            showMonth(offset: width < 0 ? 1 : -1)
        }
    }

    private func showMonth(offset: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: offset, to: month) else { return }
        withAnimation(.snappy) { month = newMonth }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            selectedDay = Calendar.current.startOfDay(for: .now)
            month = Date.now.startOfMonth
        }
    }
}

/// Weekday header plus a grid of days with status dots.
private struct MonthGrid: View {
    let month: Date
    @Binding var selectedDay: Date
    /// All tasks in the visible weeks, including grey days of neighbouring months.
    @Query private var tasks: [PlannerTask]

    private let days: [Date]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(month: Date, selectedDay: Binding<Date>) {
        self.month = month
        _selectedDay = selectedDay
        days = Self.gridDays(for: month)
        let range = days.first!..<days.last!.dayRange.upperBound
        _tasks = Query(PlannerTask.descriptor(in: range))
    }

    var body: some View {
        let statuses = dayStatuses()

        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.footnote.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    DayCell(
                        day: day,
                        isInMonth: Calendar.current.isDate(day, equalTo: month, toGranularity: .month),
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                        status: statuses[day]
                    ) {
                        selectedDay = day
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// For each day with tasks: true when all of them are done.
    private func dayStatuses() -> [Date: Bool] {
        Dictionary(grouping: tasks) { Calendar.current.startOfDay(for: $0.day) }
            .mapValues { dayTasks in dayTasks.allSatisfy(\.isDone) }
    }

    /// Weekday initials in the user's locale order, e.g. MON … SUN.
    private static var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols.map { $0.uppercased() }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Whole weeks covering the month, starting on the locale's first weekday.
    private static func gridDays(for month: Date) -> [Date] {
        let calendar = Calendar.current
        let firstOfMonth = month.startOfMonth
        let dayCount = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let leading = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        let total = Int((Double(leading + dayCount) / 7).rounded(.up)) * 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth)!
        return (0..<total).map { calendar.date(byAdding: .day, value: $0, to: gridStart)! }
    }
}

/// One day number with an optional status dot.
private struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let isSelected: Bool
    /// nil = no tasks, false = some open, true = all done.
    let status: Bool?
    let action: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day())
                    .font(.title3.weight(isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .opacity(status == nil ? 0 : 1)
            }
            .padding(.top, 6)
            .frame(width: 44, height: 44)
            .background {
                if isSelected {
                    Circle()
                        .fill(Color.accentPurple)
                        .shadow(color: Color.accentPurple.opacity(0.6), radius: 12)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentPurpleLight }
        return isInMonth ? .white : .white.opacity(0.3)
    }

    private var dotColor: Color {
        if isSelected { return .white }
        return status == true ? .mint : .accentPurpleLight
    }

    private var accessibilityText: String {
        let date = day.formatted(date: .complete, time: .omitted)
        switch status {
        case nil: return date
        case false?: return "\(date), tasks open"
        case true?: return "\(date), all tasks done"
        }
    }
}

/// Header and task list for the selected day.
private struct DayTasks: View {
    let day: Date
    let onEdit: (PlannerTask) -> Void
    @Query private var tasks: [PlannerTask]
    @Environment(\.modelContext) private var modelContext

    init(day: Date, onEdit: @escaping (PlannerTask) -> Void) {
        self.day = day
        self.onEdit = onEdit
        _tasks = Query(PlannerTask.descriptor(for: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title3.weight(.bold))
                Spacer()
                Text(tasks.count == 1 ? "1 task" : "\(tasks.count) tasks")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            if tasks.isEmpty {
                Text("No tasks")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        CalendarTaskRow(task: task) { onEdit(task) }
                            .contextMenu {
                                Button(task.isDone ? "Mark as not done" : "Mark as done", systemImage: "checkmark.circle") {
                                    withAnimation { task.toggleDone() }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    withAnimation { modelContext.deleteTask(task) }
                                }
                            }
                        if task.id != tasks.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
    }
}

/// Task row with the time on the left, as in the calendar mockup.
private struct CalendarTaskRow: View {
    let task: PlannerTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Group {
                    if let time = task.time {
                        Text(time, format: .dateTime.hour().minute())
                    } else {
                        Text("–")
                    }
                }
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(task.isDone ? Color.secondary : Color.accentPurpleLight)
                .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    if !task.details.isEmpty {
                        Text(task.details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if task.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.mint)
                        .accessibilityLabel("Done")
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "New task" button for a day in the calendar, aware of the daily limit.
private struct DayNewTaskButton: View {
    let day: Date
    let action: () -> Void
    @Query private var tasks: [PlannerTask]

    init(day: Date, action: @escaping () -> Void) {
        self.day = day
        self.action = action
        _tasks = Query(PlannerTask.descriptor(for: day))
    }

    var body: some View {
        NewTaskButton(isFull: tasks.count >= PlannerTask.maxPerDay, action: action)
    }
}

extension Date {
    /// First moment of this date's month.
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
    .preferredColorScheme(.dark)
    .modelContainer(for: PlannerTask.self, inMemory: true)
}
