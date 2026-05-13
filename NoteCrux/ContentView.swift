import SwiftData
import SwiftUI

// MARK: - Tab Definition

enum NCTab: String, CaseIterable {
    case home, tasks, highlights, profile

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .tasks: "checkmark.circle.fill"
        case .highlights: "sparkles"
        case .profile: "person.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home: "house"
        case .tasks: "checkmark.circle"
        case .highlights: "sparkles"
        case .profile: "person"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .highlights: "Insights"
        case .profile: "Settings"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appLockBiometricsEnabled") private var appLockBiometricsEnabled = false
    @AppStorage("pinHash") private var pinHash = ""
    @AppStorage("themeMode") private var themeMode = "System"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isRecording = false
    @State private var recordingInitialContext: RecordingRoomView.InitialContext? = nil
    @State private var isUnlocked = false
    @State private var selectedTab: NCTab = .home
    @State private var showSplash = true
    @State private var showPaywall = false

    var body: some View {
        ZStack {
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

            if showSplash {
                SplashScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            #if DEBUG
            DebugSeed.seedIfRequested(context: modelContext)
            #endif
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.5)) {
                showSplash = false
            }
        }
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
                    case .profile:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .id(selectedTab)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)

                // Custom tab bar
                NCTabBar(selectedTab: $selectedTab, onRecord: {
                    isRecording = true
                })
            }
            .sheet(isPresented: $isRecording, onDismiss: { recordingInitialContext = nil }) {
                RecordingRoomView(initialContext: recordingInitialContext)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
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
        guard appLockEnabled else { return false }
        // Don't block the UI if the user has never actually configured
        // an unlock method — that produces a dead-end lock screen.
        let hasUnlockMethod = !pinHash.isEmpty || appLockBiometricsEnabled
        return hasUnlockMethod && !isUnlocked
    }
}

// MARK: - Custom Tab Bar

private struct NCTabBar: View {
    @Binding var selectedTab: NCTab
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.tasks)
            recordButton
            tabButton(.highlights)
            tabButton(.profile)
        }
        .padding(.horizontal, NCSpacing.sm)
        .padding(.bottom, NCSpacing.sm)
        .background(
            Color.ncSurface
                .shadow(color: .black.opacity(0.06), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: NCTab) -> some View {
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
        .accessibilityLabel(tab.label)
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
        .frame(maxWidth: .infinity)
        .offset(y: -8)
    }
}

// MARK: - Splash Screen

private struct SplashScreen: View {
    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.ncBackground
                .ignoresSafeArea()

            VStack(spacing: NCSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.ncPurple.opacity(0.10))
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(Color.ncPurple.opacity(0.20))
                        .frame(width: 90, height: 90)
                    Circle()
                        .fill(Color.ncPurple)
                        .frame(width: 64, height: 64)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: NCSpacing.sm) {
                    Text("NoteCrux")
                        .font(.ncLargeTitle)
                        .foregroundStyle(Color.ncInk)

                    Text("AI Meeting Notes")
                        .font(.ncFootnote)
                        .tracking(1.2)
                        .foregroundStyle(Color.ncMuted)
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    logoScale = 1.0
                    logoOpacity = 1.0
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Meeting.self, MeetingFolder.self, MeetingActionItem.self], inMemory: true)
}
