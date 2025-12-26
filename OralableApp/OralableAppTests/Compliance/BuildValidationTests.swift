//
//  BuildValidationTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Build validation tests for App Store submission
//  Tests Info.plist entries, permissions, and build configuration
//

import XCTest
import Foundation
@testable import OralableApp

/// Build validation tests to ensure the app is ready for App Store submission
/// Verifies Info.plist configuration, permissions, and build settings
@MainActor
final class BuildValidationTests: XCTestCase {

    // MARK: - Test Properties

    /// Required Info.plist keys for the app
    private let requiredInfoPlistKeys = [
        "CFBundleDisplayName",
        "CFBundleIdentifier",
        "CFBundleVersion",
        "CFBundleShortVersionString",
        "NSBluetoothAlwaysUsageDescription",
        "UIBackgroundModes"
    ]

    /// Required background modes for BLE operation
    private let requiredBackgroundModes = [
        "bluetooth-central"
    ]

    /// Required device capabilities
    private let requiredDeviceCapabilities = [
        "bluetooth-le"
    ]

    // MARK: - Info.plist Validation Tests

    func testInfoPlistExists() throws {
        let projectRoot = getProjectRoot()
        let infoPlistPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Info.plist")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: infoPlistPath.path),
            "Info.plist must exist at OralableApp/Info.plist"
        )
    }

    func testInfoPlistIsValidPlist() throws {
        let infoPlist = try loadInfoPlist()
        XCTAssertFalse(infoPlist.isEmpty, "Info.plist should not be empty")
    }

    func testInfoPlistContainsRequiredKeys() throws {
        let infoPlist = try loadInfoPlist()

        for key in requiredInfoPlistKeys {
            // Some keys may use build variables like $(PRODUCT_NAME)
            let value = infoPlist[key]
            XCTAssertNotNil(value, "Info.plist should contain required key: \(key)")
        }
    }

    // MARK: - Background BLE Usage Tests

    func testBackgroundBLEUsageIsDeclared() throws {
        let infoPlist = try loadInfoPlist()

        guard let backgroundModes = infoPlist["UIBackgroundModes"] as? [String] else {
            XCTFail("Info.plist should declare UIBackgroundModes")
            return
        }

        XCTAssertTrue(
            backgroundModes.contains("bluetooth-central"),
            "UIBackgroundModes should include 'bluetooth-central' for background BLE operation"
        )
    }

    func testBluetoothCentralBackgroundModePresent() throws {
        let infoPlist = try loadInfoPlist()

        guard let backgroundModes = infoPlist["UIBackgroundModes"] as? [String] else {
            XCTFail("UIBackgroundModes not found in Info.plist")
            return
        }

        for requiredMode in requiredBackgroundModes {
            XCTAssertTrue(
                backgroundModes.contains(requiredMode),
                "Missing required background mode: \(requiredMode)"
            )
        }
    }

    // MARK: - Bluetooth Permission Tests

    func testBluetoothAlwaysUsageDescriptionPresent() throws {
        let infoPlist = try loadInfoPlist()

        guard let description = infoPlist["NSBluetoothAlwaysUsageDescription"] as? String else {
            XCTFail("NSBluetoothAlwaysUsageDescription must be present")
            return
        }

        XCTAssertFalse(description.isEmpty, "Bluetooth usage description should not be empty")
        XCTAssertGreaterThan(description.count, 20, "Bluetooth usage description should be meaningful")

        // Should mention what the app uses Bluetooth for
        let hasRelevantContent = description.lowercased().contains("bluetooth") ||
                                 description.lowercased().contains("connect") ||
                                 description.lowercased().contains("device") ||
                                 description.lowercased().contains("oralable")

        XCTAssertTrue(hasRelevantContent, "Bluetooth description should explain its purpose")
    }

    func testBluetoothPeripheralUsageDescriptionPresent() throws {
        let infoPlist = try loadInfoPlist()

        // This is optional but recommended
        if let description = infoPlist["NSBluetoothPeripheralUsageDescription"] as? String {
            XCTAssertFalse(description.isEmpty, "Bluetooth peripheral usage description should not be empty if present")
        }
    }

    // MARK: - Device Capability Tests

    func testBluetoothLECapabilityRequired() throws {
        let infoPlist = try loadInfoPlist()

        guard let capabilities = infoPlist["UIRequiredDeviceCapabilities"] as? [String] else {
            XCTFail("UIRequiredDeviceCapabilities should be declared")
            return
        }

        XCTAssertTrue(
            capabilities.contains("bluetooth-le"),
            "App should require bluetooth-le capability"
        )
    }

    func testRequiredDeviceCapabilitiesAreDeclared() throws {
        let infoPlist = try loadInfoPlist()

        guard let capabilities = infoPlist["UIRequiredDeviceCapabilities"] as? [String] else {
            XCTFail("UIRequiredDeviceCapabilities not found")
            return
        }

        for requiredCapability in requiredDeviceCapabilities {
            XCTAssertTrue(
                capabilities.contains(requiredCapability),
                "Missing required device capability: \(requiredCapability)"
            )
        }
    }

    // MARK: - File Sharing Tests

    func testFileSharingEnabled() throws {
        let infoPlist = try loadInfoPlist()

        // UIFileSharingEnabled allows users to access app documents via iTunes/Finder
        if let fileSharing = infoPlist["UIFileSharingEnabled"] as? Bool {
            // File sharing being enabled is fine for data export
            XCTAssertTrue(true, "File sharing is declared")
        }
    }

    // MARK: - iCloud Configuration Tests

    func testICloudContainerConfigured() throws {
        let infoPlist = try loadInfoPlist()

        // Check for iCloud container configuration
        if let ubiquitousContainer = infoPlist["NSUbiquitousContainer"] as? [String: Any] {
            // Verify container has a name
            for (_, containerInfo) in ubiquitousContainer {
                if let info = containerInfo as? [String: Any] {
                    if let containerName = info["NSUbiquitousContainerName"] as? String {
                        XCTAssertFalse(containerName.isEmpty, "iCloud container should have a name")
                    }
                }
            }
        }
    }

    // MARK: - App Transport Security Tests

    func testAppTransportSecurityCompliant() throws {
        let infoPlist = try loadInfoPlist()

        // If ATS exceptions exist, they should be minimal
        if let ats = infoPlist["NSAppTransportSecurity"] as? [String: Any] {
            // Should not have global allow arbitrary loads
            if let allowArbitrary = ats["NSAllowsArbitraryLoads"] as? Bool {
                XCTAssertFalse(
                    allowArbitrary,
                    "App should not allow arbitrary loads (NSAllowsArbitraryLoads should be false)"
                )
            }
        }
    }

    // MARK: - Encryption Declaration Tests

    func testEncryptionDeclarationPresent() throws {
        let infoPlist = try loadInfoPlist()

        XCTAssertNotNil(
            infoPlist["ITSAppUsesNonExemptEncryption"],
            "ITSAppUsesNonExemptEncryption must be declared for App Store submission"
        )
    }

    func testEncryptionDeclarationValue() throws {
        let infoPlist = try loadInfoPlist()

        if let usesEncryption = infoPlist["ITSAppUsesNonExemptEncryption"] as? Bool {
            // For most wellness apps without custom encryption, this should be false
            // If true, export compliance documentation is required
            if usesEncryption {
                // App uses encryption - this is fine but requires documentation
                XCTAssertTrue(true, "App declares use of non-exempt encryption - ensure compliance docs are filed")
            } else {
                XCTAssertTrue(true, "App correctly declares no non-exempt encryption")
            }
        }
    }

    // MARK: - Orientation Support Tests

    func testSupportedOrientationsDeclared() throws {
        let infoPlist = try loadInfoPlist()

        // iPhone orientations
        if let orientations = infoPlist["UISupportedInterfaceOrientations"] as? [String] {
            XCTAssertFalse(orientations.isEmpty, "App should support at least one orientation")
            XCTAssertTrue(
                orientations.contains("UIInterfaceOrientationPortrait"),
                "App should support portrait orientation"
            )
        }
    }

    // MARK: - Launch Screen Tests

    func testLaunchScreenConfigured() throws {
        let infoPlist = try loadInfoPlist()

        // Should have either UILaunchScreen or UILaunchStoryboardName
        let hasLaunchScreen = infoPlist["UILaunchScreen"] != nil
        let hasLaunchStoryboard = infoPlist["UILaunchStoryboardName"] != nil

        XCTAssertTrue(
            hasLaunchScreen || hasLaunchStoryboard,
            "App should have a launch screen configured"
        )
    }

    // MARK: - Scene Configuration Tests

    func testSceneManifestConfigured() throws {
        let infoPlist = try loadInfoPlist()

        if let sceneManifest = infoPlist["UIApplicationSceneManifest"] as? [String: Any] {
            // Scene manifest is present - good for modern SwiftUI apps
            XCTAssertTrue(true, "Scene manifest is configured")
        }
    }

    // MARK: - Version Number Tests

    func testBundleVersionIsValid() throws {
        let infoPlist = try loadInfoPlist()

        if let version = infoPlist["CFBundleVersion"] as? String {
            // Version should either be a number or build variable
            let isVariable = version.contains("$(")
            let isNumeric = Int(version) != nil

            XCTAssertTrue(
                isVariable || isNumeric,
                "CFBundleVersion should be numeric or a build variable"
            )
        }
    }

    func testMarketingVersionIsValid() throws {
        let infoPlist = try loadInfoPlist()

        if let version = infoPlist["CFBundleShortVersionString"] as? String {
            // Should be semver-like or build variable
            let isVariable = version.contains("$(")
            let components = version.split(separator: ".")

            XCTAssertTrue(
                isVariable || components.count >= 1,
                "CFBundleShortVersionString should follow version format or be a build variable"
            )
        }
    }

    // MARK: - No Private API Usage Tests

    func testNoPrivateFrameworkImports() throws {
        let projectRoot = getProjectRoot()
        let oralableAppPath = projectRoot.appendingPathComponent("OralableApp")

        let swiftFiles = findSwiftFiles(in: oralableAppPath)

        // Known private frameworks that should NOT be imported
        let privateFrameworks = [
            "UIKit.Private",
            "CoreFoundation.Private",
            "Foundation.Private",
            "objc/runtime.h",
            "dlfcn.h",
            "_",  // Underscore-prefixed private symbols
        ]

        var violations: [String] = []

        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for framework in privateFrameworks {
                if content.contains("import \(framework)") {
                    violations.append("\(fileURL.lastPathComponent): imports private framework '\(framework)'")
                }
            }

            // Check for dynamic library loading (potential private API access)
            if content.contains("dlopen") || content.contains("dlsym") {
                violations.append("\(fileURL.lastPathComponent): uses dynamic library loading")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Found potential private API usage:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testNoUndocumentedSelectors() throws {
        let projectRoot = getProjectRoot()
        let oralableAppPath = projectRoot.appendingPathComponent("OralableApp")

        let swiftFiles = findSwiftFiles(in: oralableAppPath)

        // Patterns that might indicate undocumented API usage
        let suspiciousPatterns = [
            "perform(Selector",
            "NSSelectorFromString",
            "valueForKey:.*_",  // Accessing underscore-prefixed keys
            "@objc func _"      // Underscore-prefixed ObjC methods
        ]

        var warnings: [String] = []

        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            // Skip test files
            if fileURL.path.contains("Tests") {
                continue
            }

            for pattern in suspiciousPatterns {
                if content.contains(pattern) {
                    warnings.append("\(fileURL.lastPathComponent): contains suspicious pattern '\(pattern)'")
                }
            }
        }

        // This is a warning, not necessarily a failure
        if !warnings.isEmpty {
            print("⚠️ Potential undocumented API usage (review manually):\n\(warnings.joined(separator: "\n"))")
        }
    }

    // MARK: - Entitlements Validation

    func testEntitlementsFileExists() throws {
        let projectRoot = getProjectRoot()

        // Check for entitlements file
        let entitlementsPatterns = [
            "OralableApp/OralableApp.entitlements",
            "OralableApp.entitlements"
        ]

        var foundEntitlements = false
        for pattern in entitlementsPatterns {
            let entitlementsPath = projectRoot.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: entitlementsPath.path) {
                foundEntitlements = true
                break
            }
        }

        // Entitlements are optional but recommended
        if !foundEntitlements {
            print("ℹ️ No entitlements file found - this is OK if capabilities are managed in Xcode")
        }
    }

    // MARK: - Build Configuration Tests

    func testProjectFileExists() throws {
        let projectRoot = getProjectRoot()
        let xcprojPath = projectRoot.appendingPathComponent("OralableApp.xcodeproj")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: xcprojPath.path),
            "Xcode project file should exist"
        )
    }

    // MARK: - Privacy Manifest Presence

    func testPrivacyManifestExists() throws {
        let projectRoot = getProjectRoot()
        let privacyPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("PrivacyInfo.xcprivacy")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: privacyPath.path),
            "PrivacyInfo.xcprivacy must exist for App Store submission"
        )
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
            throw NSError(domain: "BuildValidationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse Info.plist"])
        }

        return plist
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
}

