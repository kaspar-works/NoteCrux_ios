import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingActionItem.title) private var actionItems: [MeetingActionItem]
    @State private var filter: TaskFilter = .pending
    @State private var showAddSheet = false
    @State private var editingItem: MeetingActionItem?
    @State private var showContent = false
    @State private var recentlyDeleted: MeetingActionItem?
    @State private var showUndoBar = false
    @State private var undoTimer: Task<Void, Never>?
    @State private var showPaywall = false

    private var allActive: [MeetingActionItem] {
        actionItems.filter { !$0.isDeleted }
    }

    private var filteredItems: [MeetingActionItem] {
        allActive
            .filter { item in
                switch filter {
                case .all: return true
                case .pending: return !item.isComplete
                case .completed: return item.isComplete
                }
            }
            .sorted(by: taskSort)
    }

    private var pendingItems: [MeetingActionItem] {
        allActive.filter { !$0.isComplete }
    }

    private var completedItems: [MeetingActionItem] {
        allActive.filter { $0.isComplete }
    }

    private var aiFollowUps: [MeetingActionItem] {
        pendingItems
            .filter { $0.confidence != .low || $0.priority == .high || $0.deadline != nil || $0.reminderDate != nil }
            .sorted(by: taskSort)
    }

    private var overdueItems: [MeetingActionItem] {
        pendingItems.filter { item in
            guard let date = item.deadline ?? item.reminderDate else { return false }
            return date < Date()
        }
    }

    private var highPriorityToday: [MeetingActionItem] {
        pendingItems.filter { $0.priority == .high && taskDay($0) == .today }
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

    private var contextBanner: String? {
        let overdue = overdueItems.count
        let highToday = highPriorityToday.count
        if overdue > 0 {
            return "\(overdue) task\(overdue == 1 ? "" : "s") overdue — take action"
        } else if highToday > 0 {
            return "You have \(highToday) high-priority task\(highToday == 1 ? "" : "s") today"
        } else if pendingItems.isEmpty && !completedItems.isEmpty {
            return "All caught up — great work!"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.ncBackground, Color.ncBackground, Color.ncPurple.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xl + 2) {
                        // Header
                        TaskPageHeader()
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 12)

                        // Context banner
                        if let banner = contextBanner {
                            ContextBannerView(text: banner, isOverdue: !overdueItems.isEmpty)
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 12)
                        }

                        // AI suggestion
                        if aiFollowUps.count > 0 {
                            AIFollowUpCard(count: aiFollowUps.count, add: {
                                addFollowUpsToList()
                            }, review: {
                                withAnimation(.ncSpring) { filter = .pending }
                            })
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)
                        }

                        // Filters
                        TaskSegmentedFilter(
                            selection: $filter,
                            allCount: allActive.count,
                            pendingCount: pendingItems.count,
                            completedCount: completedItems.count
                        )
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 16)

                        // Task list
                        if filteredItems.isEmpty {
                            EmptyTaskCard(filter: filter) {
                                showAddSheet = true
                            }
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)
                        } else {
                            VStack(spacing: NCSpacing.xl + 4) {
                                if !todayItems.isEmpty {
                                    taskSection(title: "TODAY", items: todayItems)
                                }
                                if !tomorrowItems.isEmpty {
                                    taskSection(title: "TOMORROW", items: tomorrowItems)
                                }
                                if !laterItems.isEmpty {
                                    taskSection(title: "LATER", items: laterItems)
                                }
                            }
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 110)
                }

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showAddSheet = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                    .shadow(color: Color.ncPurple.opacity(0.35), radius: 16, y: 6)

                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(FABPressStyle())
                        .padding(.trailing, NCSpacing.xl)
                        .padding(.bottom, NCSpacing.lg)
                        .accessibilityLabel("Add task")
                    }
                }

                // Undo bar
                if showUndoBar {
                    UndoSnackbar {
                        undoDelete()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 80)
                    .zIndex(10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddSheet) {
                AddTaskSheet { title, detail, owner, priority, deadline, hasReminder in
                    createTask(
                        title: title,
                        detail: detail,
                        owner: owner,
                        priority: priority,
                        deadline: deadline,
                        hasReminder: hasReminder
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingItem) { item in
                EditTaskSheet(item: item)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func taskSection(title: String, items: [MeetingActionItem]) -> some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack {
                Text(title)
                    .font(.ncOverline)
                    .tracking(1.4)
                    .foregroundStyle(Color.ncMuted)

                Spacer()

                Text("\(items.count)")
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncPurple)
                    .frame(width: 20, height: 20)
                    .background(Color.ncPurple.opacity(0.10), in: Circle())
            }

            ForEach(items) { item in
                PremiumTaskCard(
                    item: item,
                    onToggle: { toggleComplete(item) },
                    onTap: { editingItem = item },
                    onDelete: { deleteItem(item) }
                )
            }
        }
    }

    // MARK: - Actions

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
        if Calendar.current.isDateInToday(date) || date < Date() { return .today }
        if Calendar.current.isDateInTomorrow(date) { return .tomorrow }
        return .later
    }

    private func toggleComplete(_ item: MeetingActionItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            item.isComplete.toggle()
            if item.isComplete {
                TaskReminderScheduler.cancel(identifier: item.notificationIdentifier)
                item.notificationIdentifier = nil
            }
            try? modelContext.save()
        }
    }

    private func deleteItem(_ item: MeetingActionItem) {
        undoTimer?.cancel()
        recentlyDeleted = item

        withAnimation(.easeOut(duration: 0.3)) {
            showUndoBar = true
        }

        modelContext.delete(item)
        try? modelContext.save()

        undoTimer = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        showUndoBar = false
                        recentlyDeleted = nil
                    }
                }
            }
        }
    }

    private func undoDelete() {
        undoTimer?.cancel()
        if let item = recentlyDeleted {
            let restored = MeetingActionItem(
                title: item.title,
                detail: item.detail,
                owner: item.owner,
                deadline: item.deadline,
                priority: item.priority,
                reminderDate: item.reminderDate,
                confidence: item.confidence,
                sourceQuote: item.sourceQuote,
                isComplete: item.isComplete
            )
            modelContext.insert(restored)
            try? modelContext.save()
        }
        withAnimation {
            showUndoBar = false
            recentlyDeleted = nil
        }
    }

    private func createTask(title: String, detail: String, owner: String, priority: TaskPriority, deadline: Date?, hasReminder: Bool) {
        let item = MeetingActionItem(
            title: title,
            detail: detail,
            owner: owner.isEmpty ? "Me" : owner,
            deadline: deadline,
            priority: priority,
            reminderDate: hasReminder ? (deadline ?? TaskReminderScheduler.snoozeDate(minutes: 60)) : nil,
            confidence: .medium
        )
        modelContext.insert(item)
        try? modelContext.save()
        if hasReminder {
            Task {
                item.notificationIdentifier = await TaskReminderScheduler.schedule(for: item)
                try? modelContext.save()
            }
        }
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

// MARK: - Page Header

private struct TaskPageHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.ncCaption1)
                .foregroundStyle(Color.ncMuted)

            Text("Action Items")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.ncInk)
        }
        .padding(.top, NCSpacing.sm)
    }
}

