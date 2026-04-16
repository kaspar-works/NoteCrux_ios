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
            Color.detailBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MeetingDetailTopBar(
                        back: { dismiss() },
                        refresh: {
                            Task { await regenerateNotes() }
                        },
                        isRegenerating: isRegenerating
                    )

                    VStack(alignment: .leading, spacing: 9) {
                        Text("\(meeting.createdAt.detailDate)  •  \(meeting.duration.detailDuration) DURATION")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Color.detailPurple)

                        TextField("Meeting title", text: $meeting.title, axis: .vertical)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Color.detailInk)
                            .textInputAutocapitalization(.words)
                            .lineLimit(3)
                            .onSubmit { save() }

                        HStack(spacing: 5) {
                            ParticipantBubble(label: "👨‍💻")
                            ParticipantBubble(label: "🎨")
                            ParticipantBubble(label: "+\(max(1, meeting.tags.count + 1))")
                        }
                    }

                    DetailTabBar(selection: $selectedTab)

                    tabContent

                    BottomMetrics(
                        actionCount: meeting.actionItems.count,
                        score: smartInsights.effectivenessScore
                    )

                    RelatedMeetingsCard(meetings: smartInsights.relatedMeetings)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 94)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
                criticalInsight: criticalInsight
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
        isRegenerating = true
        let insights = await insightGenerator.generate(from: meeting.transcript)

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
}

private struct MeetingDetailTopBar: View {
    let back: () -> Void
    let refresh: () -> Void
    let isRegenerating: Bool

    var body: some View {
        HStack(spacing: 10) {
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)

            Text("DeepPocket")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.detailInk)

            Spacer()

            Button(action: refresh) {
                if isRegenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.detailMuted)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRegenerating)
        }
        .overlay(alignment: .leading) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.detailMuted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -38)
            .opacity(0)
        }
    }
}

private struct ParticipantBubble: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: label.hasPrefix("+") ? 10 : 14, weight: .bold))
            .frame(width: 25, height: 25)
            .background(Color.detailPurple.opacity(0.10), in: Circle())
            .foregroundStyle(Color.detailPurple)
    }
}

private struct DetailTabBar: View {
    @Binding var selection: DetailTab

    var body: some View {
        HStack(spacing: 21) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(selection == tab ? Color.detailPurple : Color.detailInk)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.detailPurple)
                                    .frame(height: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct NotesDetailContent: View {
    let summary: String
    let takeaways: [String]
    let milestones: [String]
    let criticalInsight: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DetailCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Executive Summary", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.detailInk)

                    Text(summary)
                        .font(.system(size: 14, weight: .medium))
                        .lineSpacing(5)
                        .foregroundStyle(Color.detailMuted)
                        .lineLimit(7)

                    Text("KEY TAKEAWAYS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Color.detailPurple)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(takeaways, id: \.self) { takeaway in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(Color.detailPurple)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 7)
                                Text(takeaway)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineSpacing(3)
                                    .foregroundStyle(Color.detailInk)
                            }
                        }
                    }
                }
                .padding(18)
            }

            VStack(alignment: .leading, spacing: 13) {
                Text("Roadmap Milestones")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.detailInk)

                DetailCard(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.offset) { index, item in
                        RoadmapRow(
                            title: item,
                            subtitle: index == 0 ? "Finalize review scheduled for July 20th" : "Sync with owner and confirm next checkpoint",
                            showsDivider: index < milestones.count - 1
                        )
                    }
                }
            }

            CriticalInsightCard(text: criticalInsight)
        }
    }
}

private struct TranscriptDetailCard: View {
    @Binding var transcript: String
    let save: () -> Void

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Transcript", systemImage: "text.quote")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.detailInk)

                TextEditor(text: $transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.detailInk)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 280)
                    .onChange(of: transcript) { _, _ in save() }
            }
            .padding(18)
        }
    }
}

private struct TasksDetailContent: View {
    let items: [MeetingActionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Action Items")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.detailInk)

            if items.isEmpty {
                DetailCard {
                    Text("No tasks extracted yet.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.detailMuted)
                        .padding(18)
                }
            } else {
                ForEach(items) { item in
                    TaskChecklistRow(item: item, showsMeetingTitle: false)
                }
            }
        }
    }
}

private struct HighlightsDetailContent: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Highlights")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.detailInk)

            if items.isEmpty {
                DetailCard {
                    Text("No highlights generated yet.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.detailMuted)
                        .padding(18)
                }
            } else {
                ForEach(items, id: \.self) { item in
                    DetailCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.detailPurple)
                            Text(item)
                                .font(.system(size: 14, weight: .medium))
                                .lineSpacing(4)
                                .foregroundStyle(Color.detailInk)
                        }
                        .padding(18)
                    }
                }
            }
        }
    }
}

private struct RoadmapRow: View {
    let title: String
    let subtitle: String
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.detailInk)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.detailMuted)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.detailMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            if showsDivider {
                Rectangle()
                    .fill(Color.detailBackground)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }
}

private struct CriticalInsightCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Critical Insight", systemImage: "diamond.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)

            Text("“\(text)”")
                .font(.system(size: 17, weight: .bold))
                .lineSpacing(4)
                .foregroundStyle(.white)
                .lineLimit(5)

            HStack(spacing: 9) {
                ParticipantBubble(label: "👤")
                    .background(.clear)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alex Johnson")
                        .font(.system(size: 11, weight: .bold))
                    Text("Design Lead")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.76)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.detailPurple, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.detailPurple.opacity(0.22), radius: 18, y: 9)
    }
}

private struct BottomMetrics: View {
    let actionCount: Int
    let score: Int

    var body: some View {
        HStack(spacing: 14) {
            MetricBox(title: "ACTION ITEMS", value: "\(actionCount)")
            MetricBox(title: "SENTIMENT", value: "\(min(100, max(0, score)))%", valueColor: Color(red: 0.10, green: 0.68, blue: 0.34))
        }
    }
}

private struct MetricBox: View {
    let title: String
    let value: String
    var valueColor: Color = Color.detailInk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.detailMuted)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.detailSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 12, y: 6)
    }
}

private struct RelatedMeetingsCard: View {
    let meetings: [Meeting]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("RELATED MEETINGS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.detailMuted)

            DetailCard(spacing: 0) {
                if meetings.isEmpty {
                    Text("No related meetings found yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.detailMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(Array(meetings.prefix(2).enumerated()), id: \.element.id) { index, meeting in
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meeting.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.detailInk)
                                    Text(meeting.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.detailMuted)
                                }
                                Spacer()
                            }
                            .padding(14)

                            if index == 0 && meetings.count > 1 {
                                Rectangle()
                                    .fill(Color.detailBackground)
                                    .frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DetailCard<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.detailSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 12, y: 6)
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case notes = "Notes"
    case tasks = "Tasks"
    case highlights = "Highlight"

    var id: String { rawValue }
}

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

private extension Color {
    static let detailBackground = Color.adaptive(light: (0.982, 0.982, 0.988), dark: (0.055, 0.056, 0.072))
    static let detailSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let detailInk = Color.adaptive(light: (0.13, 0.13, 0.15), dark: (0.93, 0.94, 0.97))
    static let detailMuted = Color.adaptive(light: (0.49, 0.49, 0.56), dark: (0.62, 0.64, 0.72))
    static let detailPurple = Color.adaptive(light: (0.25, 0.18, 0.86), dark: (0.58, 0.50, 1.0))
}