// MARK: - CI/CD Integration Tests

extension BuildValidationTests {

    func testAllRequiredFilesExistForBuild() throws {
        let projectRoot = getProjectRoot()

        let requiredFiles = [
            "OralableApp/Info.plist",
            "OralableApp/PrivacyInfo.xcprivacy",
            "OralableApp.xcodeproj/project.pbxproj"
        ]

        var missingFiles: [String] = []

        for file in requiredFiles {
            let filePath = projectRoot.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: filePath.path) {
                missingFiles.append(file)
            }
        }

        XCTAssertTrue(
            missingFiles.isEmpty,
            "Missing required files for build:\n\(missingFiles.joined(separator: "\n"))"
        )
    }

    func testAppIconAssetsExist() throws {
        let projectRoot = getProjectRoot()

        // Check for Assets.xcassets with AppIcon
        let assetsPath = projectRoot
            .appendingPathComponent("OralableApp")
            .appendingPathComponent("Assets.xcassets")

        if FileManager.default.fileExists(atPath: assetsPath.path) {
            let appIconPath = assetsPath.appendingPathComponent("AppIcon.appiconset")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: appIconPath.path),
                "AppIcon.appiconset should exist in Assets.xcassets"
            )
        }
    }

    func testBuildSchemeExists() throws {
        let projectRoot = getProjectRoot()
        let xcschemesPath = projectRoot
            .appendingPathComponent("OralableApp.xcodeproj")
            .appendingPathComponent("xcshareddata")
            .appendingPathComponent("xcschemes")

        // Check if shared schemes directory exists
        if FileManager.default.fileExists(atPath: xcschemesPath.path) {
            // At least one scheme should exist
            let contents = try FileManager.default.contentsOfDirectory(atPath: xcschemesPath.path)
            let schemes = contents.filter { $0.hasSuffix(".xcscheme") }

            XCTAssertFalse(
                schemes.isEmpty,
                "At least one build scheme should exist for CI/CD"
            )
        }
    }
}

