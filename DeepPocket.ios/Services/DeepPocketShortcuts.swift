import AppIntents

struct DeepPocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start a \(.applicationName) recording",
                "Record a meeting in \(.applicationName)"
            ],
            shortTitle: "Start recording",
            systemImageName: "mic.circle.fill"
        )
        AppShortcut(
            intent: TodaysAgendaIntent(),
            phrases: [
                "What's on my agenda in \(.applicationName)",
                "Read my \(.applicationName) agenda"
            ],
            shortTitle: "Today's agenda",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AskDeepPocketIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my \(.applicationName) notes"
            ],
            shortTitle: "Ask DeepPocket",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: LastMeetingDecisionsIntent(),
            phrases: [
                "What were my last \(.applicationName) decisions",
                "Read decisions from my last \(.applicationName) meeting"
            ],
            shortTitle: "Last meeting decisions",
            systemImageName: "checkmark.seal"
        )
    }
}
