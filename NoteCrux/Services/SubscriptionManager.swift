import Foundation
import StoreKit

@MainActor
@Observable
final class SubscriptionManager {

    static let shared = SubscriptionManager()

    // Semantic: `isSubscribed` now means "has purchased Remove Ads".
    // Property name kept for call-site compatibility across the app.
    var isSubscribed = false
    var products: [Product] = []
    var purchaseError: String?
    var isPurchasing = false

    static let removeAdsID = "com.codergautamyt.NoteCrux.removeads"
    private static let productIDs: Set<String> = [removeAdsID]

    private let cachedAdFreeKey = "nc_isAdFree"

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        isSubscribed = UserDefaults.standard.bool(forKey: cachedAdFreeKey)

        updateListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
            }
        }
    }

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            products = storeProducts
        } catch {
            purchaseError = "Could not load products. Please try again."
        }
    }

    func checkSubscriptionStatus() async {
        var adFree = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.removeAdsID {
                adFree = true
            }
        }

        isSubscribed = adFree
        persistCache()
    }

    func purchase(product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                purchaseError = "Purchase failed. Please try again."
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()

            if !isSubscribed {
                purchaseError = "No previous purchase found."
            }
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
    }

    var removeAdsProduct: Product? {
        products.first { $0.id == Self.removeAdsID }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        await transaction.finish()
        await checkSubscriptionStatus()
    }

    private func persistCache() {
        UserDefaults.standard.set(isSubscribed, forKey: cachedAdFreeKey)
    }
}