// MARK: - Context Banner

private struct ContextBannerView: View {
    let text: String
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: NCSpacing.sm) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "brain.head.profile.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOverdue ? Color.ncDanger : Color.ncPurple)

            Text(text)
                .font(.ncFootnote.weight(.medium))
                .foregroundStyle(Color.ncInk)

            Spacer()
        }
        .padding(.horizontal, NCSpacing.md)
        .padding(.vertical, NCSpacing.sm + 2)
        .background(
            (isOverdue ? Color.ncDanger : Color.ncPurple).opacity(0.06),
            in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                .strokeBorder((isOverdue ? Color.ncDanger : Color.ncPurple).opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - AI Follow-Up Card

private struct AIFollowUpCard: View {
    let count: Int
    let add: () -> Void
    let review: () -> Void
    @State private var glowPulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.10))
                    .frame(width: 40, height: 40)
                    .scaleEffect(glowPulsing ? 1.12 : 1.0)

                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ncPurple)
            }

            VStack(alignment: .leading, spacing: NCSpacing.md) {
                Text("\(count) follow-up\(count == 1 ? "" : "s") found from your meetings")
                    .font(.ncFootnote.weight(.semibold))
                    .lineSpacing(2)
                    .foregroundStyle(Color.ncInk)

                HStack(spacing: NCSpacing.sm) {
                    Button(action: add) {
                        HStack(spacing: NCSpacing.xs) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add all")
                                .font(.ncCaption1.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, NCSpacing.md)
                        .padding(.vertical, NCSpacing.sm)
                        .background(Color.ncPurple, in: Capsule())
                    }

                    Button(action: review) {
                        Text("Review first")
                            .font(.ncCaption1.bold())
                            .foregroundStyle(Color.ncPurple)
                            .padding(.horizontal, NCSpacing.md)
                            .padding(.vertical, NCSpacing.sm)
                            .background(Color.ncPurple.opacity(0.08), in: Capsule())
                    }
                }
                .disabled(count == 0)
                .opacity(count == 0 ? 0.5 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncPurple.opacity(0.10), lineWidth: 1)
        )
        .ncShadow(.card)
        .task {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
        }
    }
}

