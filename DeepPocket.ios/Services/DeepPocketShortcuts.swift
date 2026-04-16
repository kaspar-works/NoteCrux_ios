import AppIntents

struct StartDeepPocketMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start DeepPocket Meeting"
    static var description = IntentDescription("Open DeepPocket to start recording a meeting.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct DeepPocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDeepPocketMeetingIntent(),
            phrases: [
                "Start meeting in \(.applicationName)",
                "Start DeepPocket meeting",
                "Record meeting in \(.applicationName)"
            ],
            shortTitle: "Start Meeting",
            systemImageName: "mic.fill"
        )
    }
}
