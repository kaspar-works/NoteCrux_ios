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
    @AppStorage("languageMode") private var languageMode = "English"
    @AppStorage("nc_aiEnabled") private var aiEnabled = true
    @AppStorage("nc_autoProcessAfterRecording") private var autoProcessAfterRecording = true
    @AppStorage("nc_deleteAudioAfterProcessing") private var deleteAudioAfterProcessing = false
    @AppStorage("nc_keepTranscriptsOnly") private var keepTranscriptsOnly = false
    @State private var selectedLanguage: TranscriptionLanguage = .englishUS
    @State private var liveInsights: InsightDraft?
    @State private var lastLiveProcessingLength = 0
    @State private var isLiveProcessing = false
    @State private var showTranscript = true
    @State private var showOptions = false
    @State private var hasStarted = false
    @State private var processingPhase: ProcessingPhase = .idle
    @State private var savedMeeting: Meeting?
    @State private var showScheduler = false
    @State private var agendaNotes = ""
    @State private var participantInput = ""
    @State private var participants: [String] = []
    @State private var showContent = false
    @State private var showStopConfirmation = false
    @State private var momentToast = false
    @State private var liveActionItemCount = 0
    @State private var liveDecisionCount = 0
    @State private var didWarnLongRecording = false

    private enum ProcessingPhase: Equatable {
        case idle, processing, done
    }

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
        return "Listening for speech..."
    }

    private var longRecordingBanner: (message: String, isWarning: Bool)? {
        let minutes = elapsed / 60
        if minutes >= 120 {
            return ("Recording over 2 hours. Consider stopping soon to save battery and storage.", true)
        }
        if minutes >= 45 {
            return ("Long recording — we're keeping the transcript and audio flowing.", false)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground
                    .ignoresSafeArea()

                switch processingPhase {
                case .processing:
                    processingView
                case .done:
                    if let meeting = savedMeeting {
                        meetingResultsView(meeting: meeting)
                    }
                case .idle:
                    if hasStarted {
                        activeRecordingView
                    } else {
                        preRecordingView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showScheduler) {
                if let meeting = savedMeeting {
                    ActionItemSchedulerSheet(
                        actionItems: meeting.actionItems,
                        meetingTitle: meeting.title
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .task {
            // Apply default language from settings
            switch languageMode {
            case "Spanish": selectedLanguage = .spanish
            case "French": selectedLanguage = .french
            case "German": selectedLanguage = .german
            default: selectedLanguage = .englishUS
            }
            meetingTitle = "\(selectedTemplate.titlePrefix) \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            selectedTags = Set(selectedTemplate.defaultTags)
            if let ctx = initialContext {
                meetingTitle = ctx.title
                for tag in ctx.tags where !selectedTags.contains(tag) {
                    selectedTags.insert(tag)
                }
            }
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
        .onChange(of: selectedTemplate) { _, template in
            selectedTags = Set(template.defaultTags)
            if !hasStarted {
                meetingTitle = "\(template.titlePrefix) \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            }
        }
        .onChange(of: selectedLanguage) { _, language in
            guard recorder.isRecording else { return }
            recorder.stop()
            Task {
                await recorder.start(localeIdentifier: language.localeIdentifier)
            }
        }
        .onReceive(timer) { _ in
            guard hasStarted else { return }
            elapsed = Date().timeIntervalSince(startedAt)
            saveDraft()
            maybeProcessLiveInsights()
            LiveActivityController.shared.update(
                isPaused: recorder.isPaused,
                audioLevel: Double(recorder.audioLevel),
                startedAt: startedAt,
                throttled: true
            )
            if !didWarnLongRecording, elapsed >= 120 * 60 {
                didWarnLongRecording = true
                HapticFeedback.warning()
            }
        }
        .onDisappear {
            recorder.stop()
            LiveActivityController.shared.end()
        }
    }

    // MARK: - Pre-Recording View

    private var preRecordingView: some View {
        ZStack {
            // Subtle gradient
            LinearGradient(
                colors: [Color.ncBackground, Color.ncPurple.opacity(0.03), Color.ncBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: NCSpacing.xl + 4) {
                    // Header
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.ncMuted)
                                .frame(width: 36, height: 36)
                                .background(Color.ncSurface, in: Circle())
                        }
                        .buttonStyle(NCPressButtonStyle())

                        Spacer()

                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding(.top, NCSpacing.sm)

                    // Title section
                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        Text("Start a New Meeting")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.ncInk)

                        Text("Capture conversations, tasks, and insights effortlessly")
                            .font(.ncFootnote)
                            .foregroundStyle(Color.ncSecondary)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 12)

                    // Title input card
                    SetupCard {
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("TITLE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            TextField("e.g. Weekly Standup", text: $meetingTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.ncInk)
                                .padding(NCSpacing.md)
                                .background(Color.ncBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                        .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 14)

                    // Meeting type card
                    SetupCard {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            Text("MEETING TYPE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: NCSpacing.sm) {
                                    ForEach(MeetingTemplate.allCases) { template in
                                        let isSelected = selectedTemplate == template
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedTemplate = template
                                            }
                                        } label: {
                                            VStack(spacing: NCSpacing.sm) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(isSelected
                                                              ? LinearGradient(colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                              : LinearGradient(colors: [Color.ncPurple.opacity(0.08), Color.ncPurple.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                        )
                                                        .frame(width: 44, height: 44)

                                                    Image(systemName: templateIcon(template))
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundStyle(isSelected ? .white : Color.ncPurple)
                                                }

                                                Text(template.rawValue)
                                                    .font(.ncCaption2.weight(.semibold))
                                                    .foregroundStyle(isSelected ? Color.ncPurple : Color.ncMuted)
                                            }
                                            .frame(width: 76)
                                        }
                                        .buttonStyle(NCPressButtonStyle())
                                        .scaleEffect(isSelected ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                                    }
                                }
                            }

                            // Description
                            HStack(spacing: NCSpacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.ncPurple.opacity(0.6))
                                Text(selectedTemplate.promptHint)
                                    .font(.ncCaption1)
                                    .foregroundStyle(Color.ncSecondary)
                            }
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 16)

                    // Participants card
                    ParticipantsCard(
                        participantInput: $participantInput,
                        participants: $participants,
                        addParticipant: addParticipant
                    )
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 16)

                    // Tags card
                    TagsCard(selectedTags: $selectedTags)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 16)

                    // Agenda card
                    SetupCard {
                        VStack(alignment: .leading, spacing: NCSpacing.sm) {
                            Text("AGENDA / NOTES")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            TextEditor(text: $agendaNotes)
                                .font(.ncCallout)
                                .foregroundStyle(Color.ncInk)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 72, maxHeight: 120)
                                .padding(NCSpacing.md)
                                .background(Color.ncBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    if agendaNotes.isEmpty {
                                        Text("What will you discuss? Add agenda or key points...")
                                            .font(.ncCallout.weight(.medium))
                                            .foregroundStyle(Color.ncMuted.opacity(0.5))
                                            .padding(.top, NCSpacing.md + 8)
                                            .padding(.leading, NCSpacing.md + 5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                        .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 16)

                    // Language selector
                    SetupCard {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            Text("LANGUAGE")
                                .font(.ncOverline)
                                .tracking(1.4)
                                .foregroundStyle(Color.ncMuted)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: NCSpacing.sm) {
                                    ForEach(TranscriptionLanguage.allCases) { language in
                                        let isSelected = selectedLanguage == language
                                        Button {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                                selectedLanguage = language
                                            }
                                        } label: {
                                            Text(language.rawValue)
                                                .font(.ncCaption1.bold())
                                                .foregroundStyle(isSelected ? .white : Color.ncMuted)
                                                .padding(.horizontal, NCSpacing.md)
                                                .padding(.vertical, NCSpacing.sm + 1)
                                                .background(isSelected ? Color.ncPurple : Color.ncBackground.opacity(0.5), in: Capsule())
                                                .overlay(
                                                    Capsule().strokeBorder(isSelected ? Color.clear : Color.ncDivider, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 16)

                    // Auth warning
                    if let message = recorder.authorizationMessage {
                        HStack(spacing: NCSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(message)
                                .font(.ncCaption1.weight(.medium))
                        }
                        .foregroundStyle(Color.ncWarning)
                        .padding(.horizontal, NCSpacing.lg)
                        .padding(.vertical, NCSpacing.md)
                        .frame(maxWidth: .infinity)
                        .background(Color.ncWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                .strokeBorder(Color.ncWarning.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Start button
                    VStack(spacing: NCSpacing.sm) {
                        Button {
                            Task { await startMeeting() }
                        } label: {
                            HStack(spacing: NCSpacing.md) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Start Recording")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NCSpacing.lg + 2)
                            .background(
                                LinearGradient(
                                    colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                            )
                            .shadow(color: Color.ncPurple.opacity(0.35), radius: 16, y: 6)
                        }
                        .buttonStyle(NCPressButtonStyle())

                        Text("AI will capture notes, tasks & highlights")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 16)
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.bottom, NCSpacing.xxxl)
            }
        }
    }

    // MARK: - Active Recording View

    private var activeRecordingView: some View {
        ZStack {
            // Animated background
            LinearGradient(
                colors: [
                    Color.ncBackground,
                    Color.ncPurple.opacity(0.04),
                    Color.ncBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    RecordingHeader(
                        title: meetingTitle,
                        isPaused: recorder.isPaused,
                        back: {
                            recorder.stop()
                            dismiss()
                        },
                        options: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showOptions.toggle()
                            }
                        }
                    )

                    // Timer
                    VStack(spacing: NCSpacing.xs) {
                        Text("Recording...")
                            .font(.ncCaption1.weight(.medium))
                            .foregroundStyle(Color.ncMuted)
                            .opacity(recorder.isPaused ? 0.5 : 1.0)

                        Text(formatDuration(elapsed))
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.ncInk)
                            .shadow(color: Color.ncPurple.opacity(0.08), radius: 8, y: 2)
                    }
                    .padding(.top, NCSpacing.xl)

                    if let banner = longRecordingBanner {
                        LongRecordingBanner(message: banner.message, isWarning: banner.isWarning)
                            .padding(.horizontal, NCSpacing.lg)
                            .padding(.top, NCSpacing.md)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Mic visualization
                    PulsatingMicView(
                        audioLevel: recorder.audioLevel,
                        isRecording: recorder.isRecording && !recorder.isPaused
                    )
                    .frame(width: 200, height: 200)
                    .padding(.top, NCSpacing.xl)

                    // Waveform
                    PremiumWaveform(level: recorder.audioLevel)
                        .frame(width: 160, height: 40)
                        .padding(.top, NCSpacing.md)

                    // Live AI stats
                    if liveActionItemCount > 0 || liveDecisionCount > 0 {
                        HStack(spacing: NCSpacing.lg) {
                            if liveActionItemCount > 0 {
                                LiveStatPill(
                                    icon: "checkmark.square",
                                    text: "\(liveActionItemCount) action item\(liveActionItemCount == 1 ? "" : "s")",
                                    color: Color.ncPurple
                                )
                            }
                            if liveDecisionCount > 0 {
                                LiveStatPill(
                                    icon: "lightbulb.fill",
                                    text: "\(liveDecisionCount) decision\(liveDecisionCount == 1 ? "" : "s")",
                                    color: Color.ncSuccess
                                )
                            }
                        }
                        .padding(.top, NCSpacing.md)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Cards section
                    VStack(spacing: NCSpacing.md) {
                        // AI insights card
                        LiveInsightsCard(
                            text: liveInsightText,
                            isProcessing: isLiveProcessing
                        )

                        // Transcript toggle
                        TranscriptToggle(isOn: $showTranscript)

                        // Options
                        if showOptions {
                            RecordingOptionsCard(
                                selectedTemplate: $selectedTemplate,
                                selectedLanguage: $selectedLanguage,
                                selectedTags: $selectedTags
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Live transcript
                        if showTranscript {
                            TranscriptPreview(
                                transcript: Binding(
                                    get: { recorder.transcript },
                                    set: { _ in }
                                ),
                                timestampedLines: recorder.timestampedLines
                            )
                        }
                    }
                    .padding(.top, NCSpacing.xxl)

                    // Auth message
                    if let message = recorder.authorizationMessage {
                        HStack(spacing: NCSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(message)
                                .font(.ncCaption1.weight(.medium))
                        }
                        .foregroundStyle(Color.ncDanger)
                        .padding(.horizontal, NCSpacing.lg)
                        .padding(.vertical, NCSpacing.sm + 2)
                        .frame(maxWidth: .infinity)
                        .background(Color.ncDanger.opacity(0.06), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                        .padding(.top, NCSpacing.md)
                    }

                    // Controls
                    PremiumRecordingControls(
                        isPaused: recorder.isPaused,
                        isSaving: isSaving,
                        pauseOrResume: {
                            HapticFeedback.pauseResume()
                            let willBePaused = !recorder.isPaused
                            recorder.isPaused ? recorder.resume() : recorder.pause()
                            LiveActivityController.shared.update(
                                isPaused: willBePaused,
                                audioLevel: 0,
                                startedAt: startedAt
                            )
                        },
                        stop: {
                            showStopConfirmation = true
                        },
                        mark: {
                            HapticFeedback.bookmark()
                            bookmarkedSeconds.append(elapsed)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                momentToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { momentToast = false }
                            }
                        }
                    )
                    .padding(.top, NCSpacing.xxxl)
                    .padding(.bottom, NCSpacing.xxl + 2)
                }
                .padding(.horizontal, NCSpacing.lg + 2)
            }

            // Moment toast
            if momentToast {
                VStack {
                    MomentToast(timestamp: formatDuration(elapsed))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 60)
                    Spacer()
                }
                .zIndex(10)
            }
        }
        .alert("End Meeting?", isPresented: $showStopConfirmation) {
            Button("Save & Generate Insights", role: .none) {
                Task { await stopAndSave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop recording and generate AI-powered notes, tasks, and highlights from your meeting.")
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: NCSpacing.xxl) {
            Spacer()

            ProcessingOrb()

            VStack(spacing: NCSpacing.md) {
                Text("Processing Meeting")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.ncInk)

                Text("Generating notes, tasks & highlights...")
                    .font(.ncCallout.weight(.medium))
                    .foregroundStyle(Color.ncMuted)
            }

            // Processing steps
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                ProcessingStep(icon: "doc.text.fill", text: "Analyzing transcript", done: true)
                ProcessingStep(icon: "list.bullet", text: "Extracting key points", done: true)
                ProcessingStep(icon: "checkmark.square.fill", text: "Identifying action items", done: false)
                ProcessingStep(icon: "sparkles", text: "Generating summary", done: false)
            }
            .padding(.top, NCSpacing.lg)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, NCSpacing.xl)
    }

    // MARK: - Results View

    private func meetingResultsView(meeting: Meeting) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: NCSpacing.xl) {
                // Success header
                HStack {
                    Spacer()
                    VStack(spacing: NCSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.ncSuccess.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Circle()
                                .fill(Color.ncSuccess.opacity(0.20))
                                .frame(width: 60, height: 60)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(Color.ncSuccess)
                        }

                        Text("Meeting Saved")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.ncInk)

                        HStack(spacing: NCSpacing.sm) {
                            HStack(spacing: NCSpacing.xs) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11, weight: .medium))
                                Text(formatDuration(elapsed))
                                    .font(.ncCaption1.weight(.medium))
                            }

                            Text("·")

                            Text(meeting.tags.joined(separator: ", "))
                                .font(.ncCaption1.weight(.medium))
                        }
                        .foregroundStyle(Color.ncMuted)
                    }
                    Spacer()
                }
                .padding(.top, NCSpacing.xxl)

                // Quick stats
                HStack(spacing: NCSpacing.sm) {
                    ResultStatPill(value: "\(meeting.actionItems.count)", label: "Tasks", color: Color.ncPurple)
                    ResultStatPill(value: "\(meeting.highlights.count + meeting.importantLines.count)", label: "Highlights", color: Color.ncSuccess)
                    ResultStatPill(value: "\(meeting.keyPoints.count)", label: "Key Points", color: Color.ncWarning)
                }

                // Summary
                if !meeting.summary.isEmpty {
                    ResultSection(icon: "doc.text.fill", title: "Summary") {
                        Text(meeting.summary)
                            .font(.ncCallout.weight(.medium))
                            .lineSpacing(5)
                            .foregroundStyle(Color.ncSecondary)
                    }
                }

                // Key Points
                let bullets = meeting.bulletSummary.isEmpty ? meeting.keyPoints : meeting.bulletSummary
                if !bullets.isEmpty {
                    ResultSection(icon: "list.bullet", title: "Key Points") {
                        VStack(alignment: .leading, spacing: NCSpacing.sm + 2) {
                            ForEach(bullets.prefix(5), id: \.self) { point in
                                HStack(alignment: .top, spacing: NCSpacing.sm) {
                                    Circle()
                                        .fill(Color.ncPurple)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 7)
                                    Text(point)
                                        .font(.ncCallout.weight(.medium))
                                        .foregroundStyle(Color.ncInk)
                                        .lineSpacing(3)
                                }
                            }
                        }
                    }
                }

                // Tasks
                if !meeting.actionItems.isEmpty {
                    ResultSection(icon: "checkmark.square.fill", title: "Tasks (\(meeting.actionItems.count))") {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            ForEach(meeting.actionItems.prefix(5)) { item in
                                HStack(alignment: .top, spacing: NCSpacing.sm) {
                                    Image(systemName: "square")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.ncPurple)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.ncCallout.weight(.semibold))
                                            .foregroundStyle(Color.ncInk)
                                        if item.owner != "Unassigned" {
                                            Text(item.owner)
                                                .font(.ncCaption2.weight(.medium))
                                                .foregroundStyle(Color.ncMuted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Highlights
                let highlights = meeting.highlights + meeting.importantLines
                if !highlights.isEmpty {
                    ResultSection(icon: "sparkles", title: "Highlights") {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            ForEach(Array(highlights.prefix(4).enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: NCSpacing.sm) {
                                    Image(systemName: "quote.opening")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.ncPurple)
                                        .padding(.top, 4)
                                    Text(item)
                                        .font(.ncCallout.weight(.medium))
                                        .italic()
                                        .foregroundStyle(Color.ncSecondary)
                                        .lineSpacing(3)
                                }
                            }
                        }
                    }
                }

                // Transcript preview
                if !meeting.transcript.isEmpty {
                    ResultSection(icon: "text.quote", title: "Transcript") {
                        let preview = meeting.transcript.count > 200
                        ? String(meeting.transcript.prefix(197)) + "..."
                        : meeting.transcript
                        Text(preview)
                            .font(.ncCaption1.weight(.medium))
                            .foregroundStyle(Color.ncMuted)
                            .lineSpacing(4)
                    }
                }

                // Done button
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NCSpacing.lg)
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
                .padding(.top, NCSpacing.md)
                .padding(.bottom, NCSpacing.xxl)
            }
            .padding(.horizontal, NCSpacing.lg + 2)
        }
    }

    // MARK: - Actions

    private func templateIcon(_ template: MeetingTemplate) -> String {
        switch template {
        case .general: return "rectangle.3.group.bubble"
        case .standup: return "person.3.fill"
        case .clientCall: return "phone.fill"
        case .oneOnOne: return "person.2.fill"
        case .planning: return "calendar.badge.clock"
        }
    }

    private func addParticipant() {
        let name = participantInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            participants.append(name)
        }
        participantInput = ""
    }

    private func startMeeting() async {
        startedAt = .now
        meetingTitle = "\(selectedTemplate.titlePrefix) \(startedAt.formatted(date: .abbreviated, time: .shortened))"
        if let ctx = initialContext {
            meetingTitle = ctx.title
        }
        await recorder.start(localeIdentifier: selectedLanguage.localeIdentifier)
        guard recorder.isRecording else { return }
        HapticFeedback.start()
        LiveActivityController.shared.start(title: meetingTitle, startedAt: startedAt)
        withAnimation(.easeInOut(duration: 0.4)) {
            hasStarted = true
        }
    }

    private func stopAndSave() async {
        guard !isSaving else { return }
        isSaving = true
        HapticFeedback.stop()
        recorder.stop()
        LiveActivityController.shared.end()

        withAnimation(.easeInOut(duration: 0.3)) {
            processingPhase = .processing
        }

        let transcript = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let canAI = aiEnabled && autoProcessAfterRecording && FreeLimitTracker.shared.canUseAI()
        let insights: InsightDraft
        if canAI {
            insights = await insightGenerator.generate(from: transcript)
            FreeLimitTracker.shared.recordAIInsightUsed()
        } else {
            insights = InsightDraft()
        }
        let speakerEntries = speakerLabeler.label(
            transcriptEntries: recorder.timestampedLines,
            fallbackTranscript: transcript
        )
        let meeting = Meeting(
            title: meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Meeting" : meetingTitle,
            createdAt: startedAt,
            duration: elapsed,
            audioFilePath: recorder.audioFileURL?.lastPathComponent,
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

        // Apply advanced privacy settings
        if deleteAudioAfterProcessing, let url = meeting.audioFileURL {
            try? FileManager.default.removeItem(at: url)
            meeting.audioFilePath = nil
        }
        if keepTranscriptsOnly {
            meeting.summary = ""
            meeting.paragraphNotes = ""
            meeting.bulletSummary = []
            meeting.highlights = []
            meeting.importantLines = []
            meeting.quickRead = ""
            meeting.keyPoints = []
            meeting.decisions = []
            meeting.risks = []
            meeting.actionItems = []
        }

        modelContext.insert(meeting)
        try? modelContext.save()
        UserDefaults.standard.removeObject(forKey: draftKey)

        savedMeeting = meeting
        withAnimation(.easeInOut(duration: 0.4)) {
            processingPhase = .done
        }

        // Offer to schedule each action item as a calendar event. Only
        // present when we actually have follow-ups to schedule.
        if !meeting.actionItems.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showScheduler = true
            }
        }

        // Show an interstitial after a successful save (throttled + skipped
        // automatically when the user has purchased Remove Ads).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            AdManager.shared.maybeShowInterstitial()
        }
    }

    private func maybeProcessLiveInsights() {
        guard aiEnabled else { return }
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
                liveActionItemCount = insights.actionItems.count
                liveDecisionCount = insights.decisions.count
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
            audioFilePath: recorder.audioFileURL?.lastPathComponent
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

// MARK: - Participants Card

private struct ParticipantsCard: View {
    @Binding var participantInput: String
    @Binding var participants: [String]
    let addParticipant: () -> Void

    var body: some View {
        SetupCard {
            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                Text("PARTICIPANTS")
                    .font(.ncOverline)
                    .tracking(1.4)
                    .foregroundStyle(Color.ncMuted)

                HStack(spacing: NCSpacing.sm) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ncMuted)

                    TextField("Add name, press return", text: $participantInput)
                        .font(.ncCallout)
                        .foregroundStyle(Color.ncInk)
                        .onSubmit { addParticipant() }
                }
                .padding(NCSpacing.md)
                .background(Color.ncBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                        .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                )

                if !participants.isEmpty {
                    ParticipantChipList(participants: $participants)
                }
            }
        }
    }
}

