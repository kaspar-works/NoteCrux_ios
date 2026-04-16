import SwiftData
import SwiftUI

struct ProInsightsView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                VStack(alignment: .leading, spacing: 18) {
                    header

                    analyticsGrid

                    ProSection(title: "Knowledge Memory", icon: "brain") {
                        ProBulletList(items: memory.learnedThemes, emptyText: "Record more meetings to build your private knowledge base.")
                    }

                    ProSection(title: "AI Suggestions", icon: "lightbulb") {
                        VStack(alignment: .leading, spacing: 12) {
                            ProBulletList(items: memory.suggestedNextSteps, emptyText: "No urgent next steps detected.")
                            ProBulletList(items: memory.suggestedImprovements, emptyText: "No meeting improvements detected.")
                        }
                    }

                    ProSection(title: "Recurring Patterns", icon: "repeat") {
                        VStack(alignment: .leading, spacing: 12) {
                            ProBulletList(items: memory.recurringDecisions, emptyText: "No repeated decision patterns yet.")
                            ProBulletList(items: memory.recurringRisks, emptyText: "No repeated risk patterns yet.")
                        }
                    }

                    ProSection(title: "Meeting Scores", icon: "target") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(meetings.prefix(8)) { meeting in
                                MeetingScoreRow(meeting: meeting, score: engine.meetingUsefulness(meeting))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(NoteCruxTheme.background(for: colorScheme))
            .navigationTitle("Pro")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knowledge Memory")
                .font(.largeTitle.bold())
            Text("A private readout of what your meetings are teaching you.")
                .foregroundStyle(.secondary)
        }
    }

    private var analyticsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricTile(value: analytics.formattedMeetingTime, label: "Meeting Time", icon: "clock")
                MetricTile(value: "\(analytics.productivityScore)", label: "Productivity", icon: "chart.bar")
            }

            HStack(spacing: 12) {
                MetricTile(value: percent(analytics.taskCompletionRate), label: "Tasks Done", icon: "checkmark.circle")
                MetricTile(value: "\(analytics.actionableMeetingCount)", label: "Actionable", icon: "target")
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
        PremiumCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                content
            }
        }
    }
}

private struct ProBulletList: View {
    let items: [String]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(.top, 3)
                        Text(item)
                            .font(.subheadline)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meeting.title)
                    .font(.headline)
                Spacer()
                Text("\(score.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(score.score >= 70 ? .green : .yellow)
            }

            Text(score.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label("\(meeting.actionItems.count) tasks", systemImage: "checklist")
                Label("\(meeting.decisions.count) decisions", systemImage: "checkmark.seal")
                Label(formatDuration(meeting.duration), systemImage: "timer")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return "\(minutes)m"
    }
}
