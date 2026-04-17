import SwiftData
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var actionItems: [MeetingActionItem]
    @Binding var isRecording: Bool
    @Binding var recordingInitialContext: RecordingRoomView.InitialContext?
    @StateObject private var calendarService = CalendarImportService.shared
    @State private var recoveredDraft: RecordingDraft?

    private let draftKey = "activeRecordingDraft"
    private let insightGenerator = LocalInsightGenerator()
    private let speakerLabeler = SpeakerLabeler()

    private var todaysMeetings: [Meeting] {
        meetings.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var pendingTasks: [MeetingActionItem] {
        actionItems.filter { !$0.isComplete }
    }

    private var recentHighlightsCount: Int {
        meetings.flatMap(\.highlights).count
    }

    private var recentMeetings: [Meeting] {
        Array(meetings.prefix(8))
    }

    private var followUps: [MeetingActionItem] {
        actionItems
            .filter { !$0.isComplete }
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xl) {
                        // Header
                        DashboardHeader(greeting: greeting)

                        // Quick stats row
                        HStack(spacing: NCSpacing.sm + 2) {
                            MiniStatTile(
                                icon: "calendar",
                                value: "\(todaysMeetings.count)",
                                label: "Today",
                                color: Color.ncPurple
                            )
                            MiniStatTile(
                                icon: "checklist",
                                value: "\(pendingTasks.count)",
                                label: "Tasks",
                                color: Color.ncWarning
                            )
                            MiniStatTile(
                                icon: "sparkles",
                                value: "\(recentHighlightsCount)",
                                label: "Highlights",
                                color: Color.ncSuccess
                            )
                        }

                        // Quick record CTA
                        QuickRecordCard {
                            isRecording = true
                        }

                        if let recoveredDraft {
                            RecoveryCard(draft: recoveredDraft) {
                                Task { await recover(draft: recoveredDraft) }
                            } discard: {
                                discardDraft()
                            }
                        }

                        if !followUps.isEmpty {
                            FollowUpStrip(items: followUps) { item in
                                Task { await scheduleFollowUp(for: item) }
                            }
                        }

                        agendaSection

                        // Recent meetings
                        if !recentMeetings.isEmpty {
                            VStack(alignment: .leading, spacing: NCSpacing.md) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Recent")
                                        .font(.ncTitle2)
                                        .foregroundStyle(Color.ncInk)

                                    Spacer()

                                    NavigationLink {
                                        VaultView()
                                    } label: {
                                        Text("See all")
                                            .font(.ncCaption1.bold())
                                            .foregroundStyle(Color.ncPurple)
                                    }
                                }

                                ForEach(recentMeetings) { meeting in
                                    NavigationLink {
                                        InsightView(meeting: meeting)
                                    } label: {
                                        MeetingListCard(meeting: meeting)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            EmptyStateCard {
                                isRecording = true
                            }
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 94)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            loadDraft()
            await calendarService.refresh()
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

    private func discardDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        recoveredDraft = nil
    }

    private func scheduleFollowUp(for item: MeetingActionItem) async {
        item.notificationIdentifier = await TaskReminderScheduler.scheduleFollowUp(for: item, minutesFromNow: 60)
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
                VStack(alignment: .leading, spacing: NCSpacing.md) {
                    NCSectionHeader(title: "TODAY'S AGENDA")
                    if calendarService.todaysEvents.isEmpty {
                        Text("No events today.")
                            .font(.ncFootnote)
                            .foregroundStyle(Color.ncSecondary)
                    } else {
                        ForEach(calendarService.todaysEvents) { event in
                            agendaRow(event: event)
                        }
                    }
                    if !calendarService.upcomingEvents.isEmpty {
                        Divider().padding(.top, NCSpacing.xs)
                        Text("Upcoming")
                            .font(.ncFootnote.weight(.semibold))
                            .foregroundStyle(Color.ncSecondary)
                        ForEach(calendarService.upcomingEvents.prefix(5)) { event in
                            agendaRow(event: event)
                        }
                    }
                }
                .padding(NCSpacing.lg)
                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                .ncShadow(.subtle)
            }
        case .denied:
            calendarDeniedCard
        case .notDetermined:
            EmptyView()
        }
    }

    private func agendaRow(event: CalendarEventSummary) -> some View {
        Button {
            recordingInitialContext = RecordingRoomView.InitialContext(
                title: event.title,
                tags: event.attendees
            )
            isRecording = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.ncFootnote.weight(.medium))
                    Text(Self.timeFormatter.string(from: event.startDate))
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncSecondary)
                }
                Spacer()
                Image(systemName: "mic.circle.fill")
                    .foregroundStyle(Color.ncPurple)
            }
            .padding(.vertical, NCSpacing.sm)
        }
        .buttonStyle(.plain)
    }

    private var calendarDeniedCard: some View {
        HStack(alignment: .top) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(Color.ncSecondary)
            VStack(alignment: .leading, spacing: NCSpacing.xs) {
                Text("Calendar access is off")
                    .font(.ncFootnote.weight(.semibold))
                Text("Enable calendar access in Settings to see today's agenda.")
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncSecondary)
                Button("Enable") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.ncCaption1.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
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

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.xs) {
            HStack {
                Text("NoteCrux")
                    .font(.ncCaption2)
                    .tracking(1.2)
                    .foregroundStyle(Color.ncPurple)

                Spacer()

                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncMuted)
            }

            Text(greeting)
                .font(.ncLargeTitle)
                .foregroundStyle(Color.ncInk)
        }
        .padding(.top, NCSpacing.sm)
    }
}

