import Foundation

struct ProInsightsEngine {
    func knowledgeMemory(meetings: [Meeting], tasks: [MeetingActionItem]) -> KnowledgeMemorySnapshot {
        let themes = topTerms(from: meetings.flatMap { meeting in
            [meeting.summary, meeting.paragraphNotes, meeting.keyPoints.joined(separator: " "), meeting.highlights.joined(separator: " ")]
        }.joined(separator: " "))

        let decisions = repeatedLines(
            meetings.flatMap(\.decisions),
            fallbackPrefix: "Decision pattern"
        )

        let risks = repeatedLines(
            meetings.flatMap(\.risks),
            fallbackPrefix: "Risk pattern"
        )

        return KnowledgeMemorySnapshot(
            learnedThemes: themes.map { "You keep learning about \($0)." },
            recurringDecisions: decisions,
            recurringRisks: risks,
            suggestedNextSteps: suggestedNextSteps(meetings: meetings, tasks: tasks),
            suggestedImprovements: suggestedImprovements(meetings: meetings, tasks: tasks)
        )
    }

    func analytics(meetings: [Meeting], tasks: [MeetingActionItem]) -> ProductivityAnalytics {
        let totalTasks = tasks.count
        let completedTasks = tasks.filter(\.isComplete).count
        let completionRate = totalTasks == 0 ? 0 : Double(completedTasks) / Double(totalTasks)
        let totalMeetingTime = meetings.reduce(0) { $0 + $1.duration }
        let actionable = meetings.filter { !$0.actionItems.isEmpty || !$0.decisions.isEmpty }.count
        let lowValue = meetings.filter { meeting in
            meeting.actionItems.isEmpty &&
                meeting.decisions.isEmpty &&
                meeting.duration > 20 * 60
        }.count

        var score = Int(completionRate * 45)
        if !meetings.isEmpty {
            score += Int((Double(actionable) / Double(meetings.count)) * 40)
        }
        if lowValue == 0 {
            score += 15
        } else {
            score += max(0, 15 - lowValue * 5)
        }

        return ProductivityAnalytics(
            totalMeetingTime: totalMeetingTime,
            meetingCount: meetings.count,
            completedTaskCount: completedTasks,
            totalTaskCount: totalTasks,
            taskCompletionRate: completionRate,
            productivityScore: min(max(score, 0), 100),
            actionableMeetingCount: actionable,
            lowValueMeetingCount: lowValue
        )
    }

    func meetingUsefulness(_ meeting: Meeting) -> (score: Int, summary: String) {
        var score = 40
        score += min(meeting.actionItems.count * 8, 24)
        score += min(meeting.decisions.count * 10, 20)
        score += min(meeting.highlights.count * 3, 9)
        score -= min(meeting.risks.count * 4, 16)
        if meeting.duration > 3600 { score -= 8 }
        if meeting.actionItems.isEmpty && meeting.decisions.isEmpty { score -= 16 }

        let bounded = min(max(score, 0), 100)
        let summary: String
        if bounded >= 75 {
            summary = "Useful meeting: it produced decisions, tasks, or clear takeaways."
        } else if bounded >= 50 {
            summary = "Moderately useful: some value was captured, but follow-up could be clearer."
        } else {
            summary = "Low actionability: this may have been more discussion than progress."
        }

        return (bounded, summary)
    }

    private func suggestedNextSteps(meetings: [Meeting], tasks: [MeetingActionItem]) -> [String] {
        var suggestions: [String] = []
        let pendingHigh = tasks.filter { !$0.isComplete && $0.priority == .high }
        let overdue = tasks.filter { task in
            !task.isComplete && (task.deadline ?? task.reminderDate ?? .distantFuture) < Date()
        }

        if !pendingHigh.isEmpty {
            suggestions.append("Finish or reschedule \(pendingHigh.count) high-priority open task\(pendingHigh.count == 1 ? "" : "s").")
        }

        if !overdue.isEmpty {
            suggestions.append("Review \(overdue.count) missed deadline\(overdue.count == 1 ? "" : "s") before the next meeting.")
        }

        let meetingsWithoutActions = meetings.filter { $0.actionItems.isEmpty && $0.decisions.isEmpty }
        if !meetingsWithoutActions.isEmpty {
            suggestions.append("Add explicit decisions or tasks to meetings that currently have no outcomes.")
        }

        return Array(suggestions.prefix(5))
    }

    private func suggestedImprovements(meetings: [Meeting], tasks: [MeetingActionItem]) -> [String] {
        var improvements: [String] = []
        let longMeetings = meetings.filter { $0.duration > 3600 }
        let unassignedTasks = tasks.filter { !$0.isComplete && $0.owner == "Unassigned" }

        if !longMeetings.isEmpty {
            improvements.append("Shorten long meetings or split them into focused sessions.")
        }

        if !unassignedTasks.isEmpty {
            improvements.append("Assign owners to \(unassignedTasks.count) open task\(unassignedTasks.count == 1 ? "" : "s").")
        }

        if meetings.contains(where: { $0.risks.count > $0.decisions.count + 2 }) {
            improvements.append("Convert repeated risks into tracked tasks before they carry into the next meeting.")
        }

        return Array(improvements.prefix(5))
    }

    private func repeatedLines(_ lines: [String], fallbackPrefix: String) -> [String] {
        let tokens = topTerms(from: lines.joined(separator: " "))
        if tokens.isEmpty {
            return Array(lines.prefix(3))
        }
        return tokens.map { "\(fallbackPrefix): \($0)." }
    }

    private func topTerms(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "that", "this", "with", "from", "have", "will", "need", "meeting",
            "about", "there", "their", "should", "would", "could", "were",
            "been", "into", "next", "task", "tasks", "notes", "summary"
        ]

        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }

        let counts = Dictionary(grouping: words, by: { $0 }).mapValues(\.count)
        return counts
            .filter { $0.value > 1 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(6)
            .map(\.key)
    }
}
