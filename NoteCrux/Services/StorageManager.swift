import Foundation
import SwiftData

// MARK: - Models

enum StorageCategory: String, CaseIterable, Identifiable {
    case audio = "Audio Recordings"
    case meetings = "Meeting Data"
    case transcripts = "Transcripts"
    case insights = "AI Insights"
    case exports = "Exports"
    case backups = "Backups"
    case cache = "Cache & Temp"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .audio: return "waveform"
        case .meetings: return "doc.text.fill"
        case .transcripts: return "text.alignleft"
        case .insights: return "sparkles"
        case .exports: return "square.and.arrow.up.fill"
        case .backups: return "externaldrive.fill"
        case .cache: return "arrow.triangle.2.circlepath"
        }
    }

    var color: String {
        switch self {
        case .audio: return "ncPurple"
        case .meetings: return "ncInk"
        case .transcripts: return "ncSuccess"
        case .insights: return "ncWarning"
        case .exports: return "ncDanger"
        case .backups: return "ncMuted"
        case .cache: return "ncSecondary"
        }
    }
}

struct StorageBreakdownItem: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let bytes: Int64
    let category: StorageCategory
}

struct LargeMeetingItem: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let audioBytes: Int64
    let hasAudio: Bool
}

// MARK: - StorageManager

@MainActor
@Observable
final class StorageManager {

    static let shared = StorageManager()

    var totalBytesUsed: Int64 = 0
    var breakdown: [StorageBreakdownItem] = []
    var largeMeetings: [LargeMeetingItem] = []
    var isLoading = false
    var cleanupSuggestion: String?

    private let fm = FileManager.default

    private var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {}

    // MARK: - Load

    func loadStorageUsage(meetings: [Meeting]) {
        isLoading = true
        defer { isLoading = false }

        var items: [StorageBreakdownItem] = []

        // Audio recordings
        let recordingsURL = documentsURL.appendingPathComponent("Recordings", isDirectory: true)
        let audioSize = directorySize(at: recordingsURL)
        let audioCount = fileCount(at: recordingsURL)
        items.append(StorageBreakdownItem(title: "Audio Recordings", count: audioCount, bytes: audioSize, category: .audio))

        // Meeting metadata (estimate from model data)
        let meetingDataSize = estimateMeetingDataSize(meetings)
        items.append(StorageBreakdownItem(title: "Meeting Data", count: meetings.count, bytes: meetingDataSize, category: .meetings))

        // Transcripts
        let transcriptSize = meetings.reduce(Int64(0)) { $0 + Int64($1.transcript.utf8.count) }
        let transcriptCount = meetings.filter { !$0.transcript.isEmpty }.count
        items.append(StorageBreakdownItem(title: "Transcripts", count: transcriptCount, bytes: transcriptSize, category: .transcripts))

        // AI Insights (summaries, notes, key points etc.)
        var insightSize: Int64 = 0
        for m in meetings {
            insightSize += Int64(m.summary.utf8.count)
            insightSize += Int64(m.paragraphNotes.utf8.count)
            insightSize += Int64(m.quickRead.utf8.count)
            insightSize += Int64(m.bulletSummary.joined().utf8.count)
            insightSize += Int64(m.highlights.joined().utf8.count)
            insightSize += Int64(m.importantLines.joined().utf8.count)
            insightSize += Int64(m.keyPoints.joined().utf8.count)
            insightSize += Int64(m.decisions.joined().utf8.count)
            insightSize += Int64(m.risks.joined().utf8.count)
        }
        let insightCount = meetings.filter { !$0.summary.isEmpty || !$0.keyPoints.isEmpty }.count
        items.append(StorageBreakdownItem(title: "AI Insights", count: insightCount, bytes: insightSize, category: .insights))

        // Exports
        let exportsURL = documentsURL.appendingPathComponent("Exports", isDirectory: true)
        let exportSize = directorySize(at: exportsURL)
        let exportCount = fileCount(at: exportsURL)
        items.append(StorageBreakdownItem(title: "Exports", count: exportCount, bytes: exportSize, category: .exports))

        // Backups
        let backupsURL = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        let backupSize = directorySize(at: backupsURL)
        let backupCount = fileCount(at: backupsURL)
        items.append(StorageBreakdownItem(title: "Backups", count: backupCount, bytes: backupSize, category: .backups))

        // Cache / Temp
        let tempSize = directorySize(at: fm.temporaryDirectory)
        let tempCount = fileCount(at: fm.temporaryDirectory)
        items.append(StorageBreakdownItem(title: "Cache & Temp", count: tempCount, bytes: tempSize, category: .cache))

        breakdown = items
        totalBytesUsed = items.reduce(0) { $0 + $1.bytes }

        // Large meetings
        largeMeetings = meetings
            .map { m in
                let aSize = audioFileSize(for: m)
                return LargeMeetingItem(
                    id: m.id,
                    title: m.title,
                    date: m.createdAt,
                    audioBytes: aSize,
                    hasAudio: m.audioFilePath != nil
                )
            }
            .filter { $0.audioBytes > 0 }
            .sorted { $0.audioBytes > $1.audioBytes }

        // Cleanup suggestion
        let exportMB = Double(exportSize) / 1_048_576
        let cacheMB = Double(tempSize) / 1_048_576
        let totalFreeable = exportMB + cacheMB
        if totalFreeable > 1 {
            cleanupSuggestion = "You can free \(StorageManager.formattedSize(exportSize + tempSize)) by clearing exports and cache."
        } else {
            cleanupSuggestion = nil
        }
    }

    // MARK: - Cleanup Actions

    func clearCache() {
        let tempDir = fm.temporaryDirectory
        removeContents(of: tempDir)
    }

    func deleteExports() {
        let exportsURL = documentsURL.appendingPathComponent("Exports", isDirectory: true)
        removeContents(of: exportsURL)
    }

    func deleteBackups() {
        let backupsURL = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        removeContents(of: backupsURL)
    }

    func deleteAudio(for meetings: [Meeting]) {
        for meeting in meetings {
            guard let url = meeting.audioFileURL else { continue }
            try? fm.removeItem(at: url)
            meeting.audioFilePath = nil
        }
    }

    // MARK: - Helpers

    private func directorySize(at url: URL) -> Int64 {
        guard fm.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func fileCount(at url: URL) -> Int {
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.filter { !$0.hasPrefix(".") }.count
    }

    private func removeContents(of url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            try? fm.removeItem(at: item)
        }
    }

    private func estimateMeetingDataSize(_ meetings: [Meeting]) -> Int64 {
        // Rough estimate: each meeting model ~2KB metadata + action items + tags + entries
        meetings.reduce(Int64(0)) { total, m in
            let base: Int64 = 2048
            let actionItems = Int64(m.actionItems.count * 512)
            let entries = Int64((m.transcriptEntries.count + m.speakerTranscriptEntries.count) * 128)
            let tags = Int64(m.tags.joined().utf8.count)
            return total + base + actionItems + entries + tags
        }
    }

    private func audioFileSize(for meeting: Meeting) -> Int64 {
        guard let url = meeting.audioFileURL else { return 0 }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    // MARK: - Formatting

    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
