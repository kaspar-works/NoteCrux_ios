import Foundation
import OSLog

struct MeetingAssistantEngine {
    private let search = LocalMeetingSearch()
    private let proEngine = ProInsightsEngine()

    struct AnswerResult {
        let answer: String
        let citedMeetings: [Meeting]
        let usedFM: Bool
    }

    func answer(
        question: String,
        meetings: [Meeting],
        tasks: [MeetingActionItem],
        topN: Int = 5
    ) async -> AnswerResult {
        let ranked = rankedMeetings(for: question, in: meetings).prefix(topN)

        guard FoundationModelClient.shared.isAvailable else {
            return AnswerResult(
                answer: keywordAnswer(question: question, meetings: meetings, tasks: tasks),
                citedMeetings: Array(ranked),
                usedFM: false
            )
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let context = ranked.map { meeting in
                FoundationModelClient.MeetingContext(
                    title: meeting.title,
                    summary: meeting.summary,
                    createdAt: meeting.createdAt
                )
            }

            do {
                let fm = try await FoundationModelClient.shared.answer(question: question, context: context)
                // Map cited titles back to Meetings; capped at 5 in the prompt.
                let cited = fm.citedMeetingTitles.compactMap { title in
                    meetings.first(where: { $0.title == title })
                }
                return AnswerResult(answer: fm.answer, citedMeetings: cited, usedFM: true)
            } catch {
                NoteCruxLog.ai.debug("MeetingAssistantEngine: FM failed, falling back to keyword")
                return AnswerResult(
                    answer: keywordAnswer(question: question, meetings: meetings, tasks: tasks),
                    citedMeetings: Array(ranked),
                    usedFM: false
                )
            }
        }
        #endif
        return AnswerResult(
            answer: keywordAnswer(question: question, meetings: meetings, tasks: tasks),
            citedMeetings: Array(ranked),
            usedFM: false
        )
    }

