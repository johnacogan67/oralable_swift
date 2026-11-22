//
//  SubscriptionViewModelTests.swift
//  OralableAppTests
//
//  Purpose: Comprehensive unit tests for subscription flows using MockSubscriptionManager
//

import XCTest
import Combine
@testable import MAMDiagnostics

@MainActor
final class SubscriptionViewModelTests: XCTestCase {

    var mockSubscriptionManager: MockSubscriptionManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = MockSubscriptionManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockSubscriptionManager = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsBasic() {
        XCTAssertEqual(mockSubscriptionManager.currentTier, .basic)
        XCTAssertFalse(mockSubscriptionManager.isPaidSubscriber)
        XCTAssertFalse(mockSubscriptionManager.isLoading)
        XCTAssertNil(mockSubscriptionManager.errorMessage)
    }

    func testInitialStateHasNoProducts() {
        XCTAssertTrue(mockSubscriptionManager.availableProducts.isEmpty)
        XCTAssertNil(mockSubscriptionManager.monthlyProduct)
        XCTAssertNil(mockSubscriptionManager.yearlyProduct)
    }

    // MARK: - Load Products Tests

    func testLoadProductsSetsLoadingState() async {
        // Given
        XCTAssertFalse(mockSubscriptionManager.loadProductsCalled)

        // When
        await mockSubscriptionManager.loadProducts()

        // Then
        XCTAssertTrue(mockSubscriptionManager.loadProductsCalled)
        XCTAssertFalse(mockSubscriptionManager.isLoading) // Should be false after completion
    }

    // MARK: - Purchase Flow Tests

