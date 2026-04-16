import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFilePath: String?
    var tags: [String]
    var transcript: String
    var transcriptEntries: [String]
    var speakerTranscriptEntries: [String]
    var importance: MeetingImportance
    var summary: String
    var paragraphNotes: String
    var bulletSummary: [String]
    var highlights: [String]
    var importantLines: [String]
    var quickRead: String
    var keyPoints: [String]
    var decisions: [String]
    var risks: [String]
    var bookmarkSeconds: [Double]
    var folder: MeetingFolder?
    @Relationship(deleteRule: .cascade, inverse: \MeetingActionItem.meeting)
    var actionItems: [MeetingActionItem]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        audioFilePath: String? = nil,
        tags: [String] = [],
        transcript: String = "",
        transcriptEntries: [String] = [],
        speakerTranscriptEntries: [String] = [],
        importance: MeetingImportance = .normal,
        summary: String = "",
        paragraphNotes: String = "",
        bulletSummary: [String] = [],
        highlights: [String] = [],
        importantLines: [String] = [],
        quickRead: String = "",
        keyPoints: [String] = [],
        decisions: [String] = [],
        risks: [String] = [],
        bookmarkSeconds: [Double] = [],
        folder: MeetingFolder? = nil,
        actionItems: [MeetingActionItem] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.tags = tags
        self.transcript = transcript
        self.transcriptEntries = transcriptEntries
        self.speakerTranscriptEntries = speakerTranscriptEntries
        self.importance = importance
        self.summary = summary
        self.paragraphNotes = paragraphNotes
        self.bulletSummary = bulletSummary
        self.highlights = highlights
        self.importantLines = importantLines
        self.quickRead = quickRead
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.risks = risks
        self.bookmarkSeconds = bookmarkSeconds
        self.folder = folder
        self.actionItems = actionItems
    }
}

@Model
final class MeetingFolder {
    var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Meeting.folder)
    var meetings: [Meeting]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        meetings: [Meeting] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.meetings = meetings
    }
}

@Model
final class MeetingActionItem {
    var id: UUID
    var title: String
    var detail: String
    var owner: String
    var deadline: Date?
    var priority: TaskPriority
    var reminderDate: Date?
    var notificationIdentifier: String?
    var confidence: ActionConfidence
    var sourceQuote: String
    var isComplete: Bool
    var meeting: Meeting?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        owner: String = "Unassigned",
        deadline: Date? = nil,
        priority: TaskPriority = .medium,
        reminderDate: Date? = nil,
        notificationIdentifier: String? = nil,
        confidence: ActionConfidence = .medium,
        sourceQuote: String = "",
        isComplete: Bool = false,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.owner = owner
        self.deadline = deadline
        self.priority = priority
        self.reminderDate = reminderDate
        self.notificationIdentifier = notificationIdentifier
        self.confidence = confidence
        self.sourceQuote = sourceQuote
        self.isComplete = isComplete
        self.meeting = meeting
    }
}

enum ActionConfidence: String, Codable, CaseIterable {
    case high
    case medium
    case low
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
}

enum MeetingImportance: String, Codable, CaseIterable, Identifiable {
    case normal = "Normal"
    case important = "Important"
    case critical = "Critical"

    var id: String { rawValue }
}
