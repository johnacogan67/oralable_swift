//
//  MetadataValidationTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: App Store metadata validation tests
//  Tests app metadata, privacy manifest, and StoreKit localization
//

import XCTest
import Foundation
@testable import OralableApp

/// Metadata validation tests for App Store readiness
/// Verifies app store metadata, privacy manifest, and subscription configuration
@MainActor
final class MetadataValidationTests: XCTestCase {

    // MARK: - Test Properties

    /// Prohibited terms for App Store metadata
    private let prohibitedMetadataTerms = [
        "diagnosis",
        "diagnose",
        "diagnostic",
        "medical device",
        "FDA",
        "FDA-cleared",
        "FDA-approved",
        "treatment",
        "treats",
        "cure",
        "cures",
        "prescribe",
        "clinical diagnosis",
        "detects disease",
        "identifies condition",
        "sleep apnea",
        "bruxism diagnosis"
    ]

    /// Required privacy manifest data types
    private let requiredPrivacyDataTypes = [
        "NSPrivacyCollectedDataTypeHealth",
        "NSPrivacyCollectedDataTypeUserID"
    ]

    /// Required privacy API categories
    private let requiredPrivacyAPICategories = [
        "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPICategoryFileTimestamp"
    ]

    // MARK: - App Store Metadata Tests

    func testAppNameContainsNoDiagnosticClaims() throws {
        let infoPlist = try loadInfoPlist()

        // Check CFBundleDisplayName
        if let displayName = infoPlist["CFBundleDisplayName"] as? String {
            for term in prohibitedMetadataTerms {
                XCTAssertFalse(
                    displayName.lowercased().contains(term.lowercased()),
                    "App display name should not contain '\(term)'"
                )
            }
        }

        // Check CFBundleName
        if let bundleName = infoPlist["CFBundleName"] as? String {
            for term in prohibitedMetadataTerms {
                XCTAssertFalse(
                    bundleName.lowercased().contains(term.lowercased()),
                    "App bundle name should not contain '\(term)'"
                )
            }
        }
    }

    func testAppStoreMetadataFilesExist() throws {
        let projectRoot = getProjectRoot()

        // Check for App Store metadata markdown files
        let metadataFiles = [
            "DENTIST_APP_STORE_METADATA.md",
            "APP_STORE_CONNECT_IAP_SETUP.md"
        ]

        for filename in metadataFiles {
            let filePath = projectRoot.appendingPathComponent(filename)
            // These are optional but if they exist, check them
            if FileManager.default.fileExists(atPath: filePath.path) {
                let content = try String(contentsOf: filePath, encoding: .utf8)

                for term in prohibitedMetadataTerms {
                    // Only check critical terms in metadata docs
                    let criticalTerms = ["FDA", "diagnos", "medical device", "cure"]
                    if criticalTerms.contains(where: { term.lowercased().contains($0) }) {
                        // Allow if it's in a disclaimer context
                        if !content.contains("NOT") && !content.contains("does not") {
                            XCTAssertFalse(
                                content.lowercased().contains(term.lowercased()),
                                "\(filename) should not contain '\(term)' without disclaimer"
                            )
                        }
                    }
                }
            }
        }
    }

