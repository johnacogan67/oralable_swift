//
//  SettingsViewModelTests.swift
//  OralableAppTests
//
//  Created: November 11, 2025
//  Testing SettingsViewModel functionality
//  Updated: November 29, 2025 - Removed OralableBLE dependency
//

import XCTest
import Combine
@testable import MAMDiagnostics

@MainActor
class SettingsViewModelTests: XCTestCase {

    var viewModel: SettingsViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = SettingsViewModel(sensorDataProcessor: SensorDataProcessor.shared)
        cancellables = []

        // Clear UserDefaults for clean state
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "notificationsEnabled")
        userDefaults.removeObject(forKey: "dataRetentionDays")
        userDefaults.removeObject(forKey: "autoConnectEnabled")
    }

    override func tearDown() async throws {
        viewModel = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertTrue(viewModel.notificationsEnabled)
        XCTAssertEqual(viewModel.dataRetentionDays, 30)
        XCTAssertTrue(viewModel.autoConnectEnabled)
        XCTAssertFalse(viewModel.showDebugInfo)
        XCTAssertTrue(viewModel.connectionAlerts)
        XCTAssertTrue(viewModel.batteryAlerts)
        XCTAssertEqual(viewModel.lowBatteryThreshold, 20)
        XCTAssertTrue(viewModel.useMetricUnits)
        XCTAssertTrue(viewModel.show24HourTime)
        XCTAssertEqual(viewModel.chartRefreshRate, .realTime)
        XCTAssertFalse(viewModel.shareAnalytics)
        XCTAssertTrue(viewModel.localStorageOnly)
    }

    // MARK: - Settings Persistence Tests

    func testNotificationsEnabledPersistence() {
        // When
        viewModel.notificationsEnabled = false

        // Wait for Combine to process
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then
        let saved = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        XCTAssertFalse(saved)
    }

    func testDataRetentionDaysPersistence() {
        // Given
        let newRetention = 60

        // When
        viewModel.dataRetentionDays = newRetention

        // Wait for Combine to process
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Then
        let saved = UserDefaults.standard.integer(forKey: "dataRetentionDays")
        XCTAssertEqual(saved, newRetention)
    }

    // MARK: - Version Information Tests

    func testVersionInformation() {
        XCTAssertFalse(viewModel.appVersion.isEmpty)
        XCTAssertFalse(viewModel.buildNumber.isEmpty)
        XCTAssertTrue(viewModel.versionText.contains("Version"))
        XCTAssertTrue(viewModel.versionText.contains(viewModel.appVersion))
    }

    // MARK: - Settings Validation Tests

    func testSettingsValidation() {
        // Valid settings
        viewModel.dataRetentionDays = 30
        viewModel.lowBatteryThreshold = 20
        XCTAssertTrue(viewModel.validateSettings())

        // Invalid data retention (too low)
        viewModel.dataRetentionDays = 0
        XCTAssertFalse(viewModel.validateSettings())

        // Invalid data retention (too high)
        viewModel.dataRetentionDays = 400
        XCTAssertFalse(viewModel.validateSettings())

        // Valid range restored
        viewModel.dataRetentionDays = 30

        // Invalid battery threshold (too low)
        viewModel.lowBatteryThreshold = 0
        XCTAssertFalse(viewModel.validateSettings())

        // Invalid battery threshold (too high)
        viewModel.lowBatteryThreshold = 150
        XCTAssertFalse(viewModel.validateSettings())
    }

    // MARK: - Reset to Defaults Tests

    func testResetToDefaults() {
        // Given - change some settings
        viewModel.notificationsEnabled = false
        viewModel.dataRetentionDays = 60
        viewModel.autoConnectEnabled = false
        viewModel.useMetricUnits = false

        // When
        viewModel.resetToDefaults()

        // Then
        XCTAssertTrue(viewModel.notificationsEnabled)
        XCTAssertEqual(viewModel.dataRetentionDays, 30)
        XCTAssertTrue(viewModel.autoConnectEnabled)
        XCTAssertTrue(viewModel.useMetricUnits)
    }

    // MARK: - Export/Import Settings Tests

    func testExportSettings() {
        // Given
        viewModel.dataRetentionDays = 90

        // When
        let exported = viewModel.exportSettings()

        // Then
        XCTAssertEqual(exported["dataRetentionDays"] as? Int, 90)
    }

    func testImportSettings() {
        // Given
        let settings: [String: Any] = [
            "dataRetentionDays": 120,
            "notificationsEnabled": false,
            "useMetricUnits": false
        ]

        // When
        viewModel.importSettings(from: settings)

        // Then
        XCTAssertEqual(viewModel.dataRetentionDays, 120)
        XCTAssertFalse(viewModel.notificationsEnabled)
        XCTAssertFalse(viewModel.useMetricUnits)
    }

    // MARK: - Chart Refresh Rate Tests

    func testChartRefreshRateOptions() {
        XCTAssertEqual(ChartRefreshRate.allCases.count, 3)
        XCTAssertTrue(ChartRefreshRate.allCases.contains(.realTime))
        XCTAssertTrue(ChartRefreshRate.allCases.contains(.everySecond))
        XCTAssertTrue(ChartRefreshRate.allCases.contains(.everyFiveSeconds))
    }

    // MARK: - Notification Settings Tests

    func testNotificationSettingsInteraction() {
        // Given
        viewModel.notificationsEnabled = true

        // When enabled, can set alerts
        viewModel.connectionAlerts = true
        viewModel.batteryAlerts = true
        viewModel.lowBatteryThreshold = 25

        // Then
        XCTAssertTrue(viewModel.connectionAlerts)
        XCTAssertTrue(viewModel.batteryAlerts)
        XCTAssertEqual(viewModel.lowBatteryThreshold, 25)

        // When disabled
        viewModel.notificationsEnabled = false

        // Alerts still retain their values (up to view to disable UI)
        XCTAssertTrue(viewModel.connectionAlerts)
        XCTAssertTrue(viewModel.batteryAlerts)
    }

    // MARK: - Privacy Settings Tests

    func testPrivacySettings() {
        // Default state
        XCTAssertFalse(viewModel.shareAnalytics)
        XCTAssertTrue(viewModel.localStorageOnly)

        // Toggle privacy settings
        viewModel.shareAnalytics = true
        viewModel.localStorageOnly = false

        XCTAssertTrue(viewModel.shareAnalytics)
        XCTAssertFalse(viewModel.localStorageOnly)
    }

    // MARK: - Display Settings Tests

    func testDisplaySettings() {
        // Test metric units toggle
        viewModel.useMetricUnits = false
        XCTAssertFalse(viewModel.useMetricUnits)

        // Test 24-hour time toggle
        viewModel.show24HourTime = false
        XCTAssertFalse(viewModel.show24HourTime)

        // Test chart refresh rate
        viewModel.chartRefreshRate = .everyFiveSeconds
        XCTAssertEqual(viewModel.chartRefreshRate, .everyFiveSeconds)
    }

    // MARK: - UI State Tests

    func testUIState() {
        // Test confirmation dialogs state
        XCTAssertFalse(viewModel.showResetConfirmation)
        XCTAssertFalse(viewModel.showClearDataConfirmation)

        viewModel.showResetConfirmation = true
        XCTAssertTrue(viewModel.showResetConfirmation)

        viewModel.showClearDataConfirmation = true
        XCTAssertTrue(viewModel.showClearDataConfirmation)
    }
}
