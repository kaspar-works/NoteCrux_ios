import SwiftData
import SwiftUI

struct RecordingRoomView: View {

    struct InitialContext: Equatable {
        let title: String
        let tags: [String]
    }

    let initialContext: InitialContext?

    init(initialContext: InitialContext? = nil) {
        self.initialContext = initialContext
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var recorder = RecordingTranscriptionController()
    @State private var bookmarkedSeconds: [Double] = []
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isSaving = false
    @State private var meetingTitle = ""
    @State private var selectedTags: Set<String> = ["Work"]
    @State private var selectedTemplate: MeetingTemplate = .general
    @State private var selectedLanguage: TranscriptionLanguage = .englishUS
    @State private var liveInsights: InsightDraft?
    @State private var lastLiveProcessingLength = 0
    @State private var isLiveProcessing = false
    @State private var showTranscript = true
    @State private var showOptions = false

    private let insightGenerator = LocalInsightGenerator()
    private let speakerLabeler = SpeakerLabeler()
    private let draftKey = "activeRecordingDraft"

    private var liveInsightText: String {
        if let liveInsights, !liveInsights.quickRead.isEmpty {
            return liveInsights.quickRead
        }

        let transcript = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            return transcript.count > 145 ? String(transcript.prefix(142)) + "..." : transcript
        }

        return "\"...the quarterly goal aligns with the new budget constraints we discussed in the last sprint planning session. We need to focus on —\""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        RecordingHeader(
                            title: meetingTitle,
                            back: {
                                recorder.stop()
                                dismiss()
                            },
                            options: {
                                showOptions.toggle()
                            }
                        )

                        Text(formatDuration(elapsed))
                            .font(.ncMonoLarge)
                            .foregroundStyle(Color.ncInk)
                            .padding(.top, NCSpacing.lg + 2)

                        ZStack {
                            Circle()
                                .fill(Color.ncPurple.opacity(0.08))
                                .frame(width: 160, height: 160)
                            Circle()
                                .fill(Color.ncPurple.opacity(0.18))
                                .frame(width: 130, height: 130)
                            Circle()
                                .fill(Color.ncPurple.opacity(0.38))
                                .frame(width: 108, height: 108)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, NCSpacing.xxxl)

                        MiniWaveform(level: recorder.audioLevel)
                            .frame(width: 120, height: 36)
                            .padding(.top, NCSpacing.lg)

                        VStack(spacing: NCSpacing.md) {
                            LiveInsightsCard(
                                text: liveInsightText,
                                isProcessing: isLiveProcessing
                            )

                            TranscriptToggle(isOn: $showTranscript)

                            if showOptions {
                                RecordingOptionsCard(
                                    selectedTemplate: $selectedTemplate,
                                    selectedLanguage: $selectedLanguage,
                                    selectedTags: $selectedTags
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if showTranscript {
                                TranscriptPreview(
                                    transcript: $recorder.transcript,
                                    timestampedLines: recorder.timestampedLines
                                )
                            }
                        }
                        .padding(.top, NCSpacing.xxl)

                        if let message = recorder.authorizationMessage {
                            Text(message)
                                .font(.ncFootnote.bold())
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, NCSpacing.xxl)
                                .padding(.top, NCSpacing.lg)
                        }

                        RecordingControls(
                            isPaused: recorder.isPaused,
                            isSaving: isSaving,
                            pauseOrResume: {
                                recorder.isPaused ? recorder.resume() : recorder.pause()
                            },
                            stop: {
                                Task { await stopAndSave() }
                            },
                            mark: {
                                bookmarkedSeconds.append(elapsed)
                            }
                        )
                        .padding(.top, NCSpacing.xxxl)
                        .padding(.bottom, NCSpacing.xxl + 2)
                    }
                    .padding(.horizontal, NCSpacing.xl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            startedAt = .now
            meetingTitle = "\(selectedTemplate.titlePrefix) \(startedAt.formatted(date: .abbreviated, time: .shortened))"
            selectedTags = Set(selectedTemplate.defaultTags)
            if let ctx = initialContext {
                meetingTitle = ctx.title
                for tag in ctx.tags where !selectedTags.contains(tag) {
                    selectedTags.insert(tag)
                }
            }
            await recorder.start(localeIdentifier: selectedLanguage.localeIdentifier)
        }
        .onChange(of: selectedTemplate) { _, template in
            selectedTags = Set(template.defaultTags)
            meetingTitle = "\(template.titlePrefix) \(startedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        .onChange(of: selectedLanguage) { _, language in
            guard recorder.isRecording else { return }
            recorder.stop()
            Task {
                await recorder.start(localeIdentifier: language.localeIdentifier)
            }
        }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(startedAt)
            saveDraft()
            maybeProcessLiveInsights()
        }
        .onDisappear {
            recorder.stop()
        }
    }

    private func stopAndSave() async {
        guard !isSaving else { return }
        isSaving = true
        recorder.stop()

        let transcript = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let insights = await insightGenerator.generate(from: transcript)
        let speakerEntries = speakerLabeler.label(
            transcriptEntries: recorder.timestampedLines,
            fallbackTranscript: transcript
        )
        let meeting = Meeting(
            title: meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Meeting" : meetingTitle,
            createdAt: startedAt,
            duration: elapsed,
            audioFilePath: recorder.audioFileURL?.path,
            tags: Array(selectedTags).sorted(),
            transcript: transcript,
            transcriptEntries: recorder.timestampedLines,
            speakerTranscriptEntries: speakerEntries,
            summary: insights.summary,
            paragraphNotes: insights.paragraphNotes,
            bulletSummary: insights.bulletSummary,
            highlights: insights.highlights,
            importantLines: insights.importantLines,
            quickRead: insights.quickRead,
            keyPoints: insights.keyPoints,
            decisions: insights.decisions,
            risks: insights.risks,
            bookmarkSeconds: bookmarkedSeconds
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

        await scheduleAutomaticReminders(for: meeting.actionItems)

        modelContext.insert(meeting)
        try? modelContext.save()
        UserDefaults.standard.removeObject(forKey: draftKey)
        dismiss()
    }

    private func maybeProcessLiveInsights() {
        let transcript = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recorder.isRecording,
              !recorder.isPaused,
              !isLiveProcessing,
              transcript.count >= 80,
              transcript.count - lastLiveProcessingLength >= 80 else {
            return
        }

        lastLiveProcessingLength = transcript.count
        isLiveProcessing = true

        Task {
            let insights = await insightGenerator.generate(from: transcript)
            await MainActor.run {
                liveInsights = insights
                isLiveProcessing = false
            }
        }
    }

    private func scheduleAutomaticReminders(for items: [MeetingActionItem]) async {
        for item in items where item.reminderDate != nil || item.priority == .high {
            if item.reminderDate == nil {
                item.reminderDate = item.deadline ?? TaskReminderScheduler.snoozeDate(minutes: 60)
            }
            item.notificationIdentifier = await TaskReminderScheduler.schedule(for: item)
        }
    }

    private func saveDraft() {
        guard recorder.isRecording || recorder.isPaused else { return }
        let draft = RecordingDraft(
            title: meetingTitle,
            startedAt: startedAt,
            elapsed: elapsed,
            tags: Array(selectedTags).sorted(),
            transcript: recorder.transcript,
            transcriptEntries: recorder.timestampedLines,
            audioFilePath: recorder.audioFileURL?.path
        )

        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: draftKey)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds / 60) % 60, totalSeconds % 60)
    }
}

