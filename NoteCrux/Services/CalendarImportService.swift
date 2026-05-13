import Foundation
import EventKit
import OSLog

struct CalendarEventSummary: Identifiable, Hashable {
    let id: String              // EKEvent.eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let attendees: [String]     // display names
    let isToday: Bool
}

enum CalendarAuthorizationState {
    case notDetermined
    case granted
    case denied
}

@MainActor
final class CalendarImportService: ObservableObject {
    static let shared = CalendarImportService()

    @Published private(set) var authorizationState: CalendarAuthorizationState = .notDetermined
    @Published private(set) var events: [CalendarEventSummary] = []

    private let store = EKEventStore()
    private let calendar = Calendar.current

    private init() {
        self.authorizationState = Self.currentState()
    }

    func requestAccessIfNeeded() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            authorizationState = .granted
        case .denied, .restricted:
            authorizationState = .denied
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                authorizationState = granted ? .granted : .denied
            } catch {
                NoteCruxLog.calendar.debug("EventStore access request failed: \(String(describing: error), privacy: .public)")
                authorizationState = .denied
            }
        case .writeOnly:
            authorizationState = .denied
        @unknown default:
            authorizationState = .denied
        }
    }

    /// Returns today's events + upcoming events for the next 7 days, sorted by start date.
    func refresh() async {
        await requestAccessIfNeeded()
        guard authorizationState == .granted else {
            events = []
            return
        }

        let now = Date()
        guard let windowEnd = calendar.date(byAdding: .day, value: 7, to: now) else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(
            withStart: calendar.startOfDay(for: now),
            end: windowEnd,
            calendars: nil
        )
        let raw = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        events = raw.map { event in
            CalendarEventSummary(
                id: "\(event.eventIdentifier):\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "Untitled event",
                startDate: event.startDate,
                endDate: event.endDate,
                attendees: (event.attendees ?? []).compactMap { $0.name },
                isToday: calendar.isDateInToday(event.startDate)
            )
        }

        NoteCruxLog.calendar.debug("CalendarImport: loaded \(self.events.count) events")
    }

    /// Creates a new event in the user's default calendar. Returns the
    /// created event's identifier on success, nil if authorization is
    /// missing or the save fails.
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        durationMinutes: Int = 30,
        notes: String? = nil
    ) async -> String? {
        await requestAccessIfNeeded()
        guard authorizationState == .granted else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent, commit: true)
            NoteCruxLog.calendar.debug("Created event '\(title, privacy: .public)' at \(startDate, privacy: .public)")
            return event.eventIdentifier
        } catch {
            NoteCruxLog.calendar.debug("createEvent failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Uses NSDataDetector to pull the first date/time reference out of a
    /// piece of text (e.g. an action item title or detail). Returns nil
    /// if no date was found.
    static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let match = detector.matches(in: text, options: [], range: range).first
        return match?.date
    }

    var todaysEvents: [CalendarEventSummary] {
        events.filter { $0.isToday }
    }

    var upcomingEvents: [CalendarEventSummary] {
        events.filter { !$0.isToday }
    }

    private static func currentState() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess: return .granted
        case .denied, .restricted, .writeOnly: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
