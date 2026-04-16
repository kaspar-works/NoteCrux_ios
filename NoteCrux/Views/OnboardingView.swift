import SwiftUI

struct OnboardingView: View {
    let complete: () -> Void
    @State private var page = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            Color.onboardingBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingTopBar {
                    complete()
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                            .padding(.horizontal, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                OnboardingProgress(current: page, count: pages.count)
                    .padding(.bottom, 22)

                Button {
                    if page == pages.count - 1 {
                        complete()
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            page += 1
                        }
                    }
                } label: {
                    Text(pages[page].buttonTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(pages[page].isFinal ? Color.onboardingFinalButton : Color.onboardingPurple, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 25)
            }
        }
    }
}

private struct OnboardingTopBar: View {
    let close: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("NoteCrux")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onboardingInk)

                Capsule()
                    .fill(Color.onboardingPurple)
                    .frame(width: 20, height: 3)
            }

            Spacer()

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.onboardingMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close onboarding")
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            page.hero
                .frame(height: 200)
                .padding(.bottom, 38)

            VStack(spacing: 13) {
                Text(page.title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Color.onboardingInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(Color.onboardingMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
            }

            if !page.features.isEmpty {
                VStack(spacing: 13) {
                    Text(page.featureTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.onboardingInk)
                        .padding(.top, 44)

                    Capsule()
                        .fill(Color.onboardingPurple)
                        .frame(width: 24, height: 3)

                    VStack(spacing: 13) {
                        ForEach(page.features) { feature in
                            OnboardingFeatureRow(feature: feature)
                        }
                    }
                    .padding(.top, 18)
                }
            }

            Spacer(minLength: 18)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.onboardingPurple)
                .frame(width: 34, height: 34)
                .background(Color.onboardingPurple.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.onboardingInk)

                Text(feature.subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.onboardingMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.onboardingSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 12, y: 6)
    }
}

private struct OnboardingProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.onboardingPurple : Color.onboardingPurple.opacity(0.26))
                    .frame(width: index == current ? 18 : 5, height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}

private struct WaveHero: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(alignment: .center, spacing: 8) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.onboardingPurple)
                        .frame(width: 4, height: [28, 54, 86, 116, 138, 104, 75, 46, 24][index])
                }
            }
            .frame(height: 150)

            Spacer()
        }
    }
}

private struct SecurityHero: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.onboardingPurple.opacity(0.08))
                    .frame(width: 86, height: 86)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.onboardingPurple)
            }

            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                    Text("SECURE STORAGE")
                }
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.onboardingPurple)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.onboardingMuted.opacity(0.18))
                            .frame(height: 5)
                    }
                }
            }
            .padding(16)
            .frame(width: 190)
            .background(Color.onboardingSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 16, y: 7)
        }
    }
}

private struct RecorderHero: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.onboardingSurface)
                .frame(width: 166, height: 122)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 10)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.40, blue: 0.20), Color(red: 0.95, green: 0.18, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 98, height: 82)

            ZStack {
                Circle()
                    .fill(Color.onboardingSurface.opacity(0.86))
                    .frame(width: 42, height: 42)
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.onboardingMuted)
            }
            .offset(x: 22, y: 14)
        }
    }
}

private struct OnboardingPage {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let featureTitle: String
    let features: [OnboardingFeature]
    let isFinal: Bool
    let hero: AnyView

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Your private AI\nmeeting assistant",
            subtitle: "Summarize spoken conversations without anything ever touching our cloud.",
            buttonTitle: "Next",
            featureTitle: "Features",
            features: [
                OnboardingFeature(icon: "doc.text.fill", title: "Record, summarize, act", subtitle: "Capture meetings and notes locally"),
                OnboardingFeature(icon: "sparkles", title: "Instant summaries", subtitle: "Extract key insights and action items"),
                OnboardingFeature(icon: "calendar.badge.clock", title: "Action items", subtitle: "Tasks, due dates, and owners")
            ],
            isFinal: false,
            hero: AnyView(WaveHero())
        ),
        OnboardingPage(
            title: "Your Voice, Your\nDevice",
            subtitle: "Everything stays on your device. No bots. No cloud. 0% cloud.",
            buttonTitle: "Understand & Continue",
            featureTitle: "Security",
            features: [],
            isFinal: false,
            hero: AnyView(SecurityHero())
        ),
        OnboardingPage(
            title: "Ready to capture\nthe conversation?",
            subtitle: "Join NoteCrux for a premium meeting experience.",
            buttonTitle: "Get Started",
            featureTitle: "",
            features: [],
            isFinal: true,
            hero: AnyView(RecorderHero())
        )
    ]
}

private struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

private extension Color {
    static let onboardingBackground = Color.adaptive(light: (0.985, 0.984, 0.990), dark: (0.055, 0.056, 0.072))
    static let onboardingSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let onboardingInk = Color.adaptive(light: (0.11, 0.11, 0.13), dark: (0.93, 0.94, 0.97))
    static let onboardingMuted = Color.adaptive(light: (0.48, 0.48, 0.55), dark: (0.62, 0.64, 0.72))
    static let onboardingPurple = Color.adaptive(light: (0.25, 0.18, 0.86), dark: (0.58, 0.50, 1.0))
    static let onboardingFinalButton = Color.adaptive(light: (0.06, 0.07, 0.08), dark: (0.25, 0.18, 0.86))
}