private struct ParticipantChipList: View {
    @Binding var participants: [String]

    var body: some View {
        FlowLayout(spacing: NCSpacing.sm) {
            ForEach(Array(participants.enumerated()), id: \.offset) { index, name in
                ParticipantChip(name: name) {
                    removeParticipant(at: index)
                }
            }
        }
    }

    private func removeParticipant(at index: Int) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            guard index < participants.count else { return }
            participants.remove(at: index)
        }
    }
}

private struct ParticipantChip: View {
    let name: String
    let remove: () -> Void

    private var purpleBg: Color { Color.ncPurple.opacity(0.08) }
    private var purpleInitials: Color { Color.ncPurple.opacity(0.15) }

    var body: some View {
        HStack(spacing: NCSpacing.xs) {
            ZStack {
                Circle()
                    .fill(purpleInitials)
                    .frame(width: 22, height: 22)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.ncPurple)
            }

            Text(name)
                .font(.ncCaption1.weight(.semibold))

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(Color.ncPurple)
        .padding(.leading, NCSpacing.xs)
        .padding(.trailing, NCSpacing.sm)
        .padding(.vertical, NCSpacing.sm)
        .background(purpleBg, in: Capsule())
    }
}

// MARK: - Tags Card

private struct TagsCard: View {
    @Binding var selectedTags: Set<String>

