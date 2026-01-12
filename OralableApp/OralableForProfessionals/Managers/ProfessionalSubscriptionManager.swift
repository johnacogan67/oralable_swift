//
//  ProfessionalSubscriptionManager.swift
//  OralableForProfessionals
//
//  Manages subscriptions for professional app.
//
//  Subscription Tiers:
//  - Starter (Free): Up to 5 participants
//  - Professional (€29.99/mo): Up to 50 participants
//  - Practice (€99.99/mo): Unlimited participants
//
//  Responsibilities:
//  - StoreKit integration for purchases
//  - Subscription verification
//  - Patient limit enforcement
//  - Feature gating based on tier
//

import Foundation
import StoreKit
import Combine

// MARK: - Professional Subscription Tiers

enum ProfessionalSubscriptionTier: String, Codable, CaseIterable {
    case starter = "starter"       // Free - up to 5 participants
    case professional = "professional"  // €29.99/month - up to 50 participants
    case practice = "practice"     // €99.99/month - unlimited participants

    var displayName: String {
        switch self {
        case .starter:
            return "Starter"
        case .professional:
            return "Professional"
        case .practice:
            return "Practice"
        }
    }

    var maxPatients: Int {
        switch self {
        case .starter:
            return 5
        case .professional:
            return 50
        case .practice:
            return .max  // Unlimited
        }
    }

    var monthlyPrice: String {
        switch self {
        case .starter:
            return "Free"
        case .professional:
            return "€29.99/month"
        case .practice:
            return "€99.99/month"
        }
    }

    var features: [String] {
        switch self {
        case .starter:
            return [
                "Up to 5 participants",
                "Basic participant monitoring",
                "View shared data",
                "Daily summaries",
                "Data export (CSV)"
            ]
        case .professional:
            return [
                "Up to 50 participants",
                "Advanced analytics",
                "Trend analysis",
                "Custom reports",
                "Priority support",
                "API access"
            ]
        case .practice:
            return [
                "Unlimited participants",
                "Multi-professional access",
                "Practice-wide analytics",
                "White-label reports",
                "Dedicated support",
                "Custom integrations",
                "HIPAA compliance tools"
            ]
        }
    }

    var isPaid: Bool {
        return self != .starter
    }
}

// MARK: - Professional Subscription Manager

@MainActor
class ProfessionalSubscriptionManager: ObservableObject {
    static let shared = ProfessionalSubscriptionManager()

    // MARK: - Published Properties

    @Published var currentTier: ProfessionalSubscriptionTier = .starter
    @Published var isSubscriptionActive: Bool = false
    @Published var subscriptionExpiryDate: Date?
    @Published var availableProducts: [Product] = []
    @Published var purchaseInProgress: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Never>?
    private let productIDs: Set<String> = [
        ProductIdentifier.professionalMonthly,
        ProductIdentifier.professionalYearly
        // Practice tier deferred to post-launch
    ]

    // MARK: - Product Identifiers

    private enum ProductIdentifier {
        static let professionalMonthly = "com.jacdental.oralable.professional.monthly"
        static let professionalYearly = "com.jacdental.oralable.professional.yearly"
        // Practice tier deferred to post-launch:
        // static let practiceMonthly = "com.jacdental.oralable.practice.monthly"
        // static let practiceYearly = "com.jacdental.oralable.practice.yearly"
    }

    // MARK: - Initialization

    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load current subscription status
        Task {
            await loadSubscriptionStatus()
            await loadProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            let products = try await Product.products(for: productIDs)
            await MainActor.run {
                self.availableProducts = products.sorted { $0.price < $1.price }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load products: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Purchase Management

    func purchase(_ product: Product) async throws {
        await MainActor.run {
            purchaseInProgress = true
            errorMessage = nil
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateSubscriptionStatus(for: transaction)
                await transaction.finish()

                await MainActor.run {
                    purchaseInProgress = false
                }

            case .userCancelled:
                await MainActor.run {
                    purchaseInProgress = false
                }

            case .pending:
                await MainActor.run {
                    purchaseInProgress = false
                    errorMessage = "Purchase is pending approval"
                }

            @unknown default:
                await MainActor.run {
                    purchaseInProgress = false
                    errorMessage = "Unknown purchase result"
                }
            }
        } catch {
            await MainActor.run {
                purchaseInProgress = false
                errorMessage = "Purchase failed: \(error.localizedDescription)"
            }
            throw error
        }
    }

    func restorePurchases() async {
        await MainActor.run {
            purchaseInProgress = true
            errorMessage = nil
        }

        do {
            try await AppStore.sync()
            await loadSubscriptionStatus()

            await MainActor.run {
                purchaseInProgress = false
            }
        } catch {
            await MainActor.run {
                purchaseInProgress = false
                errorMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Subscription Status

    func loadSubscriptionStatus() async {
        var highestTier: ProfessionalSubscriptionTier = .starter
        var isActive = false
        var expiryDate: Date?

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if let tier = tierForProductID(transaction.productID) {
                    if tier.rawValue > highestTier.rawValue {
                        highestTier = tier
                        isActive = true
                        expiryDate = transaction.expirationDate
                    }
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }

        await MainActor.run {
            self.currentTier = highestTier
            self.isSubscriptionActive = isActive
            self.subscriptionExpiryDate = expiryDate
        }
    }

    private func updateSubscriptionStatus(for transaction: Transaction) async {
        guard let tier = tierForProductID(transaction.productID) else { return }

        await MainActor.run {
            self.currentTier = tier
            self.isSubscriptionActive = true
            self.subscriptionExpiryDate = transaction.expirationDate
        }
    }

    // MARK: - Transaction Verification

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateSubscriptionStatus(for: transaction)
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func tierForProductID(_ productID: String) -> ProfessionalSubscriptionTier? {
        switch productID {
        case ProductIdentifier.professionalMonthly,
             ProductIdentifier.professionalYearly:
            return .professional
        // Practice tier deferred to post-launch
        // case ProductIdentifier.practiceMonthly,
        //      ProductIdentifier.practiceYearly:
        //     return .practice
        default:
            return nil
        }
    }

    func canAddMorePatients(currentCount: Int) -> Bool {
        return currentCount < currentTier.maxPatients
    }

    func patientsRemaining(currentCount: Int) -> Int {
        let maxPatients = currentTier.maxPatients
        if maxPatients == .max {
            return .max
        }
        return Swift.max(0, maxPatients - currentCount)
    }

    func needsUpgrade(forPatientCount count: Int) -> Bool {
        return count >= currentTier.maxPatients
    }

    func suggestedUpgradeTier(forPatientCount count: Int) -> ProfessionalSubscriptionTier? {
        if count >= ProfessionalSubscriptionTier.practice.maxPatients {
            return .practice
        } else if count >= ProfessionalSubscriptionTier.professional.maxPatients {
            return .professional
        } else if count >= ProfessionalSubscriptionTier.starter.maxPatients {
            return .professional
        }
        return nil
    }
}

// MARK: - Store Errors

enum StoreError: Error {
    case failedVerification

    var localizedDescription: String {
        switch self {
        case .failedVerification:
            return "Transaction verification failed"
        }
    }
}
