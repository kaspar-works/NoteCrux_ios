import Foundation
import SwiftData

struct DeepPocketBackup: Codable {
    var exportedAt: Date
    var meetings: [MeetingBackup]
    var folders: [FolderBackup]
    var tasks: [TaskBackup]
}

struct MeetingBackup: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFilePath: String?
    var tags: [String]
    var transcript: String
    var transcriptEntries: [String]
    var speakerTranscriptEntries: [String]
    var importance: String
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
    var folderID: UUID?
}

struct FolderBackup: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
}

struct TaskBackup: Codable {
    var id: UUID
    var meetingID: UUID?
    var title: String
    var detail: String
    var owner: String
    var deadline: Date?
    var priority: String
    var reminderDate: Date?
    var confidence: String
    var sourceQuote: String
    var isComplete: Bool
}

enum LocalBackupService {
    static func export(meetings: [Meeting], folders: [MeetingFolder], tasks: [MeetingActionItem]) throws -> URL {
        let backup = DeepPocketBackup(
            exportedAt: .now,
            meetings: meetings.map(MeetingBackup.init),
            folders: folders.map(FolderBackup.init),
            tasks: tasks.map(TaskBackup.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(backup)
        let folderURL = try backupsFolderURL()
        let fileURL = folderURL.appendingPathComponent("DeepPocket-Backup-\(Self.timestamp()).json")
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        DataProtectionService.protectFile(at: fileURL)
        return fileURL
    }

    static func deleteLocalFiles() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folders = ["Recordings", "Backups"]

        for folder in folders {
            let url = documentsURL.appendingPathComponent(folder, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        UserDefaults.standard.removeObject(forKey: "activeRecordingDraft")
    }

    private static func backupsFolderURL() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        DataProtectionService.protectFolder(at: folderURL)
        return folderURL
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

private extension MeetingBackup {
    init(_ meeting: Meeting) {
        self.id = meeting.id
        self.title = meeting.title
        self.createdAt = meeting.createdAt
        self.duration = meeting.duration
        self.audioFilePath = meeting.audioFilePath
        self.tags = meeting.tags
        self.transcript = meeting.transcript
        self.transcriptEntries = meeting.transcriptEntries
        self.speakerTranscriptEntries = meeting.speakerTranscriptEntries
        self.importance = meeting.importance.rawValue
        self.summary = meeting.summary
        self.paragraphNotes = meeting.paragraphNotes
        self.bulletSummary = meeting.bulletSummary
        self.highlights = meeting.highlights
        self.importantLines = meeting.importantLines
        self.quickRead = meeting.quickRead
        self.keyPoints = meeting.keyPoints
        self.decisions = meeting.decisions
        self.risks = meeting.risks
        self.bookmarkSeconds = meeting.bookmarkSeconds
        self.folderID = meeting.folder?.id
    }
}

private extension FolderBackup {
    init(_ folder: MeetingFolder) {
        self.id = folder.id
        self.name = folder.name
        self.createdAt = folder.createdAt
    }
}

private extension TaskBackup {
    init(_ task: MeetingActionItem) {
        self.id = task.id
        self.meetingID = task.meeting?.id
        self.title = task.title
        self.detail = task.detail
        self.owner = task.owner
        self.deadline = task.deadline
        self.priority = task.priority.rawValue
        self.reminderDate = task.reminderDate
        self.confidence = task.confidence.rawValue
        self.sourceQuote = task.sourceQuote
        self.isComplete = task.isComplete
    }
}