private struct RecordingHeader: View {
    let title: String
    let back: () -> Void
    let options: () -> Void

    var body: some View {
        VStack(spacing: NCSpacing.sm - 2) {
            HStack {
                Button(action: back) {
                    Label("BACK TO MEETINGS", systemImage: "chevron.left")
                        .font(.ncFootnote.bold())
                        .tracking(1.0)
                        .foregroundStyle(Color.ncMuted)
                }
                .buttonStyle(NCPressButtonStyle())

                Spacer()

                HStack(spacing: NCSpacing.sm) {
                    Circle()
                        .fill(Color.ncDanger)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.ncDanger.opacity(0.5), radius: 4, y: 0)
                        .modifier(PulsingDotModifier())
                    Text("REC")
                        .font(.ncCallout.bold())
                        .tracking(1.4)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()

                Button(action: options) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.ncMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(NCPressButtonStyle())
            }

            Text(title.uppercased())
                .font(.ncCallout.bold())
                .tracking(4.0)
                .foregroundStyle(Color.ncInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, NCSpacing.sm + 2)
    }
}

private struct PulsingDotModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

private struct MiniWaveform: View {
    let level: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: NCSpacing.sm - 2) {
            ForEach(0..<8, id: \.self) { index in
                let base = CGFloat([0.24, 0.34, 0.22, 0.50, 0.82, 0.45, 0.30, 0.22][index])
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.ncPurple)
                    .frame(width: 4, height: 8 + 28 * max(base, level * base))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveInsightsCard: View {
    let text: String
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(spacing: NCSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.ncFootnote.bold())
                Text("AI LIVE INSIGHTS")
                    .font(.ncCallout.bold())
                    .tracking(0.8)

                Spacer()

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.72)
                }
            }
            .foregroundStyle(Color.ncPurple)

            Text(text)
                .font(.ncBody.weight(.medium))
                .italic()
                .lineSpacing(6)
                .foregroundStyle(Color.ncMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
        }
        .padding(NCSpacing.xl + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
    }
}

