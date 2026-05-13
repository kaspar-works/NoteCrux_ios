import Foundation
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

/// AdMob configuration. Replace only if switching accounts.
enum AdMobConfig {
    /// Must also appear in Info.plist as `GADApplicationIdentifier`.
    static let applicationID    = "ca-app-pub-3340825671684972~8161161276"
    static let interstitialUnitID = "ca-app-pub-3340825671684972/4585924520"

    /// Minimum seconds between two interstitials (AdMob policy + UX).
    static let minInterstitialIntervalSeconds: TimeInterval = 300

    /// Show an interstitial at most once every Nth eligible call.
    static let meetingsPerInterstitial = 2
}

/// Manages:
/// 1. Google UMP consent flow (GDPR / CCPA). Requested at launch; consent
///    form is presented if the user's region requires it.
/// 2. AdMob SDK initialization. Only starts once consent has been resolved
///    so we don't serve pre-consent personalized ads.
/// 3. Preloaded interstitial that fires at natural transition moments
///    (e.g. after a meeting is saved), throttled and auto-skipped for
///    users who have purchased Remove Ads.
@MainActor
final class AdManager: NSObject {

    static let shared = AdManager()

    private var hasStarted = false
    private var sdkStarted = false
    private var lastShownAt: Date?
    private var eligibleCallsSinceLastAd = 0

    #if canImport(GoogleMobileAds)
    private var interstitial: InterstitialAd?
    #endif

    override private init() { super.init() }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await bootstrap() }
    }

    var shouldShowAds: Bool {
        !SubscriptionManager.shared.isSubscribed
    }

    func maybeShowInterstitial() {
        guard shouldShowAds else { return }
        if let last = lastShownAt,
           Date().timeIntervalSince(last) < AdMobConfig.minInterstitialIntervalSeconds {
            return
        }

        eligibleCallsSinceLastAd += 1
        guard eligibleCallsSinceLastAd >= AdMobConfig.meetingsPerInterstitial else { return }

        #if canImport(GoogleMobileAds)
        guard sdkStarted else { return }
        guard let ad = interstitial, let rvc = Self.topViewController() else {
            Task { await self.loadInterstitial() }
            return
        }
        ad.present(from: rvc)
        lastShownAt = Date()
        eligibleCallsSinceLastAd = 0
        interstitial = nil
        Task { await self.loadInterstitial() }
        #endif
    }

    // MARK: - Private

    private func bootstrap() async {
        await requestConsentIfNeeded()
        startSDKIfNeeded()

        #if canImport(GoogleMobileAds)
        await loadInterstitial()
        #endif
    }

    private func requestConsentIfNeeded() async {
        #if canImport(UserMessagingPlatform)
        let params = RequestParameters()
        // If you flip this to true, Google treats the user as a minor and
        // only serves age-appropriate (non-personalized) ads.
        params.isTaggedForUnderAgeOfConsent = false

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
            guard let rvc = Self.topViewController() else { return }
            try await ConsentForm.loadAndPresentIfRequired(from: rvc)
        } catch {
            // Swallow — if consent can't be collected we still fall back
            // to non-personalized ads inside the SDK.
        }
        #endif
    }

    private func startSDKIfNeeded() {
        guard !sdkStarted else { return }
        sdkStarted = true

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start { _ in }
        #endif
    }

    #if canImport(GoogleMobileAds)
    private func loadInterstitial() async {
        guard sdkStarted else { return }
        do {
            let ad = try await InterstitialAd.load(
                with: AdMobConfig.interstitialUnitID,
                request: Request()
            )
            interstitial = ad
        } catch {
            interstitial = nil
        }
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var vc = keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
    #endif
}
