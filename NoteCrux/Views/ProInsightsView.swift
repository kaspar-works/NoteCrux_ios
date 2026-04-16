import SwiftData
import SwiftUI

struct ProInsightsView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var tasks: [MeetingActionItem]

    private let engine = ProInsightsEngine()

    private var memory: KnowledgeMemorySnapshot {
        engine.knowledgeMemory(meetings: meetings, tasks: tasks)
    }

    private var analytics: ProductivityAnalytics {
        engine.analytics(meetings: meetings, tasks: tasks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpacing.xl) {
                    header

                    analyticsGrid

                    ProSection(title: "Knowledge Memory", icon: "brain") {
                        ProBulletList(items: memory.learnedThemes, emptyText: "Record more meetings to build your private knowledge base.")
                    }

                    ProSection(title: "AI Suggestions", icon: "lightbulb") {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            ProBulletList(items: memory.suggestedNextSteps, emptyText: "No urgent next steps detected.")
                            ProBulletList(items: memory.suggestedImprovements, emptyText: "No meeting improvements detected.")
                        }
                    }

                    ProSection(title: "Recurring Patterns", icon: "repeat") {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            ProBulletList(items: memory.recurringDecisions, emptyText: "No repeated decision patterns yet.")
                            ProBulletList(items: memory.recurringRisks, emptyText: "No repeated risk patterns yet.")
                        }
                    }

                    ProSection(title: "Meeting Scores", icon: "target") {
                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            ForEach(meetings.prefix(8)) { meeting in
                                MeetingScoreRow(meeting: meeting, score: engine.meetingUsefulness(meeting))
                            }
                        }
                    }
                }
                .padding(NCSpacing.xl)
            }
            .background(Color.ncBackground)
            .navigationTitle("Pro")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            Text("Knowledge Memory")
                .font(.ncLargeTitle)
                .foregroundStyle(Color.ncInk)
            Text("A private readout of what your meetings are teaching you.")
                .font(.ncCallout)
                .foregroundStyle(Color.ncSecondary)
        }
    }

    private var analyticsGrid: some View {
        VStack(spacing: NCSpacing.md) {
            HStack(spacing: NCSpacing.md) {
                NCMetricCard(title: "MEETING TIME", value: analytics.formattedMeetingTime, icon: "clock", isPrimary: true)
                NCMetricCard(title: "PRODUCTIVITY", value: "\(analytics.productivityScore)", icon: "chart.bar")
            }

            HStack(spacing: NCSpacing.md) {
                NCMetricCard(title: "TASKS DONE", value: percent(analytics.taskCompletionRate), icon: "checkmark.circle")
                NCMetricCard(title: "ACTIONABLE", value: "\(analytics.actionableMeetingCount)", icon: "target")
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}

private struct ProSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        NCCard {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                Label(title, systemImage: icon)
                    .font(.ncTitle3.bold())
                    .foregroundStyle(Color.ncPurple)
                content
            }
        }
    }
}

private struct ProBulletList: View {
    let items: [String]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            if items.isEmpty {
                Text(emptyText)
                    .font(.ncCallout)
                    .foregroundStyle(Color.ncMuted)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: NCSpacing.sm) {
                        Image(systemName: "sparkle")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncWarning)
                            .padding(.top, 3)
                        Text(item)
                            .font(.ncCallout)
                            .foregroundStyle(Color.ncInk)
                    }
                }
            }
        }
    }
}

private struct MeetingScoreRow: View {
    let meeting: Meeting
    let score: (score: Int, summary: String)

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            HStack {
                Text(meeting.title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)
                Spacer()
                Text("\(score.score)")
                    .font(.ncHeadline.monospacedDigit())
                    .foregroundStyle(score.score >= 70 ? Color.ncSuccess : Color.ncWarning)
            }

            Text(score.summary)
                .font(.ncCaption1)
                .foregroundStyle(Color.ncSecondary)

            HStack(spacing: NCSpacing.sm + 2) {
                Label("\(meeting.actionItems.count) tasks", systemImage: "checklist")
                Label("\(meeting.decisions.count) decisions", systemImage: "checkmark.seal")
                Label(formatDuration(meeting.duration), systemImage: "timer")
            }
            .font(.ncCaption2)
            .foregroundStyle(Color.ncMuted)
        }
        .padding(NCSpacing.md)
        .background(Color.ncSurfaceElevated, in: RoundedRectangle(cornerRadius: NCRadius.small))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return "\(minutes)m"
    }
}