private struct TranscriptToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            Text("Live Transcription")
                .font(.ncCallout.bold())
                .foregroundStyle(Color.ncMuted)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.ncPurple)
                .scaleEffect(0.82)
        }
        .padding(.horizontal, NCSpacing.lg)
        .frame(height: 36)
        .background(Color.ncSurface, in: Capsule())
        .ncShadow(.subtle)
    }
}

private struct TranscriptPreview: View {
    @Binding var transcript: String
    let timestampedLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm + 2) {
            TextEditor(text: $transcript)
                .font(.ncCallout)
                .foregroundStyle(Color.ncInk)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92, maxHeight: 118)
                .overlay(alignment: .topLeading) {
                    if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Listening for local speech...")
                            .font(.ncCallout.weight(.medium))
                            .foregroundStyle(Color.ncMuted)
                            .padding(.top, NCSpacing.sm)
                            .padding(.leading, 5)
                    }
                }

            if !timestampedLines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(timestampedLines.suffix(4), id: \.self) { line in
                            Text(line)
                                .font(.ncCaption2.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(Color.ncMuted)
                                .padding(.horizontal, 9)
                                .padding(.vertical, NCSpacing.sm - 2)
                                .background(Color.ncBackground, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(NCSpacing.lg - 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

private struct RecordingOptionsCard: View {
    @Binding var selectedTemplate: MeetingTemplate
    @Binding var selectedLanguage: TranscriptionLanguage
    @Binding var selectedTags: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack {
                Picker("Template", selection: $selectedTemplate) {
                    ForEach(MeetingTemplate.allCases) { template in
                        Text(template.rawValue).tag(template)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Picker("Language", selection: $selectedLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NCSpacing.sm) {
                    ForEach(Array(MeetingTag.allCases)) { tag in
                        let isSelected = selectedTags.contains(tag.rawValue)
                        Button {
                            if isSelected {
                                selectedTags.remove(tag.rawValue)
                            } else {
                                selectedTags.insert(tag.rawValue)
                            }
                        } label: {
                            Text(tag.rawValue)
                                .font(.ncCaption1.bold())
                                .foregroundStyle(isSelected ? .white : Color.ncPurple)
                                .padding(.horizontal, NCSpacing.sm + 2)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.ncPurple : Color.ncPurple.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(NCPressButtonStyle())
                    }
                }
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

private struct RecordingControls: View {
    let isPaused: Bool
    let isSaving: Bool
    let pauseOrResume: () -> Void
    let stop: () -> Void
    let mark: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            RecordingControlButton(
                icon: isPaused ? "play.fill" : "pause.fill",
                title: isPaused ? "RESUME" : "PAUSE",
                fill: Color.ncSurfaceElevated,
                foreground: Color.ncInk,
                action: pauseOrResume
            )

            Spacer()

            RecordingControlButton(
                icon: isSaving ? "hourglass" : "stop.fill",
                title: "STOP &\nSAVE",
                fill: Color.ncDanger,
                foreground: .white,
                action: stop
            )
            .disabled(isSaving)

            Spacer()

            RecordingControlButton(
                icon: "list.bullet.rectangle.fill",
                title: "MARK\nMOMENT",
                fill: Color.ncSurfaceElevated,
                foreground: Color.ncInk,
                action: mark
            )
        }
        .padding(.horizontal, 2)
    }
}

private struct RecordingControlButton: View {
    let icon: String
    let title: String
    let fill: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: NCSpacing.sm + 2) {
                ZStack {
                    Circle()
                        .fill(fill)
                        .frame(width: 72, height: 72)
                        .ncShadow(.card)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(foreground)
                }

                Text(title)
                    .font(.ncCaption1.bold())
                    .tracking(1.4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(fill == Color.ncDanger ? fill : Color.ncMuted)
                    .frame(width: 82)
            }
        }
        .buttonStyle(NCPressButtonStyle())
    }
}
