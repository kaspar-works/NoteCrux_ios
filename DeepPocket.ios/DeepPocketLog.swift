import Foundation
import OSLog

enum DeepPocketLog {
    static let subsystem = "works.kaspar.deeppocket"

    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let intents = Logger(subsystem: subsystem, category: "intents")
    static let export = Logger(subsystem: subsystem, category: "export")
}