    var body: some View {
        SetupCard {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                Text("TAGS")
                    .font(.ncOverline)
                    .tracking(1.4)
                    .foregroundStyle(Color.ncMuted)

                FlowLayout(spacing: NCSpacing.sm) {
                    ForEach(Array(MeetingTag.allCases)) { tag in
                        TagToggleChip(
                            label: tag.rawValue,
                            isSelected: selectedTags.contains(tag.rawValue)
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                if selectedTags.contains(tag.rawValue) {
                                    selectedTags.remove(tag.rawValue)
                                } else {
                                    selectedTags.insert(tag.rawValue)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TagToggleChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.ncCaption1.bold())
                .foregroundStyle(isSelected ? .white : Color.ncMuted)
                .padding(.horizontal, NCSpacing.md)
                .padding(.vertical, NCSpacing.sm + 1)
                .background(
                    isSelected ? Color.ncPurple : Color.ncBackground.opacity(0.5),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.ncDivider, lineWidth: 1)
                )
        }
        .buttonStyle(NCPressButtonStyle())
    }
}

// MARK: - Setup Card Container

private struct SetupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(NCSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                    .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
            )
            .ncShadow(.card)
    }
}

// MARK: - Recording Header

private struct RecordingHeader: View {
    let title: String
    let isPaused: Bool
    let back: () -> Void
    let options: () -> Void

