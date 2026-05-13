import SwiftData
import SwiftUI

struct TaskChecklistRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: MeetingActionItem
    var showsMeetingTitle = false

    @State private var hasReminder = false
    @State private var checkScale: CGFloat = 1.0

    private var accentColor: Color {
        switch item.priority {
        case .high: return Color.ncDanger
        case .medium: return Color.ncWarning
        case .low: return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(alignment: .top, spacing: NCSpacing.md) {
                // Animated checkbox
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        checkScale = 1.3
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            checkScale = 1.0
                        }
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        item.isComplete.toggle()
                        if item.isComplete {
                            TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                            item.notificationIdentifier = nil
                        }
                        save()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(item.isComplete ? Color.ncSuccess : Color.clear)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        item.isComplete ? Color.ncSuccess : accentColor.opacity(0.5),
                                        lineWidth: 2
                                    )
                            )

                        if item.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .scaleEffect(checkScale)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: NCSpacing.sm) {
                    TextField("Task title", text: $item.title, axis: .vertical)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.isComplete ? Color.ncMuted : Color.ncInk)
                        .strikethrough(item.isComplete, color: Color.ncMuted)
                        .onSubmit { save() }

                    HStack(spacing: NCSpacing.sm) {
                        if !item.owner.isEmpty && item.owner != "Unassigned" {
                            HStack(spacing: NCSpacing.xs) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(item.owner)
                                    .font(.ncCaption1)
                            }
                            .foregroundStyle(Color.ncMuted)
                        }

                        if showsMeetingTitle, let title = item.meeting?.title {
                            HStack(spacing: NCSpacing.xs) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(title)
                                    .font(.ncCaption1)
                            }
                            .foregroundStyle(Color.ncMuted)
                            .lineLimit(1)
                        }
                    }
                }
            }

            // Detail
            if !item.detail.isEmpty || item.isComplete == false {
                TextField("Details", text: $item.detail, axis: .vertical)
                    .font(.ncCallout)
                    .foregroundStyle(Color.ncSecondary)
                    .onSubmit { save() }
                    .padding(.leading, 36)
            }

            // Priority + Metadata
            HStack(spacing: NCSpacing.sm) {
                PriorityBadge(priority: item.priority)

                Picker("", selection: $item.priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.rawValue).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .onChange(of: item.priority) { _, _ in save() }
            }
            .padding(.leading, 36)

            // Reminder
            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                Toggle(isOn: $hasReminder) {
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.ncWarning)
                        Text("Reminder")
                            .font(.ncCallout)
                    }
                }
                .tint(Color.ncPurple)
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
                    .tint(Color.ncPurple)

                    HStack(spacing: NCSpacing.sm) {
                        Button {
                            Task { await scheduleReminder() }
                        } label: {
                            HStack(spacing: NCSpacing.xs) {
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Schedule")
                                    .font(.ncCaption1.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, NCSpacing.md)
                            .padding(.vertical, NCSpacing.sm)
                            .background(Color.ncSuccess, in: Capsule())
                        }

                        Button {
                            item.reminderDate = TaskReminderScheduler.snoozeDate(minutes: 60)
                            Task { await scheduleReminder() }
                        } label: {
                            Text("Snooze 1h")
                                .font(.ncCaption1.bold())
                                .foregroundStyle(Color.ncPurple)
                                .padding(.horizontal, NCSpacing.md)
                                .padding(.vertical, NCSpacing.sm)
                                .background(Color.ncPurple.opacity(0.08), in: Capsule())
                        }

                        Spacer()
                    }
                }

                if let deadline = item.deadline {
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                        Text(deadline.formatted(date: .abbreviated, time: .shortened))
                            .font(.ncCaption1)
                    }
                    .foregroundStyle(Color.ncSecondary)
                }
            }
            .padding(.leading, 36)
        }
        .padding(NCSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSurface)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.isComplete ? Color.ncMuted.opacity(0.3) : accentColor)
                        .frame(width: 3)
                        .padding(.vertical, NCSpacing.sm)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
        .opacity(item.isComplete ? 0.7 : 1.0)
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

    private var color: Color {
        switch priority {
        case .high: return Color.ncDanger
        case .medium: return Color.ncWarning
        case .low: return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }

    private var label: String {
        switch priority {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, NCSpacing.sm)
            .padding(.vertical, NCSpacing.xs)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.15), lineWidth: 0.5))
    }
}
