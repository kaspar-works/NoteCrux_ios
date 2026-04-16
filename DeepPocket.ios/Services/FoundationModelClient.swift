import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct FMInsightOutput {
    @Guide(description: "Three to five sentence summary of the meeting in plain prose.")
    var summary: String

    @Guide(description: "A short, single-paragraph note suitable for a daily digest.")
    var paragraphNotes: String

    @Guide(description: "Bullet list of the main points, 3 to 7 items, each one short line.")
    var bulletSummary: [String]

    @Guide(description: "The most quotable or interesting lines from the meeting, up to 5.")
    var highlights: [String]

    @Guide(description: "Concrete decisions that were made. Empty list if none.")
    var decisions: [String]

    @Guide(description: "Risks, blockers, or concerns raised. Empty list if none.")
    var risks: [String]

    @Guide(description: "Discrete action items extracted from the meeting.")
    var actionItems: [FMActionItemOutput]
}

@Generable
struct FMActionItemOutput {
    @Guide(description: "Short imperative title, under 80 characters.")
    var title: String

    @Guide(description: "One-sentence detail explaining the task.")
    var detail: String

    @Guide(description: "Owner name if stated or implied, else 'Unassigned'.")
    var owner: String

    @Guide(description: "Natural-language deadline if mentioned, else empty string.")
    var deadline: String

    @Guide(description: "Priority: 'high', 'medium', or 'low'.")
    var priority: String
}

@Generable
struct FMAnswerOutput {
    @Guide(description: "Direct answer to the user's question in 2 to 4 sentences, spoken-friendly.")
    var answer: String

    @Guide(description: "Up to 5 meeting titles cited as sources for the answer.")
    var citedMeetingTitles: [String]
}
#endif

/// Shared on-device LLM client. Returns heuristic-shaped output on success,
/// and throws on any failure so callers can fall back to heuristics.
final class FoundationModelClient {
    static let shared = FoundationModelClient()

