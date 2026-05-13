import ActivityKit
import Foundation

// Shared with NoteCruxWidgets/RecordingActivityAttributes.swift — ActivityKit
// requires the struct to have the identical shape in the app target and the
// widgets extension target. Xcode synchronized groups give each target
// visibility only into its own folder, so this file is duplicated across
// both. Update both files together.
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var isPaused: Bool
        var audioLevel: Double
    }

    var meetingTitle: String
}
