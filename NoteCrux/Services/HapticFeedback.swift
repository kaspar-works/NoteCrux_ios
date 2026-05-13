import UIKit

enum HapticFeedback {
    static func start() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func pauseResume() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func stop() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func bookmark() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