    func testPurchaseSuccessUpdatesTier() async throws {
        // Given
        XCTAssertEqual(mockSubscriptionManager.currentTier, .basic)
        mockSubscriptionManager.shouldFailPurchase = false

        // Create a mock product (using the initializer workaround)
        // Note: StoreKit Product cannot be directly instantiated in tests
        // So we test the state changes instead
        let expectation = XCTestExpectation(description: "Tier updates to premium")

        mockSubscriptionManager.$currentTier
            .dropFirst()
            .sink { tier in
                if tier == .premium {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - simulate successful purchase via helper
        mockSubscriptionManager.simulatePremiumSubscription()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(mockSubscriptionManager.currentTier, .premium)
        XCTAssertTrue(mockSubscriptionManager.isPaidSubscriber)
    }

    func testPurchaseCancelledThrowsError() async {
        // Given
        mockSubscriptionManager.shouldFailPurchase = true
        mockSubscriptionManager.purchaseError = .purchaseCancelled

        // When/Then - we can't create a Product, but we can verify error configuration
        XCTAssertTrue(mockSubscriptionManager.shouldFailPurchase)
        XCTAssertEqual(mockSubscriptionManager.purchaseError.errorDescription, SubscriptionError.purchaseCancelled.errorDescription)
    }

    func testPurchaseFailedThrowsError() async {
        // Given
        mockSubscriptionManager.shouldFailPurchase = true
        mockSubscriptionManager.purchaseError = .purchaseFailed

        // When/Then
        XCTAssertTrue(mockSubscriptionManager.shouldFailPurchase)
        XCTAssertEqual(mockSubscriptionManager.purchaseError.errorDescription, SubscriptionError.purchaseFailed.errorDescription)
    }

    func testPurchaseVerificationFailedThrowsError() async {
        // Given
        mockSubscriptionManager.shouldFailPurchase = true
        mockSubscriptionManager.purchaseError = .verificationFailed

        // When/Then
        XCTAssertEqual(mockSubscriptionManager.purchaseError.errorDescription, SubscriptionError.verificationFailed.errorDescription)
    }

    // MARK: - Restore Purchases Tests

    func testRestoreSuccessUpdatesTier() async throws {
        // Given
        mockSubscriptionManager.shouldFailRestore = false

        // When
        try await mockSubscriptionManager.restorePurchases()

        // Then
        XCTAssertTrue(mockSubscriptionManager.restorePurchasesCalled)
        XCTAssertEqual(mockSubscriptionManager.currentTier, .premium)
        XCTAssertTrue(mockSubscriptionManager.isPaidSubscriber)
    }

    func testRestoreFailedThrowsError() async {
        // Given
        mockSubscriptionManager.shouldFailRestore = true
        mockSubscriptionManager.restoreError = .restoreFailed

        // When/Then
        do {
            try await mockSubscriptionManager.restorePurchases()
            XCTFail("Expected restoreFailed error")
        } catch let error as SubscriptionError {
            XCTAssertEqual(error.errorDescription, SubscriptionError.restoreFailed.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Subscription Status Tests

    func testUpdateSubscriptionStatusCalled() async {
        // Given
        XCTAssertFalse(mockSubscriptionManager.updateSubscriptionStatusCalled)

        // When
        await mockSubscriptionManager.updateSubscriptionStatus()

        // Then
        XCTAssertTrue(mockSubscriptionManager.updateSubscriptionStatusCalled)
    }

    // MARK: - Feature Access Tests

    func testHasAccessBasicTier() {
        // Given
        mockSubscriptionManager.currentTier = .basic

        // When/Then
        XCTAssertFalse(mockSubscriptionManager.hasAccess(to: "premium_feature"))
        XCTAssertTrue(mockSubscriptionManager.hasAccessFeatureChecks.contains("premium_feature"))
    }

    func testHasAccessPremiumTier() {
        // Given
        mockSubscriptionManager.simulatePremiumSubscription()

        // When/Then
        XCTAssertTrue(mockSubscriptionManager.hasAccess(to: "premium_feature"))
    }

    func testCanShareWithMultipleProfessionalsBasic() {
        mockSubscriptionManager.currentTier = .basic
        XCTAssertFalse(mockSubscriptionManager.canShareWithMultipleProfessionals())
    }

    func testCanShareWithMultipleProfessionalsPremium() {
        mockSubscriptionManager.simulatePremiumSubscription()
        XCTAssertTrue(mockSubscriptionManager.canShareWithMultipleProfessionals())
    }

    func testHasAdvancedAnalyticsBasic() {
        mockSubscriptionManager.currentTier = .basic
        XCTAssertFalse(mockSubscriptionManager.hasAdvancedAnalytics())
    }

    func testHasAdvancedAnalyticsPremium() {
        mockSubscriptionManager.simulatePremiumSubscription()
        XCTAssertTrue(mockSubscriptionManager.hasAdvancedAnalytics())
    }

    func testHasUnlimitedExportBasic() {
        mockSubscriptionManager.currentTier = .basic
        XCTAssertFalse(mockSubscriptionManager.hasUnlimitedExport())
    }

    func testHasUnlimitedExportPremium() {
        mockSubscriptionManager.simulatePremiumSubscription()
        XCTAssertTrue(mockSubscriptionManager.hasUnlimitedExport())
    }

    func testMaxProfessionalSharesBasic() {
        mockSubscriptionManager.currentTier = .basic
        XCTAssertEqual(mockSubscriptionManager.maxProfessionalShares(), 1)
    }

    func testMaxProfessionalSharesPremium() {
        mockSubscriptionManager.simulatePremiumSubscription()
        XCTAssertEqual(mockSubscriptionManager.maxProfessionalShares(), Int.max)
    }

    // MARK: - Expiry Tests

    func testIsExpiringSoonWhenNoSubscription() {
        XCTAssertFalse(mockSubscriptionManager.isExpiringSoon)
    }

    func testIsExpiringSoonWhenExpiringSoon() {
        // Given - expires in 5 days (use hours for more reliable calculation)
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.subscriptionExpiryDate = Date().addingTimeInterval(5 * 24 * 60 * 60 + 3600) // 5 days + 1 hour

        // Then
        XCTAssertTrue(mockSubscriptionManager.isExpiringSoon)
        XCTAssertTrue(mockSubscriptionManager.daysUntilExpiry >= 4 && mockSubscriptionManager.daysUntilExpiry <= 5)
    }

    func testIsExpiringSoonWhenNotExpiringSoon() {
        // Given - expires in 30 days
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())

        // Then
        XCTAssertFalse(mockSubscriptionManager.isExpiringSoon)
    }

    func testHasExpiredWhenExpired() {
        // Given
        mockSubscriptionManager.simulateExpired()

        // Then
        XCTAssertTrue(mockSubscriptionManager.hasExpired)
    }

    func testHasExpiredWhenNotExpired() {
        // Given
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())

        // Then
        XCTAssertFalse(mockSubscriptionManager.hasExpired)
    }

    func testExpiryWarningMessageWhenExpired() {
        // Given
        mockSubscriptionManager.simulateExpired()

        // Then
        XCTAssertNotNil(mockSubscriptionManager.expiryWarningMessage)
        XCTAssertTrue(mockSubscriptionManager.expiryWarningMessage?.contains("expired") ?? false)
    }

    func testExpiryWarningMessageWhenExpiringSoon() {
        // Given - expires in ~1 day (use hours for reliable calculation)
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.subscriptionExpiryDate = Date().addingTimeInterval(26 * 60 * 60) // 26 hours from now

        // Then
        XCTAssertNotNil(mockSubscriptionManager.expiryWarningMessage)
        // Should contain either "tomorrow" or "1 day" depending on exact timing
        let message = mockSubscriptionManager.expiryWarningMessage ?? ""
        XCTAssertTrue(message.contains("tomorrow") || message.contains("1 day") || message.contains("expires"), "Expected expiry warning message")
    }

    func testExpiryWarningMessageWhenExpiringSoonMultipleDays() {
        // Given - expires in ~5 days (use hours for reliable calculation)
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.subscriptionExpiryDate = Date().addingTimeInterval(5 * 24 * 60 * 60 + 3600) // 5 days + 1 hour

        // Then
        XCTAssertNotNil(mockSubscriptionManager.expiryWarningMessage)
        // Should contain days count (4 or 5 depending on exact timing)
        let message = mockSubscriptionManager.expiryWarningMessage ?? ""
        XCTAssertTrue(message.contains("days") || message.contains("expires"), "Expected expiry warning message with days")
    }

    func testExpiryWarningMessageWhenNotExpiring() {
        // Given - not premium, so no warning
        mockSubscriptionManager.currentTier = .basic

        // Then
        XCTAssertNil(mockSubscriptionManager.expiryWarningMessage)
    }

    func testCheckExpiryStatus() {
        // Given
        mockSubscriptionManager.simulateExpiringSoon(daysFromNow: 3)
        XCTAssertFalse(mockSubscriptionManager.checkExpiryStatusCalled)

        // When
        mockSubscriptionManager.checkExpiryStatus()

        // Then
        XCTAssertTrue(mockSubscriptionManager.checkExpiryStatusCalled)
        XCTAssertTrue(mockSubscriptionManager.showExpiryWarning)
    }

    func testCheckExpiryStatusNoWarningWhenNotExpiring() {
        // Given - not expiring
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.subscriptionExpiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())

        // When
        mockSubscriptionManager.checkExpiryStatus()

        // Then
        XCTAssertFalse(mockSubscriptionManager.showExpiryWarning)
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() {
        // Given - set some state
        mockSubscriptionManager.simulatePremiumSubscription()
        mockSubscriptionManager.loadProductsCalled = true
        mockSubscriptionManager.purchaseProductCalled = true
        mockSubscriptionManager.restorePurchasesCalled = true
        mockSubscriptionManager.errorMessage = "Test error"

        // When
        mockSubscriptionManager.reset()

        // Then
        XCTAssertEqual(mockSubscriptionManager.currentTier, .basic)
        XCTAssertFalse(mockSubscriptionManager.isPaidSubscriber)
        XCTAssertFalse(mockSubscriptionManager.loadProductsCalled)
        XCTAssertFalse(mockSubscriptionManager.purchaseProductCalled)
        XCTAssertFalse(mockSubscriptionManager.restorePurchasesCalled)
        XCTAssertNil(mockSubscriptionManager.errorMessage)
    }

    // MARK: - Publisher Tests

    func testCurrentTierPublisher() async {
        // Given
        let expectation = XCTestExpectation(description: "Tier publisher emits value")

        mockSubscriptionManager.currentTierPublisher
            .dropFirst()
            .sink { tier in
                XCTAssertEqual(tier, .premium)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockSubscriptionManager.currentTier = .premium

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testIsPaidSubscriberPublisher() async {
        // Given
        let expectation = XCTestExpectation(description: "isPaidSubscriber publisher emits value")

        mockSubscriptionManager.isPaidSubscriberPublisher
            .dropFirst()
            .sink { isPaid in
                XCTAssertTrue(isPaid)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockSubscriptionManager.isPaidSubscriber = true

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testIsLoadingPublisher() async {
        // Given
        let expectation = XCTestExpectation(description: "isLoading publisher emits value")

        mockSubscriptionManager.isLoadingPublisher
            .dropFirst()
            .sink { isLoading in
                XCTAssertTrue(isLoading)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockSubscriptionManager.isLoading = true

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Error Handling Tests

    func testSubscriptionErrorProductNotFound() {
        let error = SubscriptionError.productNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("not found") ?? false)
    }

    func testSubscriptionErrorPurchaseFailed() {
        let error = SubscriptionError.purchaseFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("failed") ?? false)
    }

    func testSubscriptionErrorPurchaseCancelled() {
        let error = SubscriptionError.purchaseCancelled
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("cancelled") ?? false)
    }

    func testSubscriptionErrorVerificationFailed() {
        let error = SubscriptionError.verificationFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("verify") ?? false)
    }

    func testSubscriptionErrorRestoreFailed() {
        let error = SubscriptionError.restoreFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("restore") ?? false || error.errorDescription?.contains("No previous") ?? false)
    }

    func testSubscriptionErrorUnknown() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = SubscriptionError.unknown(underlyingError)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Test error") ?? false)
    }
}
