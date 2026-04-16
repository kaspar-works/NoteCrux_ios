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

    private init() {}

    #if canImport(FoundationModels)
    func generateInsights(from transcript: String) async throws -> FMInsightOutput {
        guard isAvailable else {
            DeepPocketLog.ai.debug("FM unavailable; caller should use heuristic fallback.")
            throw ClientError.unavailable
        }

        let session = LanguageModelSession()
        let prompt = Self.insightPrompt(transcript: transcript)

        do {
            let start = Date()
            let response = try await session.respond(to: prompt, generating: FMInsightOutput.self)
            let duration = Date().timeIntervalSince(start)
            DeepPocketLog.ai.debug("FM insight generation ok, duration=\(duration, format: .fixed(precision: 2))s")
            return response.content
        } catch is CancellationError {
            DeepPocketLog.ai.debug("FM insight generation cancelled.")
            throw ClientError.cancelled
        } catch {
            DeepPocketLog.ai.debug("FM insight generation failed: \(String(describing: error), privacy: .public)")
            throw ClientError.generationFailed(underlying: error)
        }
    }

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
    #endif
}
