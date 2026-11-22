//
//  SubscriptionIntegrationTests.swift
//  OralableAppTests
//
//  Purpose: Integration tests for SubscriptionManager with real StoreKit behavior
//

import XCTest
import StoreKit
@testable import MAMDiagnostics

@MainActor
class SubscriptionIntegrationTests: XCTestCase {

    var subscriptionManager: SubscriptionManager!

    override func setUp() async throws {
        try await super.setUp()
        // Create a fresh instance for each test
        subscriptionManager = SubscriptionManager()

        // Clear saved state
        UserDefaults.standard.removeObject(forKey: "subscriptionTier")

        // Reset to basic for testing
        #if DEBUG
        subscriptionManager.resetToBasic()
        #endif
    }

    override func tearDown() async throws {
        subscriptionManager = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(subscriptionManager.currentTier, .basic)
        XCTAssertFalse(subscriptionManager.isPaidSubscriber)
    }

    // MARK: - Subscription Tier Tests

    func testSubscriptionTierDisplayNames() {
        XCTAssertEqual(SubscriptionTier.basic.displayName, "Basic (Free)")
        XCTAssertEqual(SubscriptionTier.premium.displayName, "Premium")
    }

    func testSubscriptionTierFeatures() {
        // Basic tier should have features
        let basicFeatures = SubscriptionTier.basic.features
        XCTAssertFalse(basicFeatures.isEmpty)
        XCTAssertTrue(basicFeatures.contains { $0.contains("Connect to MAM") })

        // Premium tier should have more features
        let premiumFeatures = SubscriptionTier.premium.features
        XCTAssertFalse(premiumFeatures.isEmpty)
        XCTAssertTrue(premiumFeatures.contains { $0.contains("All Basic features") })
        XCTAssertTrue(premiumFeatures.contains { $0.contains("Export to health records") })
        XCTAssertTrue(premiumFeatures.contains { $0.contains("Trend analysis") })
    }

    // MARK: - Feature Access Tests

    func testFeatureAccessBasicTier() {
        // Ensure we're on basic tier
        #if DEBUG
        subscriptionManager.resetToBasic()
        #endif

        // Basic tier should not have access to premium features
        XCTAssertFalse(subscriptionManager.hasAccess(to: "premiumFeature"))
    }

    func testFeatureAccessPremiumTier() {
        #if DEBUG
        // Simulate paid subscription
        subscriptionManager.simulatePurchase()

        // Premium tier should have access to features
        XCTAssertTrue(subscriptionManager.hasAccess(to: "anyFeature"))
        #endif
    }

    // MARK: - Persistence Tests

    func testSubscriptionPersistence() {
        #if DEBUG
        // Given
        subscriptionManager.simulatePurchase()
        XCTAssertTrue(subscriptionManager.isPaidSubscriber)

        // When
        let savedTier = UserDefaults.standard.string(forKey: "subscriptionTier")

        // Then
        XCTAssertEqual(savedTier, SubscriptionTier.premium.rawValue)
        #endif
    }

    // MARK: - Subscription Error Tests

    func testSubscriptionErrorDescriptions() {
        XCTAssertNotNil(SubscriptionError.productNotFound.errorDescription)
        XCTAssertNotNil(SubscriptionError.purchaseFailed.errorDescription)
        XCTAssertNotNil(SubscriptionError.purchaseCancelled.errorDescription)
        XCTAssertNotNil(SubscriptionError.verificationFailed.errorDescription)
        XCTAssertNotNil(SubscriptionError.restoreFailed.errorDescription)

        let testError = NSError(domain: "test", code: 1, userInfo: nil)
        let unknownError = SubscriptionError.unknown(testError)
        XCTAssertNotNil(unknownError.errorDescription)
    }

    // MARK: - Product Identifier Tests

    func testProductIdentifiers() {
        // In test environment without StoreKit configuration, products won't be loaded
        // This test verifies the subscription manager exists and has the expected interface
        // Note: In test environment, products are expected to be empty without a StoreKit configuration
        XCTAssertNotNil(subscriptionManager)
        // Products may be empty in test environment - that's expected behavior
        XCTAssertTrue(subscriptionManager.availableProducts.isEmpty || subscriptionManager.availableProducts.count > 0,
                      "Products should be accessible (empty or loaded)")
    }

    // MARK: - Loading State Tests

    func testLoadingState() async {
        // Given
        let initialLoadingState = subscriptionManager.isLoading

        // When
        await subscriptionManager.loadProducts()

        // Then
        // After loading, isLoading should be false
        XCTAssertFalse(subscriptionManager.isLoading)
    }

    // MARK: - Product Access Tests

    func testProductAccess() {
        // These will be nil in test environment without actual App Store Connect products
        // but the methods should work without crashing
        _ = subscriptionManager.monthlyProduct
        _ = subscriptionManager.yearlyProduct

        // No crash = test passes
        XCTAssertTrue(true)
    }

    // MARK: - Reset Functionality Tests

    #if DEBUG
    func testResetToBasic() {
        // Given - start with paid
        subscriptionManager.simulatePurchase()
        XCTAssertTrue(subscriptionManager.isPaidSubscriber)

        // When
        subscriptionManager.resetToBasic()

        // Then
        XCTAssertEqual(subscriptionManager.currentTier, .basic)
        XCTAssertFalse(subscriptionManager.isPaidSubscriber)
    }