    var body: some View {
        VStack(spacing: NCSpacing.sm) {
            HStack {
                Button(action: back) {
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                            .font(.ncCaption1.bold())
                    }
                    .foregroundStyle(Color.ncMuted)
                }
                .buttonStyle(NCPressButtonStyle())

                Spacer()

                // Live indicator
                HStack(spacing: NCSpacing.sm) {
                    Circle()
                        .fill(isPaused ? Color.ncWarning : Color.ncDanger)
                        .frame(width: 7, height: 7)
                        .shadow(color: (isPaused ? Color.ncWarning : Color.ncDanger).opacity(0.5), radius: 4)
                        .modifier(PulsingDotModifier())

                    Text(isPaused ? "PAUSED" : "LIVE")
                        .font(.ncCaption2)
                        .tracking(1.4)
                        .foregroundStyle(Color.ncMuted)
                }
                .padding(.horizontal, NCSpacing.md)
                .padding(.vertical, NCSpacing.xs + 2)
                .background(Color.ncSurface, in: Capsule())

                Spacer()

                Button(action: options) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ncMuted)
                        .frame(width: 34, height: 34)
                        .background(Color.ncSurface, in: Circle())
                }
                .buttonStyle(NCPressButtonStyle())
            }

            Text(title.uppercased())
                .font(.ncCaption1.bold())
                .tracking(2.0)
                .foregroundStyle(Color.ncInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, NCSpacing.sm + 2)
    }
}

