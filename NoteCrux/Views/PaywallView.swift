import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var subscription = SubscriptionManager.shared
    @State private var showContent = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.ncBackground, Color.ncPurple.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: NCSpacing.xl + 4) {
                    closeButton
                    hero.opacity(showContent ? 1 : 0).offset(y: showContent ? 0 : 16)
                    benefits.opacity(showContent ? 1 : 0).offset(y: showContent ? 0 : 20)
                    purchaseCard.opacity(showContent ? 1 : 0).offset(y: showContent ? 0 : 24)
                    footer.opacity(showContent ? 1 : 0)
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.bottom, 40)
            }
        }
        .task {
            await subscription.loadProducts()
            withAnimation(.easeOut(duration: 0.6)) { showContent = true }
        }
        .alert("Error", isPresented: Binding(
            get: { subscription.purchaseError != nil },
            set: { if !$0 { subscription.purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subscription.purchaseError ?? "")
        }
        .onChange(of: subscription.isSubscribed) { _, adFree in
            if adFree { dismiss() }
        }
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ncMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.ncSurface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, NCSpacing.md)
    }

    private var hero: some View {
        VStack(spacing: NCSpacing.md) {
            ZStack {
                Circle().fill(Color.ncPurple.opacity(0.10)).frame(width: 120, height: 120)
                Circle().fill(Color.ncPurple.opacity(0.20)).frame(width: 90, height: 90)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.ncPurple)
            }

            Text("Remove Ads")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.ncInk)

            Text("Enjoy NoteCrux ad-free forever with a single one-time purchase.")
                .font(.ncCallout)
                .foregroundStyle(Color.ncSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NCSpacing.md)
        }
    }

    private var benefits: some View {
        VStack(spacing: NCSpacing.sm + 4) {
            benefit("checkmark.seal.fill", "No banner ads, ever")
            benefit("bolt.fill", "Faster, distraction-free UI")
            benefit("lock.shield.fill", "All features stay free — nothing unlocks here")
            benefit("arrow.counterclockwise", "Restore on any of your devices")
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: NCSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ncPurple)
                .frame(width: 28)
            Text(text)
                .font(.ncBody)
                .foregroundStyle(Color.ncInk)
            Spacer()
        }
    }

    private var purchaseCard: some View {
        VStack(spacing: NCSpacing.md) {
            if let product = subscription.removeAdsProduct {
                VStack(spacing: 4) {
                    Text(product.displayPrice)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.ncInk)
                    Text("One-time • No subscription")
                        .font(.ncFootnote)
                        .foregroundStyle(Color.ncMuted)
                }

                Button {
                    Task { await subscription.purchase(product: product) }
                } label: {
                    HStack {
                        if subscription.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Remove Ads")
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NCSpacing.lg)
                    .background(Color.ncPurple, in: Capsule())
                }
                .buttonStyle(NCPressButtonStyle())
                .disabled(subscription.isPurchasing)
            } else {
                ProgressView("Loading…")
                    .frame(height: 120)
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: NCSpacing.md) {
            Button("Restore Purchase") {
                Task { await subscription.restorePurchases() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ncPurple)

            HStack(spacing: NCSpacing.md) {
                Link("Privacy", destination: URL(string: "https://www.notion.so/NoteCrux-Privacy-Policy-348ea5c71e68803c9c55fabf36d025fc")!)
                Text("•").foregroundStyle(Color.ncMuted)
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.ncFootnote)
            .foregroundStyle(Color.ncMuted)
        }
        .padding(.top, NCSpacing.sm)
    }
}

#Preview {
    PaywallView()
}
