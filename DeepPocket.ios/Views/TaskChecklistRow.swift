import SwiftData
import SwiftUI

struct TaskChecklistRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: MeetingActionItem
    var showsMeetingTitle = false

    @State private var hasReminder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    item.isComplete.toggle()
                    if item.isComplete {
                        TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                        item.notificationIdentifier = nil
                    }
                    save()
                } label: {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isComplete ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Task title", text: $item.title, axis: .vertical)
                        .font(.headline)
                        .strikethrough(item.isComplete)
                        .onSubmit { save() }

                    TextField("Owner", text: $item.owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onSubmit { save() }

                    if showsMeetingTitle, let title = item.meeting?.title {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TextField("Details", text: $item.detail, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .onSubmit { save() }

            HStack {
                Picker("Priority", selection: $item.priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.rawValue).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: item.priority) { _, _ in save() }
            }

            Toggle("Reminder", isOn: $hasReminder)
                .font(.subheadline)
                .onChange(of: hasReminder) { _, enabled in
                    if enabled {
                        item.reminderDate = item.reminderDate ?? item.deadline ?? TaskReminderScheduler.snoozeDate(minutes: 60)
                    } else {
                        TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                        item.notificationIdentifier = nil
                        item.reminderDate = nil
                    }
                    save()
                }

            if hasReminder {
                DatePicker(
                    "Alert",
                    selection: Binding(
                        get: { item.reminderDate ?? TaskReminderScheduler.snoozeDate(minutes: 60) },
                        set: { newDate in
                            item.reminderDate = newDate
                            item.deadline = item.deadline ?? newDate
                            save()
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)

                HStack {
                    Button("Schedule") {
                        Task { await scheduleReminder() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Snooze 1h") {
                        item.reminderDate = TaskReminderScheduler.snoozeDate(minutes: 60)
                        Task { await scheduleReminder() }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            HStack {
                PriorityBadge(priority: item.priority)

                if let deadline = item.deadline {
                    Label(deadline.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            hasReminder = item.reminderDate != nil || item.deadline != nil
        }
    }

    private func scheduleReminder() async {
        if item.reminderDate == nil {
            item.reminderDate = item.deadline ?? TaskReminderScheduler.snoozeDate(minutes: 60)
        }

        item.notificationIdentifier = await TaskReminderScheduler.schedule(for: item)
        save()
    }

    private func save() {
        try? modelContext.save()
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.rawValue)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(priority == .high ? .black : .primary)
            .background(color.opacity(priority == .high ? 1 : 0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch priority {
        case .high:
            return .yellow
        case .medium:
            return .green
        case .low:
            return .gray
        }
    }
}
