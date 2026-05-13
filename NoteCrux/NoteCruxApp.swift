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
    @AppStorage("nc_iCloudSyncEnabled") private var iCloudSyncEnabled = false

    private static func makeContainer(iCloudEnabled: Bool) -> ModelContainer {
        let schema = Schema([
            Meeting.self,
            MeetingFolder.self,
            MeetingActionItem.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: iCloudEnabled ? .automatic : .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        let fallback = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return (try? ModelContainer(for: schema, configurations: [fallback]))
            ?? (try! ModelContainer(for: schema))
    }

    init() {
        // One-time migration: earlier builds defaulted the app lock ON,
        // which left users stuck at a lock screen even when they hadn't
        // chosen a PIN or enabled biometrics. Reset to "off" once, so
        // the new opt-in behavior takes effect.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "nc_appLockMigrated_v2") {
            defaults.removeObject(forKey: "appLockEnabled")
            defaults.removeObject(forKey: "appLockBiometricsEnabled")
            defaults.set(true, forKey: "nc_appLockMigrated_v2")
        }

        let r = AppRouter()
        _router = State(wrappedValue: r)

        AppDependencyManager.shared.add(dependency: r)
        NoteCruxShortcuts.updateAppShortcutParameters()
        AdManager.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .task {
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                    await SubscriptionManager.shared.loadProducts()
                }
        }
        .modelContainer(Self.makeContainer(iCloudEnabled: iCloudSyncEnabled))
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                FoundationModelClient.shared.purgeSessionCache()
            }
            if newValue == .active {
                Task {
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                }
            }
        }
    }
}