// MARK: - Segmented Filter

private struct TaskSegmentedFilter: View {
    @Binding var selection: TaskFilter
    let allCount: Int
    let pendingCount: Int
    let completedCount: Int
    @Namespace private var filterAnimation

    private func count(for filter: TaskFilter) -> Int {
        switch filter {
        case .all: return allCount
        case .pending: return pendingCount
        case .completed: return completedCount
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TaskFilter.allCases) { filter in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection = filter
                    }
                } label: {
                    HStack(spacing: NCSpacing.xs) {
                        Text(filter.rawValue)
                            .font(.ncCallout.bold())

                        if count(for: filter) > 0 {
                            Text("\(count(for: filter))")
                                .font(.ncCaption2)
                                .foregroundStyle(selection == filter ? .white.opacity(0.8) : Color.ncMuted)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(
                                    selection == filter ? Color.white.opacity(0.2) : Color.ncDivider,
                                    in: Circle()
                                )
                        }
                    }
                    .foregroundStyle(selection == filter ? .white : Color.ncMuted)
                    .frame(height: 38)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selection == filter {
                            Capsule()
                                .fill(Color.ncPurple)
                                .matchedGeometryEffect(id: "filter_bg", in: filterAnimation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.ncSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Premium Task Card

private struct PremiumTaskCard: View {
    @Bindable var item: MeetingActionItem
    let onToggle: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var checkScale: CGFloat = 1.0

    private var isOverdue: Bool {
        guard !item.isComplete, let date = item.deadline ?? item.reminderDate else { return false }
        return date < Date()
    }

    private var isDueSoon: Bool {
        guard !item.isComplete, !isOverdue, let date = item.deadline ?? item.reminderDate else { return false }
        return date.timeIntervalSinceNow < 3600 * 3
    }

    private var accentColor: Color {
        if isOverdue { return Color.ncDanger }
        switch item.priority {
        case .high: return Color.ncDanger
        case .medium: return Color.ncWarning
        case .low: return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.isComplete ? Color.ncMuted.opacity(0.3) : accentColor)
                    .frame(width: 3)
                    .padding(.vertical, NCSpacing.sm)

                HStack(alignment: .top, spacing: NCSpacing.md) {
                    // Checkbox
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            checkScale = 1.3
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                checkScale = 1.0
                            }
                        }
                        onToggle()
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

                    // Content
                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        HStack(alignment: .top) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(item.isComplete ? Color.ncMuted : Color.ncInk)
                                .strikethrough(item.isComplete, color: Color.ncMuted)
                                .lineLimit(2)

                            Spacer()

                            PremiumPriorityPill(priority: item.priority, isComplete: item.isComplete)
                        }

                        // Due info
                        HStack(spacing: NCSpacing.sm) {
                            if isOverdue {
                                HStack(spacing: NCSpacing.xs) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Overdue")
                                        .font(.ncCaption2)
                                }
                                .foregroundStyle(Color.ncDanger)
                            } else if isDueSoon {
                                HStack(spacing: NCSpacing.xs) {
                                    Image(systemName: "clock.badge.exclamationmark")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Due soon")
                                        .font(.ncCaption2)
                                }
                                .foregroundStyle(Color.ncWarning)
                            }

                            if let date = item.deadline ?? item.reminderDate {
                                HStack(spacing: NCSpacing.xs) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10, weight: .medium))
                                    Text(dueText(date))
                                        .font(.ncCaption1)
                                }
                                .foregroundStyle(item.isComplete ? Color.ncMuted.opacity(0.6) : Color.ncMuted)
                            }
                        }

                        // Bottom metadata
                        HStack(spacing: NCSpacing.sm) {
                            if !item.owner.isEmpty && item.owner != "Unassigned" {
                                HStack(spacing: NCSpacing.xs) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(item.owner)
                                        .font(.ncCaption1)
                                }
                                .foregroundStyle(Color.ncMuted)
                                .lineLimit(1)
                            }

                            if let meetingTitle = item.meeting?.title, !meetingTitle.isEmpty {
                                HStack(spacing: NCSpacing.xs) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(meetingTitle)
                                        .font(.ncCaption1)
                                }
                                .foregroundStyle(Color.ncMuted)
                                .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.leading, NCSpacing.md)
                .padding(.trailing, NCSpacing.lg)
                .padding(.vertical, NCSpacing.lg)
            }
            .background {
                RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                    .fill(Color.ncSurface)
                    .overlay(alignment: .leading) {
                        if isOverdue && !item.isComplete {
                            LinearGradient(
                                colors: [Color.ncDanger.opacity(0.04), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 80)
                            .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                    .strokeBorder(
                        isOverdue && !item.isComplete ? Color.ncDanger.opacity(0.15) : Color.ncDivider.opacity(0.4),
                        lineWidth: 0.5
                    )
            )
            .ncShadow(.card)
            .opacity(item.isComplete ? 0.7 : 1.0)
        }
        .buttonStyle(TaskCardPressStyle())
        .contextMenu {
            Button { onTap() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func dueText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Premium Priority Pill

private struct PremiumPriorityPill: View {
    let priority: TaskPriority
    let isComplete: Bool

    private var color: Color {
        if isComplete { return Color.ncMuted }
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

// MARK: - Empty State

private struct EmptyTaskCard: View {
    let filter: TaskFilter
    let add: () -> Void
    @State private var glowPulsing = false

    var body: some View {
        VStack(spacing: NCSpacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.06))
                    .frame(width: 88, height: 88)
                    .scaleEffect(glowPulsing ? 1.08 : 0.95)

                Circle()
                    .fill(Color.ncPurple.opacity(0.12))
                    .frame(width: 60, height: 60)

                Image(systemName: filter == .completed ? "checkmark.circle" : "checklist")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.ncPurple.opacity(0.7))
            }

            VStack(spacing: NCSpacing.sm) {
                Text(filter.emptyTitle)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text(filter.emptyDescription)
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 240)
            }

            if filter != .completed {
                Button(action: add) {
                    HStack(spacing: NCSpacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Add Task")
                            .font(.ncCallout.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, NCSpacing.xxl)
                    .padding(.vertical, NCSpacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color.ncPurple.opacity(0.3), radius: 12, y: 4)
                }
                .buttonStyle(NCPressButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.xxxl)
        .padding(.horizontal, NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
        .task {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
        }
    }
}

// MARK: - Add Task Sheet

private struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, String, TaskPriority, Date?, Bool) -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var owner = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var hasReminder = false
    @State private var shakeOffset: CGFloat = 0
    @State private var showTitleError = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xl + 4) {
                        // Title field
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("TASK TITLE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            TextField("What needs to be done?", text: $title, axis: .vertical)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.ncInk)
                                .focused($titleFocused)
                                .padding(NCSpacing.md)
                                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                        .strokeBorder(showTitleError ? Color.ncDanger.opacity(0.5) : Color.ncDivider.opacity(0.5), lineWidth: 1)
                                )
                                .offset(x: shakeOffset)
                                .onChange(of: title) { _, _ in
                                    if showTitleError { showTitleError = false }
                                }
                        }

                        // Priority
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("PRIORITY")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            HStack(spacing: NCSpacing.sm) {
                                ForEach(TaskPriority.allCases) { p in
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            priority = p
                                        }
                                    } label: {
                                        Text(p.rawValue)
                                            .font(.ncCallout.bold())
                                            .foregroundStyle(priority == p ? .white : priorityColor(p))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                priority == p ? priorityColor(p) : priorityColor(p).opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                                    .strokeBorder(priorityColor(p).opacity(priority == p ? 0 : 0.2), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Due date
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Toggle(isOn: $hasDueDate.animation(.spring(response: 0.3, dampingFraction: 0.7))) {
                                HStack(spacing: NCSpacing.sm) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.ncPurple)
                                    Text("Due Date & Time")
                                        .font(.ncHeadline)
                                        .foregroundStyle(Color.ncInk)
                                }
                            }
                            .tint(Color.ncPurple)

                            if hasDueDate {
                                DatePicker(
                                    "",
                                    selection: $dueDate,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.graphical)
                                .tint(Color.ncPurple)
                                .padding(NCSpacing.sm)
                                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            }
                        }

                        // Reminder
                        if hasDueDate {
                            Toggle(isOn: $hasReminder) {
                                HStack(spacing: NCSpacing.sm) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.ncWarning)
                                    Text("Set Reminder")
                                        .font(.ncHeadline)
                                        .foregroundStyle(Color.ncInk)
                                }
                            }
                            .tint(Color.ncPurple)
                            .transition(.opacity)
                        }

                        // Assignee
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("ASSIGNEE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            HStack(spacing: NCSpacing.sm) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.ncMuted)

                                TextField("Who is responsible?", text: $owner)
                                    .font(.ncBody)
                                    .foregroundStyle(Color.ncInk)
                            }
                            .padding(NCSpacing.md)
                            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                    .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                            )
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("NOTES")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            TextField("Additional details...", text: $detail, axis: .vertical)
                                .font(.ncBody)
                                .foregroundStyle(Color.ncInk)
                                .lineLimit(3...6)
                                .padding(NCSpacing.md)
                                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                        .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 100)
                }

                // Bottom button
                VStack {
                    Spacer()
                    Button(action: submit) {
                        Text("Create Task")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(
                                    colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                            )
                            .shadow(color: Color.ncPurple.opacity(0.3), radius: 12, y: 4)
                    }
                    .buttonStyle(NCPressButtonStyle())
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.bottom, NCSpacing.lg)
                    .background(
                        LinearGradient(
                            colors: [Color.ncBackground.opacity(0), Color.ncBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .offset(y: -40),
                        alignment: .top
                    )
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ncMuted)
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showTitleError = true
            shakeField()
            return
        }
        onCreate(trimmed, detail, owner, priority, hasDueDate ? dueDate : nil, hasReminder)
        dismiss()
    }

    private func shakeField() {
        withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { shakeOffset = 0 }
        }
    }

    private func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .high: return Color.ncDanger
        case .medium: return Color.ncWarning
        case .low: return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }
}

