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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.ncBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.lg + 2) {
                        DashboardHeader()

                        VStack(spacing: NCSpacing.md) {
                            NCMetricCard(
                                title: "TODAY'S MEETINGS",
                                value: "\(todaysMeetings.count)",
                                isPrimary: true
                            )
                            NCMetricCard(
                                title: "PENDING TASKS",
                                value: "\(pendingTasks.count)",
                                isPrimary: false
                            )
                            NCMetricCard(
                                title: "RECENT HIGHLIGHTS",
                                value: "\(recentHighlightsCount)",
                                isPrimary: false
                            )
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

                        HStack(alignment: .firstTextBaseline) {
                            Text("Recent Meetings")
                                .font(.ncTitle2)
                                .foregroundStyle(Color.ncInk)

                            Spacer()

                            NavigationLink {
                                VaultView()
                            } label: {
                                Text("View all")
                                    .font(.ncCaption1.bold())
                                    .foregroundStyle(Color.ncPurple)
                            }
                        }
                        .padding(.top, 6)

                        if recentMeetings.isEmpty {
                            EmptyRecentMeetingCard {
                                isRecording = true
                            }
                        } else {
                            VStack(spacing: NCSpacing.lg + 2) {
                                ForEach(Array(recentMeetings.enumerated()), id: \.element.id) { index, meeting in
                                    NavigationLink {
                                        InsightView(meeting: meeting)
                                    } label: {
                                        MeetingPreviewCard(meeting: meeting, index: index)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md + 2)
                    .padding(.bottom, 94)
                }

                Button {
                    isRecording = true
                } label: {
                    Label("Record Meeting", systemImage: "mic.fill")
                        .font(.ncCallout.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, NCSpacing.lg + 2)
                        .padding(.vertical, NCSpacing.md + 1)
                        .background(Color.ncPurple, in: Capsule())
                        .shadow(color: Color.ncPurple.opacity(0.25), radius: 14, y: 8)
                }
                .padding(.trailing, NCSpacing.lg + 2)
                .padding(.bottom, NCSpacing.lg)
                .accessibilityLabel("Record meeting")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            loadDraft()
            await calendarService.refresh()
        }
    }

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
                    Text("Today's agenda")
                        .font(.ncHeadline)
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
                .background(Color.ncSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium))
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
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 6)
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
        .background(Color.ncSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium))
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

private struct DashboardHeader: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WELCOME BACK")
                    .font(.ncOverline)
                    .tracking(0.8)
                    .foregroundStyle(Color.ncMuted)

                Text("Good morning,")
                    .font(.ncTitle3)
                    .foregroundStyle(Color.ncInk)

                Text("Bistro")
                    .font(.ncTitle3)
                    .foregroundStyle(Color.ncInk)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.ncPurple, Color(red: 0.98, green: 0.70, blue: 0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("B")
                    .font(.ncCallout.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 33, height: 33)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .ncShadow(.subtle)
        }
    }
}

private struct MeetingPreviewCard: View {
    let meeting: Meeting
    let index: Int

    private var excerpt: String {
        let candidates = [
            meeting.quickRead,
            meeting.summary,
            meeting.highlights.first ?? "",
            meeting.transcript
        ]

        let text = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "No notes yet. Open this meeting to review transcript and AI output."

        return text.count > 112 ? String(text.prefix(109)) + "..." : text
    }

    private var chips: [String] {
        let base = meeting.tags.isEmpty ? ["AI Summary"] : Array(meeting.tags.prefix(2))
        if meeting.importance != .normal {
            return Array((base + [meeting.importance.rawValue]).prefix(3))
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetingThumbnail(index: index)
                .frame(height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                Text("\(meeting.createdAt.dashboardDate)  •  \(meeting.duration.dashboardDuration)")
                    .font(.ncOverline)
                    .tracking(0.6)
                    .foregroundStyle(Color.ncMuted)

                Text(meeting.title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)
                    .lineLimit(1)

                Text(excerpt)
                    .font(.ncFootnote)
                    .lineSpacing(2)
                    .foregroundStyle(Color.ncSecondary)
                    .lineLimit(3)

                HStack(spacing: 7) {
                    ForEach(chips, id: \.self) { chip in
                        NCChip(label: chip, color: chipColor(chip))
                    }
                }
            }
            .padding(NCSpacing.md + 2)
        }
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
    }

