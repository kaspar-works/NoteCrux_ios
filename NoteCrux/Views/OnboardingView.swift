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
            Spacer(minLength: NCSpacing.xl)

            page.hero
                .frame(height: 180)
                .padding(.bottom, NCSpacing.xxl)

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
                    .frame(maxWidth: 310)
            }

            if !page.features.isEmpty {
                VStack(spacing: NCSpacing.md) {
                    Text(page.featureTitle)
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncInk)
                        .padding(.top, NCSpacing.xxl)

                    Capsule()
                        .fill(Color.ncPurple)
                        .frame(width: 24, height: 3)

                    VStack(spacing: NCSpacing.sm + 2) {
                        ForEach(page.features) { feature in
                            OnboardingFeatureRow(feature: feature)
                        }
                    }
                    .padding(.top, NCSpacing.md)
                }
            }

            Spacer(minLength: NCSpacing.lg)
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

// MARK: - Hero illustrations

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

private struct OnDeviceAIHero: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ncPurple.opacity(0.08))
                .frame(width: 160, height: 160)
            Circle()
                .fill(Color.ncPurple.opacity(0.18))
                .frame(width: 110, height: 110)
            Image(systemName: "cpu.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(Color.ncPurple)
            // Orbiting spark
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.ncPurple, in: Circle())
                .offset(x: 60, y: -50)
        }
    }
}

private struct PrivateVaultHero: View {
    var body: some View {
        VStack(spacing: NCSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.08))
                    .frame(width: 86, height: 86)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.ncPurple)
            }

            VStack(spacing: NCSpacing.sm) {
                HStack(spacing: 7) {
                    Image(systemName: "iphone")
                    Text("ON THIS DEVICE")
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
            .frame(width: 200)
            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
            .ncShadow(.subtle)
        }
    }
}

private struct ActionItemsHero: View {
    var body: some View {
        VStack(spacing: NCSpacing.sm) {
            ForEach(0..<3, id: \.self) { idx in
                HStack(spacing: NCSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.ncPurple.opacity(idx == 0 ? 1.0 : 0.3))
                        .font(.system(size: 20, weight: .bold))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ncMuted.opacity(0.25))
                        .frame(width: [140, 120, 90][idx], height: 6)
                    Spacer()
                    if idx < 2 {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.ncPurple)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.horizontal, NCSpacing.lg)
                .padding(.vertical, NCSpacing.md)
                .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                .frame(width: 240)
            }
        }
    }
}

private struct RecorderHero: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ncPurple.opacity(0.08))
                .frame(width: 140, height: 140)
            Circle()
                .fill(Color.ncPurple.opacity(0.18))
                .frame(width: 100, height: 100)
            Circle()
                .fill(Color.ncPurple)
                .frame(width: 72, height: 72)
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Page data

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
            title: "Record any\nconversation",
            subtitle: "Capture meetings, calls, interviews, or quick voice notes. NoteCrux turns them into searchable notes instantly.",
            buttonTitle: "Next",
            featureTitle: "What you get",
            features: [
                OnboardingFeature(icon: "waveform", title: "High-quality recording", subtitle: "Start and stop with one tap"),
                OnboardingFeature(icon: "doc.text.fill", title: "Live transcript", subtitle: "See every word as it's spoken"),
                OnboardingFeature(icon: "sparkles", title: "AI summaries", subtitle: "Highlights and decisions, auto-extracted")
            ],
            isFinal: false,
            hero: AnyView(WaveHero())
        ),
        OnboardingPage(
            title: "Powered by\non-device AI",
            subtitle: "Transcripts and summaries are generated right on your iPhone using Apple Intelligence Foundation Models. No internet required after setup.",
            buttonTitle: "Next",
            featureTitle: "How it works",
            features: [
                OnboardingFeature(icon: "cpu.fill", title: "Apple Foundation Models", subtitle: "Apple's on-device LLM runs the AI"),
                OnboardingFeature(icon: "wifi.slash", title: "No cloud processing", subtitle: "Audio never leaves your phone"),
                OnboardingFeature(icon: "bolt.fill", title: "Works offline", subtitle: "Record anywhere, no signal needed")
            ],
            isFinal: false,
            hero: AnyView(OnDeviceAIHero())
        ),
        OnboardingPage(
            title: "Your notes stay\nwith you",
            subtitle: "Everything — recordings, transcripts, summaries, tasks — is stored locally on your device. We have no servers that hold your data.",
            buttonTitle: "Next",
            featureTitle: "Where your data lives",
            features: [
                OnboardingFeature(icon: "iphone", title: "Stored on this device", subtitle: "In NoteCrux's private SwiftData store"),
                OnboardingFeature(icon: "lock.shield.fill", title: "Face ID protected", subtitle: "Optional app lock for extra privacy"),
                OnboardingFeature(icon: "xmark.icloud", title: "Zero accounts, zero tracking", subtitle: "No sign-in, no analytics pipelines")
            ],
            isFinal: false,
            hero: AnyView(PrivateVaultHero())
        ),
        OnboardingPage(
            title: "Turn talk into\ntasks",
            subtitle: "After each meeting, NoteCrux surfaces action items and lets you add them to your calendar — so nothing falls through the cracks.",
            buttonTitle: "Next",
            featureTitle: "After every meeting",
            features: [
                OnboardingFeature(icon: "checkmark.circle.fill", title: "Auto-extracted action items", subtitle: "Who's doing what, by when"),
                OnboardingFeature(icon: "calendar.badge.plus", title: "One-tap calendar scheduling", subtitle: "Add follow-ups to your calendar"),
                OnboardingFeature(icon: "bell.badge.fill", title: "Task reminders", subtitle: "Get nudged at the right time")
            ],
            isFinal: false,
            hero: AnyView(ActionItemsHero())
        ),
        OnboardingPage(
            title: "Ready when\nyou are",
            subtitle: "Every feature is free. A single ad shows between meetings — remove it anytime for $4.99 in Settings.",
            buttonTitle: "Start Recording",
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