// MARK: - Edit Task Sheet

private struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: MeetingActionItem

    @State private var hasReminder: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xl + 4) {
                        // Title
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("TASK TITLE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            TextField("Task title", text: $item.title, axis: .vertical)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.ncInk)
                                .padding(NCSpacing.md)
                                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                        .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                                )
                        }

                        // Priority
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("PRIORITY")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            HStack(spacing: NCSpacing.sm) {
                                ForEach(TaskPriority.allCases) { p in
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            item.priority = p
                                        }
                                    } label: {
                                        Text(p.rawValue)
                                            .font(.ncCallout.bold())
                                            .foregroundStyle(item.priority == p ? .white : editPriorityColor(p))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                item.priority == p ? editPriorityColor(p) : editPriorityColor(p).opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                                    .strokeBorder(editPriorityColor(p).opacity(item.priority == p ? 0 : 0.2), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Due date
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            HStack(spacing: NCSpacing.sm) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.ncPurple)
                                Text("Due Date")
                                    .font(.ncHeadline)
                                    .foregroundStyle(Color.ncInk)
                            }

                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { item.deadline ?? Date() },
                                    set: { item.deadline = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .tint(Color.ncPurple)
                            .padding(NCSpacing.sm)
                            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                        }

                        // Reminder
                        Toggle(isOn: $hasReminder) {
                            HStack(spacing: NCSpacing.sm) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.ncWarning)
                                Text("Reminder")
                                    .font(.ncHeadline)
                                    .foregroundStyle(Color.ncInk)
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
                            try? modelContext.save()
                        }

                        if hasReminder {
                            HStack(spacing: NCSpacing.sm) {
                                Button {
                                    Task {
                                        item.notificationIdentifier = await TaskReminderScheduler.schedule(for: item)
                                        try? modelContext.save()
                                    }
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
                                    Task {
                                        item.notificationIdentifier = await TaskReminderScheduler.schedule(for: item)
                                        try? modelContext.save()
                                    }
                                } label: {
                                    Text("Snooze 1h")
                                        .font(.ncCaption1.bold())
                                        .foregroundStyle(Color.ncPurple)
                                        .padding(.horizontal, NCSpacing.md)
                                        .padding(.vertical, NCSpacing.sm)
                                        .background(Color.ncPurple.opacity(0.08), in: Capsule())
                                }
                            }
                            .transition(.opacity)
                        }

                        // Assignee
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("ASSIGNEE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            HStack(spacing: NCSpacing.sm) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.ncMuted)

                                TextField("Owner", text: $item.owner)
                                    .font(.ncBody)
                                    .foregroundStyle(Color.ncInk)
                            }
                            .padding(NCSpacing.md)
                            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                    .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                            )
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("DETAILS")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            TextField("Details", text: $item.detail, axis: .vertical)
                                .font(.ncBody)
                                .foregroundStyle(Color.ncInk)
                                .lineLimit(3...6)
                                .padding(NCSpacing.md)
                                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                        .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                                )
                        }

                        // Source quote
                        if !item.sourceQuote.isEmpty {
                            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                                Text("SOURCE QUOTE")
                                    .font(.ncOverline)
                                    .tracking(1.4)
                                    .foregroundStyle(Color.ncMuted)

                                HStack(alignment: .top, spacing: NCSpacing.sm) {
                                    Rectangle()
                                        .fill(Color.ncPurple.opacity(0.4))
                                        .frame(width: 3)

                                    Text("\"\(item.sourceQuote)\"")
                                        .font(.ncFootnote)
                                        .italic()
                                        .foregroundStyle(Color.ncSecondary)
                                        .lineSpacing(2)
                                }
                                .padding(NCSpacing.md)
                                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncPurple)
                }
            }
            .onAppear {
                hasReminder = item.reminderDate != nil || item.deadline != nil
            }
        }
    }

    private func editPriorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .high: return Color.ncDanger
        case .medium: return Color.ncWarning
        case .low: return Color(red: 0.31, green: 0.55, blue: 0.70)
        }
    }
}