    private func chipColor(_ chip: String) -> Color {
        let colors: [Color] = [
            .ncPurple,
            Color(red: 0.20, green: 0.53, blue: 0.83),
            Color(red: 0.84, green: 0.33, blue: 0.31),
            Color(red: 0.14, green: 0.56, blue: 0.43)
        ]
        let sum = chip.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }
}

private struct MeetingThumbnail: View {
    let index: Int

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.10, green: 0.18, blue: 0.20), Color(red: 0.83, green: 0.91, blue: 0.91)],
            [Color(red: 0.77, green: 0.70, blue: 0.55), Color(red: 0.96, green: 0.95, blue: 0.80)],
            [Color(red: 0.11, green: 0.33, blue: 0.38), Color(red: 0.92, green: 0.86, blue: 0.70)],
            [Color(red: 0.21, green: 0.28, blue: 0.30), Color(red: 0.76, green: 0.87, blue: 0.93)]
        ]
        return palettes[index % palettes.count]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)

                ForEach(0..<6, id: \.self) { column in
                    Rectangle()
                        .fill(.white.opacity(column.isMultiple(of: 2) ? 0.18 : 0.08))
                        .frame(width: 2)
                        .offset(x: CGFloat(column) * proxy.size.width / 6 - proxy.size.width / 2 + 20)
                }

                Rectangle()
                    .fill(.black.opacity(0.10))
                    .frame(height: 30)
                    .offset(y: proxy.size.height / 2 - 20)

                if index % 3 == 1 {
                    StickyWall()
                        .padding(NCSpacing.lg + 2)
                } else {
                    MeetingPeopleScene(index: index)
                }
            }
        }
    }
}

private struct MeetingPeopleScene: View {
    let index: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 42) {
            PersonShape(color: Color(red: 0.94, green: 0.72, blue: 0.42))
            PersonShape(color: Color(red: 0.20, green: 0.55, blue: 0.65))
        }
        .padding(.bottom, NCSpacing.xxl)
        .offset(x: index.isMultiple(of: 2) ? 10 : -12)
        .opacity(0.86)
    }
}

private struct PersonShape: View {
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color.opacity(0.95))
                .frame(width: 15, height: 15)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 30, height: 42)
        }
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

private struct StickyWall: View {
    private let notes: [Color] = [
        .pink, .yellow, .green, .orange, .cyan, .yellow, .pink, .green, .orange
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(Array(notes.enumerated()), id: \.offset) { offset, color in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.72))
                    .frame(height: 22)
                    .rotationEffect(.degrees(Double((offset % 3) - 1) * 5))
            }
        }
        .frame(width: 118)
        .padding(NCSpacing.lg)
        .background(.white.opacity(0.36), in: Circle())
    }
}

private struct EmptyRecentMeetingCard: View {
    let startRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetingThumbnail(index: 0)
                .frame(height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(0.70)

            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                Text("NO MEETINGS YET")
                    .font(.ncOverline)
                    .tracking(0.6)
                    .foregroundStyle(Color.ncMuted)

                Text("Start your first meeting")
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text("Record locally, transcribe offline, then turn the transcript into notes and tasks.")
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)
                    .lineLimit(3)

                Button(action: startRecording) {
                    Text("Record now")
                        .font(.ncCaption1.bold())
                        .foregroundStyle(Color.ncPurple)
                }
            }
            .padding(NCSpacing.md + 2)
        }
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
    }
}

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
