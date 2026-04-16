import AppIntents
import Foundation
import SwiftData

// MARK: - Start Recording

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start NoteCrux recording"
    static let description = IntentDescription("Opens NoteCrux and begins a new meeting recording.")
    static var openAppWhenRun: Bool { true }

    @Dependency private var router: AppRouter

    @MainActor
    func perform() async throws -> some IntentResult {
        router.requestRecording()
        NoteCruxLog.intents.debug("StartRecordingIntent fired")
        return .result()
    }
}

// MARK: - Today's Agenda

struct TodaysAgendaIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's agenda"
    static let description = IntentDescription("Reads today's scheduled calendar events.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await CalendarImportService.shared.refresh()
        let events = CalendarImportService.shared.todaysEvents
        NoteCruxLog.intents.debug("TodaysAgendaIntent: \(events.count) events")

        if events.isEmpty {
            return .result(dialog: "You have nothing scheduled today.")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let bullets = events.map { "\($0.title) at \(formatter.string(from: $0.startDate))" }
        let joined: String
        if bullets.count == 1 {
            joined = bullets[0]
        } else if bullets.count == 2 {
            joined = "\(bullets[0]) and \(bullets[1])"
        } else {
            joined = bullets.dropLast().joined(separator: ", ") + ", and " + bullets.last!
        }
        return .result(dialog: "You have \(events.count) event\(events.count == 1 ? "" : "s") today: \(joined).")
    }
}

// MARK: - Ask NoteCrux

struct AskNoteCruxIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask NoteCrux"
    static let description = IntentDescription("Answers a question using your meeting notes.")
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Question")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (meetings, tasks) = try await fetchMeetingsAndTasks()
        let engine = MeetingAssistantEngine()
        let result = await engine.answer(question: question, meetings: meetings, tasks: tasks)
        NoteCruxLog.intents.debug("AskNoteCruxIntent: usedFM=\(result.usedFM), cites=\(result.citedMeetings.count)")
        return .result(dialog: IntentDialog(stringLiteral: result.answer))
    }

    @MainActor
    private func fetchMeetingsAndTasks() async throws -> ([Meeting], [MeetingActionItem]) {
        let container = try ModelContainer(for: Meeting.self, MeetingFolder.self, MeetingActionItem.self)
        let context = ModelContext(container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        let tasks = try context.fetch(FetchDescriptor<MeetingActionItem>())
        return (meetings, tasks)
    }
}

// MARK: - Last Meeting Decisions

struct LastMeetingDecisionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Last meeting decisions"
    static let description = IntentDescription("Reads the decisions from your most recent meeting.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try ModelContainer(for: Meeting.self, MeetingFolder.self, MeetingActionItem.self)
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\Meeting.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let meetings = try context.fetch(descriptor)
        guard let meeting = meetings.first else {
            return .result(dialog: "You have no meetings yet.")
        }
        if meeting.decisions.isEmpty {
            return .result(dialog: "Your last meeting, \(meeting.title), did not record any decisions.")
        }
        let list = meeting.decisions.joined(separator: ". ")
        return .result(dialog: "From your last meeting, \(meeting.title): \(list).")
    }
}
