import SwiftData
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var actionItems: [MeetingActionItem]
    @AppStorage("selfDestructDays") private var selfDestructDays = 0
    @Binding var isRecording: Bool
    @Binding var recordingInitialContext: RecordingRoomView.InitialContext?
    @StateObject private var calendarService = CalendarImportService.shared
    @State private var recoveredDraft: RecordingDraft?
    @State private var showDeleteAllConfirmation = false
    @State private var meetingToDelete: Meeting?
    @State private var meetingToDeleteTitle = ""
    @State private var showContent = false

    private let draftKey = "activeRecordingDraft"
    private let insightGenerator = LocalInsightGenerator()
    private let speakerLabeler = SpeakerLabeler()

    private var activeMeetings: [Meeting] {
        meetings.filter { !$0.isDeleted }
    }

    private var todaysMeetings: [Meeting] {
        activeMeetings.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var pendingTasks: [MeetingActionItem] {
        actionItems.filter { !$0.isComplete && !$0.isDeleted }
    }

    private var recentHighlightsCount: Int {
        activeMeetings.flatMap(\.highlights).count
    }

    private var recentMeetings: [Meeting] {
        Array(activeMeetings.prefix(8))
    }

    private var followUps: [MeetingActionItem] {
        actionItems
            .filter { !$0.isComplete && !$0.isDeleted }
            .sorted { followUpScore($0) > followUpScore($1) }
            .prefix(3)
            .map { $0 }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private var contextualSubtitle: String {
        let taskCount = pendingTasks.count
        let meetingCount = todaysMeetings.count
        if taskCount > 0 && meetingCount > 0 {
            return "You have \(taskCount) task\(taskCount == 1 ? "" : "s") and \(meetingCount) meeting\(meetingCount == 1 ? "" : "s") today"
        } else if taskCount > 0 {
            return "You have \(taskCount) pending task\(taskCount == 1 ? "" : "s") to follow up"
        } else if meetingCount > 0 {
            return "\(meetingCount) meeting\(meetingCount == 1 ? "" : "s") recorded today"
        } else {
            return "Ready to capture your next meeting"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color.ncBackground,
                        Color.ncBackground,
                        Color.ncPurple.opacity(0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xl + 4) {
                        // Header
                        DashboardHeader(
                            greeting: greeting,
                            subtitle: contextualSubtitle
                        )
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 12)

                        // Stats row
                        HStack(spacing: NCSpacing.sm + 2) {
                            NavigationLink {
                                TodayMeetingsDetailView()
                            } label: {
                                GlassStatTile(
                                    icon: "calendar",
                                    value: "\(todaysMeetings.count)",
                                    label: "Today",
                                    accentColor: Color.ncPurple,
                                    gradient: [Color.ncPurple.opacity(0.15), Color.ncPurple.opacity(0.05)]
                                )
                            }
                            .buttonStyle(CardPressStyle())

                            NavigationLink {
                                TasksView()
                            } label: {
                                GlassStatTile(
                                    icon: "checklist",
                                    value: "\(pendingTasks.count)",
                                    label: "Tasks",
                                    accentColor: Color.ncWarning,
                                    gradient: [Color.ncWarning.opacity(0.15), Color.ncWarning.opacity(0.05)]
                                )
                            }
                            .buttonStyle(CardPressStyle())

                            NavigationLink {
                                HighlightsDetailView()
                            } label: {
                                GlassStatTile(
                                    icon: "sparkles",
                                    value: "\(recentHighlightsCount)",
                                    label: "Highlights",
                                    accentColor: Color.ncSuccess,
                                    gradient: [Color.ncSuccess.opacity(0.15), Color.ncSuccess.opacity(0.05)]
                                )
                            }
                            .buttonStyle(CardPressStyle())
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 16)

                        if let recoveredDraft {
                            RecoveryCard(draft: recoveredDraft) {
                                Task { await recover(draft: recoveredDraft) }
                            } discard: {
                                discardDraft()
                            }
                        }

                        // Follow-ups
                        if !followUps.isEmpty {
                            FollowUpSection(items: followUps) { item in
                                Task { await scheduleFollowUp(for: item) }
                            } complete: { item in
                                item.isComplete = true
                                try? modelContext.save()
                            }
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)
                        }

                        // Agenda
                        agendaSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Recent meetings
                        if !recentMeetings.isEmpty {
                            recentMeetingsSection
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 16)
                        } else {
                            EmptyStateCard {
                                isRecording = true
                            }
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 94)
                }
                .refreshable {
                    await calendarService.refresh()
                    syncWidgetData()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Delete All Meetings?", isPresented: $showDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) {
                deleteAllMeetings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(meetings.count) meetings. This cannot be undone.")
        }
        .alert("Delete Meeting?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    deleteMeeting(meeting)
                    meetingToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                meetingToDelete = nil
            }
        } message: {
            Text("This will permanently delete \"\(meetingToDeleteTitle)\" and its notes, tasks, and transcript.")
        }
        .task {
            loadDraft()
            autoDeleteExpiredMeetings()
            await calendarService.refresh()
            syncWidgetData()
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
        .onChange(of: activeMeetings.count) { _, _ in syncWidgetData() }
        .onChange(of: pendingTasks.count) { _, _ in syncWidgetData() }
        .onChange(of: calendarService.todaysEvents.count) { _, _ in syncWidgetData() }
    }

    private func syncWidgetData() {
        let nextEvent = calendarService.todaysEvents
            .first(where: { $0.startDate > Date() })
            ?? calendarService.upcomingEvents.first
        WidgetDataSync.update(
            todaysMeetingCount: todaysMeetings.count,
            pendingTasksCount: pendingTasks.count,
            nextEventTitle: nextEvent?.title,
            nextEventStart: nextEvent?.startDate
        )
    }

    // MARK: - Recent Meetings Section

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                    Text("RECENT MEETINGS")
                        .font(.ncOverline)
                        .tracking(1.4)
                        .foregroundStyle(Color.ncMuted)

                    Text("\(activeMeetings.count) total")
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncSecondary)
                }

                Spacer()

                Menu {
                    NavigationLink {
                        VaultView()
                    } label: {
                        Label("View All", systemImage: "list.bullet")
                    }

                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                } label: {
                    HStack(spacing: NCSpacing.xs) {
                        Text("View all")
                            .font(.ncCaption1.bold())
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.ncPurple)
                }
            }

            ForEach(recentMeetings) { meeting in
                NavigationLink {
                    InsightView(meeting: meeting)
                } label: {
                    PremiumMeetingCard(meeting: meeting)
                }
                .buttonStyle(CardPressStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        meetingToDeleteTitle = meeting.title
                        meetingToDelete = meeting
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Data Actions

    private func loadDraft() {
        guard let data = UserDefaults.standard.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(RecordingDraft.self, from: data),
              !draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recoveredDraft = nil
            return
        }

        recoveredDraft = draft
    }

    private func recover(draft: RecordingDraft) async {
        let transcript = draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let insights = await insightGenerator.generate(from: transcript)
        let speakerEntries = speakerLabeler.label(
            transcriptEntries: draft.transcriptEntries,
            fallbackTranscript: transcript
        )
        let meeting = Meeting(
            title: draft.title.isEmpty ? "Recovered Meeting" : draft.title,
            createdAt: draft.startedAt,
            duration: draft.elapsed,
            audioFilePath: draft.audioFilePath,
            tags: draft.tags,
            transcript: transcript,
            transcriptEntries: draft.transcriptEntries,
            speakerTranscriptEntries: speakerEntries,
            summary: insights.summary,
            paragraphNotes: insights.paragraphNotes,
            bulletSummary: insights.bulletSummary,
            highlights: insights.highlights,
            importantLines: insights.importantLines,
            quickRead: insights.quickRead,
            keyPoints: insights.keyPoints,
            decisions: insights.decisions,
            risks: insights.risks
        )

        meeting.actionItems = insights.actionItems.map { draft in
            MeetingActionItem(
                title: draft.title,
                detail: draft.detail,
                owner: draft.owner,
                deadline: draft.deadline,
                priority: draft.priority,
                reminderDate: draft.deadline,
                confidence: draft.confidence,
                sourceQuote: draft.sourceQuote,
                meeting: meeting
            )
        }

        modelContext.insert(meeting)
        Task {
            await scheduleAutomaticReminders(for: meeting.actionItems)
        }
        try? modelContext.save()
        discardDraft()
    }

    private func deleteMeeting(_ meeting: Meeting) {
        modelContext.delete(meeting)
        try? modelContext.save()
    }

    private func deleteAllMeetings() {
        for meeting in meetings {
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }

    private func discardDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        recoveredDraft = nil
    }

    private func scheduleFollowUp(for item: MeetingActionItem) async {
        item.notificationIdentifier = await TaskReminderScheduler.scheduleFollowUp(for: item, minutesFromNow: 60)
        try? modelContext.save()
    }

    private func autoDeleteExpiredMeetings() {
        guard selfDestructDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -selfDestructDays, to: Date()) ?? Date()
        let expired = meetings.filter { $0.createdAt < cutoff }
        guard !expired.isEmpty else { return }
        for meeting in expired {
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }

    private func scheduleAutomaticReminders(for items: [MeetingActionItem]) async {
        for item in items where item.reminderDate != nil || item.priority == .high {
            if item.reminderDate == nil {
                item.reminderDate = item.deadline ?? TaskReminderScheduler.snoozeDate(minutes: 60)
            }
            item.notificationIdentifier = await TaskReminderScheduler.schedule(for: item)
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private var agendaSection: some View {
        switch calendarService.authorizationState {
        case .granted:
            if calendarService.events.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("TODAY'S AGENDA")
                            .font(.ncOverline)
                            .tracking(1.4)
                            .foregroundStyle(Color.ncMuted)

                        Spacer()

                        Text("\(calendarService.todaysEvents.count) event\(calendarService.todaysEvents.count == 1 ? "" : "s")")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncSecondary)
                    }
                    .padding(.bottom, NCSpacing.md)

                    if calendarService.todaysEvents.isEmpty {
                        HStack(spacing: NCSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.ncSuccess)
                            Text("No events scheduled for today")
                                .font(.ncFootnote)
                                .foregroundStyle(Color.ncSecondary)
                        }
                        .padding(.vertical, NCSpacing.md)
                    } else {
                        // Timeline events
                        VStack(spacing: 0) {
                            ForEach(Array(calendarService.todaysEvents.enumerated()), id: \.element.id) { index, event in
                                AgendaTimelineRow(
                                    event: event,
                                    isFirst: index == 0,
                                    isLast: index == calendarService.todaysEvents.count - 1 && calendarService.upcomingEvents.isEmpty,
                                    isNext: isNextEvent(event)
                                ) {
                                    recordingInitialContext = RecordingRoomView.InitialContext(
                                        title: event.title,
                                        tags: event.attendees
                                    )
                                    isRecording = true
                                }
                            }
                        }
                    }

                    if !calendarService.upcomingEvents.isEmpty {
                        // Upcoming separator
                        HStack(spacing: NCSpacing.sm) {
                            Rectangle()
                                .fill(Color.ncDivider)
                                .frame(height: 1)
                            Text("UPCOMING")
                                .font(.ncOverline)
                                .tracking(1.0)
                                .foregroundStyle(Color.ncMuted)
                            Rectangle()
                                .fill(Color.ncDivider)
                                .frame(height: 1)
                        }
                        .padding(.vertical, NCSpacing.md)

                        VStack(spacing: 0) {
                            ForEach(Array(calendarService.upcomingEvents.prefix(4).enumerated()), id: \.element.id) { index, event in
                                AgendaTimelineRow(
                                    event: event,
                                    isFirst: index == 0,
                                    isLast: index == min(3, calendarService.upcomingEvents.count - 1),
                                    isNext: false,
                                    showDate: true
                                ) {
                                    recordingInitialContext = RecordingRoomView.InitialContext(
                                        title: event.title,
                                        tags: event.attendees
                                    )
                                    isRecording = true
                                }
                            }
                        }
                    }
                }
                .padding(NCSpacing.lg)
                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                .ncShadow(.card)
            }
        case .denied:
            calendarDeniedCard
        case .notDetermined:
            EmptyView()
        }
    }

    private func isNextEvent(_ event: CalendarEventSummary) -> Bool {
        let now = Date()
        return event.startDate > now && calendarService.todaysEvents.first(where: { $0.startDate > now })?.id == event.id
    }

    private var calendarDeniedCard: some View {
        HStack(alignment: .top, spacing: NCSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.ncWarning.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ncWarning)
            }

            VStack(alignment: .leading, spacing: NCSpacing.xs) {
                Text("Calendar access is off")
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)
                Text("Enable calendar access in Settings to see today's agenda and auto-import meetings.")
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)
                    .lineSpacing(2)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Enable in Settings")
                        .font(.ncCaption1.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, NCSpacing.md)
                        .padding(.vertical, NCSpacing.sm)
                        .background(Color.ncPurple, in: Capsule())
                }
                .padding(.top, NCSpacing.xs)
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func followUpScore(_ item: MeetingActionItem) -> Int {
        var score = 0
        if item.priority == .high { score += 100 }
        if let dueDate = item.deadline ?? item.reminderDate, dueDate < Date() { score += 80 }
        if item.meeting != nil { score += 10 }
        return score
    }
}

