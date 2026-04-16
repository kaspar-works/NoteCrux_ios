import Foundation

enum MeetingTemplate: String, CaseIterable, Identifiable {
    case general = "General"
    case standup = "Standup"
    case clientCall = "Client Call"
    case oneOnOne = "1:1"
    case planning = "Planning"

    var id: String { rawValue }

    var defaultTags: [String] {
        switch self {
        case .general:
            return ["Work"]
        case .standup:
            return ["Work"]
        case .clientCall:
            return ["Client"]
        case .oneOnOne:
            return ["Work", "Personal"]
        case .planning:
            return ["Work"]
        }
    }

    var titlePrefix: String {
        switch self {
        case .general:
            return "Meeting"
        case .standup:
            return "Standup"
        case .clientCall:
            return "Client Call"
        case .oneOnOne:
            return "1:1"
        case .planning:
            return "Planning"
        }
    }

    var promptHint: String {
        switch self {
        case .general:
            return "Capture decisions, tasks, and highlights."
        case .standup:
            return "Track yesterday, today, blockers, and handoffs."
        case .clientCall:
            return "Track client needs, risks, decisions, owners, and follow-up email points."
        case .oneOnOne:
            return "Track feedback, support needs, decisions, and growth actions."
        case .planning:
            return "Track scope, milestones, deadlines, risks, and owners."
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case englishUS = "English (US)"
    case englishUK = "English (UK)"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .englishUS:
            return "en-US"
        case .englishUK:
            return "en-GB"
        case .spanish:
            return "es-ES"
        case .french:
            return "fr-FR"
        case .german:
            return "de-DE"
        }
    }
}