// MARK: - Undo Snackbar

private struct UndoSnackbar: View {
    let undo: () -> Void

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            Image(systemName: "trash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ncDanger)

            Text("Task deleted")
                .font(.ncFootnote.weight(.semibold))
                .foregroundStyle(Color.ncInk)

            Spacer()

            Button(action: undo) {
                Text("Undo")
                    .font(.ncCaption1.bold())
                    .foregroundStyle(Color.ncPurple)
                    .padding(.horizontal, NCSpacing.md)
                    .padding(.vertical, NCSpacing.sm)
                    .background(Color.ncPurple.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
        )
        .ncShadow(.elevated)
        .padding(.horizontal, NCSpacing.lg)
    }
}

// MARK: - Button Styles

private struct FABPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct TaskCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Enums

private enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Done"

    var id: String { rawValue }

    var emptyTitle: String {
        switch self {
        case .all: return "No tasks yet"
        case .pending: return "All caught up!"
        case .completed: return "Nothing completed yet"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: return "Start by adding your first action item or record a meeting to get AI-generated tasks."
        case .pending: return "No pending tasks right now. Record a meeting or add one manually."
        case .completed: return "Completed tasks will appear here as you check them off."
        }
    }
}

private enum TaskDay {
    case today
    case tomorrow
    case later
}
