import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<RecordingActivityAttributes>?
    private var lastUpdateAt: Date = .distantPast

    private init() {}

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(title: String, startedAt: Date) {
        guard isAvailable else { return }
        guard activity == nil else { return }

        let attributes = RecordingActivityAttributes(meetingTitle: title.isEmpty ? "Meeting" : title)
        let state = RecordingActivityAttributes.ContentState(
            startedAt: startedAt,
            isPaused: false,
            audioLevel: 0
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastUpdateAt = .now
        } catch {
            activity = nil
        }
    }

    func update(isPaused: Bool, audioLevel: Double, startedAt: Date, throttled: Bool = false) {
        guard let activity else { return }
        if throttled, Date().timeIntervalSince(lastUpdateAt) < 2.0 {
            return
        }
        let state = RecordingActivityAttributes.ContentState(
            startedAt: startedAt,
            isPaused: isPaused,
            audioLevel: audioLevel
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        lastUpdateAt = .now
    }

    func end() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