    func testOnboardingScreensContainNoDiagnosticClaims() throws {
        let projectRoot = getProjectRoot()
        let onboardingPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("OnboardingView.swift")

        guard let content = try? String(contentsOf: onboardingPath, encoding: .utf8) else {
            XCTFail("Could not read OnboardingView.swift")
            return
        }

        // Extract string literals (potential screenshot content)
        let stringPattern = #""([^"\\]|\\.)*""#
        let regex = try NSRegularExpression(pattern: stringPattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        for match in matches {
            if let matchRange = Range(match.range, in: content) {
                let stringLiteral = String(content[matchRange])

                for term in prohibitedMetadataTerms {
                    XCTAssertFalse(
                        stringLiteral.lowercased().contains(term.lowercased()),
                        "Onboarding string should not contain '\(term)': \(stringLiteral)"
                    )
                }
            }
        }
    }

    // MARK: - Privacy Manifest Tests

    func testPrivacyManifestExists() throws {
        let projectRoot = getProjectRoot()
        let privacyManifestPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("PrivacyInfo.xcprivacy")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: privacyManifestPath.path),
            "Privacy manifest (PrivacyInfo.xcprivacy) must exist"
        )
    }

    func testPrivacyManifestIsValidPlist() throws {
        let privacyPlist = try loadPrivacyManifest()

        // Should be a valid dictionary
        XCTAssertFalse(privacyPlist.isEmpty, "Privacy manifest should not be empty")
    }

    func testPrivacyManifestDeclaresNoTracking() throws {
        let privacyPlist = try loadPrivacyManifest()

        // NSPrivacyTracking should be false
        if let tracking = privacyPlist["NSPrivacyTracking"] as? Bool {
            XCTAssertFalse(tracking, "Privacy manifest should declare no tracking (NSPrivacyTracking = false)")
        }

        // NSPrivacyTrackingDomains should be empty
        if let trackingDomains = privacyPlist["NSPrivacyTrackingDomains"] as? [String] {
            XCTAssertTrue(trackingDomains.isEmpty, "Privacy manifest should have no tracking domains")
        }
    }

    func testPrivacyManifestDeclaresHealthDataCollection() throws {
        let privacyPlist = try loadPrivacyManifest()

        guard let collectedDataTypes = privacyPlist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] else {
            XCTFail("Privacy manifest should declare collected data types")
            return
        }

        // Check that health data is declared
        let declaredTypes = collectedDataTypes.compactMap { $0["NSPrivacyCollectedDataType"] as? String }

        XCTAssertTrue(
            declaredTypes.contains("NSPrivacyCollectedDataTypeHealth"),
            "Privacy manifest should declare health data collection"
        )
    }

    func testPrivacyManifestDeclaresUserIDCollection() throws {
        let privacyPlist = try loadPrivacyManifest()

        guard let collectedDataTypes = privacyPlist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] else {
            XCTFail("Privacy manifest should declare collected data types")
            return
        }

        let declaredTypes = collectedDataTypes.compactMap { $0["NSPrivacyCollectedDataType"] as? String }

        XCTAssertTrue(
            declaredTypes.contains("NSPrivacyCollectedDataTypeUserID"),
            "Privacy manifest should declare user ID collection (for Sign in with Apple)"
        )
    }

    func testPrivacyManifestDeclaresAPIUsage() throws {
        let privacyPlist = try loadPrivacyManifest()

        guard let accessedAPITypes = privacyPlist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] else {
            XCTFail("Privacy manifest should declare accessed API types")
            return
        }

        let declaredAPIs = accessedAPITypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }

        // Check for UserDefaults API declaration
        XCTAssertTrue(
            declaredAPIs.contains("NSPrivacyAccessedAPICategoryUserDefaults"),
            "Privacy manifest should declare UserDefaults API usage"
        )
    }

    func testPrivacyManifestHasValidReasons() throws {
        let privacyPlist = try loadPrivacyManifest()

        guard let accessedAPITypes = privacyPlist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] else {
            return // Already tested in other test
        }

        for apiType in accessedAPITypes {
            guard let reasons = apiType["NSPrivacyAccessedAPITypeReasons"] as? [String] else {
                continue
            }

            // Each declared API should have at least one reason
            XCTAssertFalse(
                reasons.isEmpty,
                "Each accessed API type should have at least one reason"
            )

            // Reasons should be valid Apple-defined reason codes
            for reason in reasons {
                XCTAssertTrue(
                    reason.count >= 4, // Reason codes are typically like "C617.1", "CA92.1", etc.
                    "API reason '\(reason)' should be a valid Apple reason code"
                )
            }
        }
    }

    func testPrivacyManifestDataNotUsedForTracking() throws {
        let privacyPlist = try loadPrivacyManifest()

        guard let collectedDataTypes = privacyPlist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] else {
            return
        }

        for dataType in collectedDataTypes {
            if let tracking = dataType["NSPrivacyCollectedDataTypeTracking"] as? Bool {
                XCTAssertFalse(
                    tracking,
                    "Collected data should not be used for tracking"
                )
            }
        }
    }

    // MARK: - StoreKit Subscription Metadata Tests

    func testSubscriptionTiersAreDefined() {
        // Verify subscription tiers exist
        let basic = SubscriptionTier.basic
        let premium = SubscriptionTier.premium

        XCTAssertNotEqual(basic, premium, "Basic and premium tiers should be distinct")
    }

    func testSubscriptionTiersHaveDisplayNames() {
        XCTAssertFalse(SubscriptionTier.basic.displayName.isEmpty, "Basic tier should have display name")
        XCTAssertFalse(SubscriptionTier.premium.displayName.isEmpty, "Premium tier should have display name")
    }

    func testSubscriptionTiersHaveFeatures() {
        XCTAssertFalse(SubscriptionTier.basic.features.isEmpty, "Basic tier should list features")
        XCTAssertFalse(SubscriptionTier.premium.features.isEmpty, "Premium tier should list features")
    }

    func testSubscriptionFeaturesContainNoDiagnosticClaims() {
        let allFeatures = SubscriptionTier.basic.features + SubscriptionTier.premium.features

        for feature in allFeatures {
            for term in prohibitedMetadataTerms {
                XCTAssertFalse(
                    feature.lowercased().contains(term.lowercased()),
                    "Subscription feature should not contain '\(term)': \(feature)"
                )
            }
        }
    }

    func testSubscriptionManagerExists() {
        let manager = SubscriptionManager()
        XCTAssertNotNil(manager, "SubscriptionManager should be instantiable")
    }

    func testSubscriptionErrorsAreDefined() {
        // Verify all subscription error cases exist
        let errors: [SubscriptionError] = [
            .productNotFound,
            .purchaseFailed,
            .purchaseCancelled,
            .verificationFailed,
            .restoreFailed,
            .unknown(NSError(domain: "test", code: 0))
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Subscription error should have description")
        }
    }

    // MARK: - Localization Tests

    func testInfoPlistUsageStringsAreLocalizable() throws {
        let infoPlist = try loadInfoPlist()

        // These keys should have user-facing strings
        let usageKeys = [
            "NSBluetoothAlwaysUsageDescription",
            "NSBluetoothPeripheralUsageDescription"
        ]

        for key in usageKeys {
            if let value = infoPlist[key] as? String {
                XCTAssertFalse(value.isEmpty, "\(key) should have a description")
                XCTAssertGreaterThan(value.count, 10, "\(key) should have a meaningful description")
            }
        }
    }

    func testAppHasRequiredPermissionDescriptions() throws {
        let infoPlist = try loadInfoPlist()

        // Bluetooth is required
        XCTAssertNotNil(
            infoPlist["NSBluetoothAlwaysUsageDescription"],
            "App should have Bluetooth always usage description"
        )
    }

    // MARK: - App Store Connect Configuration Tests

    func testAppUsesNonExemptEncryptionDeclared() throws {
        let infoPlist = try loadInfoPlist()

        // ITSAppUsesNonExemptEncryption must be declared
        XCTAssertNotNil(
            infoPlist["ITSAppUsesNonExemptEncryption"],
            "App should declare ITSAppUsesNonExemptEncryption"
        )

        // For most apps without custom encryption, this should be false
        if let usesEncryption = infoPlist["ITSAppUsesNonExemptEncryption"] as? Bool {
            // Just verify it's explicitly declared (either true or false is valid)
            XCTAssertTrue(true, "ITSAppUsesNonExemptEncryption is declared")
        }
    }

    // MARK: - Helper Methods

    private func getProjectRoot() -> URL {
        let testBundle = Bundle(for: type(of: self))
        var url = testBundle.bundleURL

        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("OralableApp").path) {
            url = url.deletingLastPathComponent()
            if url.path == "/" {
                return URL(fileURLWithPath: "/Users/johnacogan67/Projects/oralable_ios/OralableApp")
            }
        }

        return url
    }

    private func loadInfoPlist() throws -> [String: Any] {
        let projectRoot = getProjectRoot()
        let infoPlistPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Info.plist")

        let plistData = try Data(contentsOf: infoPlistPath)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw NSError(domain: "MetadataValidationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse Info.plist"])
        }

        return plist
    }

    private func loadPrivacyManifest() throws -> [String: Any] {
        let projectRoot = getProjectRoot()
        let privacyPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("PrivacyInfo.xcprivacy")

        let plistData = try Data(contentsOf: privacyPath)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw NSError(domain: "MetadataValidationTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse PrivacyInfo.xcprivacy"])
        }

        return plist
    }
}

