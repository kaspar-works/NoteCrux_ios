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
                Color.ncBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xxl) {
                        TaskTopBar()

                        Text("Action Items")
                            .font(.ncLargeTitle)
                            .foregroundStyle(Color.ncInk)
                            .padding(.top, NCSpacing.sm + 2)

                        AIFollowUpCard(count: aiFollowUps.count) {
                            addFollowUpsToList()
                        }

                        TaskSegmentedFilter(selection: $filter)

                        if filteredItems.isEmpty {
                            EmptyTaskCard(filter: filter) {
                                createManualTask()
                            }
                        } else {
                            VStack(spacing: NCSpacing.xxl - 2) {
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
                    .padding(.horizontal, NCSpacing.xxl - 2)
                    .padding(.top, NCSpacing.lg)
                    .padding(.bottom, 104)
                }

                Button {
                    createManualTask()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.ncPurple, in: Circle())
                        .shadow(color: Color.ncPurple.opacity(0.28), radius: NCSpacing.lg, y: NCSpacing.sm)
                }
                .padding(.trailing, NCSpacing.xl)
                .padding(.bottom, NCSpacing.lg + 2)
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
        HStack(spacing: NCSpacing.md) {
            ZStack {
                Circle()
                    .fill(NoteCruxTheme.brandGradient)

                Image(systemName: "waveform")
                    .font(.ncFootnote.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            Text("NoteCrux")
                .font(.ncTitle2.weight(.bold))
                .foregroundStyle(Color.ncInk)

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.ncMuted)
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
        NCCard {
            HStack(alignment: .top, spacing: NCSpacing.lg - 1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.ncPurple.opacity(0.12))

                    Image(systemName: "sparkles")
                        .font(.ncHeadline.bold())
                        .foregroundStyle(Color.ncPurple)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: NCSpacing.md + 2) {
                    Text("I've detected \(count) new follow-up\(count == 1 ? "" : "s") from your latest meeting. Shall I add them to your list?")
                        .font(.ncCallout.bold())
                        .lineSpacing(3)
                        .foregroundStyle(Color.ncInk)
                        .fixedSize(horizontal: false, vertical: true)

                    NCButton(title: "Add to list", action: add)
                        .disabled(count == 0)
                        .opacity(count == 0 ? 0.55 : 1)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct TaskSegmentedFilter: View {
    @Binding var selection: TaskFilter

    var body: some View {
        HStack(spacing: NCSpacing.sm + 2) {
            ForEach(TaskFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.ncCallout.bold())
                        .foregroundStyle(selection == filter ? .white : Color.ncMuted)
                        .frame(height: 38)
                        .padding(.horizontal, NCSpacing.xl - 1)
                        .background(selection == filter ? Color.ncPurple : Color.ncSurface.opacity(0.78), in: Capsule())
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
                .font(.ncCaption2)
                .tracking(1.7)
                .foregroundStyle(Color.ncMuted)

            Spacer()

            Text("\(count) task\(count == 1 ? "" : "s")")
                .font(.ncCaption1.bold())
                .foregroundStyle(Color.ncMuted)
        }
        .padding(.horizontal, NCSpacing.sm)
        .padding(.bottom, -NCSpacing.sm - 2)
    }
}

private struct TaskCardList: View {
    let items: [MeetingActionItem]

    var body: some View {
        VStack(spacing: NCSpacing.md + 2) {
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
        HStack(alignment: .top, spacing: NCSpacing.md + 2) {
            Button {
                item.isComplete.toggle()
                if item.isComplete {
                    TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                    item.notificationIdentifier = nil
                }
                save()
            } label: {
                Circle()
                    .stroke(item.isComplete ? Color.ncPurple : Color(red: 0.78, green: 0.78, blue: 0.88), lineWidth: 2)
                    .overlay {
                        if item.isComplete {
                            Image(systemName: "checkmark")
                                .font(.ncOverline)
                                .foregroundStyle(Color.ncPurple)
                        }
                    }
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: NCSpacing.sm + 1) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(.ncTitle3)
                        .foregroundStyle(Color.ncInk)
                        .strikethrough(item.isComplete)
                        .lineLimit(2)

                    Spacer()

                    PriorityPill(priority: item.priority)
                }

                Text(dueText)
                    .font(.ncFootnote.weight(.medium))
                    .foregroundStyle(Color.ncMuted)

                if let meetingTitle = item.meeting?.title, !meetingTitle.isEmpty {
                    Label(meetingTitle, systemImage: "folder.fill")
                        .font(.ncCaption1.bold())
                        .foregroundStyle(Color.ncMuted)
                        .lineLimit(1)
                } else if !item.owner.isEmpty {
                    Label(item.owner, systemImage: "person.fill")
                        .font(.ncCaption1.bold())
                        .foregroundStyle(Color.ncMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, NCSpacing.lg + 2)
        .padding(.vertical, NCSpacing.lg + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
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
            .font(.ncOverline)
            .tracking(0.7)
            .foregroundStyle(priority.color)
            .padding(.horizontal, NCSpacing.sm + 1)
            .padding(.vertical, NCSpacing.xs + 1)
            .background(priority.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct EmptyTaskCard: View {
    let filter: TaskFilter
    let add: () -> Void

    var body: some View {
        NCCard {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                Text(filter.emptyTitle)
                    .font(.ncTitle3.weight(.bold))
                    .foregroundStyle(Color.ncInk)

                Text(filter.emptyDescription)
                    .font(.ncCallout.weight(.medium))
                    .foregroundStyle(Color.ncMuted)
                    .lineSpacing(3)

                NCButton(title: "Create task", action: add)
            }
        }
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
            return Color.ncDanger
        case .medium:
            return Color.ncPurple
        case .low:
            return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }
}
