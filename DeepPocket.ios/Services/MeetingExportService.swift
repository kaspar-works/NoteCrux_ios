import Foundation
import UIKit

enum MeetingExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case text = "Text"
    case pdf = "PDF"
    case followUpEmail = "Email"

    var id: String { rawValue }
}

enum MeetingExportService {
    static func export(_ meeting: Meeting, format: MeetingExportFormat) throws -> URL {
        let folderURL = try exportsFolderURL()
        let safeTitle = safeFileName(meeting.title)

        switch format {
        case .markdown:
            let url = folderURL.appendingPathComponent("\(safeTitle).md")
            try markdown(for: meeting).write(to: url, atomically: true, encoding: .utf8)
            DataProtectionService.protectFile(at: url)
            return url
        case .text:
            let url = folderURL.appendingPathComponent("\(safeTitle).txt")
            try plainText(for: meeting).write(to: url, atomically: true, encoding: .utf8)
            DataProtectionService.protectFile(at: url)
            return url
        case .pdf:
            let url = folderURL.appendingPathComponent("\(safeTitle).pdf")
            try pdfData(for: meeting).write(to: url, options: [.atomic, .completeFileProtection])
            DataProtectionService.protectFile(at: url)
            return url
        case .followUpEmail:
            let url = folderURL.appendingPathComponent("\(safeTitle)-Follow-Up.txt")
            try followUpEmail(for: meeting).write(to: url, atomically: true, encoding: .utf8)
            DataProtectionService.protectFile(at: url)
            return url
        }
    }

    static func markdown(for meeting: Meeting) -> String {
        var output: [String] = [
            "# \(meeting.title)",
            "",
            "- Date: \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))",
            "- Duration: \(formatDuration(meeting.duration))",
            "- Tags: \(meeting.tags.isEmpty ? "None" : meeting.tags.joined(separator: ", "))",
            "",
            "## Quick Read",
            meeting.quickRead,
            "",
            "## Summary",
            meeting.summary,
            "",
            "## Smart Notes",
            meeting.paragraphNotes,
            ""
        ]

        appendSection("Highlights", items: meeting.highlights, to: &output)
        appendSection("Key Points", items: meeting.keyPoints, to: &output)
        appendSection("Decisions", items: meeting.decisions, to: &output)
        appendSection("Risks", items: meeting.risks, to: &output)
        appendTasks(meeting.actionItems, to: &output)

        output.append(contentsOf: [
            "",
            "## Transcript",
            meeting.transcript.isEmpty ? "No transcript captured." : meeting.transcript
        ])

        return output.joined(separator: "\n")
    }

    static func plainText(for meeting: Meeting) -> String {
        markdown(for: meeting)
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "- [ ] ", with: "- ")
            .replacingOccurrences(of: "- [x] ", with: "- ")
    }

    static func followUpEmail(for meeting: Meeting) -> String {
        let openTasks = meeting.actionItems.filter { !$0.isComplete }
        var lines: [String] = [
            "Subject: Follow-up from \(meeting.title)",
            "",
            "Hi,",
            "",
            "Here is a quick follow-up from \(meeting.title):",
            "",
            "Summary:",
            meeting.quickRead.isEmpty ? meeting.summary : meeting.quickRead,
            ""
        ]

        if !meeting.decisions.isEmpty {
            lines.append("Decisions:")
            lines.append(contentsOf: meeting.decisions.map { "- \($0)" })
            lines.append("")
        }

        if !openTasks.isEmpty {
            lines.append("Action items:")
            lines.append(contentsOf: openTasks.map { task in
                let owner = task.owner == "Unassigned" ? "Owner TBD" : task.owner
                return "- \(task.title) | \(owner) | \(task.priority.rawValue)"
            })
            lines.append("")
        }

        lines.append("Thanks,")
        return lines.joined(separator: "\n")
    }

    private static func pdfData(for meeting: Meeting) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let text = plainText(for: meeting) as NSString

        return renderer.pdfData { context in
            context.beginPage()

            let margin: CGFloat = 42
            let pageRect = CGRect(x: margin, y: margin, width: 612 - margin * 2, height: 792 - margin * 2)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.label
            ]

            text.draw(with: pageRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        }
    }

    private static func appendSection(_ title: String, items: [String], to output: inout [String]) {
        guard !items.isEmpty else { return }
        output.append("")
        output.append("## \(title)")
        output.append(contentsOf: items.map { "- \($0)" })
    }

    private static func appendTasks(_ tasks: [MeetingActionItem], to output: inout [String]) {
        guard !tasks.isEmpty else { return }
        output.append("")
        output.append("## Tasks")
        output.append(contentsOf: tasks.map { task in
            let checkbox = task.isComplete ? "[x]" : "[ ]"
            let owner = task.owner == "Unassigned" ? "Unassigned" : task.owner
            return "- \(checkbox) \(task.title) | \(task.priority.rawValue) | \(owner)"
        })
    }

    private static func exportsFolderURL() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent("Exports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        DataProtectionService.protectFolder(at: folderURL)
        return folderURL
    }

    private static func safeFileName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: invalidCharacters).joined(separator: "-")
        return cleaned.isEmpty ? "DeepPocket-Meeting" : cleaned
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }

    /// Items suitable for presenting in a `UIActivityViewController`.
    /// Writes the markdown to a temp file so it travels nicely to Mail, Files, Messages.
    static func shareItems(for meeting: Meeting) throws -> [Any] {
        let markdown = markdown(for: meeting)
        let tempDir = FileManager.default.temporaryDirectory
        let safeTitle = sanitizedFilenameSegment(meeting.title)
        let datePart = isoDate(meeting.createdAt)
        let mdURL = tempDir.appendingPathComponent("\(safeTitle)__\(datePart).md")
        try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

        var items: [Any] = [mdURL]
        if let audioPath = meeting.audioFilePath {
            let audioURL = URL(fileURLWithPath: audioPath)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                items.append(audioURL)
            }
        }
        return items
    }

    /// Produces a zip of markdown files (one per meeting) in a temp directory.
    /// Files are named `<sanitized-title>__<ISO-date>.md`.
    /// Returns the zip URL.
    static func exportAll(_ meetings: [Meeting]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let stageDir = tempDir.appendingPathComponent("deeppocket-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        for meeting in meetings {
            let safeTitle = sanitizedFilenameSegment(meeting.title)
            let datePart = isoDate(meeting.createdAt)
            let fileURL = stageDir.appendingPathComponent("\(safeTitle)__\(datePart).md")
            let md = markdown(for: meeting)
            try md.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let zipURL = tempDir.appendingPathComponent("DeepPocket-Export-\(isoDate(Date())).zip")
        try zipDirectory(stageDir, to: zipURL)
        return zipURL
    }

    private static func sanitizedFilenameSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let stripped = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return stripped.isEmpty ? "Untitled" : stripped
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    /// Zips the given directory using Foundation's NSFileCoordinator via archive-by-copy.
    /// Uses `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading, ...)`, which
    /// produces a zip archive suitable for the share sheet.
    private static func zipDirectory(_ source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var closureError: NSError?
        var resultURL: URL?
        coordinator.coordinate(readingItemAt: source, options: [.forUploading], error: &coordError) { tmpURL in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: tmpURL, to: destination)
                resultURL = destination
            } catch {
                closureError = error as NSError
            }
        }
        if let err = coordError ?? closureError { throw err }
        guard resultURL != nil else {
            throw NSError(
                domain: "MeetingExportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Zip archive creation failed."]
            )
        }
    }
}
