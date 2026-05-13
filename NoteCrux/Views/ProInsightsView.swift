import SwiftData
import SwiftUI

struct ProInsightsView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var tasks: [MeetingActionItem]
    @State private var showContent = false

    private let engine = ProInsightsEngine()

    private var activeMeetings: [Meeting] {
        meetings.filter { !$0.isDeleted }
    }

    private var activeTasks: [MeetingActionItem] {
        tasks.filter { !$0.isDeleted }
    }

    private var memory: KnowledgeMemorySnapshot {
        engine.knowledgeMemory(meetings: activeMeetings, tasks: activeTasks)
    }

    private var analytics: ProductivityAnalytics {
        engine.analytics(meetings: activeMeetings, tasks: activeTasks)
    }

    private var emotionalInsight: String? {
        let rate = analytics.taskCompletionRate
        let score = analytics.productivityScore
        if activeMeetings.isEmpty { return nil }
        if rate > 0.8 && score >= 70 {
            return "You're running efficient, action-driven meetings"
        } else if rate > 0.5 {
            return "Your follow-up clarity is improving"
        } else if analytics.lowValueMeetingCount == 0 {
            return "All your meetings produced outcomes this period"
        }
        return "Keep recording meetings to build your intelligence profile"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.ncBackground, Color.ncBackground, Color.ncPurple.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NCSpacing.xl + 4) {
                        // Header
                        InsightsHeader(emotionalInsight: emotionalInsight)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 12)

                        // Analytics widgets
                        analyticsWidgets
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Knowledge memory
                        if !memory.learnedThemes.isEmpty {
                            knowledgeMemorySection
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 16)
                        }

                        // AI suggestions
                        if !memory.suggestedNextSteps.isEmpty || !memory.suggestedImprovements.isEmpty {
                            aiSuggestionsSection
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 16)
                        }

                        // Recurring patterns
                        if !memory.recurringDecisions.isEmpty || !memory.recurringRisks.isEmpty {
                            recurringPatternsSection
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 16)
                        }

                        // Meeting scores
                        if !activeMeetings.isEmpty {
                            meetingScoresSection
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 16)
                        }

                        // Empty state
                        if activeMeetings.isEmpty {
                            InsightsEmptyState()
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 16)
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 94)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }

    // MARK: - Analytics Widgets

    private var analyticsWidgets: some View {
        VStack(spacing: NCSpacing.sm + 2) {
            HStack(spacing: NCSpacing.sm + 2) {
                // Productivity score ring
                ProductivityRingCard(
                    score: analytics.productivityScore,
                    label: "Productivity"
                )

                // Task completion
                ProgressMetricCard(
                    icon: "checkmark.circle.fill",
                    value: "\(Int(analytics.taskCompletionRate * 100))%",
                    label: "Tasks Done",
                    progress: analytics.taskCompletionRate,
                    accentColor: Color.ncSuccess
                )
            }

            HStack(spacing: NCSpacing.sm + 2) {
                // Meeting time
                IconMetricCard(
                    icon: "clock.fill",
                    value: analytics.formattedMeetingTime,
                    label: "Meeting Time",
                    subtitle: "\(analytics.meetingCount) meeting\(analytics.meetingCount == 1 ? "" : "s")",
                    accentColor: Color.ncPurple
                )

                // Actionable
                IconMetricCard(
                    icon: "target",
                    value: "\(analytics.actionableMeetingCount)",
                    label: "Actionable",
                    subtitle: analytics.lowValueMeetingCount > 0 ? "\(analytics.lowValueMeetingCount) low value" : "All productive",
                    accentColor: analytics.lowValueMeetingCount > 0 ? Color.ncWarning : Color.ncSuccess
                )
            }
        }
    }

    // MARK: - Knowledge Memory

    private var knowledgeMemorySection: some View {
        InsightsSectionCard(icon: "brain.fill", title: "Knowledge Memory", accent: Color.ncPurple) {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                // Theme chips
                FlowLayoutInsights(spacing: NCSpacing.sm) {
                    ForEach(memory.learnedThemes.prefix(6), id: \.self) { theme in
                        let keyword = extractKeyword(from: theme)
                        ThemeChip(text: keyword)
                    }
                }

                // Theme descriptions
                ForEach(Array(memory.learnedThemes.prefix(4).enumerated()), id: \.offset) { _, theme in
                    HStack(alignment: .top, spacing: NCSpacing.sm) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ncPurple)
                            .padding(.top, 4)
                        Text(theme)
                            .font(.ncFootnote.weight(.medium))
                            .foregroundStyle(Color.ncInk)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    // MARK: - AI Suggestions

    private var aiSuggestionsSection: some View {
        InsightsSectionCard(icon: "sparkles", title: "AI Suggestions", accent: Color.ncWarning) {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                ForEach(Array((memory.suggestedNextSteps + memory.suggestedImprovements).prefix(5).enumerated()), id: \.offset) { index, suggestion in
                    SuggestionRow(
                        text: suggestion,
                        isUrgent: index < memory.suggestedNextSteps.count && suggestion.contains("high-priority") || suggestion.contains("missed deadline")
                    )
                }
            }
        }
    }

    // MARK: - Recurring Patterns

    private var recurringPatternsSection: some View {
        InsightsSectionCard(icon: "arrow.triangle.2.circlepath", title: "Recurring Patterns", accent: Color(red: 0.31, green: 0.55, blue: 0.70)) {
            VStack(alignment: .leading, spacing: NCSpacing.md) {
                if !memory.recurringDecisions.isEmpty {
                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        HStack(spacing: NCSpacing.xs) {
                            Image(systemName: "arrow.right.arrow.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("DECISIONS")
                                .font(.ncCaption2)
                                .tracking(0.8)
                        }
                        .foregroundStyle(Color.ncMuted)

                        ForEach(Array(memory.recurringDecisions.prefix(3).enumerated()), id: \.offset) { _, item in
                            PatternRow(text: item, icon: "checkmark.seal.fill", color: Color.ncSuccess)
                        }
                    }
                }

                if !memory.recurringRisks.isEmpty {
                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        HStack(spacing: NCSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10, weight: .semibold))
                            Text("RISKS")
                                .font(.ncCaption2)
                                .tracking(0.8)
                        }
                        .foregroundStyle(Color.ncMuted)

                        ForEach(Array(memory.recurringRisks.prefix(3).enumerated()), id: \.offset) { _, item in
                            PatternRow(text: item, icon: "exclamationmark.triangle.fill", color: Color.ncDanger)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Meeting Scores

    private var meetingScoresSection: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack {
                HStack(spacing: NCSpacing.sm) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ncPurple)
                    Text("MEETING SCORES")
                        .font(.ncOverline)
                        .tracking(1.4)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()

                Text("\(activeMeetings.prefix(8).count) recent")
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncSecondary)
            }

            ForEach(activeMeetings.prefix(8)) { meeting in
                NavigationLink {
                    InsightView(meeting: meeting)
                } label: {
                    MeetingScoreCard(meeting: meeting, score: engine.meetingUsefulness(meeting))
                }
                .buttonStyle(InsightCardPressStyle())
            }
        }
    }

    private func extractKeyword(from theme: String) -> String {
        let words = theme.components(separatedBy: ": ")
        if words.count > 1 { return words.last ?? theme }
        return theme.replacingOccurrences(of: "You frequently discuss ", with: "")
            .replacingOccurrences(of: "Recurring topic: ", with: "")
            .replacingOccurrences(of: "Common theme across meetings: ", with: "")
            .replacingOccurrences(of: "Repeated focus area: ", with: "")
    }
}