// MARK: - Header

private struct DashboardHeader: View {
    let greeting: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)

                    HStack(spacing: NCSpacing.sm) {
                        Text(greeting)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.ncInk)
                    }
                }

                Spacer()

                // Ask AI button
                NavigationLink {
                    AssistantView()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.ncPurple.opacity(0.15), Color.ncPurple.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)

                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.ncPurple)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(subtitle)
                .font(.ncFootnote)
                .foregroundStyle(Color.ncSecondary)
                .lineSpacing(2)
        }
        .padding(.top, NCSpacing.sm)
    }
}

// MARK: - Glass Stat Tile

private struct GlassStatTile: View {
    let icon: String
    let value: String
    let label: String
    let accentColor: Color
    let gradient: [Color]

    var body: some View {
        VStack(spacing: NCSpacing.sm + 2) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.ncInk)
                .contentTransition(.numericText(value: Double(value) ?? 0))

            Text(label.uppercased())
                .font(.ncOverline)
                .tracking(0.8)
                .foregroundStyle(Color.ncMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.md + 4)
        .background {
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSurface)
                .overlay(
                    LinearGradient(
                        colors: [accentColor.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(accentColor.opacity(0.08), lineWidth: 1)
        )
        .ncShadow(.card)
    }
}

// MARK: - Premium Meeting Card

private struct PremiumMeetingCard: View {
    let meeting: Meeting

