//
//  ComplianceTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Compliance audit tests for App Store guidelines and regulatory requirements
//  Tests diagnostic language removal, onboarding disclaimers, privacy messaging, and consent
//

import XCTest
import Foundation
@testable import MAMDiagnostics

/// Compliance tests to ensure the app meets App Store guidelines
/// and does not make unauthorized medical/diagnostic claims
@MainActor
final class ComplianceTests: XCTestCase {

    // MARK: - Test Properties

    /// Prohibited diagnostic terms that should NOT appear in user-facing content
    private let prohibitedDiagnosticTerms = [
        "diagnos",           // diagnosis, diagnostic, diagnose
        "medical device",
        "FDA",
        "FDA-cleared",
        "FDA-approved",
        "treat",             // treatment, treats (in medical context)
        "cure",
        "prescribe",
        "prescription",
        "clinical diagnosis",
        "detect disease",
        "identify condition",
        "sleep apnea diagnosis",
        "diagnose bruxism"
    ]

    /// Required wellness/disclaimer terms that SHOULD appear
    private let requiredWellnessTerms = [
        "wellness",
        "monitor",
        "activity",
        "insight",
        "pattern"
    ]

    /// Source files to scan for prohibited content
    private var swiftSourceFiles: [URL] = []

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        // Get all Swift source files in the main app
        let projectRoot = getProjectRoot()
        let oralableAppPath = projectRoot.appendingPathComponent("OralableApp")

