import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("appLockBiometricsEnabled") private var appLockBiometricsEnabled = true
    @AppStorage("pinHash") private var pinHash = ""
    @AppStorage("themeMode") private var themeMode = "System"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isRecording = false
    @State private var isUnlocked = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainApp
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .preferredColorScheme(DeepPocketTheme.preferredColorScheme(themeMode))
    }

    private var mainApp: some View {
        ZStack {
            TabView {
                DashboardView(isRecording: $isRecording)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                TasksView()
                    .tabItem {
                        Label("Tasks", systemImage: "checkmark.circle")
                    }

                ProInsightsView()
                    .tabItem {
                        Label("Highlights", systemImage: "sparkles")
                    }

                AssistantView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                SettingsView()
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
            }
            .tint(Color(red: 0.25, green: 0.18, blue: 0.86))
            .sheet(isPresented: $isRecording) {
                RecordingRoomView()
            }
            .blur(radius: shouldShowLock ? 12 : 0)

            if shouldShowLock {
                AppLockView(
                    useBiometrics: appLockBiometricsEnabled,
                    pinHash: pinHash,
                    unlock: {
                        isUnlocked = true
                    }
                )
                .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                if appLockEnabled {
                    isUnlocked = false
                }
            }
        }
    }

    private var shouldShowLock: Bool {
        appLockEnabled && !isUnlocked
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Meeting.self, MeetingFolder.self, MeetingActionItem.self], inMemory: true)
}