    enum ClientError: Error {
        case unavailable
        case generationFailed(underlying: Error)
        case cancelled
    }

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return true
        case .unavailable: return false
        @unknown default: return false
        }
        #else
        return false
        #endif
    }

    struct MeetingContext {
        let title: String
        let summary: String
        let createdAt: Date
    }

    #if canImport(FoundationModels)
    // MARK: - LRU Session Cache

    private struct SessionCache {
        private var order: [String] = []
        private var store: [String: FMInsightOutput] = [:]
        private let limit = 20

        mutating func get(_ key: String) -> FMInsightOutput? {
            guard let value = store[key] else { return nil }
            if let idx = order.firstIndex(of: key) {
                order.remove(at: idx)
                order.append(key)
            }
            return value
        }

        mutating func put(_ key: String, _ value: FMInsightOutput) {
            if store[key] != nil {
                order.removeAll { $0 == key }
            } else if store.count >= limit, let evict = order.first {
                order.removeFirst()
                store.removeValue(forKey: evict)
            }
            store[key] = value
            order.append(key)
        }

        mutating func purge() {
            order.removeAll()
            store.removeAll()
        }
    }

    private var cache = SessionCache()
    private let cacheQueue = DispatchQueue(label: "works.kaspar.deeppocket.fm.cache")
    #endif

    private init() {}

    #if canImport(FoundationModels)
    // MARK: - generateInsights (cached, map-reduce)

    func generateInsights(from transcript: String) async throws -> FMInsightOutput {
        try Task.checkCancellation()
        let key = Self.cacheKey(for: transcript)

        if let hit = cacheQueue.sync(execute: { cache.get(key) }) {
            DeepPocketLog.ai.debug("FM cache hit")
            return hit
        }

        let output = try await generateInsightsUncached(from: transcript)
        cacheQueue.sync { cache.put(key, output) }
        return output
    }

    private func generateInsightsUncached(from transcript: String) async throws -> FMInsightOutput {
        try Task.checkCancellation()
        guard isAvailable else { throw ClientError.unavailable }

        let chunks = Self.chunk(transcript: transcript)
        DeepPocketLog.ai.debug("FM generation, chunks=\(chunks.count)")

        if chunks.count == 1 {
            return try await singleShotInsight(chunks[0])
        }

        // Map: summarize each chunk
        var chunkSummaries: [String] = []
        chunkSummaries.reserveCapacity(chunks.count)
        for (i, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let partial = try await singleShotInsight(chunk)
            chunkSummaries.append("Chunk \(i + 1): \(partial.summary)\nBullets: \(partial.bulletSummary.joined(separator: " | "))")
        }

        // Reduce: final call merges the chunk summaries
        let merged = chunkSummaries.joined(separator: "\n\n")
        let final = try await singleShotInsight(merged)

        // Action items across chunks need their own merge pass
        var actionItemsAllChunks: [FMActionItemOutput] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let out = try await singleShotInsight(chunk)
            actionItemsAllChunks.append(contentsOf: out.actionItems)
        }

        let deduped = Self.dedupeActionItems(actionItemsAllChunks)

        return FMInsightOutput(
            summary: final.summary,
            paragraphNotes: final.paragraphNotes,
            bulletSummary: final.bulletSummary,
            highlights: final.highlights,
            decisions: final.decisions,
            risks: final.risks,
            actionItems: deduped
        )
    }

    // MARK: - Single-shot call

    private func singleShotInsight(_ transcript: String) async throws -> FMInsightOutput {
        try Task.checkCancellation()
        let session = LanguageModelSession()
        let prompt = Self.insightPrompt(transcript: transcript)
        do {
            let response = try await session.respond(to: prompt, generating: FMInsightOutput.self)
            return response.content
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch {
            throw ClientError.generationFailed(underlying: error)
        }
    }

    // MARK: - insightPrompt

    private static func insightPrompt(transcript: String) -> String {
        """
        You are an assistant that extracts structured notes from a meeting transcript.
        Read the transcript below and return a populated FMInsightOutput value.

        Rules:
        - Be faithful to the transcript. Do not invent facts, names, or dates.
        - If a field has no content in the transcript, use an empty string or empty list.
        - Keep summaries short and direct.

        Transcript:
        \(transcript)
        """
    }

    // MARK: - answer

    func answer(question: String, context: [MeetingContext]) async throws -> FMAnswerOutput {
        guard isAvailable else { throw ClientError.unavailable }

        let session = LanguageModelSession()
        let prompt = Self.answerPrompt(question: question, context: context)

        do {
            let response = try await session.respond(to: prompt, generating: FMAnswerOutput.self)
            DeepPocketLog.ai.debug("FM answer ok, cites=\(response.content.citedMeetingTitles.count)")
            return response.content
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch {
            DeepPocketLog.ai.debug("FM answer failed: \(String(describing: error), privacy: .public)")
            throw ClientError.generationFailed(underlying: error)
        }
    }

    private static func answerPrompt(question: String, context: [MeetingContext]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let bullets = context.map { item in
            "- [\(item.title) — \(formatter.string(from: item.createdAt))] \(item.summary)"
        }.joined(separator: "\n")

        return """
        You are DeepPocket, a concise meeting assistant.
        Answer the user's question using ONLY the meeting notes below.
        If the notes do not contain the answer, say so briefly.
        Keep the answer to 2 to 4 sentences, suitable for being spoken aloud.
        Cite up to 5 meeting titles you used.

        Meeting notes:
        \(bullets)

        Question: \(question)
        """
    }

    // MARK: - Chunking, cache key, dedupe helpers

    /// Planning assumption: ~4 characters per token; conservative single-call budget ≈ 2,500 tokens → 10,000 characters.
    private static let singleCallCharacterBudget = 10_000
    private static let chunkCharacterSize = 8_000

    static func chunk(transcript: String) -> [String] {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > singleCallCharacterBudget else { return [clean] }

        let sentences = clean
            .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            if current.count + sentence.count + 2 > chunkCharacterSize, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += sentence + ". "
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static func cacheKey(for transcript: String) -> String {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalized.count):\(normalized.hashValue)"
    }

    static func dedupeActionItems(_ items: [FMActionItemOutput]) -> [FMActionItemOutput] {
        var seenNormalized: [String] = []
        var out: [FMActionItemOutput] = []

        for item in items {
            let norm = normalizedTitle(item.title)
            if seenNormalized.contains(where: { isDuplicate($0, norm) }) { continue }
            seenNormalized.append(norm)
            out.append(item)
        }
        return out
    }

    private static func normalizedTitle(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filtered = lowered.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func isDuplicate(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let setA = Set(a.split(separator: " "))
        let setB = Set(b.split(separator: " "))
        let inter = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return false }
        return Double(inter) / Double(union) >= 0.85
    }

    // MARK: - Cache management

    func purgeSessionCache() {
        cacheQueue.sync { cache.purge() }
        DeepPocketLog.ai.debug("FM session cache purged")
    }
    #endif

    #if !canImport(FoundationModels)
    func purgeSessionCache() {
        // No cache exists on platforms without FoundationModels.
    }
    #endif
}
