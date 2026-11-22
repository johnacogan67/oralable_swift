//
//  DashboardIntegrationTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Integration tests for dashboard data binding and reactive updates
//  Tests ViewModel publishing, concurrent updates, and error state handling
//

import XCTest
import Combine
@testable import MAMDiagnostics

@MainActor
final class DashboardIntegrationTests: XCTestCase {

    // MARK: - Properties

    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - AutomaticRecordingSession Integration Tests

    /// Isolated session: no CloudKit sync; caller must endSession in cleanup.
    private func makeIsolatedAutomaticRecordingSession() -> AutomaticRecordingSession {
        let session = AutomaticRecordingSession()
        session.syncOnDisconnect = false
        return session
    }

    func testAutomaticRecordingSessionPublishesUpdates() async {
        // Given
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        let expectation = XCTestExpectation(description: "Session became active")

        session.$isSessionActive
            .dropFirst()
            .sink { isActive in
                if isActive {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        session.onDeviceConnected()

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(session.isSessionActive && !session.isSessionPaused)
    }

    func testAutomaticRecordingSessionDurationUpdatesOverTime() async {
        // Given — sessionDuration is computed, not @Published; poll after a known start
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        // When
        session.onDeviceConnected()
        try? await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

        // Then
        XCTAssertGreaterThan(session.sessionDuration, 0)
        XCTAssertFalse(session.formattedDuration.isEmpty)
    }

    func testAutomaticRecordingSessionEndResetsState() async {
        // Given
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        session.onDeviceConnected()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let stopExpectation = XCTestExpectation(description: "Session ended")

        session.$isSessionActive
            .sink { isActive in
                if !isActive {
                    stopExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When — endSession (not disconnect/pause) fully resets
        session.endSession()

        // Then
        await fulfillment(of: [stopExpectation], timeout: 2.0)
        XCTAssertFalse(session.isSessionActive)
        XCTAssertFalse(session.isSessionPaused)
        XCTAssertNil(session.sessionStartTime)
    }

    func testAutomaticRecordingSessionConnectThenEnd() async {
        // Given
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        // When - connect starts recording
        session.onDeviceConnected()

        // Then
        XCTAssertTrue(session.isSessionActive && !session.isSessionPaused, "Should be recording after connect")

        // When - endSession stops recording (replaces legacy toggle off)
        session.endSession()

        // Then
        XCTAssertFalse(session.isSessionActive, "Should not be active after endSession")
        XCTAssertFalse(session.isSessionPaused, "Should not be paused after endSession")
    }

    // MARK: - ThresholdSettings Integration Tests

    func testThresholdSettingsPublishChanges() async {
        // Given
        let settings = ThresholdSettings.shared
        let originalThreshold = settings.movementThreshold

        let expectation = XCTestExpectation(description: "Threshold changed")

        settings.$movementThreshold
            .dropFirst()
            .sink { newThreshold in
                if newThreshold != originalThreshold {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        let newThreshold = originalThreshold + 100
        settings.movementThreshold = newThreshold

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(settings.movementThreshold, newThreshold)

        // Cleanup - restore original
        settings.movementThreshold = originalThreshold
    }

    func testThresholdSettingsPersistence() async {
        // Given
        let settings = ThresholdSettings.shared
        let originalThreshold = settings.movementThreshold

        // When
        let testThreshold = 2500.0
        settings.movementThreshold = testThreshold

        // Then
        XCTAssertEqual(settings.movementThreshold, testThreshold)

        // Cleanup
        settings.movementThreshold = originalThreshold
    }

    // MARK: - FeatureFlags Integration Tests

    func testFeatureFlagsPublishChanges() async {
        // Given
        let flags = FeatureFlags.shared
        let originalState = flags.demoModeEnabled

        let expectation = XCTestExpectation(description: "Feature flag changed")

        flags.$demoModeEnabled
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        flags.demoModeEnabled = !originalState

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(flags.demoModeEnabled, !originalState)

        // Cleanup - restore original
        flags.demoModeEnabled = originalState
    }

    func testFeatureFlagsShowCards() {
        // Given
        let flags = FeatureFlags.shared

        // Test various card visibility flags exist and are accessible
        _ = flags.showEMGCard
        _ = flags.showMovementCard
        _ = flags.showHeartRateCard
        _ = flags.showSpO2Card
        _ = flags.showTemperatureCard
        _ = flags.showBatteryCard

        // Then - should not crash when accessing flags
        XCTAssertTrue(true, "Feature flags should be accessible")
    }

    // MARK: - Concurrent Updates Tests

    func testMultiplePublishersCanUpdateConcurrently() async {
        // Given
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        let settings = ThresholdSettings.shared
        let flags = FeatureFlags.shared

        // Store original values
        let originalThreshold = settings.movementThreshold
        let originalDemo = flags.demoModeEnabled

        var sessionUpdated = false
        var settingsUpdated = false
        var flagsUpdated = false

        let allUpdatedExpectation = XCTestExpectation(description: "All updated")

        session.$isSessionActive
            .dropFirst()
            .sink { _ in
                sessionUpdated = true
                if sessionUpdated && settingsUpdated && flagsUpdated {
                    allUpdatedExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        settings.$movementThreshold
            .dropFirst()
            .sink { _ in
                settingsUpdated = true
                if sessionUpdated && settingsUpdated && flagsUpdated {
                    allUpdatedExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        flags.$demoModeEnabled
            .dropFirst()
            .sink { _ in
                flagsUpdated = true
                if sessionUpdated && settingsUpdated && flagsUpdated {
                    allUpdatedExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - update all concurrently
        session.onDeviceConnected()
        settings.movementThreshold = originalThreshold + 50
        flags.demoModeEnabled = !originalDemo

        // Then
        await fulfillment(of: [allUpdatedExpectation], timeout: 3.0)

        XCTAssertTrue(sessionUpdated, "Session should be updated")
        XCTAssertTrue(settingsUpdated, "Settings should be updated")
        XCTAssertTrue(flagsUpdated, "Flags should be updated")

        // Cleanup - restore original values
        settings.movementThreshold = originalThreshold
        flags.demoModeEnabled = originalDemo
    }

    // MARK: - Error State Tests

    func testDisconnectedStateReflectedInDeviceManager() async {
        // Given - new device manager with no connections
        let deviceManager = DeviceManager()

        // Then - should show disconnected state
        XCTAssertTrue(deviceManager.connectedDevices.isEmpty, "Should have no connected devices initially")
    }

    func testDeviceManagerInitialState() async {
        // Given
        let deviceManager = DeviceManager()

        // Then - verify initial state
        XCTAssertFalse(deviceManager.isScanning, "Should not be scanning initially")
        XCTAssertTrue(deviceManager.connectedDevices.isEmpty, "Should have no connected devices")
    }

    // MARK: - Performance Tests

    func testPublisherPerformanceUnderLoad() async {
        // Given
        let settings = ThresholdSettings.shared
        let originalThreshold = settings.movementThreshold
        var updateCount = 0
        let targetUpdates = 50

        let expectation = XCTestExpectation(description: "Updates processed")

        settings.$movementThreshold
            .dropFirst()
            .sink { _ in
                updateCount += 1
                if updateCount >= targetUpdates {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - rapid updates
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<targetUpdates {
            settings.movementThreshold = originalThreshold + Double(i)
        }

        // Then
        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 2.0, "Should process updates quickly")

        // Cleanup
        settings.movementThreshold = originalThreshold
    }

    // MARK: - Session Duration Format Tests

    func testAutomaticRecordingSessionDurationFormatting() async {
        // Given
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        // When
        session.onDeviceConnected()

        // Wait for some duration then read computed properties
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Then
        let duration = session.sessionDuration
        XCTAssertGreaterThan(duration, 0, "Duration should be greater than 0")

        let formatted = session.formattedDuration
        XCTAssertFalse(formatted.isEmpty, "formattedDuration should not be empty")
        XCTAssertTrue(formatted.contains(":"), "formattedDuration should include a colon separator")
    }

    // MARK: - State Reset Tests

    func testAutomaticRecordingSessionResetsCleanly() async {
        // Given
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        // Start a session
        session.onDeviceConnected()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // When
        session.endSession()

        // Then
        XCTAssertFalse(session.isSessionActive, "Should not be active after endSession")
        XCTAssertFalse(session.isSessionPaused, "Should not be paused after endSession")
        XCTAssertNil(session.sessionStartTime, "Session start time should be nil")
    }

    // MARK: - SensorDataProcessor Integration Tests

    func testSensorDataProcessorExists() {
        // Given
        let processor = SensorDataProcessor.shared

        // Then - processor should exist and be accessible
        XCTAssertNotNil(processor, "SensorDataProcessor.shared should exist")
    }

    // MARK: - HistoricalDataManager Integration Tests

    func testHistoricalDataManagerCanBeCreated() {
        // Given
        let processor = SensorDataProcessor.shared

        // When
        let manager = HistoricalDataManager(sensorDataProcessor: processor)

        // Then
        XCTAssertNotNil(manager, "HistoricalDataManager should be created successfully")
    }

    // MARK: - Demo Mode Integration Tests

    func testDemoModeCanBeToggled() async {
        // Given
        let flags = FeatureFlags.shared
        let originalState = flags.demoModeEnabled

        // When
        flags.demoModeEnabled = true
        XCTAssertTrue(flags.demoModeEnabled, "Demo mode should be enabled")

        flags.demoModeEnabled = false
        XCTAssertFalse(flags.demoModeEnabled, "Demo mode should be disabled")

        // Cleanup
        flags.demoModeEnabled = originalState
    }

    func testDemoDataProviderAccessible() {
        // Given
        let provider = DemoDataProvider.shared

        // Then
        XCTAssertNotNil(provider, "DemoDataProvider.shared should exist")
        XCTAssertFalse(provider.deviceName.isEmpty, "Demo device should have a name")
    }
}