    private var excerpt: String {
        let candidates = [
            meeting.quickRead,
            meeting.summary,
            meeting.highlights.first ?? "",
            meeting.transcript
        ]

        let text = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "No notes yet."

        return text.count > 120 ? String(text.prefix(117)) + "..." : text
    }

    private var chips: [String] {
        let base = meeting.tags.isEmpty ? ["AI Summary"] : Array(meeting.tags.prefix(2))
        if meeting.importance != .normal {
            return Array((base + [meeting.importance.rawValue]).prefix(3))
        }
        return base
    }

    private var chipColor: Color {
        switch meeting.importance {
        case .critical: return Color.ncDanger
        case .important: return Color.ncWarning
        case .normal: return Color.ncPurple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            // Top row: title + chevron
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NCSpacing.xs + 1) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(1)

                    HStack(spacing: NCSpacing.sm) {
                        HStack(spacing: NCSpacing.xs) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .medium))
                            Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)

                        Text("·")
                            .foregroundStyle(Color.ncMuted)

                        Text(meeting.duration.dashboardDuration)
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ncMuted.opacity(0.6))
                    .padding(.top, 4)
            }

            // Excerpt
            Text(excerpt)
                .font(.ncFootnote)
                .lineSpacing(3)
                .foregroundStyle(Color.ncSecondary)
                .lineLimit(2)

            // Bottom row: chips + action count
            HStack(spacing: NCSpacing.sm) {
                if !meeting.actionItems.isEmpty {
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(meeting.actionItems.count)")
                            .font(.ncCaption2.weight(.bold))
                    }
                    .foregroundStyle(Color.ncPurple)
                    .padding(.horizontal, NCSpacing.sm + 2)
                    .padding(.vertical, NCSpacing.xs + 1)
                    .background(Color.ncPurple.opacity(0.08), in: Capsule())
                }

                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.ncCaption2)
                        .foregroundStyle(chip == meeting.importance.rawValue && meeting.importance != .normal ? chipColor : Color.ncPurple)
                        .padding(.horizontal, NCSpacing.sm + 2)
                        .padding(.vertical, NCSpacing.xs + 1)
                        .background(
                            (chip == meeting.importance.rawValue && meeting.importance != .normal ? chipColor : Color.ncPurple).opacity(0.08),
                            in: Capsule()
                        )
                }

                Spacer()

                // Waveform hint
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.ncPurple.opacity(0.25))
                            .frame(width: 2, height: CGFloat([4, 8, 12, 6, 9][i]))
                    }
                }
            }
        }
        .padding(NCSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSurface)
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [chipColor.opacity(0.06), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 60)
                    .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 0.5)
        )
        .ncShadow(.card)
    }
}

