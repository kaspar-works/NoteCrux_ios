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
                DeepPocketLog.calendar.debug("EventStore access request failed: \(String(describing: error), privacy: .public)")
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
                id: event.eventIdentifier,
                title: event.title ?? "Untitled event",
                startDate: event.startDate,
                endDate: event.endDate,
                attendees: (event.attendees ?? []).compactMap { $0.name },
                isToday: calendar.isDateInToday(event.startDate)
            )
        }

        DeepPocketLog.calendar.debug("CalendarImport: loaded \(self.events.count) events")
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
