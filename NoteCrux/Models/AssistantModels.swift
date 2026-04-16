import Foundation

struct AssistantMessage: Identifiable {
    let id = UUID()
    var role: AssistantRole
    var text: String
    var createdAt = Date()
}

enum AssistantRole {
    case user
    case assistant
}

struct MeetingSmartInsights {
    var repeatedIssues: [String]
    var missedDeadlines: [MeetingActionItem]
    var relatedMeetings: [Meeting]
    var effectivenessScore: Int
    var effectivenessSummary: String
}

struct KnowledgeMemorySnapshot {
    var learnedThemes: [String]
    var recurringDecisions: [String]
    var recurringRisks: [String]
    var suggestedNextSteps: [String]
    var suggestedImprovements: [String]
}

struct ProductivityAnalytics {
    var totalMeetingTime: TimeInterval
    var meetingCount: Int
    var completedTaskCount: Int
    var totalTaskCount: Int
    var taskCompletionRate: Double
    var productivityScore: Int
    var actionableMeetingCount: Int
    var lowValueMeetingCount: Int

    var formattedMeetingTime: String {
        let hours = Int(totalMeetingTime) / 3600
        let minutes = (Int(totalMeetingTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
