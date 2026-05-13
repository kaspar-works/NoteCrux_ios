import AVFoundation
import OSLog
import SwiftData
import SwiftUI

struct InsightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]
    @Query private var allTasks: [MeetingActionItem]
    @Bindable var meeting: Meeting
    @State private var selectedTab: DetailTab = .notes
    @State private var isRegenerating = false
    @AppStorage("focusReadingMode") private var focusReadingMode = false
    @AppStorage("nc_aiEnabled") private var aiEnabled = true
    @State private var shareItems: [Any]? = nil
    @State private var shareError: String? = nil
    @State private var showPaywall = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var playbackError: String?

    private let insightGenerator = LocalInsightGenerator()
    private let speakerLabeler = SpeakerLabeler()
    private let assistantEngine = MeetingAssistantEngine()

    private var smartInsights: MeetingSmartInsights {
        assistantEngine.smartInsights(for: meeting, allMeetings: allMeetings, tasks: allTasks)
    }

    private var summaryText: String {
        let candidates = [meeting.summary, meeting.quickRead, meeting.paragraphNotes, meeting.transcript]
        let text = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return text ?? "No executive summary generated yet. Refresh notes after recording to create a local-only summary."
    }

    private var takeaways: [String] {
        let items = meeting.keyPoints + meeting.decisions + meeting.bulletSummary
        if !items.isEmpty { return Array(items.prefix(4)) }
        if !meeting.highlights.isEmpty { return Array(meeting.highlights.prefix(4)) }
        return ["Confirm next steps from the transcript", "Review owners and deadlines before sharing notes"]
    }

    private var milestones: [String] {
        let taskTitles = meeting.actionItems.map(\.title)
        let items = meeting.decisions + taskTitles + meeting.keyPoints
        if !items.isEmpty { return Array(items.prefix(4)) }
        return ["Review transcript", "Generate action items", "Share follow-up notes"]
    }

    private var criticalInsight: String {
        meeting.importantLines.first
        ?? meeting.highlights.first
        ?? meeting.risks.first
        ?? "No critical insight detected yet. Important lines will appear here after local AI processing."
    }

    var body: some View {
        ZStack {
            Color.ncBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NCSpacing.xl) {
                    MeetingDetailTopBar(
                        back: { dismiss() },
                        refresh: {
                            Task { await regenerateNotes() }
                        },
                        isRegenerating: isRegenerating
                    )

                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        Text("\(meeting.createdAt.detailDate)  •  \(meeting.duration.detailDuration) DURATION")
                            .font(.ncOverline)
                            .tracking(1.2)
                            .foregroundStyle(Color.ncPurple)

                        TextField("Meeting title", text: $meeting.title, axis: .vertical)
                            .font(.ncLargeTitle)
                            .foregroundStyle(Color.ncInk)
                            .textInputAutocapitalization(.words)
                            .lineLimit(3)
                            .onSubmit { save() }

                        HStack(spacing: NCSpacing.sm) {
                            Picker("Importance", selection: $meeting.importance) {
                                ForEach(MeetingImportance.allCases) { level in
                                    Text(level.rawValue.capitalized).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(meeting.importance == .critical ? Color.ncDanger : meeting.importance == .important ? Color.ncWarning : Color.ncMuted)
                            .onChange(of: meeting.importance) { _, _ in save() }

                            if !focusReadingMode {
                                Spacer()
                                HStack(spacing: NCSpacing.xs) {
                                    ParticipantBubble(label: "👨‍💻")
                                    ParticipantBubble(label: "🎨")
                                    ParticipantBubble(label: "+\(max(1, meeting.tags.count + 1))")
                                }
                            }
                        }
                    }

                    // Audio playback — only show if a non-empty recording actually
                    // exists on disk. CAF files below ~8KB are header-only (no
                    // captured audio), which would render a broken player.
                    if let url = meeting.audioFileURL,
                       audioFileByteCount(at: url) >= 8192 {
                        audioPlayerBar
                    }

                    DetailTabBar(selection: $selectedTab)

                    tabContent

                    if !focusReadingMode {
                        BottomMetrics(
                            actionCount: meeting.actionItems.count,
                            score: smartInsights.effectivenessScore
                        )

                        RelatedMeetingsCard(meetings: smartInsights.relatedMeetings)
                    }
                }
                .padding(.horizontal, NCSpacing.lg)
                .padding(.top, NCSpacing.lg)
                .padding(.bottom, 94)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if FreeLimitTracker.shared.canExport() {
                        do {
                            shareItems = try MeetingExportService.shareItems(for: meeting)
                        } catch {
                            shareError = error.localizedDescription
                            NoteCruxLog.export.debug("InsightView share failed: \(String(describing: error), privacy: .public)")
                        }
                    } else {
                        // Basic text share for free users
                        shareItems = ["\(meeting.title)\n\n\(meeting.transcript)"]
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: Binding(
            get: { shareItems.map { ShareItemsWrapper(items: $0) } },
            set: { shareItems = $0?.items }
        )) { wrapper in
            MeetingShareSheet(items: wrapper.items)
        }
        .alert("Could not prepare share", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .alert("Playback unavailable", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .transcript:
            TranscriptDetailCard(transcript: $meeting.transcript) {
                save()
            }
        case .notes:
            NotesDetailContent(
                summary: summaryText,
                takeaways: takeaways,
                milestones: milestones,
                criticalInsight: criticalInsight,
                meetingTitle: meeting.title
            )
        case .tasks:
            TasksDetailContent(items: meeting.actionItems)
        case .highlights:
            HighlightsDetailContent(items: meeting.highlights + meeting.importantLines)
        }
    }

    private func save() {
        try? modelContext.save()
    }

    private func regenerateNotes() async {
        guard !isRegenerating else { return }
        guard aiEnabled, FreeLimitTracker.shared.canUseAI() else {
            showPaywall = true
            return
        }
        isRegenerating = true
        let insights = await insightGenerator.generate(from: meeting.transcript)
        FreeLimitTracker.shared.recordAIInsightUsed()

        meeting.summary = insights.summary
        meeting.paragraphNotes = insights.paragraphNotes
        meeting.bulletSummary = insights.bulletSummary
        meeting.highlights = insights.highlights
        meeting.importantLines = insights.importantLines
        meeting.quickRead = insights.quickRead
        meeting.keyPoints = insights.keyPoints
        meeting.decisions = insights.decisions
        meeting.risks = insights.risks
        meeting.speakerTranscriptEntries = speakerLabeler.label(
            transcriptEntries: meeting.transcriptEntries,
            fallbackTranscript: meeting.transcript
        )
        meeting.actionItems.removeAll()
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

        save()
        isRegenerating = false
    }

    // MARK: - Audio Playback

    private var audioPlayerBar: some View {
        HStack(spacing: NCSpacing.md) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ncPurple)
                    .frame(width: 36, height: 36)
                    .background(Color.ncPurple.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: NCSpacing.xs) {
                ProgressView(value: playbackProgress)
                    .tint(Color.ncPurple)

                HStack {
                    Text(formatTime(audioPlayer?.currentTime ?? 0))
                        .font(.ncCaption2)
                        .foregroundStyle(Color.ncMuted)
                    Spacer()
                    // Before first tap AVAudioPlayer is nil, so fall back to the
                    // recording's stored duration — otherwise the bar reads
                    // "0:00 / 0:00" and looks broken. After tap, the real audio
                    // duration wins.
                    Text(formatTime(audioPlayer?.duration ?? meeting.duration))
                        .font(.ncCaption2)
                        .foregroundStyle(Color.ncMuted)
                }
            }
        }
        .padding(NCSpacing.md)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
        .onDisappear {
            stopPlayback()
        }
    }

    private func togglePlayback() {
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            isPlaying = false
            playbackTimer?.invalidate()
            return
        }

        if audioPlayer == nil {
            guard let url = meeting.audioFileURL else {
                playbackError = "Audio file could not be found."
                return
            }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                let player = try AVAudioPlayer(contentsOf: url)
                guard player.duration > 0 else {
                    playbackError = "This recording contains no audio and cannot be played."
                    return
                }
                player.prepareToPlay()
                audioPlayer = player
            } catch {
                NoteCruxLog.export.debug("Audio playback setup failed: \(error.localizedDescription)")
                playbackError = "Could not play this recording. \(error.localizedDescription)"
                return
            }
        }

        audioPlayer?.play()
        isPlaying = true
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                guard let player = audioPlayer else { return }
                if player.isPlaying {
                    playbackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
                } else {
                    isPlaying = false
                    playbackTimer?.invalidate()
                }
            }
        }
    }

    private func audioFileByteCount(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = 0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - MeetingDetailTopBar

private struct MeetingDetailTopBar: View {
    let back: () -> Void
    let refresh: () -> Void
    let isRegenerating: Bool

    var body: some View {
        HStack(spacing: NCSpacing.sm) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ncInk)
                    .frame(width: 36, height: 36)
                    .background(Color.ncSurface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

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
                    .font(.ncOverline)
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)

            Text("NoteCrux")
                .font(.ncFootnote.bold())
                .foregroundStyle(Color.ncInk)

            Spacer()

            Button(action: refresh) {
                if isRegenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "gearshape.fill")
                        .font(.ncCallout.bold())
                        .foregroundStyle(Color.ncMuted)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRegenerating)
        }
    }
}

