//
//  TaskEditorSheet.swift
//  Starz
//

import SwiftUI
import SwiftData

/// What the editor sheet is showing: a new task for a day, or an existing task.
enum EditorTarget: Identifiable {
    case new(day: Date)
    case edit(PlannerTask)

    var id: String {
        switch self {
        case .new(let day): "new-\(day.timeIntervalSince1970)"
        case .edit(let task): task.id.uuidString
        }
    }
}

/// Bottom sheet for adding or editing a task.
struct TaskEditorSheet: View {
    let target: EditorTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var details = ""
    @State private var hasTime = false
    @State private var time = Date.now
    @State private var errorMessage: String?

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new(let day):
            _time = State(initialValue: Self.suggestedTime(for: day))
        case .edit(let task):
            _title = State(initialValue: task.title)
            _details = State(initialValue: task.details)
            _hasTime = State(initialValue: task.time != nil)
            _time = State(initialValue: task.time ?? Self.suggestedTime(for: task.day))
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var day: Date {
        switch target {
        case .new(let day): day
        case .edit(let task): task.day
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            topBar

            field("Title", required: true) {
                TextField("What do you need to do?", text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .padding(16)
                    .fieldBackground()
            }

            field("Description (optional)") {
                TextField("Add details", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(16)
                    .frame(minHeight: 100, alignment: .topLeading)
                    .fieldBackground()
            }

            field("Time (optional)") {
                VStack(alignment: .leading, spacing: 12) {
                    timeRow
                    if hasTime {
                        reminderNote
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            if case .edit(let task) = target {
                Button("Delete task", systemImage: "trash", role: .destructive) {
                    delete(task)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .presentationDetents([.large])
        .presentationCornerRadius(40)
        .glassSheetBackground()
        .onAppear {
            if isNew { titleFocused = true }
        }
        .onChange(of: hasTime) { _, isOn in
            if isOn { Reminders.requestPermission() }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(Color.accentPurpleLight)
                .frame(minWidth: 44, minHeight: 44)
            Spacer()
            Button(isNew ? "Add" : "Save", action: save)
                .font(.headline)
                .controlSize(.large)
                .prominentGlassButton()
                .disabled(trimmedTitle.isEmpty)
        }
        .overlay {
            Text(isNew ? "New task" : "Edit task")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var timeRow: some View {
        HStack(spacing: 12) {
            Text("Remind me")
            Spacer()
            if hasTime {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Toggle("Remind me", isOn: $hasTime.animation(.snappy))
                .labelsHidden()
                .tint(.accentPurple)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .fieldBackground()
    }

    /// "Reminders at 13:00 and 13:50", leaving out reminders that are already in the past.
    private var reminderNote: some View {
        let dates = Reminders.fireDates(for: time.onDay(day))
        let times = dates.map { $0.formatted(date: .omitted, time: .shortened) }
        let text = switch times.count {
        case 0: "Too late for reminders"
        case 1: "Reminder at \(times[0])"
        default: "Reminders at \(times[0]) and \(times[1])"
        }
        return Label(text, systemImage: dates.isEmpty ? "bell.slash" : "bell")
            .font(.subheadline)
            .foregroundStyle(Color.accentPurpleLight)
            .padding(.leading, 4)
    }

    /// Small uppercase caption above a form field.
    private func field(_ label: String, required: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                if required {
                    Text("*").foregroundStyle(Color.accentPurpleLight)
                }
            }
            .font(.footnote.weight(.medium))
            .tracking(1)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)

            content()
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let taskTime = hasTime ? time.onDay(day) : nil

        switch target {
        case .new(let day):
            let count = (try? modelContext.fetchCount(PlannerTask.descriptor(for: day))) ?? 0
            guard count < PlannerTask.maxPerDay else {
                errorMessage = "This day already has \(PlannerTask.maxPerDay) tasks."
                return
            }
            let task = PlannerTask(title: trimmedTitle, details: details, day: day, time: taskTime)
            modelContext.insert(task)
            Reminders.update(for: task)
        case .edit(let task):
            task.title = trimmedTitle
            task.details = details
            task.time = taskTime
            Reminders.update(for: task)
        }
        dismiss()
    }

    private func delete(_ task: PlannerTask) {
        modelContext.deleteTask(task)
        dismiss()
    }

    /// Next full hour today, or 09:00 on other days.
    private static func suggestedTime(for day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day),
           let nextHour = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime),
           calendar.isDateInToday(nextHour) {
            return nextHour
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}

private extension View {
    /// Dark rounded field background from the mockup.
    func fieldBackground() -> some View {
        background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