// MARK: - Header

private struct InsightsHeader: View {
    let emotionalInsight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.ncCaption1)
                .foregroundStyle(Color.ncMuted)

            Text("Your AI Insights")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.ncInk)

            Text("What your meetings are teaching you over time")
                .font(.ncFootnote)
                .foregroundStyle(Color.ncSecondary)
                .lineSpacing(2)

            if let insight = emotionalInsight {
                HStack(spacing: NCSpacing.sm) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ncPurple)
                    Text(insight)
                        .font(.ncCaption1.weight(.semibold))
                        .foregroundStyle(Color.ncPurple)
                }
                .padding(.horizontal, NCSpacing.md)
                .padding(.vertical, NCSpacing.sm + 1)
                .background(Color.ncPurple.opacity(0.06), in: Capsule())
                .padding(.top, NCSpacing.xs)
            }
        }
        .padding(.top, NCSpacing.sm)
    }
}

// MARK: - Productivity Ring Card

private struct ProductivityRingCard: View {
    let score: Int
    let label: String

    private var scoreColor: Color {
        if score >= 70 { return Color.ncSuccess }
        if score >= 50 { return Color.ncWarning }
        return Color.ncDanger
    }

    var body: some View {
        VStack(spacing: NCSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.12), lineWidth: 6)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Text("\(score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
            }