// MARK: - Agenda Timeline Row

private struct AgendaTimelineRow: View {
    let event: CalendarEventSummary
    let isFirst: Bool
    let isLast: Bool
    let isNext: Bool
    var showDate: Bool = false
    let onRecord: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.md) {
            // Timeline
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color.ncDivider)
                        .frame(width: 1.5)
                        .frame(height: 8)
                }

                // Dot
                ZStack {
                    if isNext {
                        Circle()
                            .fill(Color.ncPurple.opacity(0.15))
                            .frame(width: 16, height: 16)
                    }
                    Circle()
                        .fill(isNext ? Color.ncPurple : Color.ncMuted.opacity(0.4))
                        .frame(width: 8, height: 8)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.ncDivider)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)

            // Content
            Button(action: onRecord) {
                HStack {
                    VStack(alignment: .leading, spacing: NCSpacing.xs) {
                        Text(event.title)
                            .font(.ncFootnote.weight(.semibold))
                            .foregroundStyle(isNext ? Color.ncInk : Color.ncSecondary)
                            .lineLimit(1)

                        HStack(spacing: NCSpacing.xs) {
                            if showDate {
                                Text(event.startDate.relativeDay)
                                    .font(.ncCaption1)
                                    .foregroundStyle(Color.ncPurple.opacity(0.8))
                                Text("·")
                                    .font(.ncCaption1)
                                    .foregroundStyle(Color.ncMuted)
                            }
                            Text(Self.timeFormatter.string(from: event.startDate))
                                .font(.ncCaption1)
                                .foregroundStyle(Color.ncMuted)
                        }
                    }

                    Spacer()

                    if isNext {
                        HStack(spacing: NCSpacing.xs) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Record")
                                .font(.ncCaption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, NCSpacing.sm + 2)
                        .padding(.vertical, NCSpacing.xs + 2)
                        .background(Color.ncPurple, in: Capsule())
                    } else {
                        Image(systemName: "mic.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.ncPurple.opacity(0.5))
                    }
                }
                .padding(.vertical, NCSpacing.sm + 2)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 48)
    }
}

