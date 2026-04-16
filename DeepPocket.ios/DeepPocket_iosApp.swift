//
//  DeepPocket_iosApp.swift
//  DeepPocket.ios
//
//  Created by Bistro Kaspar on 4/16/26.
//

import SwiftUI
import SwiftData

@main
struct DeepPocket_iosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Meeting.self,
            MeetingFolder.self,
            MeetingActionItem.self
        ])
    }
}