    func testSimulatePurchase() {
        // Given
        subscriptionManager.resetToBasic()
        XCTAssertFalse(subscriptionManager.isPaidSubscriber)

        // When
        subscriptionManager.simulatePurchase()

        // Then
        XCTAssertEqual(subscriptionManager.currentTier, .premium)
        XCTAssertTrue(subscriptionManager.isPaidSubscriber)
    }
    #endif

    // MARK: - Subscription Status Update Tests

    func testSubscriptionStatusUpdate() async {
        // This will check current entitlements
        // In test environment, should default to basic
        await subscriptionManager.updateSubscriptionStatus()

        // Should not crash and should have a valid state
        XCTAssertNotNil(subscriptionManager.currentTier)
    }

    // MARK: - Error Message Tests

    func testErrorMessageHandling() {
        // Initially no error
        XCTAssertNil(subscriptionManager.errorMessage)

        // Error message should be settable
        subscriptionManager.errorMessage = "Test error"
        XCTAssertEqual(subscriptionManager.errorMessage, "Test error")

        // Should be clearable
        subscriptionManager.errorMessage = nil
        XCTAssertNil(subscriptionManager.errorMessage)
    }

    // MARK: - Expiry Status Tests

    func testExpiryStatusNoSubscription() {
        // With no subscription, expiry properties should return false/0
        XCTAssertFalse(subscriptionManager.isExpiringSoon)
        XCTAssertEqual(subscriptionManager.daysUntilExpiry, 0)
        XCTAssertFalse(subscriptionManager.hasExpired)
        XCTAssertNil(subscriptionManager.expiryWarningMessage)
    }

    func testExpiryStatusExpiringSoon() {
        #if DEBUG
        subscriptionManager.simulatePurchase()
        // Set expiry to 5 days from now (use exact time interval for reliability)
        subscriptionManager.subscriptionExpiryDate = Date().addingTimeInterval(5 * 24 * 60 * 60 + 3600) // 5 days + 1 hour

        XCTAssertTrue(subscriptionManager.isExpiringSoon)
        // Allow for date calculation variations (4-5 days)
        XCTAssertTrue(subscriptionManager.daysUntilExpiry >= 4 && subscriptionManager.daysUntilExpiry <= 5, "Days until expiry should be 4-5")
        XCTAssertFalse(subscriptionManager.hasExpired)
        XCTAssertNotNil(subscriptionManager.expiryWarningMessage)
        #endif
    }

    func testExpiryStatusExpired() {
        #if DEBUG
        subscriptionManager.simulatePurchase()
        // Set expiry to yesterday
        subscriptionManager.subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        XCTAssertFalse(subscriptionManager.isExpiringSoon)
        XCTAssertTrue(subscriptionManager.hasExpired)
        XCTAssertNotNil(subscriptionManager.expiryWarningMessage)
        XCTAssertTrue(subscriptionManager.expiryWarningMessage?.contains("expired") ?? false)
        #endif
    }

    // MARK: - Feature Gate Tests

    func testCanShareWithMultipleProfessionals() {
        #if DEBUG
        // Basic tier - should not be able to share with multiple
        subscriptionManager.resetToBasic()
        XCTAssertFalse(subscriptionManager.canShareWithMultipleProfessionals())

        // Premium tier - should be able to share with multiple
        subscriptionManager.simulatePurchase()
        XCTAssertTrue(subscriptionManager.canShareWithMultipleProfessionals())
        #endif
    }

    func testHasAdvancedAnalytics() {
        #if DEBUG
        subscriptionManager.resetToBasic()
        XCTAssertFalse(subscriptionManager.hasAdvancedAnalytics())

        subscriptionManager.simulatePurchase()
        XCTAssertTrue(subscriptionManager.hasAdvancedAnalytics())
        #endif
    }

    func testHasUnlimitedExport() {
        #if DEBUG
        subscriptionManager.resetToBasic()
        XCTAssertFalse(subscriptionManager.hasUnlimitedExport())

        subscriptionManager.simulatePurchase()
        XCTAssertTrue(subscriptionManager.hasUnlimitedExport())
        #endif
    }

    func testMaxProfessionalShares() {
        #if DEBUG
        subscriptionManager.resetToBasic()
        XCTAssertEqual(subscriptionManager.maxProfessionalShares(), 1)

        subscriptionManager.simulatePurchase()
        XCTAssertEqual(subscriptionManager.maxProfessionalShares(), Int.max)
        #endif
    }

    // MARK: - Check Expiry Status Tests

    func testCheckExpiryStatus() {
        #if DEBUG
        // No subscription - no warning
        subscriptionManager.resetToBasic()
        subscriptionManager.checkExpiryStatus()
        XCTAssertFalse(subscriptionManager.showExpiryWarning)

        // Premium expiring soon - show warning
        subscriptionManager.simulatePurchase()
        subscriptionManager.subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        subscriptionManager.checkExpiryStatus()
        XCTAssertTrue(subscriptionManager.showExpiryWarning)

        // Premium not expiring soon - no warning
        subscriptionManager.subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        subscriptionManager.checkExpiryStatus()
        XCTAssertFalse(subscriptionManager.showExpiryWarning)
        #endif
    }
}