// MARK: - ParticipantBubble

private struct ParticipantBubble: View {
    let label: String

    var body: some View {
        Text(label)
            .font(label.hasPrefix("+") ? .ncCaption2.weight(.semibold) : .ncCallout.bold())
            .frame(width: 25, height: 25)
            .background(Color.ncPurple.opacity(0.10), in: Circle())
            .foregroundStyle(Color.ncPurple)
    }
}

// MARK: - DetailTabBar

private struct DetailTabBar: View {
    @Binding var selection: DetailTab

    var body: some View {
        HStack(spacing: NCSpacing.xl) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.ncFootnote.bold())
                        .foregroundStyle(selection == tab ? Color.ncPurple : Color.ncInk)
                        .padding(.vertical, NCSpacing.sm)
                        .overlay(alignment: .bottom) {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.ncPurple)
                                    .frame(height: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.ncSpring, value: selection)
    }
}

// MARK: - NotesDetailContent

private struct NotesDetailContent: View {
    let summary: String
    let takeaways: [String]
    let milestones: [String]
    let criticalInsight: String
    var meetingTitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.xxl) {
            NCCard {
                VStack(alignment: .leading, spacing: NCSpacing.lg) {
                    Label("Executive Summary", systemImage: "sparkles")
                        .font(.ncCallout.bold())
                        .foregroundStyle(Color.ncInk)

                    Text(summary)
                        .font(.ncCallout.weight(.medium))
                        .lineSpacing(5)
                        .foregroundStyle(Color.ncMuted)
                        .lineLimit(7)

                    Text("KEY TAKEAWAYS")
                        .font(.ncOverline)
                        .tracking(1.0)
                        .foregroundStyle(Color.ncPurple)

                    VStack(alignment: .leading, spacing: NCSpacing.md) {
                        ForEach(Array(takeaways.enumerated()), id: \.offset) { _, takeaway in
                            HStack(alignment: .top, spacing: NCSpacing.sm) {
                                Circle()
                                    .fill(Color.ncPurple)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 7)
                                Text(takeaway)
                                    .font(.ncCallout.weight(.medium))
                                    .lineSpacing(3)
                                    .foregroundStyle(Color.ncInk)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: NCSpacing.md) {
                Text("Roadmap Milestones")
                    .font(.ncTitle3)
                    .foregroundStyle(Color.ncInk)

                NCCard(padding: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.offset) { index, item in
                        RoadmapRow(
                            title: item,
                            subtitle: index == 0 ? "Priority item — review and confirm" : "Follow up with owner on status",
                            showsDivider: index < milestones.count - 1
                        )
                    }
                }
            }

            CriticalInsightCard(text: criticalInsight, meetingTitle: meetingTitle)
        }
    }
}

