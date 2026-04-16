import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingActionItem.title) private var actionItems: [MeetingActionItem]
    @State private var filter: TaskFilter = .all

    private var filteredItems: [MeetingActionItem] {
        actionItems
            .filter { item in
                switch filter {
                case .all:
                    return true
                case .pending:
                    return !item.isComplete
                case .completed:
                    return item.isComplete
                }
            }
            .sorted(by: taskSort)
    }

    private var pendingItems: [MeetingActionItem] {
        actionItems.filter { !$0.isComplete }
    }

    private var aiFollowUps: [MeetingActionItem] {
        pendingItems
            .filter { $0.confidence != .low || $0.priority == .high || $0.deadline != nil || $0.reminderDate != nil }
            .sorted(by: taskSort)
    }

    private var todayItems: [MeetingActionItem] {
        filteredItems.filter { taskDay($0) == .today }
    }

    private var tomorrowItems: [MeetingActionItem] {
        filteredItems.filter { taskDay($0) == .tomorrow }
    }

    private var laterItems: [MeetingActionItem] {
        filteredItems.filter { taskDay($0) == .later }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.taskScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        TaskTopBar()

                        Text("Action Items")
                            .font(.system(size: 31, weight: .bold))
                            .foregroundStyle(Color.taskInk)
                            .padding(.top, 10)

                        AIFollowUpCard(count: aiFollowUps.count) {
                            addFollowUpsToList()
                        }

                        TaskSegmentedFilter(selection: $filter)

                        if filteredItems.isEmpty {
                            EmptyTaskCard(filter: filter) {
                                createManualTask()
                            }
                        } else {
                            VStack(spacing: 22) {
                                TaskSectionHeader(title: "TODAY", count: todayItems.count)
                                TaskCardList(items: todayItems)

                                TaskSectionHeader(title: "TOMORROW", count: tomorrowItems.count)
                                TaskCardList(items: tomorrowItems)

                                if !laterItems.isEmpty {
                                    TaskSectionHeader(title: "LATER", count: laterItems.count)
                                    TaskCardList(items: laterItems)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 104)
                }

                Button {
                    createManualTask()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.taskPurple, in: Circle())
                        .shadow(color: Color.taskPurple.opacity(0.28), radius: 16, y: 8)
                }
                .padding(.trailing, 21)
                .padding(.bottom, 18)
                .accessibilityLabel("Add task")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func taskSort(_ lhs: MeetingActionItem, _ rhs: MeetingActionItem) -> Bool {
        if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
        let lhsDate = lhs.deadline ?? lhs.reminderDate ?? .distantFuture
        let rhsDate = rhs.deadline ?? rhs.reminderDate ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return priorityScore(lhs.priority) > priorityScore(rhs.priority)
    }

    private func priorityScore(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    private func taskDay(_ item: MeetingActionItem) -> TaskDay {
        guard let date = item.deadline ?? item.reminderDate else { return .later }
        if Calendar.current.isDateInToday(date) { return .today }
        if Calendar.current.isDateInTomorrow(date) { return .tomorrow }
        return .later
    }

    private func createManualTask() {
        let item = MeetingActionItem(
            title: "New action item",
            detail: "Tap into a meeting to edit details.",
            owner: "Me",
            deadline: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
            priority: .medium,
            reminderDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
            confidence: .medium
        )
        modelContext.insert(item)
        try? modelContext.save()
        filter = .pending
    }

    private func addFollowUpsToList() {
        for item in aiFollowUps {
            if item.reminderDate == nil {
                item.reminderDate = item.deadline ?? TaskReminderScheduler.snoozeDate(minutes: 60)
            }
        }
        try? modelContext.save()
        filter = .pending
    }
}

private struct TaskTopBar: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.42, blue: 0.43), Color(red: 0.97, green: 0.72, blue: 0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            Text("DeepPocket")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.taskInk)

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.taskMuted)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AIFollowUpCard: View {
    let count: Int
    let add: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.taskPurple.opacity(0.12))

                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.taskPurple)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 14) {
                Text("I've detected \(count) new follow-up\(count == 1 ? "" : "s") from your latest meeting. Shall I add them to your list?")
                    .font(.system(size: 14, weight: .semibold))
                    .lineSpacing(3)
                    .foregroundStyle(Color.taskInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: add) {
                    Text("Add to list")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.taskPurple, in: Capsule())
                        .shadow(color: Color.taskPurple.opacity(0.24), radius: 10, y: 5)
                }
                .disabled(count == 0)
                .opacity(count == 0 ? 0.55 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background(Color.taskSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 8)
    }
}

