import SwiftData
import SwiftUI

// MARK: - Tab Definition

enum NCTab: String, CaseIterable {
    case home, tasks, highlights, search, profile

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .tasks: "checkmark.circle.fill"
        case .highlights: "sparkles"
        case .search: "magnifyingglass"
        case .profile: "person.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home: "house"
        case .tasks: "checkmark.circle"
        case .highlights: "sparkles"
        case .search: "magnifyingglass"
        case .profile: "person"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .highlights: "Highlights"
        case .search: "Search"
        case .profile: "Profile"
        }
    }
}

// MARK: - Content View

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
    @State private var selectedTab: NCTab = .home

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
            VStack(spacing: 0) {
                // Tab content
                Group {
                    switch selectedTab {
                    case .home:
                        DashboardView(
                            isRecording: $isRecording,
                            recordingInitialContext: $recordingInitialContext
                        )
                    case .tasks:
                        TasksView()
                    case .highlights:
                        ProInsightsView()
                    case .search:
                        AssistantView()
                    case .profile:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Custom tab bar
                NCTabBar(selectedTab: $selectedTab, onRecord: { isRecording = true })
            }
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

// MARK: - Custom Tab Bar

private struct NCTabBar: View {
    @Binding var selectedTab: NCTab
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NCTab.allCases, id: \.self) { tab in
                if tab == .highlights {
                    // Record button in center position
                    Spacer()
                    recordButton
                    Spacer()
                }

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(.ncSpring) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: NCSpacing.xs) {
                        Image(systemName: selectedTab == tab ? tab.icon : tab.inactiveIcon)
                            .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.ncPurple : Color.ncMuted)
                            .frame(height: 24)

                        if selectedTab == tab {
                            Text(tab.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.ncPurple)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, NCSpacing.sm + 2)
                    .padding(.bottom, NCSpacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NCSpacing.sm)
        .padding(.bottom, NCSpacing.sm)
        .background(
            Color.ncSurface
                .shadow(color: .black.opacity(0.06), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var recordButton: some View {
        Button(action: onRecord) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple)
                    .frame(width: 52, height: 52)
                    .ncShadow(NCShadow(color: Color.ncPurple.opacity(0.35), radius: 12, y: 4))

                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(NCPressButtonStyle())
        .offset(y: -8)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Meeting.self, MeetingFolder.self, MeetingActionItem.self], inMemory: true)
}
