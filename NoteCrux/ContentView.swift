import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("appLockBiometricsEnabled") private var appLockBiometricsEnabled = true
    @AppStorage("pinHash") private var pinHash = ""
    @AppStorage("themeMode") private var themeMode = "System"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isRecording = false
    @State private var recordingInitialContext: RecordingRoomView.InitialContext? = nil
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
        .preferredColorScheme(NoteCruxTheme.preferredColorScheme(themeMode))
    }

    private var mainApp: some View {
        ZStack {
            TabView {
                DashboardView(
                    isRecording: $isRecording,
                    recordingInitialContext: $recordingInitialContext
                )
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
            .sheet(isPresented: $isRecording, onDismiss: { recordingInitialContext = nil }) {
                RecordingRoomView(initialContext: recordingInitialContext)
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
        .onChange(of: router.pendingRecordingRequest) { _, newValue in
            guard let request = router.consumeRecordingRequest() else { return }
            recordingInitialContext = RecordingRoomView.InitialContext(
                title: request.title ?? "",
                tags: request.tags
            )
            isRecording = true
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