private struct TaskSegmentedFilter: View {
    @Binding var selection: TaskFilter

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TaskFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selection == filter ? .white : Color.taskMuted)
                        .frame(height: 38)
                        .padding(.horizontal, 19)
                        .background(selection == filter ? Color.taskPurple : Color.taskSurface.opacity(0.78), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TaskSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(Color.taskMuted)

            Spacer()

            Text("\(count) task\(count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.taskMuted)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, -10)
    }
}

private struct TaskCardList: View {
    let items: [MeetingActionItem]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(items) { item in
                CompactTaskCard(item: item)
            }
        }
    }
}

private struct CompactTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: MeetingActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                item.isComplete.toggle()
                if item.isComplete {
                    TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                    item.notificationIdentifier = nil
                }
                save()
            } label: {
                Circle()
                    .stroke(item.isComplete ? Color.taskPurple : Color(red: 0.78, green: 0.78, blue: 0.88), lineWidth: 2)
                    .overlay {
                        if item.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.taskPurple)
                        }
                    }
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.taskInk)
                        .strikethrough(item.isComplete)
                        .lineLimit(2)

                    Spacer()

                    PriorityPill(priority: item.priority)
                }

                Text(dueText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.taskMuted)

                if let meetingTitle = item.meeting?.title, !meetingTitle.isEmpty {
                    Label(meetingTitle, systemImage: "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.taskMuted)
                        .lineLimit(1)
                } else if !item.owner.isEmpty {
                    Label(item.owner, systemImage: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.taskMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color.taskSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 16, y: 7)
    }

    private var dueText: String {
        guard let date = item.deadline ?? item.reminderDate else {
            return "No due time"
        }

        if Calendar.current.isDateInToday(date) {
            return "Due Today, \(date.formatted(date: .omitted, time: .shortened))"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func save() {
        try? modelContext.save()
    }
}

private struct PriorityPill: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.shortLabel)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(priority.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(priority.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct EmptyTaskCard: View {
    let filter: TaskFilter
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.emptyTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.taskInk)

            Text(filter.emptyDescription)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.taskMuted)
                .lineSpacing(3)

            Button(action: add) {
                Text("Create task")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.taskPurple, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.taskSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 8)
    }
}

private enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"

    var id: String { rawValue }

    var emptyTitle: String {
        switch self {
        case .all: return "No action items yet"
        case .pending: return "No pending tasks"
        case .completed: return "No completed tasks"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: return "Record a meeting or add a task manually to start building your list."
        case .pending: return "Open meeting tasks will appear here after notes are generated."
        case .completed: return "Completed checklist items will appear here."
        }
    }
}

private enum TaskDay {
    case today
    case tomorrow
    case later
}

private extension TaskPriority {
    var shortLabel: String {
        switch self {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        }
    }

    var color: Color {
        switch self {
        case .high:
            return Color(red: 0.83, green: 0.20, blue: 0.28)
        case .medium:
            return Color.taskPurple
        case .low:
            return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }
}

private extension Color {
    static let taskScreenBackground = Color.adaptive(light: (0.978, 0.978, 0.986), dark: (0.055, 0.056, 0.072))
    static let taskSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let taskInk = Color.adaptive(light: (0.14, 0.14, 0.16), dark: (0.93, 0.94, 0.97))
    static let taskMuted = Color.adaptive(light: (0.57, 0.57, 0.64), dark: (0.62, 0.64, 0.72))
    static let taskPurple = Color.adaptive(light: (0.25, 0.18, 0.86), dark: (0.58, 0.50, 1.0))
}