// MARK: - TranscriptDetailCard

private struct TranscriptDetailCard: View {
    @Binding var transcript: String
    let save: () -> Void

    var body: some View {
        NCCard {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                Label("Transcript", systemImage: "text.quote")
                    .font(.ncCallout.bold())
                    .foregroundStyle(Color.ncInk)

                TextEditor(text: $transcript)
                    .font(.ncCallout)
                    .foregroundStyle(Color.ncInk)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 280)
                    .onChange(of: transcript) { _, _ in save() }
            }
        }
    }
}

// MARK: - TasksDetailContent

private struct TasksDetailContent: View {
    let items: [MeetingActionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.lg) {
            Text("Action Items")
                .font(.ncTitle3)
                .foregroundStyle(Color.ncInk)

            if items.isEmpty {
                NCCard {
                    Text("No tasks extracted yet.")
                        .font(.ncCallout.weight(.medium))
                        .foregroundStyle(Color.ncMuted)
                }
            } else {
                ForEach(items) { item in
                    TaskChecklistRow(item: item, showsMeetingTitle: false)
                }
            }
        }
    }
}

// MARK: - HighlightsDetailContent

private struct HighlightsDetailContent: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.lg) {
            Text("Highlights")
                .font(.ncTitle3)
                .foregroundStyle(Color.ncInk)