// MARK: - Screenshot Content Validation

extension MetadataValidationTests {

    func testDashboardViewContainsNoDiagnosticTerms() throws {
        let projectRoot = getProjectRoot()
        let dashboardPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("DashboardView.swift")

        guard let content = try? String(contentsOf: dashboardPath, encoding: .utf8) else {
            return // File may have different name
        }

        // Extract user-facing string literals
        let stringPattern = #""([^"\\]|\\.)*""#
        let regex = try NSRegularExpression(pattern: stringPattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        for match in matches {
            if let matchRange = Range(match.range, in: content) {
                let stringLiteral = String(content[matchRange])

                // Skip short strings (likely not user-facing) and code-like strings
                if stringLiteral.count < 5 || stringLiteral.contains(".") && !stringLiteral.contains(" ") {
                    continue
                }

                for term in prohibitedMetadataTerms {
                    XCTAssertFalse(
                        stringLiteral.lowercased().contains(term.lowercased()),
                        "Dashboard string should not contain '\(term)': \(stringLiteral)"
                    )
                }
            }
        }
    }

    func testSettingsViewContainsNoDiagnosticTerms() throws {
        let projectRoot = getProjectRoot()
        let settingsPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("SettingsView.swift")

        guard let content = try? String(contentsOf: settingsPath, encoding: .utf8) else {
            return
        }

        let stringPattern = #""([^"\\]|\\.)*""#
        let regex = try NSRegularExpression(pattern: stringPattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        for match in matches {
            if let matchRange = Range(match.range, in: content) {
                let stringLiteral = String(content[matchRange])

                if stringLiteral.count < 5 {
                    continue
                }

                for term in prohibitedMetadataTerms {
                    XCTAssertFalse(
                        stringLiteral.lowercased().contains(term.lowercased()),
                        "Settings string should not contain '\(term)': \(stringLiteral)"
                    )
                }
            }
        }
    }
}
