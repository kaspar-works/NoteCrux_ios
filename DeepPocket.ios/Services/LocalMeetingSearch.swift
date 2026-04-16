import Foundation

struct LocalMeetingSearch {
    func matches(_ meeting: Meeting, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        let terms = expandedTerms(for: normalizedQuery)
        let searchableText = [
            meeting.title,
            meeting.tags.joined(separator: " "),
            meeting.folder?.name ?? "",
            meeting.transcript,
            meeting.summary,
            meeting.paragraphNotes,
            meeting.quickRead,
            meeting.bulletSummary.joined(separator: " "),
            meeting.highlights.joined(separator: " "),
            meeting.importantLines.joined(separator: " "),
            meeting.keyPoints.joined(separator: " "),
            meeting.decisions.joined(separator: " "),
            meeting.risks.joined(separator: " "),
            meeting.actionItems.map { "\($0.title) \($0.detail) \($0.owner)" }.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return terms.contains { searchableText.contains($0) }
    }

    private func expandedTerms(for query: String) -> [String] {
        var terms = query
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }

        terms.append(query)

        let semanticGroups: [(triggers: [String], expansions: [String])] = [
            (
                ["api", "integration", "endpoint", "server"],
                ["api", "endpoint", "integration", "backend", "server", "request", "response"]
            ),
            (
                ["issue", "issues", "problem", "bug", "blocked", "blocker"],
                ["issue", "problem", "bug", "blocked", "blocker", "risk", "concern", "failure"]
            ),
            (
                ["deadline", "deadlines", "due", "timeline", "schedule"],
                ["deadline", "due", "timeline", "schedule", "today", "tomorrow", "next week", "friday"]
            ),
            (
                ["decision", "decisions", "approved", "agreed"],
                ["decision", "decided", "approved", "agreed", "confirmed"]
            ),
            (
                ["client", "customer", "account"],
                ["client", "customer", "account", "stakeholder"]
            ),
            (
                ["task", "tasks", "todo", "followup"],
                ["task", "todo", "to do", "follow up", "action item", "next step"]
            )
        ]

        for group in semanticGroups where group.triggers.contains(where: { query.contains($0) }) {
            terms.append(contentsOf: group.expansions)
        }

        return Array(Set(terms))
    }
}
