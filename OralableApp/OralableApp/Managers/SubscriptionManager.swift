//
//  SubscriptionManager.swift
//  OralableApp
//
//  Manages in-app purchases and subscription state.
//
//  Subscription Tiers:
//  - Basic (Free): Core features, single professional share
//  - Premium: Advanced metrics, unlimited sharing, PDF export
//
//  Responsibilities:
//  - StoreKit integration for purchases
//  - Subscription status verification
//  - Receipt validation
//  - Feature gating based on tier
//
//  Published Properties:
//  - currentTier: Active subscription level
//  - isSubscribed: Whether user has premium
//

import Foundation
import StoreKit

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable {
    case basic = "basic"
    case premium = "premium"

    var displayName: String {
        switch self {
        case .basic:
            return "Basic (Free)"
        case .premium:
            return "Premium"
        }
    }

    var features: [String] {
        switch self {
        case .basic:
            return [
                "Connect to Oralable device",
                "View real-time sensor data",
                "Daily/weekly summaries",
                "Basic data export",
                "Share with ONE professional"
            ]
        case .premium:
            return [
                "All Basic features",
                "Advanced analytics & insights",
                "Unlimited historical data storage",
                "Share with multiple providers",
                "Export to health records",
                "Trend analysis & predictions",
                "Priority support"
            ]
        }
    }
}

// MARK: - Subscription Error

enum SubscriptionError: LocalizedError {
    case productNotFound
    case purchaseFailed
    case purchaseCancelled
    case verificationFailed
    case restoreFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found. Please check your internet connection."
        case .purchaseFailed:
            return "Purchase failed. Please try again."
        case .purchaseCancelled:
            return "Purchase was cancelled."
        case .verificationFailed:
            return "Failed to verify purchase. Please contact support."
        case .restoreFailed:
            return "No previous purchases found to restore."
        case .unknown(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - Subscription Manager

@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Published Properties

    @Published var currentTier: SubscriptionTier = .basic
    @Published var isPaidSubscriber = false
    @Published var availableProducts: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var subscriptionExpiryDate: Date?
    @Published var showExpiryWarning = false

    // MARK: - Constants

    // Product IDs for Patient App
    private enum ProductIdentifier {
        static let monthlySubscription = "com.jacdental.oralable.premium.monthly"
        static let yearlySubscription = "com.jacdental.oralable.premium.yearly"
    }

    private let productIdentifiers: Set<String> = [
        ProductIdentifier.monthlySubscription,
        ProductIdentifier.yearlySubscription
    ]

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    init() {
        loadSubscriptionStatus()
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            let products = try await Product.products(for: productIdentifiers)
            self.availableProducts = products.sorted { $0.price < $1.price }
            isLoading = false
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Purchase Flow

    func purchase(_ product: Product) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Verify the transaction
                let transaction = try checkVerified(verification)

                // Update subscription status
                await updateSubscriptionStatus()

                // Finish the transaction
                await transaction.finish()

                isLoading = false

            case .userCancelled:
                isLoading = false
                throw SubscriptionError.purchaseCancelled

            case .pending:
                isLoading = false
                errorMessage = "Purchase is pending approval"

            @unknown default:
                isLoading = false
                throw SubscriptionError.purchaseFailed
            }
        } catch {
            isLoading = false
            if let subscriptionError = error as? SubscriptionError {
                throw subscriptionError
            } else {
                throw SubscriptionError.unknown(error)
            }
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async throws {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            isLoading = false

            if !isPaidSubscriber {
                throw SubscriptionError.restoreFailed
            }
        } catch {
            isLoading = false
            if let subscriptionError = error as? SubscriptionError {
                throw subscriptionError
            } else {
                throw SubscriptionError.unknown(error)
            }
        }
    }

    // MARK: - Transaction Verification

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Subscription Status

    func updateSubscriptionStatus() async {
        var hasPaidAccess = false

        // Check for active subscriptions or lifetime purchase
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // Check if this is a subscription or non-consumable
                if productIdentifiers.contains(transaction.productID) {
                    hasPaidAccess = true
                    break
                }
            } catch {
                Logger.shared.error("[SubscriptionManager] Transaction verification failed: \(error)")
            }
        }

        // Update tier
        if hasPaidAccess {
            currentTier = .premium
            isPaidSubscriber = true
        } else {
            currentTier = .basic
            isPaidSubscriber = false
        }

        saveSubscriptionStatus()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateSubscriptionStatus()
                    await transaction.finish()
                } catch {
                    Task { @MainActor in
                        Logger.shared.error("[SubscriptionManager] Transaction update failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadSubscriptionStatus() {
        if let tierString = UserDefaults.standard.string(forKey: "subscriptionTier"),
           let tier = SubscriptionTier(rawValue: tierString) {
            self.currentTier = tier
            self.isPaidSubscriber = (tier == .premium)
        }
    }

    private func saveSubscriptionStatus() {
        UserDefaults.standard.set(currentTier.rawValue, forKey: "subscriptionTier")
    }

    // MARK: - Feature Access

    func hasAccess(to feature: String) -> Bool {
        switch currentTier {
        case .basic:
            return false // Can add specific basic features check here
        case .premium:
            return true
        }
    }

    // MARK: - Product Information

    func product(for identifier: String) -> Product? {
        return availableProducts.first { $0.id == identifier }
    }

    var monthlyProduct: Product? {
        return product(for: ProductIdentifier.monthlySubscription)
    }

    var yearlyProduct: Product? {
        return product(for: ProductIdentifier.yearlySubscription)
    }

    // MARK: - Subscription Expiry Tracking

    /// Check if subscription is expiring soon (within 7 days)
    var isExpiringSoon: Bool {
        guard let expiryDate = subscriptionExpiryDate else { return false }
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        return daysUntilExpiry <= 7 && daysUntilExpiry > 0
    }

    /// Days until subscription expires
    var daysUntilExpiry: Int {
        guard let expiryDate = subscriptionExpiryDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }

    /// Check if subscription has expired
    var hasExpired: Bool {
        guard let expiryDate = subscriptionExpiryDate else { return false }
        return expiryDate < Date()
    }

    /// Get expiry warning message
    var expiryWarningMessage: String? {
        guard isPaidSubscriber else { return nil }

        if hasExpired {
            return "Your subscription has expired. Please renew to continue accessing premium features."
        } else if isExpiringSoon {
            let days = daysUntilExpiry
            if days == 1 {
                return "Your subscription expires tomorrow. Renew now to avoid interruption."
            } else {
                return "Your subscription expires in \(days) days."
            }
        }
        return nil
    }

    /// Check and update expiry warning status
    func checkExpiryStatus() {
        showExpiryWarning = isExpiringSoon || hasExpired
    }

    // MARK: - Feature Access

    func canShareWithMultipleProfessionals() -> Bool {
        return currentTier == .premium
    }

    func hasAdvancedAnalytics() -> Bool {
        return currentTier == .premium
    }

    func hasUnlimitedExport() -> Bool {
        return currentTier == .premium
    }

    func maxProfessionalShares() -> Int {
        switch currentTier {
        case .basic:
            return 1
        case .premium:
            return .max  // Unlimited
        }
    }

    // MARK: - Testing/Development

    #if DEBUG
    func resetToBasic() {
        currentTier = .basic
        isPaidSubscriber = false
        saveSubscriptionStatus()
    }

    func simulatePurchase() {
        currentTier = .premium
        isPaidSubscriber = true
        saveSubscriptionStatus()
    }
    #endif
}
