import Foundation

struct InsightDraft {
    var summary: String
    var paragraphNotes: String
    var bulletSummary: [String]
    var highlights: [String]
    var importantLines: [String]
    var quickRead: String
    var keyPoints: [String]
    var decisions: [String]
    var risks: [String]
    var actionItems: [ActionItemDraft]
}

struct ActionItemDraft: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var owner: String
    var deadline: Date?
    var priority: TaskPriority
    var confidence: ActionConfidence
    var sourceQuote: String
}
