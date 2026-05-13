import Foundation

// Deprecated after the ads-based pivot: all features are unrestricted.
// Methods are kept as no-ops so existing call sites keep compiling until
// the follow-up cleanup pass removes them.
@MainActor
@Observable
final class FreeLimitTracker {

    static let shared = FreeLimitTracker()

    static let maxFreeMeetingsPerMonth = Int.max
    static let maxFreeTasks = Int.max
    static let maxFreeAIInsightsPerDay = Int.max

    var meetingsCreatedThisMonth: Int = 0
    var aiInsightsUsedToday: Int = 0

    private init() {}

    func resetIfNeeded() {}

    func canCreateMeeting() -> Bool { true }
    func canCreateTask(currentCount: Int) -> Bool { true }
    func canUseAI() -> Bool { true }
    func canExport() -> Bool { true }
    func canViewInsights() -> Bool { true }

    func recordMeetingCreated() {}
    func recordAIInsightUsed() {}

    var remainingMeetings: Int { Int.max }
    var meetingLimitText: String { "" }
}
