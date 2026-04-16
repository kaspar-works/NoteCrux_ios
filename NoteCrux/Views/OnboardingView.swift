import SwiftUI

struct OnboardingView: View {
    let complete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            Color.ncBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingTopBar {
                    complete()
                }
                .padding(.horizontal, NCSpacing.xxl)
                .padding(.top, NCSpacing.md)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                            .padding(.horizontal, NCSpacing.xxxl)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                OnboardingProgress(current: page, count: pages.count)
                    .padding(.bottom, NCSpacing.xxl)

                Button {
                    if page == pages.count - 1 {
                        complete()
                    } else {
                        withAnimation(.ncSpring) {
                            page += 1
                        }
                    }
                } label: {
                    Text(pages[page].buttonTitle)
                        .font(.ncHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            pages[page].isFinal
                                ? (colorScheme == .dark ? Color.ncPurple : Color(red: 0.06, green: 0.07, blue: 0.08))
                                : Color.ncPurple,
                            in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                        )
                }
                .buttonStyle(NCPressButtonStyle())
                .padding(.horizontal, NCSpacing.xxxl)
                .padding(.bottom, NCSpacing.xxl + 1)
            }
        }
    }
}

private struct OnboardingTopBar: View {
    let close: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: NCSpacing.xs + 1) {
                Text("NoteCrux")
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncInk)

                Capsule()
                    .fill(Color.ncPurple)
                    .frame(width: 20, height: 3)
            }

            Spacer()

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ncMuted)
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
            Spacer(minLength: NCSpacing.xxl)

            page.hero
                .frame(height: 200)
                .padding(.bottom, NCSpacing.xxxl + 6)

            VStack(spacing: NCSpacing.md + 1) {
                Text(page.title)
                    .font(.ncTitle1)
                    .foregroundStyle(Color.ncInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.subtitle)
                    .font(.ncCallout)
                    .lineSpacing(4)
                    .foregroundStyle(Color.ncMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
            }

            if !page.features.isEmpty {
                VStack(spacing: NCSpacing.md + 1) {
                    Text(page.featureTitle)
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncInk)
                        .padding(.top, 44)

                    Capsule()
                        .fill(Color.ncPurple)
                        .frame(width: 24, height: 3)

                    VStack(spacing: NCSpacing.md + 1) {
                        ForEach(page.features) { feature in
                            OnboardingFeatureRow(feature: feature)
                        }
                    }
                    .padding(.top, NCSpacing.xl)
                }
            }

            Spacer(minLength: NCSpacing.xl)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(spacing: NCSpacing.lg) {
            Image(systemName: feature.icon)
                .font(.ncCallout)
                .foregroundStyle(Color.ncPurple)
                .frame(width: 34, height: 34)
                .background(Color.ncPurple.opacity(0.09), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.ncCallout)
                    .foregroundStyle(Color.ncInk)

                Text(feature.subtitle)
                    .font(.ncCaption2)
                    .foregroundStyle(Color.ncMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

private struct OnboardingProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.ncPurple : Color.ncPurple.opacity(0.26))
                    .frame(width: index == current ? 18 : 5, height: 4)
            }
        }
        .animation(.ncEaseOut, value: current)
    }
}

private struct WaveHero: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(alignment: .center, spacing: 8) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ncPurple)
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
        VStack(spacing: NCSpacing.xxl) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.08))
                    .frame(width: 86, height: 86)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.ncPurple)
            }

            VStack(spacing: NCSpacing.sm) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                    Text("SECURE STORAGE")
                }
                .font(.ncOverline)
                .tracking(0.8)
                .foregroundStyle(Color.ncPurple)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.ncMuted.opacity(0.18))
                            .frame(height: 5)
                    }
                }
            }
            .padding(NCSpacing.lg)
            .frame(width: 190)
            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
            .ncShadow(.subtle)
        }
    }
}

private struct RecorderHero: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSurface)
                .frame(width: 166, height: 122)
                .ncShadow(.elevated)

            RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
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
                    .fill(Color.ncSurface.opacity(0.86))
                    .frame(width: 42, height: 42)
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.ncMuted)
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
