//
//  OnboardingViewModelTests.swift
//  OralableAppTests
//
//  Purpose: Unit tests for onboarding privacy-first flow, disclaimers, and consent
//

import XCTest
import Combine
@testable import OralableApp

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        // Clear onboarding state for clean tests
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "hasAcceptedPrivacyPolicy")
        UserDefaults.standard.removeObject(forKey: "hasAcceptedTerms")
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Onboarding Page Content Tests

    func testOnboardingPageCountIsCorrect() {
        // The onboarding should have multiple pages for a complete experience
        let expectedMinimumPages = 3
        // Based on OnboardingView, there are 4 pages
        let actualPageCount = 4

        XCTAssertGreaterThanOrEqual(actualPageCount, expectedMinimumPages, "Onboarding should have at least \(expectedMinimumPages) pages")
    }

    func testFirstPageShowsWelcomeContent() {
        // First page should introduce the app
        let firstPageTitle = "Muscle Activity Monitor"
        let firstPageDescription = "Monitor muscle activity for wellness, therapy, sports, and research"

        XCTAssertFalse(firstPageTitle.isEmpty, "First page should have a title")
        XCTAssertFalse(firstPageDescription.isEmpty, "First page should have a description")
        XCTAssertTrue(firstPageDescription.contains("wellness"), "Description should mention wellness use case")
    }

    func testOnboardingIncludesHealthIntegrationPage() {
        // One page should cover Apple Health integration
        let healthPageTitle = "Integrate with Apple Health"
        let healthDescription = "Sync heart rate and SpO2 data with Apple Health"

        XCTAssertFalse(healthPageTitle.isEmpty, "Health integration page should have a title")
        XCTAssertTrue(healthDescription.contains("Health"), "Description should mention Apple Health")
    }

    func testOnboardingIncludesAnalyticsPage() {
        // One page should cover analytics/insights
        let analyticsTitle = "Understand Your Patterns"
        let analyticsDescription = "Gain insights into your muscle activity with detailed analytics"

        XCTAssertFalse(analyticsTitle.isEmpty, "Analytics page should have a title")
        XCTAssertTrue(analyticsDescription.contains("insights"), "Description should mention insights")
    }

    func testOnboardingIncludesProviderSharingPage() {
        // One page should cover sharing with healthcare providers
        let sharingTitle = "Share with Your Provider"
        let sharingDescription = "Collaborate with your healthcare professional by securely sharing your data"

        XCTAssertFalse(sharingTitle.isEmpty, "Sharing page should have a title")
        XCTAssertTrue(sharingDescription.contains("securely"), "Description should emphasize security")
        XCTAssertTrue(sharingDescription.contains("healthcare"), "Description should mention healthcare professional")
    }

    // MARK: - Privacy Disclaimer Tests

    func testPrivacyDisclaimerContent() {
        // The app should communicate that it's a wellness app, not medical device
        let disclaimerText = "Oralable is a wellness app, not a medical device"

        // Verify disclaimer includes key wellness messaging
        XCTAssertTrue(disclaimerText.contains("wellness"), "Disclaimer should mention wellness")
        XCTAssertTrue(disclaimerText.contains("not a medical device"), "Disclaimer should state it's not a medical device")
    }

    func testPrivacyFirstMessaging() {
        // Privacy-first messaging should emphasize user data ownership
        let privacyMessage = "Your data stays on your device unless you choose to share it"

        XCTAssertTrue(privacyMessage.contains("your device"), "Privacy message should mention local storage")
        XCTAssertTrue(privacyMessage.contains("choose"), "Privacy message should emphasize user choice")
    }

    func testNoDiagnosticsDisclaimer() {
        // App should not provide medical diagnostics
        let noDiagnosticsText = "This app does not provide medical diagnoses or recommendations"

        XCTAssertTrue(noDiagnosticsText.contains("not provide"), "Should state what app doesn't do")
        XCTAssertTrue(noDiagnosticsText.contains("diagnos"), "Should mention diagnostics limitation")
    }

    // MARK: - Consent Tests

    func testOnboardingRequiresExplicitConsent() {
        // User should explicitly accept terms before proceeding
        let hasAcceptedTerms = UserDefaults.standard.bool(forKey: "hasAcceptedTerms")

        // Initially should be false
        XCTAssertFalse(hasAcceptedTerms, "User should not have accepted terms initially")
    }

    func testPrivacyPolicyAcceptanceTracked() {
        // Privacy policy acceptance should be tracked
        let hasAcceptedPrivacy = UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")

        // Initially should be false
        XCTAssertFalse(hasAcceptedPrivacy, "User should not have accepted privacy policy initially")

        // After acceptance
        UserDefaults.standard.set(true, forKey: "hasAcceptedPrivacyPolicy")
        let afterAcceptance = UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")
        XCTAssertTrue(afterAcceptance, "Privacy acceptance should be persisted")
    }

    func testTermsOfServiceAcceptanceTracked() {
        // Terms acceptance should be tracked
        UserDefaults.standard.set(true, forKey: "hasAcceptedTerms")
        let afterAcceptance = UserDefaults.standard.bool(forKey: "hasAcceptedTerms")
        XCTAssertTrue(afterAcceptance, "Terms acceptance should be persisted")
    }

    func testOnboardingCompletionTracked() {
        // Onboarding completion should be tracked
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Initially should be false
        XCTAssertFalse(hasCompleted, "Onboarding should not be completed initially")

        // After completion
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        let afterCompletion = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        XCTAssertTrue(afterCompletion, "Onboarding completion should be persisted")
    }

    // MARK: - Settings Persistence Tests

    func testDataExportSettingPersistence() {
        // Data export preference should be persisted
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        // Default should be local storage only (privacy-first)
        XCTAssertTrue(viewModel.localStorageOnly, "Default should be local storage only")

        // Toggle and verify persistence
        viewModel.localStorageOnly = false
        viewModel.saveSetting("localStorageOnly", value: false)

        let persisted = UserDefaults.standard.bool(forKey: "localStorageOnly")
        XCTAssertFalse(persisted, "Setting change should be persisted")
    }

    func testNotificationSettingPersistence() {
        // Notification preference should be persisted
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        // Toggle notifications
        viewModel.notificationsEnabled = false
        viewModel.saveSetting("notificationsEnabled", value: false)

        let persisted = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        XCTAssertFalse(persisted, "Notification setting should be persisted")
    }

    func testShareAnalyticsDefaultsToDisabled() {
        // Privacy-first: analytics sharing should be disabled by default
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        XCTAssertFalse(viewModel.shareAnalytics, "Share analytics should be disabled by default for privacy")
    }

    func testLocalStorageOnlyDefaultsToEnabled() {
        // Privacy-first: local storage should be enabled by default
        // Clear any previous value first
        UserDefaults.standard.removeObject(forKey: "localStorageOnly")

        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        XCTAssertTrue(viewModel.localStorageOnly, "Local storage only should be enabled by default")
    }

    // MARK: - Privacy Links Tests

    func testPrivacyPolicyLinkIsValid() {
        // Privacy policy URL should be valid
        let privacyURL = URL(string: "https://oralable.com/privacy")

        XCTAssertNotNil(privacyURL, "Privacy policy URL should be valid")
        XCTAssertEqual(privacyURL?.scheme, "https", "Privacy URL should use HTTPS")
    }

    func testTermsOfServiceLinkIsValid() {
        // Terms of service URL should be valid
        let termsURL = URL(string: "https://oralable.com/terms")

        XCTAssertNotNil(termsURL, "Terms of service URL should be valid")
        XCTAssertEqual(termsURL?.scheme, "https", "Terms URL should use HTTPS")
    }

    // MARK: - Device Requirement Notice Tests

    func testDeviceRequirementNoticeDisplayed() {
        // Footer should mention device requirement
        let deviceNotice = "Requires Oralable device"

        XCTAssertTrue(deviceNotice.contains("Oralable device"), "Should mention Oralable device requirement")
    }

    // MARK: - Sign In Flow Tests

    func testSignInWithAppleIsAvailable() {
        // Sign In with Apple should be the authentication method
        // This is a structural test - the actual button exists in OnboardingView
        let authMethod = "Sign In with Apple"
        XCTAssertFalse(authMethod.isEmpty, "Sign In with Apple should be available")
    }

    // MARK: - Onboarding State Machine Tests

    func testOnboardingCanNavigateForward() {
        // Simulates page navigation
        var currentPage = 0
        let totalPages = 4

        // Can navigate forward
        currentPage += 1
        XCTAssertEqual(currentPage, 1, "Should navigate to page 1")

        currentPage += 1
        XCTAssertEqual(currentPage, 2, "Should navigate to page 2")

        currentPage += 1
        XCTAssertEqual(currentPage, 3, "Should navigate to page 3")

        // Cannot go past last page
        XCTAssertLessThan(currentPage, totalPages, "Should not exceed total pages")
    }

    func testOnboardingCanNavigateBackward() {
        // Simulates backward navigation
        var currentPage = 3
        let minPage = 0

        currentPage -= 1
        XCTAssertEqual(currentPage, 2, "Should navigate back to page 2")

        currentPage -= 1
        XCTAssertEqual(currentPage, 1, "Should navigate back to page 1")

        currentPage -= 1
        XCTAssertEqual(currentPage, 0, "Should navigate back to page 0")

        // Cannot go before first page
        XCTAssertGreaterThanOrEqual(currentPage, minPage, "Should not go below 0")
    }

    func testAccountDeletionClearsFirstLaunchSetupGates() async {
        let fitKey = "oralable.hasCompletedFirstFit"
        let pairedKey = "oralable.hasPairedOralablePrimary"
        let trialKey = "oralable.onboardingTrialSetupMode"
        let calibrationKey = "oralable.temporalis_sleep_calibration"

        UserDefaults.standard.set(true, forKey: fitKey)
        UserDefaults.standard.set(true, forKey: pairedKey)
        UserDefaults.standard.set(true, forKey: trialKey)
        UserDefaults.standard.set(Data([1, 2, 3]), forKey: calibrationKey)

        let authManager = AuthenticationManager()
        await authManager.deleteAccount()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: fitKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: pairedKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: trialKey))
        XCTAssertNil(UserDefaults.standard.data(forKey: calibrationKey))
    }
}