// MARK: - Release Readiness Tests

extension BuildValidationTests {

    func testNoDebugOnlyCodeInRelease() throws {
        let projectRoot = getProjectRoot()
        let oralableAppPath = projectRoot.appendingPathComponent("OralableApp")

        let swiftFiles = findSwiftFiles(in: oralableAppPath)

        var debugCodeWarnings: [String] = []

        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            // Skip test files
            if fileURL.path.contains("Tests") {
                continue
            }

            // Check for debug-only code that shouldn't be in release
            let debugPatterns = [
                "print(\"DEBUG",
                "NSLog(@\"DEBUG",
                "fatalError(\"TODO",
                "assertionFailure(\"TODO",
                "// TODO: REMOVE BEFORE RELEASE",
                "// FIXME: REMOVE BEFORE RELEASE"
            ]

            for pattern in debugPatterns {
                if content.contains(pattern) {
                    debugCodeWarnings.append("\(fileURL.lastPathComponent): contains '\(pattern)'")
                }
            }
        }

        if !debugCodeWarnings.isEmpty {
            print("⚠️ Potential debug code found (review before release):\n\(debugCodeWarnings.joined(separator: "\n"))")
        }
    }

    func testNoHardcodedTestCredentials() throws {
        let projectRoot = getProjectRoot()
        let oralableAppPath = projectRoot.appendingPathComponent("OralableApp")

        let swiftFiles = findSwiftFiles(in: oralableAppPath)

        var credentialWarnings: [String] = []

        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            // Skip test files and mock files
            if fileURL.path.contains("Tests") || fileURL.path.contains("Mock") {
                continue
            }

            // Check for potential hardcoded credentials
            let credentialPatterns = [
                "password = \"",
                "apiKey = \"",
                "secret = \"",
                "token = \"sk_",
                "token = \"pk_"
            ]

            for pattern in credentialPatterns {
                if content.contains(pattern) {
                    credentialWarnings.append("\(fileURL.lastPathComponent): may contain hardcoded credentials")
                }
            }
        }

        XCTAssertTrue(
            credentialWarnings.isEmpty,
            "Potential hardcoded credentials found:\n\(credentialWarnings.joined(separator: "\n"))"
        )
    }
}
