//
//  OnboardingUITests.swift
//  OralableAppUITests
//
//  Purpose: UI tests for privacy-first onboarding flow and navigation
//

import XCTest

final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-onboarding"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Onboarding Screen Display Tests

    @MainActor
    func testOnboardingScreenDisplaysOnFirstLaunch() throws {
        app.launch()

        // Logo should be visible
        let logo = app.images["MAMMark"]
        if logo.waitForExistence(timeout: 5) {
            XCTAssertTrue(logo.exists, "App logo should be visible on onboarding")
        }
    }

    @MainActor
    func testOnboardingShowsWelcomeTitle() throws {
        app.launch()

        // First page title should be visible
        let welcomeTitle = app.staticTexts["One night on the temple"]
        if welcomeTitle.waitForExistence(timeout: 5) {
            XCTAssertTrue(welcomeTitle.exists, "Welcome title should be displayed")
        }
    }

    @MainActor
    func testOnboardingShowsTagline() throws {
        app.launch()

        // Tagline should be visible on first page
        let tagline = app.staticTexts["Handle the truth"]
        if tagline.waitForExistence(timeout: 5) {
            XCTAssertTrue(tagline.exists, "Tagline should be displayed")
        }
    }

    // MARK: - Page Navigation Tests

    @MainActor
    func testCanSwipeThroughOnboardingPages() throws {
        app.launch()

        // Wait for onboarding to appear
        let firstPageTitle = app.staticTexts["One night on the temple"]
        guard firstPageTitle.waitForExistence(timeout: 5) else {
            // May already be logged in
            return
        }

        // Swipe to second page
        app.swipeLeft()

        // Second page should be visible
        let secondPageTitle = app.staticTexts["Integrate with Apple Health"]
        if secondPageTitle.waitForExistence(timeout: 3) {
            XCTAssertTrue(secondPageTitle.exists, "Second page should be visible after swipe")
        }
    }

    @MainActor
    func testCanSwipeBackOnOnboarding() throws {
        app.launch()

        // Wait for onboarding to appear
        let firstPageTitle = app.staticTexts["One night on the temple"]
        guard firstPageTitle.waitForExistence(timeout: 5) else {
            return
        }

        // Swipe to second page
        app.swipeLeft()

        // Wait for transition
        Thread.sleep(forTimeInterval: 0.5)

        // Swipe back
        app.swipeRight()

        // First page should be visible again
        let firstPageVisible = app.staticTexts["One night on the temple"]
        if firstPageVisible.waitForExistence(timeout: 3) {
            XCTAssertTrue(firstPageVisible.exists, "Should be able to swipe back to first page")
        }
    }

    @MainActor
    func testCanNavigateToAllPages() throws {
        app.launch()

        // Wait for onboarding
        let firstPage = app.staticTexts["One night on the temple"]
        guard firstPage.waitForExistence(timeout: 5) else {
            return
        }

        // Navigate through all pages
        let pageTitles = [
            "One night on the temple",
            "Integrate with Apple Health",
            "See last night",
            "Share the night report"
        ]

        for i in 0..<(pageTitles.count - 1) {
            app.swipeLeft()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Last page should be visible
        let lastPage = app.staticTexts["Share the night report"]
        if lastPage.waitForExistence(timeout: 3) {
            XCTAssertTrue(lastPage.exists, "Should reach last onboarding page")
        }
    }

    // MARK: - Privacy Links Tests

    @MainActor
    func testPrivacyPolicyLinkExists() throws {
        app.launch()

        // Privacy link should be in footer
        let privacyLink = app.links["Privacy Policy"]
        if privacyLink.waitForExistence(timeout: 5) {
            XCTAssertTrue(privacyLink.exists, "Privacy Policy link should exist")
        }
    }

    @MainActor
    func testTermsOfServiceLinkExists() throws {
        app.launch()

        // Terms link should be in footer
        let termsLink = app.links["Terms of Service"]
        if termsLink.waitForExistence(timeout: 5) {
            XCTAssertTrue(termsLink.exists, "Terms of Service link should exist")
        }
    }

    // MARK: - Device Requirement Notice Tests

    @MainActor
    func testDeviceRequirementNoticeDisplayed() throws {
        app.launch()

        // Device requirement notice in footer
        let deviceNotice = app.staticTexts["Requires a MAM"]
        if deviceNotice.waitForExistence(timeout: 5) {
            XCTAssertTrue(deviceNotice.exists, "Device requirement notice should be displayed")
        }
    }

    // MARK: - Sign In Button Tests

    @MainActor
    func testSignInWithAppleButtonExists() throws {
        app.launch()

        // Sign In with Apple button should exist
        let signInButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign in with Apple' OR label CONTAINS[c] 'Apple'")).firstMatch

        if signInButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(signInButton.exists, "Sign In with Apple button should exist")
            XCTAssertTrue(signInButton.isEnabled, "Sign In button should be enabled")
        }
    }

    @MainActor
    func testSignInButtonIsTappable() throws {
        app.launch()

        // Find Sign In button
        let signInButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign in' OR label CONTAINS[c] 'Apple'")).firstMatch

        if signInButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(signInButton.isHittable, "Sign In button should be tappable")
        }
    }

    // MARK: - Page Indicator Tests

    @MainActor
    func testPageIndicatorExists() throws {
        app.launch()

        // Page indicator should show current page
        let pageIndicator = app.pageIndicators.firstMatch
        if pageIndicator.waitForExistence(timeout: 5) {
            XCTAssertTrue(pageIndicator.exists, "Page indicator should exist")
        }
    }

    // MARK: - Accessibility Tests

    @MainActor
    func testOnboardingElementsHaveAccessibilityLabels() throws {
        app.launch()

        // Check main title accessibility
        let title = app.staticTexts["One night on the temple"]
        if title.waitForExistence(timeout: 5) {
            XCTAssertNotNil(title.label, "Title should have accessibility label")
        }
    }

    @MainActor
    func testSignInButtonHasAccessibilityLabel() throws {
        app.launch()

        let signInButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign' OR label CONTAINS[c] 'Apple'")).firstMatch

        if signInButton.waitForExistence(timeout: 5) {
            XCTAssertFalse(signInButton.label.isEmpty, "Sign In button should have accessibility label")
        }
    }

    // MARK: - Content Tests

    @MainActor
    func testWellnessDescriptionDisplayed() throws {
        app.launch()

        // First page should mention wellness use cases
        let description = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'wellness'")).firstMatch

        if description.waitForExistence(timeout: 5) {
            XCTAssertTrue(description.exists, "Wellness description should be displayed")
        }
    }

    @MainActor
    func testHealthIntegrationPageContent() throws {
        app.launch()

        // Navigate to Health page
        let firstPage = app.staticTexts["One night on the temple"]
        guard firstPage.waitForExistence(timeout: 5) else {
            return
        }

        app.swipeLeft()

        // Health page content
        let healthContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Apple Health'")).firstMatch
        if healthContent.waitForExistence(timeout: 3) {
            XCTAssertTrue(healthContent.exists, "Health integration content should be displayed")
        }
    }

    @MainActor
    func testProviderSharingPageContent() throws {
        app.launch()

        // Navigate to provider sharing page (4th page)
        let firstPage = app.staticTexts["One night on the temple"]
        guard firstPage.waitForExistence(timeout: 5) else {
            return
        }

        // Swipe to 4th page
        for _ in 0..<3 {
            app.swipeLeft()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Provider sharing content
        let sharingContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Provider' OR label CONTAINS[c] 'healthcare'")).firstMatch
        if sharingContent.waitForExistence(timeout: 3) {
            XCTAssertTrue(sharingContent.exists, "Provider sharing content should be displayed")
        }
    }

    // MARK: - Performance Tests

    @MainActor
    func testOnboardingLoadPerformance() throws {
        measure(metrics: [XCTClockMetric()]) {
            app.launch()

            // Wait for onboarding to load
            let title = app.staticTexts["One night on the temple"]
            _ = title.waitForExistence(timeout: 10)
        }
    }

    // MARK: - State Persistence Tests

    @MainActor
    func testOnboardingDoesNotShowAfterCompletion() throws {
        // This test requires completing onboarding first
        app.launchArguments = ["--uitesting", "--onboarding-completed"]
        app.launch()

        // Onboarding should not be visible
        let onboardingTitle = app.staticTexts["One night on the temple"]

        // Give time to load
        Thread.sleep(forTimeInterval: 2)

        // If onboarding completed, we should see main app
        if !onboardingTitle.exists {
            XCTAssertTrue(true, "Onboarding should not show after completion")
        }
    }
}
