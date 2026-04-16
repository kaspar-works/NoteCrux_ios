import Foundation
import OSLog

enum NoteCruxLog {
    static let subsystem = "works.kaspar.notecrux"

    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let intents = Logger(subsystem: subsystem, category: "intents")
    static let export = Logger(subsystem: subsystem, category: "export")
}