// MARK: - Pulsating Mic

private struct PulsatingMicView: View {
    let audioLevel: CGFloat
    let isRecording: Bool

    @State private var breathe = false

    private var outerScale: CGFloat {
        let base: CGFloat = breathe ? 1.08 : 0.95
        return base + audioLevel * 0.15
    }

    private var midScale: CGFloat {
        let base: CGFloat = breathe ? 1.04 : 0.98
        return base + audioLevel * 0.10
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .fill(Color.ncPurple.opacity(0.06))
                .frame(width: 180, height: 180)
                .scaleEffect(outerScale)

            // Mid ring
            Circle()
                .fill(Color.ncPurple.opacity(0.12))
                .frame(width: 140, height: 140)
                .scaleEffect(midScale)

            // Inner ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.ncPurple.opacity(0.35), Color.ncPurple.opacity(0.15)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 55
                    )
                )
                .frame(width: 110, height: 110)
                .scaleEffect(1.0 + audioLevel * 0.08)

            // Core
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .shadow(color: Color.ncPurple.opacity(0.3), radius: 16, y: 4)

            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
        .task {
            guard isRecording else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

// MARK: - Premium Waveform

private struct PremiumWaveform: View {
    let level: CGFloat
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                let base = CGFloat(sin(Double(index) * 0.5 + Double(phase)) * 0.5 + 0.5)
                let height = 6 + 30 * max(base * 0.4, level * base)
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color.ncPurple, Color.ncPurple.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: height)
                    .animation(.easeOut(duration: 0.15), value: level)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                phase += 0.3
            }
        }
    }
}