// MARK: - Follow-Up Section

private struct FollowUpSection: View {
    let items: [MeetingActionItem]
    let remind: (MeetingActionItem) -> Void
    let complete: (MeetingActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack {
                Text("PENDING FOLLOW-UPS")
                    .font(.ncOverline)
                    .tracking(1.4)
                    .foregroundStyle(Color.ncMuted)

                Spacer()

                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncSecondary)
            }

            ForEach(items) { item in
                FollowUpCard(item: item, remind: { remind(item) }, complete: { complete(item) })
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
    }
}

private struct FollowUpCard: View {
    let item: MeetingActionItem
    let remind: () -> Void
    let complete: () -> Void

    private var priorityColor: Color {
        switch item.priority {
        case .high: return Color.ncDanger
        case .medium: return Color.ncWarning
        case .low: return Color.ncSuccess
        }
    }

    private var iconName: String {
        if item.priority == .high { return "exclamationmark.triangle.fill" }
        if item.deadline != nil { return "calendar.badge.clock" }
        return "arrow.turn.down.right"
    }

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            // Priority indicator
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(priorityColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(priorityColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.ncFootnote.weight(.semibold))
                    .foregroundStyle(Color.ncInk)
                    .lineLimit(1)

                if let deadline = item.deadline {
                    Text("Due \(deadline.formatted(date: .abbreviated, time: .omitted))")
                        .font(.ncCaption1)
                        .foregroundStyle(deadline < Date() ? Color.ncDanger : Color.ncMuted)
                } else if let meeting = item.meeting {
                    Text("From: \(meeting.title)")
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: NCSpacing.sm) {
                Button(action: complete) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ncSuccess)
                        .frame(width: 28, height: 28)
                        .background(Color.ncSuccess.opacity(0.10), in: Circle())
                }

                Button(action: remind) {
                    Text("Remind")
                        .font(.ncCaption2)
                        .foregroundStyle(Color.ncPurple)
                        .padding(.horizontal, NCSpacing.sm + 2)
                        .padding(.vertical, NCSpacing.xs + 2)
                        .background(Color.ncPurple.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(.vertical, NCSpacing.xs)
    }
}

// MARK: - Empty State

private struct EmptyStateCard: View {
    let startRecording: () -> Void

    @State private var glowPulsing = false

