import SwiftData
import SwiftUI

struct TaskChecklistRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: MeetingActionItem
    var showsMeetingTitle = false

    @State private var hasReminder = false

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(alignment: .top, spacing: NCSpacing.sm + 2) {
                Button {
                    item.isComplete.toggle()
                    if item.isComplete {
                        TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                        item.notificationIdentifier = nil
                    }
                    save()
                } label: {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.ncTitle3)
                        .foregroundStyle(item.isComplete ? Color.ncSuccess : Color.ncSecondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: NCSpacing.sm) {
                    TextField("Task title", text: $item.title, axis: .vertical)
                        .font(.ncHeadline)
                        .strikethrough(item.isComplete)
                        .onSubmit { save() }

                    TextField("Owner", text: $item.owner)
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncSecondary)
                        .onSubmit { save() }

                    if showsMeetingTitle, let title = item.meeting?.title {
                        Text(title)
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncSecondary)
                    }
                }
            }

            TextField("Details", text: $item.detail, axis: .vertical)
                .font(.ncCallout)
                .foregroundStyle(Color.ncSecondary)
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
                .font(.ncCallout)
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
                .font(.ncCallout)

                HStack {
                    Button("Schedule") {
                        Task { await scheduleReminder() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ncSuccess)

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
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncSecondary)
                }

                Spacer()
            }
        }
        .padding(NCSpacing.md)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small))
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
            .font(.ncCaption1.bold())
            .padding(.horizontal, NCSpacing.sm)
            .padding(.vertical, NCSpacing.xs)
            .foregroundStyle(priority == .high ? .black : .primary)
            .background(color.opacity(priority == .high ? 1 : 0.18), in: RoundedRectangle(cornerRadius: NCRadius.small))
    }

    private var color: Color {
        switch priority {
        case .high:
            return Color.ncWarning
        case .medium:
            return Color.ncSuccess
        case .low:
            return Color.ncMuted
        }
    }
}
