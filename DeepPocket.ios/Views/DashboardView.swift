import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var actionItems: [MeetingActionItem]
    @Binding var isRecording: Bool
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
                Color.deepPocketDashboardBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        DashboardHeader()

                        VStack(spacing: 11) {
                            DashboardMetricCard(
                                title: "TODAY'S MEETINGS",
                                value: "\(todaysMeetings.count)",
                                isPrimary: true
                            )
                            DashboardMetricCard(
                                title: "PENDING TASKS",
                                value: "\(pendingTasks.count)",
                                isPrimary: false
                            )
                            DashboardMetricCard(
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

                        HStack(alignment: .firstTextBaseline) {
                            Text("Recent Meetings")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.deepPocketInk)

                            Spacer()

                            NavigationLink {
                                VaultView()
                            } label: {
                                Text("View all")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.deepPocketPurple)
                            }
                        }
                        .padding(.top, 6)

                        if recentMeetings.isEmpty {
                            EmptyRecentMeetingCard {
                                isRecording = true
                            }
                        } else {
                            VStack(spacing: 18) {
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
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 94)
                }

                Button {
                    isRecording = true
                } label: {
                    Label("Record Meeting", systemImage: "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(Color.deepPocketPurple, in: Capsule())
                        .shadow(color: Color.deepPocketPurple.opacity(0.25), radius: 14, y: 8)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 16)
                .accessibilityLabel("Record meeting")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            loadDraft()
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
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.deepPocketMuted)

                Text("Good morning,")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.deepPocketInk)

                Text("Bistro")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.deepPocketInk)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.deepPocketPurple, Color(red: 0.98, green: 0.70, blue: 0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("B")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 33, height: 33)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        }
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.deepPocketMuted)

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(isPrimary ? Color.deepPocketPurple : Color.deepPocketInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .frame(height: 78)
        .background(Color.deepPocketSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("\(meeting.createdAt.dashboardDate)  •  \(meeting.duration.dashboardDuration)")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.deepPocketMuted)

                Text(meeting.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.deepPocketInk)
                    .lineLimit(1)

                Text(excerpt)
                    .font(.system(size: 12, weight: .regular))
                    .lineSpacing(2)
                    .foregroundStyle(Color(red: 0.37, green: 0.38, blue: 0.44))
                    .lineLimit(3)

                HStack(spacing: 7) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(chipColor(chip))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(chipColor(chip).opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(14)
        }
        .background(Color.deepPocketSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 14, y: 6)
    }

    private func chipColor(_ chip: String) -> Color {
        let colors: [Color] = [
            .deepPocketPurple,
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
                        .padding(18)
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
        .padding(.bottom, 24)
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
        .padding(16)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("NO MEETINGS YET")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.deepPocketMuted)

                Text("Start your first meeting")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.deepPocketInk)

                Text("Record locally, transcribe offline, then turn the transcript into notes and tasks.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.37, green: 0.38, blue: 0.44))
                    .lineLimit(3)

                Button(action: startRecording) {
                    Text("Record now")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.deepPocketPurple)
                }
            }
            .padding(14)
        }
        .background(Color.deepPocketSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 14, y: 6)
    }
}

private struct FollowUpStrip: View {
    let items: [MeetingActionItem]
    let remind: (MeetingActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PENDING FOLLOW-UPS")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.deepPocketMuted)

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.priority == .high ? "exclamationmark" : "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.deepPocketPurple, in: Circle())

                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.deepPocketInk)
                        .lineLimit(1)

                    Spacer()

                    Button("Remind") {
                        remind(item)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.deepPocketPurple)
                }
            }
        }
        .padding(14)
        .background(Color.deepPocketSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
    }
}

private struct RecoveryCard: View {
    let draft: RecordingDraft
    let recover: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UNSAVED RECORDING")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.deepPocketMuted)

            Text(draft.title.isEmpty ? "Recovered Meeting" : draft.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.deepPocketInk)

            Text(draft.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Button("Recover", action: recover)
                    .font(.system(size: 12, weight: .bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color.deepPocketPurple)

                Button("Discard", role: .destructive, action: discard)
                    .font(.system(size: 12, weight: .bold))
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.deepPocketSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
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

private extension Color {
    static let deepPocketDashboardBackground = Color.adaptive(light: (0.965, 0.970, 0.980), dark: (0.055, 0.058, 0.075))
    static let deepPocketSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let deepPocketInk = Color.adaptive(light: (0.12, 0.13, 0.16), dark: (0.93, 0.94, 0.97))
    static let deepPocketMuted = Color.adaptive(light: (0.56, 0.57, 0.64), dark: (0.62, 0.64, 0.72))
    static let deepPocketPurple = Color.adaptive(light: (0.38, 0.27, 0.88), dark: (0.58, 0.50, 1.0))
}
