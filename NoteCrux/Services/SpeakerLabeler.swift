import Foundation

struct SpeakerLabeler {
    func label(transcriptEntries: [String], fallbackTranscript: String) -> [String] {
        let entries = transcriptEntries.isEmpty ? fallbackTranscriptSentences(fallbackTranscript) : transcriptEntries
        guard !entries.isEmpty else { return [] }

        var speaker = 1
        var labeled: [String] = []

        for entry in entries {
            let cleaned = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            labeled.append("Speaker \(speaker): \(cleaned)")

            if shouldSwitchSpeaker(after: cleaned) {
                speaker = speaker == 1 ? 2 : 1
            }
        }

        return labeled
    }

    private func fallbackTranscriptSentences(_ transcript: String) -> [String] {
        transcript
            .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func shouldSwitchSpeaker(after line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("?") ||
            lowercased.contains(" what ") ||
            lowercased.contains(" can ") ||
            lowercased.contains(" should ") ||
            line.count > 120
    }
}
