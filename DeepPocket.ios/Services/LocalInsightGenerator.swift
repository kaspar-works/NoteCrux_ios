import Foundation

struct LocalInsightGenerator {
    func generate(from transcript: String) async -> InsightDraft {
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else {
            return InsightDraft(
                summary: "No transcript was captured.",
                paragraphNotes: "No transcript was captured, so DeepPocket could not generate notes.",
                bulletSummary: [],
                highlights: [],
                importantLines: [],
                quickRead: "No transcript captured.",
                keyPoints: [],
                decisions: [],
                risks: [],
                actionItems: []
            )
        }

        #if canImport(FoundationModels)
        return await generateWithFoundationModels(from: cleanTranscript)
        #else
        return generateHeuristicInsights(from: cleanTranscript)
        #endif
    }

    private func generateHeuristicInsights(from transcript: String) -> InsightDraft {
        let sentences = transcript
            .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let rankedSentences = sentences.sorted { score($0) > score($1) }
        let summarySentences = Array(sentences.prefix(3))
        let paragraphNotes = makeParagraphNotes(from: sentences)
        let bulletSummary = Array(summarySentences.prefix(5))
        let highlights = Array(rankedSentences.prefix(5))
        let importantLines = Array(rankedSentences.filter { score($0) >= 3 }.prefix(8))
        let quickRead = Array(rankedSentences.prefix(3)).joined(separator: ". ")
        let summary = summarySentences.joined(separator: ". ")
        let actionItems = sentences
            .filter(isLikelyTask)
            .prefix(8)
            .map { sentence in
                ActionItemDraft(
                    title: cleanTaskTitle(sentence),
                    detail: sentence,
                    owner: detectOwner(in: sentence),
                    deadline: detectDueDate(in: sentence),
                    priority: detectPriority(in: sentence),
                    confidence: confidence(for: sentence),
                    sourceQuote: sentence
                )
            }

        let decisionMatches: [String] = sentences
            .filter {
                let lowercased = $0.lowercased()
                return lowercased.contains("decided") ||
                    lowercased.contains("approved") ||
                    lowercased.contains("agreed")
            }

        let riskMatches: [String] = sentences
            .filter {
                let lowercased = $0.lowercased()
                return lowercased.contains("blocked") ||
                    lowercased.contains("risk") ||
                    lowercased.contains("concern") ||
                    lowercased.contains("issue")
            }

        return InsightDraft(
            summary: summary.isEmpty ? "Transcript captured. Summary will improve as more speech is recorded." : summary + ".",
            paragraphNotes: paragraphNotes,
            bulletSummary: bulletSummary,
            highlights: highlights,
            importantLines: importantLines,
            quickRead: quickRead.isEmpty ? "Transcript captured." : quickRead + ".",
            keyPoints: Array(rankedSentences.prefix(6)),
            decisions: Array(decisionMatches.prefix(5)),
            risks: Array(riskMatches.prefix(5)),
            actionItems: Array(actionItems)
        )
    }

    private func makeParagraphNotes(from sentences: [String]) -> String {
        guard !sentences.isEmpty else {
            return "No transcript was captured, so DeepPocket could not generate notes."
        }

        let intro = Array(sentences.prefix(3)).joined(separator: ". ")
        let middleStart = min(3, sentences.count)
        let middleEnd = min(middleStart + 3, sentences.count)
        let followUp = sentences[middleStart..<middleEnd].joined(separator: ". ")

        if followUp.isEmpty {
            return intro + "."
        }

        return intro + ".\n\n" + followUp + "."
    }

    private func score(_ sentence: String) -> Int {
        let lowercased = sentence.lowercased()
        var value = min(sentence.count / 80, 2)

        let highSignalTerms = [
            "decided", "decision", "approved", "agreed", "important",
            "critical", "deadline", "blocker", "blocked", "risk",
            "concern", "issue", "must", "need to", "will", "follow up",
            "next step", "action item", "priority", "launch", "customer"
        ]

        for term in highSignalTerms where lowercased.contains(term) {
            value += 2
        }

        return value
    }

    private func isLikelyTask(_ sentence: String) -> Bool {
        let lowercased = sentence.lowercased()
        let taskSignals = [
            "will ", "need to", "needs to", "follow up", "todo", "to do",
            "action item", "next step", "take care of", "send", "schedule",
            "prepare", "review", "call", "email", "finish", "complete",
            "assign", "deliver"
        ]

        return taskSignals.contains { lowercased.contains($0) }
    }

    private func cleanTaskTitle(_ sentence: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(77)) + "..."
    }

    private func detectOwner(in sentence: String) -> String {
        let words = sentence
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map(String.init)

        for index in words.indices {
            let word = words[index].lowercased()
            if ["by", "from", "owner", "assigned"].contains(word),
               words.index(after: index) < words.endIndex {
                return words[words.index(after: index)].trimmingCharacters(in: .punctuationCharacters)
            }
        }

        if let first = words.first, first.first?.isUppercase == true, words.count > 2 {
            return first.trimmingCharacters(in: .punctuationCharacters)
        }

        return "Unassigned"
    }

    private func detectDueDate(in sentence: String) -> Date? {
        let lowercased = sentence.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lowercased.contains("today") {
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        }

        if lowercased.contains("tomorrow") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow)
        }

        if lowercased.contains("next week") {
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek)
        }

        let weekdayMatches: [(String, Int)] = [
            ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5),
            ("friday", 6), ("saturday", 7), ("sunday", 1)
        ]

        for (name, weekday) in weekdayMatches where lowercased.contains(name) {
            return nextDate(matchingWeekday: weekday)
        }

        return nil
    }

    private func nextDate(matchingWeekday targetWeekday: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let daysUntilTarget = (targetWeekday - currentWeekday + 7) % 7
        let offset = daysUntilTarget == 0 ? 7 : daysUntilTarget
        let targetDate = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDate)
    }

    private func detectPriority(in sentence: String) -> TaskPriority {
        let lowercased = sentence.lowercased()

        if lowercased.contains("urgent") ||
            lowercased.contains("asap") ||
            lowercased.contains("critical") ||
            lowercased.contains("blocked") ||
            lowercased.contains("must") {
            return .high
        }

        if lowercased.contains("nice to have") ||
            lowercased.contains("later") ||
            lowercased.contains("low priority") {
            return .low
        }

        return .medium
    }

    private func confidence(for sentence: String) -> ActionConfidence {
        let lowercased = sentence.lowercased()

        if lowercased.contains("action item") ||
            lowercased.contains("will ") ||
            lowercased.contains("need to") ||
            lowercased.contains("deadline") {
            return .high
        }

        if lowercased.contains("maybe") || lowercased.contains("could") {
            return .low
        }

        return .medium
    }

    #if canImport(FoundationModels)
    private func generateWithFoundationModels(from transcript: String) async -> InsightDraft {
        generateHeuristicInsights(from: transcript)
    }
    #endif
}
