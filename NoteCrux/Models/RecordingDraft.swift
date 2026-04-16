import Foundation

struct RecordingDraft: Codable {
    var title: String
    var startedAt: Date
    var elapsed: TimeInterval
    var tags: [String]
    var transcript: String
    var transcriptEntries: [String]
    var audioFilePath: String?
}

enum MeetingTag: String, CaseIterable, Identifiable {
    case work = "Work"
    case personal = "Personal"
    case client = "Client"
    case legal = "Legal"
    case medical = "Medical"

    var id: String { rawValue }
}