// MARK: - Live Stat Pill

private struct LiveStatPill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: NCSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.ncCaption2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, NCSpacing.sm + 2)
        .padding(.vertical, NCSpacing.xs + 2)
        .background(color.opacity(0.08), in: Capsule())
    }
}

// MARK: - Moment Toast

private struct MomentToast: View {
    let timestamp: String

    var body: some View {
        HStack(spacing: NCSpacing.sm) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ncPurple)
            Text("Moment saved at \(timestamp)")
                .font(.ncCaption1.bold())
                .foregroundStyle(Color.ncInk)
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .ncShadow(.elevated)
    }
}

// MARK: - Processing Orb

private struct ProcessingOrb: View {
    @State private var rotate = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ncPurple.opacity(0.06))
                .frame(width: 150, height: 150)
                .scaleEffect(breathe ? 1.1 : 0.9)

            Circle()
                .fill(Color.ncPurple.opacity(0.12))
                .frame(width: 120, height: 120)
                .scaleEffect(breathe ? 0.95 : 1.05)

            Circle()
                .fill(
                    AngularGradient(
                        colors: [Color.ncPurple.opacity(0.3), Color.ncPurple.opacity(0.05), Color.ncPurple.opacity(0.3)],
                        center: .center
                    )
                )
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(rotate ? 360 : 0))

            ProgressView()
                .scaleEffect(1.3)
                .tint(.white)
        }
        .task {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotate = true
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

// MARK: - Processing Step

private struct ProcessingStep: View {
    let icon: String
    let text: String
    let done: Bool

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            ZStack {
                Circle()
                    .fill(done ? Color.ncSuccess.opacity(0.12) : Color.ncMuted.opacity(0.08))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ncSuccess)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color.ncMuted)
                }
            }

            Text(text)
                .font(.ncFootnote.weight(.medium))
                .foregroundStyle(done ? Color.ncInk : Color.ncMuted)
        }
    }
}