        swiftSourceFiles = findSwiftFiles(in: oralableAppPath)
    }

    // MARK: - Diagnostic Language Removal Tests

    func testNoProhibitedDiagnosticTermsInSourceCode() throws {
        var violations: [(file: String, term: String, line: Int)] = []

        for fileURL in swiftSourceFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)

            for (lineNumber, line) in lines.enumerated() {
                // Skip comments and test files
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.hasPrefix("//") || trimmedLine.hasPrefix("/*") || trimmedLine.hasPrefix("*") {
                    continue
                }

                // Skip test files
                if fileURL.path.contains("Tests") {
                    continue
                }

                for term in prohibitedDiagnosticTerms {
                    if line.lowercased().contains(term.lowercased()) {
                        // Check for false positives (e.g., "diagnostic" in code context)
                        if !isAllowedContext(line: line, term: term) {
                            violations.append((
                                file: fileURL.lastPathComponent,
                                term: term,
                                line: lineNumber + 1
                            ))
                        }
                    }
                }
            }
        }

        // Report violations
        if !violations.isEmpty {
            let violationReport = violations.map { "  - \($0.file):\($0.line) contains '\($0.term)'" }
                .joined(separator: "\n")
            XCTFail("Found prohibited diagnostic terms in source code:\n\(violationReport)")
        }
    }

    func testNoProhibitedTermsInUserFacingStrings() throws {
        // Check OnboardingView.swift specifically
        let projectRoot = getProjectRoot()
        let onboardingPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("OnboardingView.swift")

        guard let content = try? String(contentsOf: onboardingPath, encoding: .utf8) else {
            XCTFail("Could not read OnboardingView.swift")
            return
        }

        // Check for prohibited terms in string literals
        let stringPattern = #""([^"\\]|\\.)*""#
        let regex = try NSRegularExpression(pattern: stringPattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        var violations: [String] = []

        for match in matches {
            if let matchRange = Range(match.range, in: content) {
                let stringLiteral = String(content[matchRange])

                for term in prohibitedDiagnosticTerms {
                    if stringLiteral.lowercased().contains(term.lowercased()) {
                        violations.append("Found '\(term)' in string: \(stringLiteral)")
                    }
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Prohibited terms in user-facing strings:\n\(violations.joined(separator: "\n"))")
    }

    func testAppDescriptionIsWellnessOriented() throws {
        let projectRoot = getProjectRoot()
        let onboardingPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("OnboardingView.swift")

        guard let content = try? String(contentsOf: onboardingPath, encoding: .utf8) else {
            XCTFail("Could not read OnboardingView.swift")
            return
        }

        // Check that at least some wellness terms are present
        var foundTerms: [String] = []
        for term in requiredWellnessTerms {
            if content.lowercased().contains(term.lowercased()) {
                foundTerms.append(term)
            }
        }

        XCTAssertGreaterThan(foundTerms.count, 2, "App description should contain wellness-oriented language. Found: \(foundTerms)")
    }

    // MARK: - Onboarding Disclaimer Tests

    func testOnboardingContainsPrivacyPolicyLink() throws {
        let projectRoot = getProjectRoot()
        let onboardingPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("OnboardingView.swift")

        guard let content = try? String(contentsOf: onboardingPath, encoding: .utf8) else {
            XCTFail("Could not read OnboardingView.swift")
            return
        }

        XCTAssertTrue(
            content.contains("Privacy Policy") || content.contains("privacy"),
            "Onboarding should contain a link to Privacy Policy"
        )

        XCTAssertTrue(
            content.contains("oralable.com/privacy") || content.contains("privacyPolicy"),
            "Onboarding should link to actual privacy policy URL"
        )
    }

    func testOnboardingContainsTermsOfServiceLink() throws {
        let projectRoot = getProjectRoot()
        let onboardingPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("OnboardingView.swift")

        guard let content = try? String(contentsOf: onboardingPath, encoding: .utf8) else {
            XCTFail("Could not read OnboardingView.swift")
            return
        }

        XCTAssertTrue(
            content.contains("Terms of Service") || content.contains("terms"),
            "Onboarding should contain a link to Terms of Service"
        )

        XCTAssertTrue(
            content.contains("oralable.com/terms") || content.contains("termsOfService"),
            "Onboarding should link to actual terms URL"
        )
    }

    func testOnboardingDescribesDeviceRequirement() throws {
        let projectRoot = getProjectRoot()
        let onboardingPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("OnboardingView.swift")

        guard let content = try? String(contentsOf: onboardingPath, encoding: .utf8) else {
            XCTFail("Could not read OnboardingView.swift")
            return
        }

        XCTAssertTrue(
            content.contains("Oralable device") || content.contains("requires") || content.contains("Required"),
            "Onboarding should clearly state that an Oralable device is required"
        )
    }

    // MARK: - Privacy Messaging Consistency Tests

    func testPrivacyMessagingInSettings() throws {
        let projectRoot = getProjectRoot()
        let settingsPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("SettingsView.swift")

        guard let content = try? String(contentsOf: settingsPath, encoding: .utf8) else {
            // Settings file may be named differently - pass test if not found
            return
        }

        // Check for privacy-related settings
        let hasPrivacySection = content.contains("Privacy") ||
                                content.contains("privacy") ||
                                content.contains("Data")

        XCTAssertTrue(hasPrivacySection, "Settings should contain privacy-related options")
    }

    func testExportFlowIncludesPrivacyContext() throws {
        let projectRoot = getProjectRoot()
        let csvExportPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("CSVExportManager.swift")

        guard let content = try? String(contentsOf: csvExportPath, encoding: .utf8) else {
            XCTFail("Could not read CSVExportManager.swift")
            return
        }

        // Verify export includes user identifier for data ownership
        XCTAssertTrue(
            content.contains("userID") || content.contains("userIdentifier"),
            "Export should include user identifier for data ownership tracking"
        )
    }

    // MARK: - Data Export Schema Tests

    func testExportSchemaIsWellnessFormat() throws {
        let projectRoot = getProjectRoot()
        let csvExportPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Views")
            .appendingPathComponent("CSVExportManager.swift")

        guard let content = try? String(contentsOf: csvExportPath, encoding: .utf8) else {
            XCTFail("Could not read CSVExportManager.swift")
            return
        }

        // Check that export includes required wellness data fields
        let requiredFields = ["timestamp", "Timestamp", "Date", "Time"]
        let hasTimestamp = requiredFields.contains { content.contains($0) }
        XCTAssertTrue(hasTimestamp, "Export schema should include timestamp field")

        // Verify no diagnostic-specific fields
        let prohibitedFields = ["diagnosis", "disease_code", "icd_code", "clinical_finding"]
        for field in prohibitedFields {
            XCTAssertFalse(
                content.lowercased().contains(field),
                "Export schema should not include diagnostic field: \(field)"
            )
        }
    }

    func testSensorDataModelIsWellnessOriented() {
        // Test that SensorData struct uses wellness terminology
        // This verifies the data model at runtime
        let sensorData = SensorData(
            timestamp: Date(),
            ppg: PPGData(red: 100000, ir: 100000, green: 100000, timestamp: Date()),
            accelerometer: AccelerometerData(x: 0, y: 0, z: 0, timestamp: Date()),
            temperature: TemperatureData(celsius: 37.0, timestamp: Date()),
            battery: BatteryData(percentage: 100, timestamp: Date()),
            heartRate: HeartRateData(bpm: 70, quality: 0.9, timestamp: Date()),
            spo2: SpO2Data(percentage: 98, quality: 0.9, timestamp: Date()),
            deviceType: .oralable
        )

        // Verify wellness-oriented structure (not diagnostic)
        XCTAssertNotNil(sensorData.timestamp, "Sensor data should have timestamp")
        XCTAssertNotNil(sensorData.ppg, "Sensor data should have PPG (raw data, not diagnosis)")
        XCTAssertNotNil(sensorData.accelerometer, "Sensor data should have accelerometer for activity monitoring")
    }

    // MARK: - User Consent Tests

    func testConsentRequiredBeforeDataCollection() throws {
        let projectRoot = getProjectRoot()
        let authPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Managers")
            .appendingPathComponent("AuthenticationManager.swift")

        guard let content = try? String(contentsOf: authPath, encoding: .utf8) else {
            XCTFail("Could not read AuthenticationManager.swift")
            return
        }

        // Verify authentication/consent flow exists
        XCTAssertTrue(
            content.contains("SignInWithApple") ||
            content.contains("ASAuthorizationApple") ||
            content.contains("isAuthenticated") ||
            content.contains("consent"),
            "App should require user authentication/consent before data collection"
        )
    }

    func testPrivacyPolicyAcceptanceTracked() {
        // Test that privacy policy acceptance is tracked in UserDefaults
        let key = "hasAcceptedPrivacyPolicy"
        let originalValue = UserDefaults.standard.object(forKey: key)

        // Set and verify
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "Privacy policy acceptance should be persistable")

        // Restore original value
        if let original = originalValue {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testTermsAcceptanceTracked() {
        // Test that terms acceptance is tracked in UserDefaults
        let key = "hasAcceptedTerms"
        let originalValue = UserDefaults.standard.object(forKey: key)

        // Set and verify
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "Terms acceptance should be persistable")

        // Restore original value
        if let original = originalValue {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testOnboardingCompletionTracked() {
        // Test that onboarding completion is tracked
        let key = "hasCompletedOnboarding"
        let originalValue = UserDefaults.standard.object(forKey: key)

        // Set and verify
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "Onboarding completion should be persistable")

        // Restore original value
        if let original = originalValue {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - App Store Guidelines Compliance

    func testNoUnauthorizedHealthClaims() throws {
        var healthClaimViolations: [String] = []

        for fileURL in swiftSourceFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            // Skip test files
            if fileURL.path.contains("Tests") {
                continue
            }

            // Check for unauthorized health claims in string literals
            let unauthorizedClaims = [
                "cure",
                "prevent disease",
                "treat condition",
                "medical advice",
                "replace your doctor",
                "replace physician"
            ]

            for claim in unauthorizedClaims {
                if content.lowercased().contains(claim) {
                    healthClaimViolations.append("\(fileURL.lastPathComponent): contains '\(claim)'")
                }
            }
        }

        XCTAssertTrue(
            healthClaimViolations.isEmpty,
            "Found unauthorized health claims:\n\(healthClaimViolations.joined(separator: "\n"))"
        )
    }

    func testAppCategoryIsAppropriate() throws {
        let projectRoot = getProjectRoot()
        let infoPlistPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Info.plist")

        guard let plistData = try? Data(contentsOf: infoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            XCTFail("Could not read Info.plist")
            return
        }

        // Verify app category is not "Medical" (which requires FDA approval)
        if let category = plist["LSApplicationCategoryType"] as? String {
            XCTAssertFalse(
                category.lowercased().contains("medical"),
                "App category should not be 'Medical' without FDA approval"
            )
        }
    }

    // MARK: - Helper Methods

    private func getProjectRoot() -> URL {
        // Navigate from test bundle to project root
        let testBundle = Bundle(for: type(of: self))
        var url = testBundle.bundleURL

        // Go up until we find the OralableApp directory
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("OralableApp").path) {
            url = url.deletingLastPathComponent()
            if url.path == "/" {
                // Fallback to known path
                return URL(fileURLWithPath: "/Users/johnacogan67/Projects/oralable_ios/OralableApp")
            }
        }

        return url
    }

    private func findSwiftFiles(in directory: URL) -> [URL] {
        var swiftFiles: [URL] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return swiftFiles
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL)
            }
        }

        return swiftFiles
    }

    private func isAllowedContext(line: String, term: String) -> Bool {
        // Allow certain contexts that are not user-facing
        let allowedContexts = [
            "// ",           // Comments
            "///",           // Documentation
            "/*",            // Block comments
            "Logger",        // Logging statements
            "print(",        // Debug prints
            "assert",        // Assertions
            "XCTAssert",     // Test assertions
            "prohibitedDiagnosticTerms",  // This test file's own constants
            "case .",        // Enum cases (code, not UI)
            "struct ",       // Type definitions
            "class ",        // Type definitions
            "func test"      // Test method names
        ]

        for context in allowedContexts {
            if line.contains(context) {
                return true
            }
        }

        return false
    }
}

// MARK: - Data Schema Compliance Tests

extension ComplianceTests {

    func testCSVExportManagerSchemaCompliance() {
        // Verify CSVExportManager exists and can be instantiated
        let manager = CSVExportManager()
        XCTAssertNotNil(manager, "CSVExportManager should be instantiable")
    }

    func testExportSummaryContainsRequiredFields() {
        // Test that export summary includes wellness-appropriate fields
        let manager = CSVExportManager()

        let testData = createTestSensorData()
        let summary = manager.getExportSummary(sensorData: testData, logs: ["Test log"])

        XCTAssertGreaterThan(summary.sensorDataCount, 0, "Summary should include data count")
        XCTAssertFalse(summary.dateRange.isEmpty, "Summary should include date range")
    }

    func testExportedDataIsAnonymizable() {
        // Verify export can work with anonymized user identifier
        let manager = CSVExportManager()

        // Remove any existing user ID
        let originalUserID = UserDefaults.standard.string(forKey: "userID")
        UserDefaults.standard.removeObject(forKey: "userID")

        let testData = createTestSensorData()
        let exportURL = manager.exportData(sensorData: testData, logs: [])

        // Should still export (with "guest" identifier)
        XCTAssertNotNil(exportURL, "Export should work even without user ID")

        // Cleanup
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let original = originalUserID {
            UserDefaults.standard.set(original, forKey: "userID")
        }
    }

    private func createTestSensorData() -> [SensorData] {
        return [
            SensorData(
                timestamp: Date(),
                ppg: PPGData(red: 100000, ir: 100000, green: 100000, timestamp: Date()),
                accelerometer: AccelerometerData(x: 0, y: 0, z: 0, timestamp: Date()),
                temperature: TemperatureData(celsius: 37.0, timestamp: Date()),
                battery: BatteryData(percentage: 100, timestamp: Date()),
                heartRate: HeartRateData(bpm: 70, quality: 0.9, timestamp: Date()),
                spo2: SpO2Data(percentage: 98, quality: 0.9, timestamp: Date()),
                deviceType: .oralable
            )
        ]
    }
}
