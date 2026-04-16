import SwiftData
import SwiftUI

struct RecordingRoomView: View {
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
                Color.recordingBackground
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
                            .font(.system(size: 54, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.recordingInk)
                            .padding(.top, 18)

                        MiniWaveform(level: recorder.audioLevel)
                            .frame(width: 104, height: 42)
                            .padding(.top, 86)

                        ZStack {
                            Circle()
                                .fill(Color.recordingPurple.opacity(0.10))
                                .frame(width: 190, height: 190)
                            Circle()
                                .fill(Color.recordingPurple.opacity(0.22))
                                .frame(width: 164, height: 164)
                            Circle()
                                .fill(Color.recordingPurple.opacity(0.42))
                                .frame(width: 146, height: 146)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 25)

                        VStack(spacing: 12) {
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
                        .padding(.top, 64)

                        if let message = recorder.authorizationMessage {
                            Text(message)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
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
                        .padding(.top, 35)
                        .padding(.bottom, 26)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            startedAt = .now
            meetingTitle = "\(selectedTemplate.titlePrefix) \(startedAt.formatted(date: .abbreviated, time: .shortened))"
            selectedTags = Set(selectedTemplate.defaultTags)
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
        VStack(spacing: 6) {
            HStack {
                Button(action: back) {
                    Label("BACK TO MEETINGS", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Color.recordingMuted)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.78, green: 0.25, blue: 0.27))
                        .frame(width: 7, height: 7)
                    Text("REC")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.recordingMuted)
                }

                Spacer()

                Button(action: options) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.recordingMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            Text("STRATEGY SYNC SESSION")
                .font(.system(size: 13, weight: .bold))
                .tracking(4.0)
                .foregroundStyle(Color.recordingInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 10)
    }
}

private struct MiniWaveform: View {
    let level: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<8, id: \.self) { index in
                let base = CGFloat([0.24, 0.34, 0.22, 0.50, 0.82, 0.45, 0.30, 0.22][index])
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.recordingPurple)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text("AI LIVE INSIGHTS")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.8)

                Spacer()

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.72)
                }
            }
            .foregroundStyle(Color.recordingPurple)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .italic()
                .lineSpacing(6)
                .foregroundStyle(Color.recordingMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
        }
        .padding(22)
        .background(Color.recordingSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 18, y: 8)
    }
}

private struct TranscriptToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Live Transcription")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.recordingMuted)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.recordingPurple)
                .scaleEffect(0.82)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.recordingSurface, in: Capsule())
        .shadow(color: .black.opacity(0.025), radius: 8, y: 4)
    }
}

private struct TranscriptPreview: View {
    @Binding var transcript: String
    let timestampedLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $transcript)
                .font(.system(size: 13))
                .foregroundStyle(Color.recordingInk)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92, maxHeight: 118)
                .overlay(alignment: .topLeading) {
                    if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Listening for local speech...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.recordingMuted)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }

            if !timestampedLines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(timestampedLines.suffix(4), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(Color.recordingMuted)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.recordingBackground, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.recordingSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 12, y: 6)
    }
}

private struct RecordingOptionsCard: View {
    @Binding var selectedTemplate: MeetingTemplate
    @Binding var selectedLanguage: TranscriptionLanguage
    @Binding var selectedTags: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                HStack(spacing: 8) {
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
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isSelected ? .white : Color.recordingPurple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.recordingPurple : Color.recordingPurple.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.recordingSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 12, y: 6)
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
                fill: Color(red: 0.91, green: 0.91, blue: 0.92),
                foreground: Color.recordingInk,
                action: pauseOrResume
            )

            Spacer()

            RecordingControlButton(
                icon: isSaving ? "hourglass" : "stop.fill",
                title: "STOP &\nSAVE",
                fill: Color(red: 0.77, green: 0.06, blue: 0.08),
                foreground: .white,
                action: stop
            )
            .disabled(isSaving)

            Spacer()

            RecordingControlButton(
                icon: "list.bullet.rectangle.fill",
                title: "MARK\nMOMENT",
                fill: Color(red: 0.91, green: 0.91, blue: 0.92),
                foreground: Color.recordingInk,
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
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(fill)
                        .frame(width: 72, height: 72)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(foreground)
                }

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(fill == Color(red: 0.77, green: 0.06, blue: 0.08) ? fill : Color.recordingMuted)
                    .frame(width: 82)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    static let recordingBackground = Color.adaptive(light: (0.982, 0.981, 0.988), dark: (0.055, 0.056, 0.072))
    static let recordingSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let recordingInk = Color.adaptive(light: (0.13, 0.13, 0.15), dark: (0.93, 0.94, 0.97))
    static let recordingMuted = Color.adaptive(light: (0.39, 0.39, 0.47), dark: (0.62, 0.64, 0.72))
    static let recordingPurple = Color.adaptive(light: (0.32, 0.25, 0.86), dark: (0.58, 0.50, 1.0))
}