// MARK: - Result Stat Pill

private struct ResultStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: NCSpacing.xs) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.ncCaption2)
                .foregroundStyle(Color.ncMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.md)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Premium Recording Controls

private struct PremiumRecordingControls: View {
    let isPaused: Bool
    let isSaving: Bool
    let pauseOrResume: () -> Void
    let stop: () -> Void
    let mark: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            // Pause/Resume
            VStack(spacing: NCSpacing.sm) {
                Button(action: pauseOrResume) {
                    ZStack {
                        Circle()
                            .fill(Color.ncSurface)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Circle().strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                            )
                            .ncShadow(.card)

                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.ncInk)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(NCPressButtonStyle())

                Text(isPaused ? "Resume" : "Pause")
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncMuted)
            }

            Spacer()

            // Stop
            VStack(spacing: NCSpacing.sm) {
                Button(action: stop) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.ncDanger, Color(red: 0.90, green: 0.20, blue: 0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.ncDanger.opacity(0.35), radius: 12, y: 4)

                        Image(systemName: isSaving ? "hourglass" : "stop.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(NCPressButtonStyle())
                .disabled(isSaving)

                Text("Stop & Save")
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncDanger)
            }

            Spacer()

            // Mark moment
            VStack(spacing: NCSpacing.sm) {
                Button(action: mark) {
                    ZStack {
                        Circle()
                            .fill(Color.ncSurface)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Circle().strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                            )
                            .ncShadow(.card)

                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.ncPurple)
                    }
                }
                .buttonStyle(NCPressButtonStyle())

                Text("Bookmark")
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncMuted)
            }
        }
        .padding(.horizontal, NCSpacing.lg)
    }
}