    var body: some View {
        VStack(spacing: NCSpacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.06))
                    .frame(width: 100, height: 100)
                    .scaleEffect(glowPulsing ? 1.08 : 0.95)

                Circle()
                    .fill(Color.ncPurple.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.ncPurple.opacity(0.7))
            }

            VStack(spacing: NCSpacing.sm) {
                Text("No meetings yet")
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text("Record your first meeting to get\nAI-powered notes and action items.")
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button(action: startRecording) {
                HStack(spacing: NCSpacing.sm) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start Recording")
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

// MARK: - Recovery Card

private struct RecoveryCard: View {
    let draft: RecordingDraft
    let recover: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ncWarning.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ncWarning)
            }

            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                Text("Unsaved Recording")
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text(draft.title.isEmpty ? "Recovered Meeting" : draft.title)
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)

                Text(draft.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncMuted)

                HStack(spacing: NCSpacing.sm) {
                    Button(action: recover) {
                        HStack(spacing: NCSpacing.xs) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                            Text("Recover")
                                .font(.ncCaption1.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, NCSpacing.md)
                        .padding(.vertical, NCSpacing.sm)
                        .background(Color.ncPurple, in: Capsule())
                    }

                    Button(action: discard) {
                        Text("Discard")
                            .font(.ncCaption1.bold())
                            .foregroundStyle(Color.ncDanger)
                            .padding(.horizontal, NCSpacing.md)
                            .padding(.vertical, NCSpacing.sm)
                            .background(Color.ncDanger.opacity(0.08), in: Capsule())
                    }
                }
            }

            Spacer()
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncWarning.opacity(0.2), lineWidth: 1)
        )
        .ncShadow(.card)
    }
}

// MARK: - Card Press Style

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Formatters

private extension Date {
    var dashboardDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: self).uppercased()
    }

    var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }
}

private extension TimeInterval {
    var dashboardDuration: String {
        let minutes = max(1, Int((self / 60).rounded()))
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Today's Meetings Detail

private struct TodayMeetingsDetailView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    private var todaysMeetings: [Meeting] {
        meetings.filter { !$0.isDeleted && Calendar.current.isDateInToday($0.createdAt) }
    }

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NCSpacing.md) {
                    if todaysMeetings.isEmpty {
                        VStack(spacing: NCSpacing.md) {
                            Image(systemName: "calendar")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(Color.ncMuted)
                            Text("No meetings today")
                                .font(.ncHeadline)
                                .foregroundStyle(Color.ncSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ForEach(todaysMeetings) { meeting in
                            NavigationLink {
                                InsightView(meeting: meeting)
                            } label: {
                                PremiumMeetingCard(meeting: meeting)
                            }
                            .buttonStyle(CardPressStyle())
                        }
                    }
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.vertical, NCSpacing.md)
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Highlights Detail

private struct HighlightsDetailView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    private var activeMeetings: [Meeting] {
        meetings.filter { !$0.isDeleted }
    }

    private var highlightEntries: [HighlightEntry] {
        activeMeetings.flatMap { meeting in
            meeting.highlights.map { HighlightEntry(meeting: meeting, text: $0) }
        }
    }

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NCSpacing.sm + 2) {
                    if highlightEntries.isEmpty {
                        VStack(spacing: NCSpacing.md) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(Color.ncMuted)
                            Text("No highlights yet")
                                .font(.ncHeadline)
                                .foregroundStyle(Color.ncSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ForEach(highlightEntries) { entry in
                            NavigationLink {
                                InsightView(meeting: entry.meeting)
                            } label: {
                                HighlightEntryCard(text: entry.text, meetingTitle: entry.meeting.title, createdAt: entry.meeting.createdAt)
                            }
                            .buttonStyle(CardPressStyle())
                        }
                    }
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.vertical, NCSpacing.md)
            }
        }
        .navigationTitle("Highlights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct HighlightEntry: Identifiable {
    let id = UUID()
    let meeting: Meeting
    let text: String
}

private struct HighlightEntryCard: View {
    let text: String
    let meetingTitle: String
    let createdAt: Date

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ncSuccess.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ncSuccess)
            }

            VStack(alignment: .leading, spacing: NCSpacing.xs) {
                Text(text)
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: NCSpacing.xs) {
                    Text(meetingTitle)
                        .font(.ncCaption1.weight(.semibold))
                        .foregroundStyle(Color.ncPurple)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(Color.ncMuted)
                    Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ncMuted.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 0.5)
        )
        .ncShadow(.card)
    }
}
