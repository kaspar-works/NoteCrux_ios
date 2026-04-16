//
//  NoteCruxApp.swift
//  NoteCrux
//
//  Created by Bistro Kaspar on 4/16/26.
//

import SwiftUI
import SwiftData
import AppIntents

@main
struct NoteCruxApp: App {
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let r = AppRouter()
        _router = State(wrappedValue: r)

        // Make AppRouter available to AppIntents (resolves @Dependency in intents).
        AppDependencyManager.shared.add(dependency: r)

        // Announce shortcuts to the OS.
        NoteCruxShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
        }
        .modelContainer(for: [
            Meeting.self,
            MeetingFolder.self,
            MeetingActionItem.self
        ])
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                FoundationModelClient.shared.purgeSessionCache()
            }
        }
    }
}