// MARK: - Shared Subviews

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

private struct LiveInsightsCard: View {
    let text: String
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(spacing: NCSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                Text("AI LIVE INSIGHTS")
                    .font(.ncCaption1.bold())
                    .tracking(0.8)

                Spacer()

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }
            .foregroundStyle(Color.ncPurple)

            Text(text)
                .font(.ncCallout.weight(.medium))
                .italic()
                .lineSpacing(5)
                .foregroundStyle(Color.ncSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncPurple.opacity(0.08), lineWidth: 1)
        )
        .ncShadow(.card)
    }
}

private struct TranscriptToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Transcription")
                    .font(.ncCallout.bold())
                    .foregroundStyle(Color.ncInk)
                Text("Real-time captions")
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncMuted)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.ncPurple)
                .scaleEffect(0.85)
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.sm + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
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
                .frame(minHeight: 92, maxHeight: 140)
                .overlay(alignment: .topLeading) {
                    if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Listening for speech...")
                            .font(.ncCallout.weight(.medium))
                            .foregroundStyle(Color.ncMuted.opacity(0.5))
                            .padding(.top, NCSpacing.sm)
                            .padding(.leading, 5)
                    }
                }

            if !timestampedLines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NCSpacing.sm) {
                        ForEach(timestampedLines.suffix(4), id: \.self) { line in
                            Text(line)
                                .font(.ncCaption2.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(Color.ncMuted)
                                .padding(.horizontal, NCSpacing.sm + 2)
                                .padding(.vertical, NCSpacing.xs + 2)
                                .background(Color.ncBackground, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(NCSpacing.lg)
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

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Result Section Card

private struct ResultSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(spacing: NCSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ncPurple)
                Text(title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
        )
        .ncShadow(.card)
    }
}

// MARK: - Long Recording Banner

private struct LongRecordingBanner: View {
    let message: String
    let isWarning: Bool

    private var accent: Color {
        isWarning ? Color.ncWarning : Color.ncPurple
    }

    private var icon: String {
        isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 1)

            Text(message)
                .font(.ncCaption1)
                .foregroundStyle(Color.ncInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, NCSpacing.md)
        .padding(.vertical, NCSpacing.sm + 2)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }
}