            if items.isEmpty {
                NCCard {
                    Text("No highlights generated yet.")
                        .font(.ncCallout.weight(.medium))
                        .foregroundStyle(Color.ncMuted)
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NCCard {
                        HStack(alignment: .top, spacing: NCSpacing.sm) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.ncPurple)
                            Text(item)
                                .font(.ncCallout.weight(.medium))
                                .lineSpacing(4)
                                .foregroundStyle(Color.ncInk)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - RoadmapRow

private struct RoadmapRow: View {
    let title: String
    let subtitle: String
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NCSpacing.md) {
                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                    Text(title)
                        .font(.ncCallout.bold())
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.ncCaption2.weight(.semibold))
                        .foregroundStyle(Color.ncMuted)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.ncCaption1.bold())
                    .foregroundStyle(Color.ncMuted)
            }
            .padding(.horizontal, NCSpacing.lg)
            .padding(.vertical, NCSpacing.lg)

            if showsDivider {
                Rectangle()
                    .fill(Color.ncDivider)
                    .frame(height: 1)
                    .padding(.leading, NCSpacing.lg)
            }
        }
    }
}

// MARK: - CriticalInsightCard

private struct CriticalInsightCard: View {
    let text: String
    var meetingTitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.lg) {
            Label("Critical Insight", systemImage: "diamond.fill")
                .font(.ncCaption1.bold())
                .foregroundStyle(.white)

            Text("\u{201C}\(text)\u{201D}")
                .font(.ncTitle3)
                .lineSpacing(4)
                .foregroundStyle(.white)
                .lineLimit(5)

            if !meetingTitle.isEmpty {
                HStack(spacing: NCSpacing.sm) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                    Text(meetingTitle)
                        .font(.ncCaption1.bold())
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NCSpacing.xxl)
        .background(Color.ncPurple, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
        .shadow(color: Color.ncPurple.opacity(0.22), radius: 18, y: 9)
    }
}

// MARK: - BottomMetrics

private struct BottomMetrics: View {
    let actionCount: Int
    let score: Int

    var body: some View {
        HStack(spacing: NCSpacing.lg) {
            MetricBox(title: "ACTION ITEMS", value: "\(actionCount)")
            MetricBox(title: "SENTIMENT", value: "\(min(100, max(0, score)))%", valueColor: Color.ncSuccess)
        }
    }
}

// MARK: - MetricBox

private struct MetricBox: View {
    let title: String
    let value: String
    var valueColor: Color = Color.ncInk

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            Text(title)
                .font(.ncOverline)
                .tracking(1.0)
                .foregroundStyle(Color.ncMuted)

            Text(value)
                .font(.ncTitle2.weight(.bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
        .ncShadow(.card)
    }
}

// MARK: - RelatedMeetingsCard

private struct RelatedMeetingsCard: View {
    let meetings: [Meeting]

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            Text("RELATED MEETINGS")
                .font(.ncCaption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.ncMuted)

            NCCard(padding: 0) {
                if meetings.isEmpty {
                    Text("No related meetings found yet.")
                        .font(.ncFootnote.weight(.medium))
                        .foregroundStyle(Color.ncMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(NCSpacing.lg)
                } else {
                    ForEach(Array(meetings.prefix(2).enumerated()), id: \.element.id) { index, meeting in
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                                    Text(meeting.title)
                                        .font(.ncFootnote.bold())
                                        .foregroundStyle(Color.ncInk)
                                    Text(meeting.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.ncCaption2.weight(.semibold))
                                        .foregroundStyle(Color.ncMuted)
                                }
                                Spacer()
                            }
                            .padding(NCSpacing.lg)

                            if index == 0 && meetings.count > 1 {
                                Rectangle()
                                    .fill(Color.ncDivider)
                                    .frame(height: 1)
                                    .padding(.leading, NCSpacing.lg)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

private enum DetailTab: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case notes = "Notes"
    case tasks = "Tasks"
    case highlights = "Highlight"

    var id: String { rawValue }
}

private struct ShareItemsWrapper: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Date / TimeInterval Extensions

private extension Date {
    var detailDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM dd, yyyy"
        return formatter.string(from: self).uppercased()
    }
}

private extension TimeInterval {
    var detailDuration: String {
        let minutes = max(1, Int((self / 60).rounded()))
        return "\(minutes) MIN"
    }
}
