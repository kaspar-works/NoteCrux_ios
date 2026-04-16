import Foundation
import Observation

/// Shared coordinator for intent → app navigation.
/// Siri intents post requests here; ContentView observes and reacts.
@Observable
final class AppRouter {
    /// Set by intents to request that the app open the recording sheet.
    /// ContentView clears this after consuming.
    var pendingRecordingRequest: RecordingRequest?

    struct RecordingRequest: Identifiable, Equatable {
        let id = UUID()
        let title: String?
        let tags: [String]

        static let blank = RecordingRequest(title: nil, tags: [])
    }

    func requestRecording(title: String? = nil, tags: [String] = []) {
        pendingRecordingRequest = RecordingRequest(title: title, tags: tags)
        DeepPocketLog.intents.debug("AppRouter: recording requested, title=\(title ?? "-", privacy: .public)")
    }

    func consumeRecordingRequest() -> RecordingRequest? {
        let request = pendingRecordingRequest
        pendingRecordingRequest = nil
        return request
    }
}
