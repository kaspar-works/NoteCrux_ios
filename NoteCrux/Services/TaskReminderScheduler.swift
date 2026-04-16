import Foundation
import UserNotifications

enum TaskReminderScheduler {
    static func schedule(for item: MeetingActionItem) async -> String? {
        guard let reminderDate = item.reminderDate ?? item.deadline,
              reminderDate > Date() else {
            return nil
        }

        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return nil }
        } catch {
            return nil
        }

        if let existingIdentifier = item.notificationIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [existingIdentifier])
        }

        let identifier = item.notificationIdentifier ?? UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = item.priority == .high ? "Urgent task due" : "Task reminder"
        content.body = item.title
        content.sound = .default
        content.userInfo = [
            "taskID": item.id.uuidString,
            "meetingID": item.meeting?.id.uuidString ?? ""
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return identifier
        } catch {
            return nil
        }
    }

    static func cancel(identifier: String?) {
        guard let identifier else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    static func scheduleFollowUp(for item: MeetingActionItem, minutesFromNow: Int = 60) async -> String? {
        guard !item.isComplete else { return nil }

        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return nil }
        } catch {
            return nil
        }

        if let existingIdentifier = item.notificationIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [existingIdentifier])
        }

        let identifier = item.notificationIdentifier ?? UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = item.priority == .high ? "Follow-up still open" : "Meeting follow-up"
        content.body = "You haven’t completed: \(item.title)"
        content.sound = .default
        content.userInfo = [
            "taskID": item.id.uuidString,
            "meetingID": item.meeting?.id.uuidString ?? "",
            "type": "followUp"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(minutesFromNow, 1) * 60), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return identifier
        } catch {
            return nil
        }
    }

    static func snoozeDate(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date().addingTimeInterval(TimeInterval(minutes * 60))
    }
}