    /// Simple keyword-score ranking for context selection. Independent of keywordAnswer output text.
    func rankedMeetings(for query: String, in meetings: [Meeting]) -> [Meeting] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }

        guard !terms.isEmpty else { return meetings.sorted { $0.createdAt > $1.createdAt } }

        func score(_ meeting: Meeting) -> Int {
            let haystack = (meeting.title + " " + meeting.summary + " " + meeting.transcript).lowercased()
            return terms.reduce(0) { partial, term in
                partial + (haystack.contains(term) ? 1 : 0)
            }
        }

        return meetings
            .map { (score($0), $0) }
            .filter { $0.0 > 0 }
            .sorted { $0.0 > $1.0 }
            .map { $0.1 }
    }

    func keywordAnswer(question: String, meetings: [Meeting], tasks: [MeetingActionItem]) -> String {
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return "Ask about decisions, tasks, deadlines, issues, or a topic from your meetings."
        }

        let lowercased = query.lowercased()
        let scopedMeetings = dateScopedMeetings(for: lowercased, meetings: meetings)
        let matchingMeetings = scopedMeetings.filter { search.matches($0, query: query) }
        let sourceMeetings = matchingMeetings.isEmpty ? scopedMeetings : matchingMeetings

        if lowercased.contains("learned") || lowercased.contains("knowledge") {
            return knowledgeAnswer(from: meetings, tasks: tasks)
        }

        if lowercased.contains("improve") || lowercased.contains("suggest") || lowercased.contains("next step") {
            return suggestionAnswer(from: meetings, tasks: tasks)
        }

        if lowercased.contains("productivity") || lowercased.contains("useful") || lowercased.contains("wasted") {
            return productivityAnswer(from: meetings, tasks: tasks)
        }

        if lowercased.contains("task") || lowercased.contains("todo") || lowercased.contains("to-do") {
            return taskAnswer(from: tasks, meetings: sourceMeetings, question: lowercased)
        }

        if lowercased.contains("decide") || lowercased.contains("decision") {
            return decisionAnswer(from: sourceMeetings)
        }

        if lowercased.contains("deadline") || lowercased.contains("due") || lowercased.contains("late") {
            return deadlineAnswer(from: tasks, meetings: sourceMeetings)
        }

        if lowercased.contains("issue") || lowercased.contains("risk") || lowercased.contains("blocked") || lowercased.contains("blocker") {
            return issueAnswer(from: sourceMeetings)
        }

        return generalAnswer(from: sourceMeetings, query: query)
    }

    func relatedMeetings(to meeting: Meeting, allMeetings: [Meeting]) -> [Meeting] {
        let terms = Set(tokens(from: [
            meeting.title,
            meeting.tags.joined(separator: " "),
            meeting.summary,
            meeting.keyPoints.joined(separator: " "),
            meeting.decisions.joined(separator: " "),
            meeting.risks.joined(separator: " ")
        ].joined(separator: " ")))

        return allMeetings
            .filter { $0.id != meeting.id }
            .map { other in
                (meeting: other, score: overlapScore(terms, tokens(from: searchableText(for: other))))
            }
            .filter { $0.score >= 2 }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map(\.meeting)
    }

    func smartInsights(for meeting: Meeting, allMeetings: [Meeting], tasks: [MeetingActionItem]) -> MeetingSmartInsights {
        let related = relatedMeetings(to: meeting, allMeetings: allMeetings)
        let repeatedIssues = repeatedIssues(in: [meeting] + related)
        let missed = tasks.filter { task in
            task.meeting?.id == meeting.id &&
                !task.isComplete &&
                (task.deadline ?? task.reminderDate ?? .distantFuture) < Date()
        }
        let score = effectivenessScore(for: meeting, missedDeadlines: missed)

        return MeetingSmartInsights(
            repeatedIssues: repeatedIssues,
            missedDeadlines: missed,
            relatedMeetings: related,
            effectivenessScore: score,
            effectivenessSummary: effectivenessSummary(score)
        )
    }

    private func dateScopedMeetings(for query: String, meetings: [Meeting]) -> [Meeting] {
        let calendar = Calendar.current

        if query.contains("yesterday") {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return meetings }
            return meetings.filter { calendar.isDate($0.createdAt, inSameDayAs: yesterday) }
        }

        if query.contains("today") {
            return meetings.filter { calendar.isDateInToday($0.createdAt) }
        }

        if query.contains("last week") {
            guard let lastWeek = calendar.date(byAdding: .day, value: -7, to: Date()) else { return meetings }
            return meetings.filter { calendar.isDate($0.createdAt, equalTo: lastWeek, toGranularity: .weekOfYear) }
        }

        return meetings
    }

    private func taskAnswer(from tasks: [MeetingActionItem], meetings: [Meeting], question: String) -> String {
        let meetingIDs = Set(meetings.map(\.id))
        let matchedTasks = tasks
            .filter { task in
                guard let meeting = task.meeting else { return false }
                return meetingIDs.contains(meeting.id)
            }
            .filter { question.contains("all") || !$0.isComplete }

        guard !matchedTasks.isEmpty else {
            return "I did not find matching tasks in those meetings."
        }

        return matchedTasks.prefix(8).map { task in
            let status = task.isComplete ? "done" : "pending"
            let owner = task.owner == "Unassigned" ? "unassigned" : task.owner
            return "- \(task.title) (\(status), \(task.priority.rawValue), \(owner))"
        }.joined(separator: "\n")
    }

    private func decisionAnswer(from meetings: [Meeting]) -> String {
        let decisions = meetings.flatMap { meeting in
            meeting.decisions.map { "- \($0) [\(meeting.title)]" }
        }

        return decisions.isEmpty ? "I did not find explicit decisions in the matching meetings." : decisions.prefix(10).joined(separator: "\n")
    }

    private func deadlineAnswer(from tasks: [MeetingActionItem], meetings: [Meeting]) -> String {
        let meetingIDs = Set(meetings.map(\.id))
        let deadlineTasks = tasks
            .filter { task in
                guard let meeting = task.meeting else { return false }
                return meetingIDs.contains(meeting.id) && (task.deadline != nil || task.reminderDate != nil)
            }

        guard !deadlineTasks.isEmpty else {
            return "I did not find deadlines in the matching meetings."
        }

        return deadlineTasks.prefix(10).map { task in
            let date = (task.deadline ?? task.reminderDate)?.formatted(date: .abbreviated, time: .shortened) ?? "No date"
            return "- \(task.title) due \(date)"
        }.joined(separator: "\n")
    }

    private func issueAnswer(from meetings: [Meeting]) -> String {
        let issues = meetings.flatMap { meeting in
            (meeting.risks + meeting.importantLines)
                .filter { line in
                    let lowercased = line.lowercased()
                    return lowercased.contains("issue") ||
                        lowercased.contains("risk") ||
                        lowercased.contains("blocked") ||
                        lowercased.contains("concern")
                }
                .map { "- \($0) [\(meeting.title)]" }
        }

        return issues.isEmpty ? "I did not find repeated issues or blockers in the matching meetings." : issues.prefix(10).joined(separator: "\n")
    }

    private func generalAnswer(from meetings: [Meeting], query: String) -> String {
        guard !meetings.isEmpty else {
            return "I could not find meetings matching “\(query)”."
        }

        return meetings.prefix(5).map { meeting in
            "- \(meeting.title): \(meeting.quickRead.isEmpty ? meeting.summary : meeting.quickRead)"
        }.joined(separator: "\n")
    }

    private func knowledgeAnswer(from meetings: [Meeting], tasks: [MeetingActionItem]) -> String {
        let memory = proEngine.knowledgeMemory(meetings: meetings, tasks: tasks)
        let items = memory.learnedThemes + memory.recurringDecisions + memory.recurringRisks
        return items.isEmpty ? "I need more meetings before I can summarize what you have learned." : items.prefix(10).map { "- \($0)" }.joined(separator: "\n")
    }

    private func suggestionAnswer(from meetings: [Meeting], tasks: [MeetingActionItem]) -> String {
        let memory = proEngine.knowledgeMemory(meetings: meetings, tasks: tasks)
        let items = memory.suggestedNextSteps + memory.suggestedImprovements
        return items.isEmpty ? "No strong next-step suggestions found yet." : items.prefix(10).map { "- \($0)" }.joined(separator: "\n")
    }

    private func productivityAnswer(from meetings: [Meeting], tasks: [MeetingActionItem]) -> String {
        let analytics = proEngine.analytics(meetings: meetings, tasks: tasks)
        return """
        Productivity score: \(analytics.productivityScore)
        Meeting time: \(analytics.formattedMeetingTime)
        Task completion: \(Int(analytics.taskCompletionRate * 100))%
        Actionable meetings: \(analytics.actionableMeetingCount)
        Low-value meetings: \(analytics.lowValueMeetingCount)
        """
    }

    private func repeatedIssues(in meetings: [Meeting]) -> [String] {
        let issueWords = meetings
            .flatMap { $0.risks + $0.importantLines }
            .flatMap(tokens)
            .filter { ["api", "deadline", "blocked", "risk", "bug", "client", "schedule", "launch", "issue"].contains($0) }

        let counts = Dictionary(grouping: issueWords, by: { $0 }).mapValues(\.count)
        return counts
            .filter { $0.value > 1 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key.capitalized) came up \($0.value) times across related meetings." }
    }

    private func effectivenessScore(for meeting: Meeting, missedDeadlines: [MeetingActionItem]) -> Int {
        var score = 72
        if !meeting.decisions.isEmpty { score += 10 }
        if !meeting.actionItems.isEmpty { score += 8 }
        if !meeting.summary.isEmpty { score += 5 }
        if meeting.risks.count > 3 { score -= 8 }
        score -= missedDeadlines.count * 8
        if meeting.duration > 3600 { score -= 5 }
        return min(max(score, 0), 100)
    }

    private func effectivenessSummary(_ score: Int) -> String {
        if score >= 85 { return "Strong meeting: clear outcomes and manageable follow-up." }
        if score >= 65 { return "Useful meeting: some decisions or tasks were captured." }
        return "Needs follow-up: unresolved risks or missed tasks may need attention."
    }

    private func searchableText(for meeting: Meeting) -> String {
        [
            meeting.title,
            meeting.tags.joined(separator: " "),
            meeting.summary,
            meeting.keyPoints.joined(separator: " "),
            meeting.decisions.joined(separator: " "),
            meeting.risks.joined(separator: " ")
        ].joined(separator: " ")
    }

    private func tokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
    }

    private func overlapScore(_ lhs: Set<String>, _ rhs: [String]) -> Int {
        rhs.reduce(0) { partialResult, token in
            partialResult + (lhs.contains(token) ? 1 : 0)
        }
    }
}
