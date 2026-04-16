import EventKit
import Foundation

@MainActor
final class CalendarIntegrationService {
    private let store = EKEventStore()

    func createCalendarEvent(from meeting: Meeting) async throws {
        try await requestCalendarAccess()

        let event = EKEvent(eventStore: store)
        event.title = meeting.title
        event.notes = MeetingExportService.plainText(for: meeting)
        event.startDate = meeting.createdAt
        event.endDate = meeting.createdAt.addingTimeInterval(max(meeting.duration, 30 * 60))
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)
    }

    func addTasksToReminders(_ tasks: [MeetingActionItem]) async throws {
        try await requestReminderAccess()

        let calendar = store.defaultCalendarForNewReminders()

        for task in tasks where !task.isComplete {
            let reminder = EKReminder(eventStore: store)
            reminder.title = task.title
            reminder.notes = task.detail.isEmpty ? task.sourceQuote : task.detail
            reminder.calendar = calendar

            if let date = task.deadline ?? task.reminderDate {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }

            try store.save(reminder, commit: false)
        }

        try store.commit()
    }

    private func requestCalendarAccess() async throws {
        if #available(iOS 17.0, *) {
            _ = try await store.requestFullAccessToEvents()
        } else {
            _ = try await store.requestAccess(to: .event)
        }
    }

    private func requestReminderAccess() async throws {
        if #available(iOS 17.0, *) {
            _ = try await store.requestFullAccessToReminders()
        } else {
            _ = try await store.requestAccess(to: .reminder)
        }
    }
}
