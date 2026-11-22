//
//  MockSubscriptionManager.swift
//  OralableAppTests
//
//  Purpose: Mock implementation of SubscriptionManagerProtocol for testing
//

import Foundation
import StoreKit
import Combine
@testable import MAMDiagnostics

@MainActor
final class MockSubscriptionManager: SubscriptionManagerProtocol, ObservableObject {

    // MARK: - Published Properties

    @Published var currentTier: SubscriptionTier = .basic
    @Published var isPaidSubscriber: Bool = false
    @Published var availableProducts: [Product] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var subscriptionExpiryDate: Date?
    @Published var showExpiryWarning: Bool = false

    // MARK: - Publishers

    var currentTierPublisher: AnyPublisher<SubscriptionTier, Never> {
        $currentTier.eraseToAnyPublisher()
    }

    var isPaidSubscriberPublisher: AnyPublisher<Bool, Never> {
        $isPaidSubscriber.eraseToAnyPublisher()
    }

    var isLoadingPublisher: AnyPublisher<Bool, Never> {
        $isLoading.eraseToAnyPublisher()
    }

    // MARK: - Test Configuration

    var shouldFailPurchase: Bool = false
    var purchaseError: SubscriptionError = .purchaseFailed
    var shouldFailRestore: Bool = false
    var restoreError: SubscriptionError = .restoreFailed

    // MARK: - Tracking Properties

    var loadProductsCalled = false
    var purchaseProductCalled = false
    var lastPurchasedProduct: Product?
    var restorePurchasesCalled = false
    var updateSubscriptionStatusCalled = false
    var hasAccessFeatureChecks: [String] = []
    var checkExpiryStatusCalled = false

    // MARK: - Product Information

    var monthlyProduct: Product?
    var yearlyProduct: Product?

    func product(for identifier: String) -> Product? {
        return availableProducts.first { $0.id == identifier }
    }

    // MARK: - Expiry Status

    var isExpiringSoon: Bool {
        guard let expiryDate = subscriptionExpiryDate else { return false }
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        return daysUntilExpiry <= 7 && daysUntilExpiry > 0
    }

    var daysUntilExpiry: Int {
        guard let expiryDate = subscriptionExpiryDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }

    var hasExpired: Bool {
        guard let expiryDate = subscriptionExpiryDate else { return false }
        return expiryDate < Date()
    }

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

    // MARK: - Protocol Methods

    func loadProducts() async {
        loadProductsCalled = true
        isLoading = true
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        isLoading = false
    }

    func purchase(_ product: Product) async throws {
        purchaseProductCalled = true
        lastPurchasedProduct = product
        isLoading = true

        // Simulate network delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        if shouldFailPurchase {
            isLoading = false
            throw purchaseError
        }

        // Successful purchase
        currentTier = .premium
        isPaidSubscriber = true
        isLoading = false
    }

    func restorePurchases() async throws {
        restorePurchasesCalled = true
        isLoading = true

        // Simulate network delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        if shouldFailRestore {
            isLoading = false
            throw restoreError
        }

        // Successful restore (assumes previous premium)
        currentTier = .premium
        isPaidSubscriber = true
        isLoading = false
    }

    func updateSubscriptionStatus() async {
        updateSubscriptionStatusCalled = true
        // No-op for mock - tier is set directly
    }

    func hasAccess(to feature: String) -> Bool {
        hasAccessFeatureChecks.append(feature)
        return currentTier == .premium
    }

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
            return .max
        }
    }

    func checkExpiryStatus() {
        checkExpiryStatusCalled = true
        showExpiryWarning = isExpiringSoon || hasExpired
    }

    // MARK: - Test Helpers

    func reset() {
        currentTier = .basic
        isPaidSubscriber = false
        availableProducts = []
        isLoading = false
        errorMessage = nil
        subscriptionExpiryDate = nil
        showExpiryWarning = false

        shouldFailPurchase = false
        purchaseError = .purchaseFailed
        shouldFailRestore = false
        restoreError = .restoreFailed

        loadProductsCalled = false
        purchaseProductCalled = false
        lastPurchasedProduct = nil
        restorePurchasesCalled = false
        updateSubscriptionStatusCalled = false
        hasAccessFeatureChecks = []
        checkExpiryStatusCalled = false
    }

    func simulatePremiumSubscription() {
        currentTier = .premium
        isPaidSubscriber = true
    }

    func simulateExpiringSoon(daysFromNow: Int) {
        simulatePremiumSubscription()
        subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())
    }

    func simulateExpired() {
        simulatePremiumSubscription()
        subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
    }
}
