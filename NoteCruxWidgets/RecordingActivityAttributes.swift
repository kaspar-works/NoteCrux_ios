import ActivityKit
import Foundation

// Mirror of NoteCrux/Services/RecordingActivityAttributes.swift. Must stay in
// lockstep — ActivityKit requires the attribute struct to have the identical
// shape in the app target and the widgets extension target. Xcode synchronized
// groups give each target visibility only into its own folder, so this file
// is duplicated here. Update both files together.
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var isPaused: Bool
        var audioLevel: Double
    }

    var meetingTitle: String
}