            Text(label.uppercased())
                .font(.ncOverline)
                .tracking(0.8)
                .foregroundStyle(Color.ncMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSurface)
                .overlay(
                    LinearGradient(
                        colors: [scoreColor.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(scoreColor.opacity(0.08), lineWidth: 1)
        )
        .ncShadow(.card)
    }
}

// MARK: - Progress Metric Card

private struct ProgressMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let progress: Double
    let accentColor: Color

    var body: some View {
        VStack(spacing: NCSpacing.sm + 2) {
            HStack(spacing: NCSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.ncInk)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor.opacity(0.12))
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor)
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 5)
                }
            }
            .frame(height: 5)
            .padding(.horizontal, NCSpacing.md)

            Text(label.uppercased())
                .font(.ncOverline)
                .tracking(0.8)
                .foregroundStyle(Color.ncMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(accentColor.opacity(0.08), lineWidth: 1)
        )
        .ncShadow(.card)
    }
}

// MARK: - Icon Metric Card

private struct IconMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let subtitle: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: NCSpacing.sm) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.ncInk)

            VStack(spacing: 2) {
                Text(label.uppercased())
                    .font(.ncOverline)
                    .tracking(0.8)
                    .foregroundStyle(Color.ncMuted)
                Text(subtitle)
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
        )
        .ncShadow(.card)
    }
}

// MARK: - Section Card

private struct InsightsSectionCard<Content: View>: View {
    let icon: String
    let title: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.lg) {
            HStack(spacing: NCSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }

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

// MARK: - Theme Chip

private struct ThemeChip: View {
    let text: String

    var body: some View {
        Text(text.capitalized)
            .font(.ncCaption1.bold())
            .foregroundStyle(Color.ncPurple)
            .padding(.horizontal, NCSpacing.md)
            .padding(.vertical, NCSpacing.sm)
            .background(Color.ncPurple.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.ncPurple.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - Suggestion Row

private struct SuggestionRow: View {
    let text: String
    let isUrgent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.sm + 2) {
            ZStack {
                Circle()
                    .fill(isUrgent ? Color.ncDanger.opacity(0.10) : Color.ncWarning.opacity(0.10))
                    .frame(width: 24, height: 24)
                Image(systemName: isUrgent ? "exclamationmark.triangle.fill" : "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isUrgent ? Color.ncDanger : Color.ncWarning)
            }

            Text(text)
                .font(.ncFootnote.weight(.medium))
                .foregroundStyle(Color.ncInk)
                .lineSpacing(2)
        }
    }
}

// MARK: - Pattern Row

private struct PatternRow: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: NCSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 3)
            Text(text)
                .font(.ncFootnote.weight(.medium))
                .foregroundStyle(Color.ncInk)
                .lineSpacing(2)
        }
    }
}

// MARK: - Meeting Score Card

private struct MeetingScoreCard: View {
    let meeting: Meeting
    let score: (score: Int, summary: String)

    private var scoreColor: Color {
        if score.score >= 70 { return Color.ncSuccess }
        if score.score >= 50 { return Color.ncWarning }
        return Color.ncDanger
    }

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 4)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(score.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                Text("\(score.score)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
            }

            VStack(alignment: .leading, spacing: NCSpacing.xs + 1) {
                Text(meeting.title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)
                    .lineLimit(1)

                Text(score.summary)
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncSecondary)
                    .lineLimit(2)
                    .lineSpacing(1)

                HStack(spacing: NCSpacing.md) {
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "checklist")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(meeting.actionItems.count)")
                            .font(.ncCaption2)
                    }
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(meeting.decisions.count)")
                            .font(.ncCaption2)
                    }
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text(formatDuration(meeting.duration))
                            .font(.ncCaption2)
                    }
                }
                .foregroundStyle(Color.ncMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ncMuted.opacity(0.5))
        }
        .padding(NCSpacing.md + 2)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
        )
        .ncShadow(.subtle)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Empty State

private struct InsightsEmptyState: View {
    @State private var glowPulsing = false

    var body: some View {
        VStack(spacing: NCSpacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.06))
                    .frame(width: 100, height: 100)
                    .scaleEffect(glowPulsing ? 1.08 : 0.95)

                Circle()
                    .fill(Color.ncPurple.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "brain.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.ncPurple.opacity(0.7))
            }

            VStack(spacing: NCSpacing.sm) {
                Text("No insights yet")
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text("Record meetings to build your private\nAI knowledge base and intelligence profile.")
                    .font(.ncFootnote)
                    .foregroundStyle(Color.ncSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.xxxl)
        .padding(.horizontal, NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
        .task {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
        }
    }
}

// MARK: - Card Press Style

private struct InsightCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Flow Layout for Insights

private struct FlowLayoutInsights: Layout {
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