// MARK: - Mini Stat Tiles

private struct MiniStatTile: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: NCSpacing.sm) {
            HStack(spacing: NCSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)

                Text(value)
                    .font(.ncTitle2)
                    .foregroundStyle(Color.ncInk)
            }

            Text(label.uppercased())
                .font(.ncOverline)
                .tracking(0.6)
                .foregroundStyle(Color.ncMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.md + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

// MARK: - Quick Record CTA

private struct QuickRecordCard: View {
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            HStack(spacing: NCSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.ncPurple)
                        .frame(width: 48, height: 48)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Recording")
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)
                    Text("Tap to capture your next meeting")
                        .font(.ncFootnote)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ncMuted)
            }
            .padding(NCSpacing.lg)
            .background(
                LinearGradient(
                    colors: [Color.ncPurple.opacity(0.08), Color.ncSurface],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                    .strokeBorder(Color.ncPurple.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(NCPressButtonStyle())
    }
}

// MARK: - Meeting List Card

private struct MeetingListCard: View {
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

        return text.count > 100 ? String(text.prefix(97)) + "..." : text
    }

    private var chips: [String] {
        let base = meeting.tags.isEmpty ? ["AI Summary"] : Array(meeting.tags.prefix(2))
        if meeting.importance != .normal {
            return Array((base + [meeting.importance.rawValue]).prefix(3))
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm + 2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                    Text(meeting.title)
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(1)

                    Text("\(meeting.createdAt.dashboardDate)  ·  \(meeting.duration.dashboardDuration)")
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ncMuted)
                    .padding(.top, 4)
            }

            Text(excerpt)
                .font(.ncFootnote)
                .lineSpacing(2)
                .foregroundStyle(Color.ncSecondary)
                .lineLimit(2)

            if !chips.isEmpty {
                HStack(spacing: NCSpacing.sm) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.ncCaption2)
                            .foregroundStyle(Color.ncPurple)
                            .padding(.horizontal, NCSpacing.sm)
                            .padding(.vertical, NCSpacing.xs)
                            .background(Color.ncPurple.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

// MARK: - Empty State

private struct EmptyStateCard: View {
    let startRecording: () -> Void

    var body: some View {
        VStack(spacing: NCSpacing.lg) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ncPurple.opacity(0.5))

            VStack(spacing: NCSpacing.sm) {
                Text("No meetings yet")
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text("Record your first meeting to get AI-powered notes, summaries, and action items.")
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            Button(action: startRecording) {
                Text("Record now")
                    .font(.ncCallout.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, NCSpacing.xxl)
                    .padding(.vertical, NCSpacing.md)
                    .background(Color.ncPurple, in: Capsule())
            }
            .buttonStyle(NCPressButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.xxxl)
        .padding(.horizontal, NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

// MARK: - Follow-Up Strip

private struct FollowUpStrip: View {
    let items: [MeetingActionItem]
    let remind: (MeetingActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            NCSectionHeader(title: "PENDING FOLLOW-UPS")

            ForEach(items) { item in
                HStack(spacing: NCSpacing.sm + 2) {
                    Image(systemName: item.priority == .high ? "exclamationmark" : "checkmark")
                        .font(.ncCaption1.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.ncPurple, in: Circle())

                    Text(item.title)
                        .font(.ncFootnote.weight(.semibold))
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(1)

                    Spacer()

                    Button("Remind") {
                        remind(item)
                    }
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncPurple)
                }
            }
        }
        .padding(NCSpacing.md + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

// MARK: - Recovery Card

private struct RecoveryCard: View {
    let draft: RecordingDraft
    let recover: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm + 2) {
            NCSectionHeader(title: "UNSAVED RECORDING")

            Text(draft.title.isEmpty ? "Recovered Meeting" : draft.title)
                .font(.ncHeadline)
                .foregroundStyle(Color.ncInk)

            Text(draft.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.ncFootnote)
                .foregroundStyle(Color.ncSecondary)

            HStack {
                Button("Recover", action: recover)
                    .font(.ncFootnote.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ncPurple)

                Button("Discard", role: .destructive, action: discard)
                    .font(.ncFootnote.bold())
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NCSpacing.md + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
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
}

private extension TimeInterval {
    var dashboardDuration: String {
        let minutes = max(1, Int((self / 60).rounded()))
        return "\(minutes) MINS"
    }
}
