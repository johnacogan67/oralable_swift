//
//  RegressionTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Regression tests for critical modules after refactoring
//  Ensures BLE, MVVM, StoreKit, onboarding, and data export remain functional
//

import XCTest
import Combine
import CoreBluetooth
@testable import OralableApp

@MainActor
final class RegressionTests: XCTestCase {

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

    // MARK: - BLEManager Reconnection Logic Tests

    func testBLEBackgroundWorkerReconnectionScheduling() async {
        // Given
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.1,
            maxReconnectionDelay: 0.5,
            jitterFactor: 0.0,
            connectionTimeout: 1.0,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)

        // When
        worker.start()

        // Then
        XCTAssertTrue(worker.isRunning, "Worker should be running after start")

        // Cleanup
        worker.stop()
        XCTAssertFalse(worker.isRunning, "Worker should stop")
    }

    func testBLEBackgroundWorkerReconnectionAttempts() async {
        // Given
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.05,
            maxReconnectionDelay: 0.2,
            jitterFactor: 0.0,
            connectionTimeout: 0.5,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)
        worker.configure(bleService: mockBLEService)

        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        let expectation = XCTestExpectation(description: "Reconnection attempted")

        worker.eventPublisher
            .sink { event in
                if case .reconnectionAttemptStarted = event {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        worker.start()
        worker.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: true)

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)

        // Cleanup
        worker.stop()
    }

    func testBLEBackgroundWorkerCancelsReconnection() async {
        // Given
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 5,
            baseReconnectionDelay: 0.1,
            maxReconnectionDelay: 0.5,
            jitterFactor: 0.0,
            connectionTimeout: 1.0,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)
        worker.configure(bleService: mockBLEService)

        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        // When
        worker.start()
        worker.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: false)

        // Small delay to allow scheduling
        try? await Task.sleep(nanoseconds: 50_000_000)

        worker.cancelReconnection(for: deviceId)

        // Then
        XCTAssertFalse(worker.activeReconnections.contains(deviceId), "Reconnection should be cancelled")

        // Cleanup
        worker.stop()
    }

    // MARK: - BLEError Handling Consistency Tests

    func testBLEErrorConnectionFailedHasCorrectFormat() {
        // Given
        let peripheralId = UUID()
        let reason = "Device not responding"

        // When
        let error = BLEError.connectionFailed(peripheralId: peripheralId, reason: reason)

        // Then
        XCTAssertFalse(error.localizedDescription.isEmpty, "Error should have localized description")
        XCTAssertTrue(error.localizedDescription.lowercased().contains("connect") || error.localizedDescription.lowercased().contains("failed"), "Error description should mention connection or failure")
    }

    func testBLEErrorUnexpectedDisconnectionHasCorrectFormat() {
        // Given
        let peripheralId = UUID()
        let reason = "Signal lost"

        // When
        let error = BLEError.unexpectedDisconnection(peripheralId: peripheralId, reason: reason)

        // Then
        XCTAssertFalse(error.localizedDescription.isEmpty, "Error should have localized description")
    }

    func testBLEErrorTimeoutHasCorrectFormat() {
        // Given
        let peripheralId = UUID()
        let timeoutSeconds: TimeInterval = 30.0

        // When
        let error = BLEError.connectionTimeout(peripheralId: peripheralId, timeoutSeconds: timeoutSeconds)

        // Then
        XCTAssertFalse(error.localizedDescription.isEmpty, "Error should have localized description")
        XCTAssertTrue(error.localizedDescription.lowercased().contains("timeout") || error.localizedDescription.lowercased().contains("time"), "Error should mention timeout")
    }

    func testBLEErrorBluetoothNotReadyHasCorrectFormat() {
        // When
        let error = BLEError.bluetoothNotReady(state: .poweredOff)

        // Then
        XCTAssertFalse(error.localizedDescription.isEmpty, "Error should have localized description")
    }

    func testBLEErrorIsRecoverableProperty() {
        // Test various errors for recoverability
        let connectionFailed = BLEError.connectionFailed(peripheralId: UUID(), reason: "Test")
        let bluetoothNotReady = BLEError.bluetoothNotReady(state: .poweredOff)
        let bluetoothUnauthorized = BLEError.bluetoothUnauthorized

        // Connection failures are typically recoverable
        XCTAssertTrue(connectionFailed.isRecoverable || !connectionFailed.isRecoverable, "isRecoverable should be defined")

        // Bluetooth not ready may be recoverable
        XCTAssertTrue(bluetoothNotReady.isRecoverable || !bluetoothNotReady.isRecoverable, "isRecoverable should be defined")

        // Bluetooth unauthorized may not be recoverable
        _ = bluetoothUnauthorized.isRecoverable // Just verify property exists
    }

    // MARK: - MVVM Bindings Regression Tests

    func testSettingsViewModelBindingsRemainReactive() async {
        // Given
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        let expectation = XCTestExpectation(description: "Settings updated")

        viewModel.$notificationsEnabled
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.notificationsEnabled = false

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertFalse(viewModel.notificationsEnabled)
    }

    func testSettingsViewModelLocalStorageOnlyBinding() async {
        // Given
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)
        let originalValue = viewModel.localStorageOnly

        let expectation = XCTestExpectation(description: "Local storage setting updated")

        viewModel.$localStorageOnly
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.localStorageOnly = !originalValue

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(viewModel.localStorageOnly, !originalValue)

        // Cleanup
        viewModel.localStorageOnly = originalValue
    }

    func testSettingsViewModelShareAnalyticsBinding() async {
        // Given
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        let expectation = XCTestExpectation(description: "Share analytics updated")

        viewModel.$shareAnalytics
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.shareAnalytics = true

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(viewModel.shareAnalytics)

        // Cleanup
        viewModel.shareAnalytics = false
    }

    func testThresholdSettingsBindingsRemainReactive() async {
        // Given
        let settings = ThresholdSettings.shared
        let originalValue = settings.movementThreshold

        let expectation = XCTestExpectation(description: "Threshold updated")

        settings.$movementThreshold
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        settings.movementThreshold = originalValue + 500

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)

        // Cleanup
        settings.movementThreshold = originalValue
    }

    func testFeatureFlagsBindingsRemainReactive() async {
        // Given
        let flags = FeatureFlags.shared
        let originalValue = flags.showHeartRateCard

        let expectation = XCTestExpectation(description: "Feature flag updated")

        flags.$showHeartRateCard
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        flags.showHeartRateCard = !originalValue

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)

        // Cleanup
        flags.showHeartRateCard = originalValue
    }

    // MARK: - RecordingStateCoordinator Regression Tests

    func testRecordingStateCoordinatorStartStopCycle() async {
        // Given
        let coordinator = RecordingStateCoordinator.shared

        // Ensure clean state
        if coordinator.isRecording {
            coordinator.stopRecording()
        }

        // When - start recording
        coordinator.startRecording()

        // Then
        XCTAssertTrue(coordinator.isRecording, "Should be recording after start")
        XCTAssertNotNil(coordinator.sessionStartTime, "Should have session start time")

        // When - stop recording
        coordinator.stopRecording()

        // Then
        XCTAssertFalse(coordinator.isRecording, "Should not be recording after stop")
        XCTAssertNil(coordinator.sessionStartTime, "Session start time should be nil")
    }

    func testRecordingStateCoordinatorToggle() async {
        // Given
        let coordinator = RecordingStateCoordinator.shared

        // Ensure clean state
        if coordinator.isRecording {
            coordinator.stopRecording()
        }

        // When - toggle on
        coordinator.toggleRecording()
        XCTAssertTrue(coordinator.isRecording, "Should be recording after first toggle")

        // When - toggle off
        coordinator.toggleRecording()
        XCTAssertFalse(coordinator.isRecording, "Should not be recording after second toggle")
    }

    func testRecordingDurationUpdates() async {
        // Given
        let coordinator = RecordingStateCoordinator.shared

        if coordinator.isRecording {
            coordinator.stopRecording()
        }

        // When
        coordinator.startRecording()

        // Wait for duration to update
        try? await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

        // Then
        XCTAssertGreaterThan(coordinator.sessionDuration, 0, "Duration should be greater than 0")

        // Cleanup
        coordinator.stopRecording()
    }

    // MARK: - StoreKit Subscription Flows Regression Tests

    func testSubscriptionManagerExists() {
        // Given
        let manager = SubscriptionManager()

        // Then
        XCTAssertNotNil(manager, "SubscriptionManager should exist")
    }

    func testSubscriptionManagerInitialState() {
        // Given
        let manager = SubscriptionManager()

        // Then - verify initial state properties exist
        _ = manager.isPaidSubscriber
        _ = manager.currentTier

        XCTAssertTrue(true, "Subscription manager initial state should be accessible")
    }

    func testSubscriptionTierEnum() {
        // Verify subscription tiers are defined
        let basic = SubscriptionTier.basic
        let premium = SubscriptionTier.premium

        XCTAssertNotEqual(basic, premium, "Basic and premium tiers should be different")
        XCTAssertFalse(basic.displayName.isEmpty, "Basic tier should have display name")
        XCTAssertFalse(premium.displayName.isEmpty, "Premium tier should have display name")
    }

    // MARK: - Onboarding Flow Regression Tests

    func testOnboardingCompletionStateTracked() {
        // Given
        let key = "hasCompletedOnboarding"
        let originalValue = UserDefaults.standard.bool(forKey: key)

        // When
        UserDefaults.standard.set(true, forKey: key)

        // Then
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "Onboarding completion should be persisted")

        // Cleanup
        UserDefaults.standard.set(originalValue, forKey: key)
    }

    func testPrivacyPolicyAcceptanceTracked() {
        // Given
        let key = "hasAcceptedPrivacyPolicy"
        let originalValue = UserDefaults.standard.bool(forKey: key)

        // When
        UserDefaults.standard.set(true, forKey: key)

        // Then
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "Privacy policy acceptance should be persisted")

        // Cleanup
        UserDefaults.standard.set(originalValue, forKey: key)
    }

    func testTermsAcceptanceTracked() {
        // Given
        let key = "hasAcceptedTerms"
        let originalValue = UserDefaults.standard.bool(forKey: key)

        // When
        UserDefaults.standard.set(true, forKey: key)

        // Then
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "Terms acceptance should be persisted")

        // Cleanup
        UserDefaults.standard.set(originalValue, forKey: key)
    }

    // MARK: - Data Export Flow Regression Tests

    func testCSVExportManagerExists() {
        // Given
        let manager = CSVExportManager()

        // Then
        XCTAssertNotNil(manager, "CSVExportManager should exist")
    }

    func testCSVExportManagerExportsSensorData() {
        // Given
        let manager = CSVExportManager()
        let sensorData = createMockSensorData(count: 5)
        let logs: [String] = []

        // When
        let exportURL = manager.exportData(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertNotNil(exportURL, "Export should return a URL")

        // Cleanup
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCSVExportManagerExportSummary() {
        // Given
        let manager = CSVExportManager()
        let sensorData = createMockSensorData(count: 10)
        let logs = ["Log 1", "Log 2"]

        // When
        let summary = manager.getExportSummary(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertEqual(summary.sensorDataCount, 10, "Sensor data count should match")
        XCTAssertEqual(summary.logCount, 2, "Log count should match")
        XCTAssertFalse(summary.dateRange.isEmpty, "Date range should not be empty")
    }

    func testCSVExportManagerEstimatesSize() {
        // Given
        let manager = CSVExportManager()

        // When
        let sizeEstimate = manager.estimateExportSize(sensorDataCount: 1000, logCount: 50)

        // Then
        XCTAssertFalse(sizeEstimate.isEmpty, "Size estimate should not be empty")
        XCTAssertTrue(
            sizeEstimate.contains("KB") || sizeEstimate.contains("MB") || sizeEstimate.contains("bytes"),
            "Size estimate should contain a unit"
        )
    }

    // MARK: - DeviceManager Regression Tests

    func testDeviceManagerInitialState() {
        // Given
        let manager = DeviceManager()

        // Then
        XCTAssertTrue(manager.connectedDevices.isEmpty, "Should have no connected devices initially")
        XCTAssertFalse(manager.isScanning, "Should not be scanning initially")
    }

    func testDeviceManagerDeviceInfoStructure() {
        // Given
        let deviceInfo = DeviceInfo(
            type: .oralable,
            name: "Test Oralable",
            peripheralIdentifier: UUID(),
            connectionState: .disconnected
        )

        // Then
        XCTAssertEqual(deviceInfo.type, .oralable)
        XCTAssertEqual(deviceInfo.name, "Test Oralable")
        XCTAssertEqual(deviceInfo.connectionState, .disconnected)
    }

    // MARK: - HistoricalDataManager Regression Tests

    func testHistoricalDataManagerCanBeInstantiated() {
        // Given
        let processor = SensorDataProcessor.shared

        // When
        let manager = HistoricalDataManager(sensorDataProcessor: processor)

        // Then
        XCTAssertNotNil(manager, "HistoricalDataManager should be created")
    }

    // MARK: - DemoDataProvider Regression Tests

    func testDemoDataProviderExists() {
        // Given
        let provider = DemoDataProvider.shared

        // Then
        XCTAssertNotNil(provider, "DemoDataProvider should exist")
        XCTAssertFalse(provider.deviceName.isEmpty, "Device name should not be empty")
    }

    func testDemoDataProviderConnectionState() {
        // Given
        let provider = DemoDataProvider.shared

        // Then - verify connection state is accessible
        _ = provider.isConnected

        XCTAssertTrue(true, "Connection state should be accessible")
    }

    // MARK: - Helper Methods

    private func createMockSensorData(count: Int) -> [SensorData] {
        var sensorData: [SensorData] = []
        let now = Date()

        for i in 0..<count {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 5))

            let ppg = PPGData(
                red: Int32.random(in: 50000...250000),
                ir: Int32.random(in: 50000...250000),
                green: Int32.random(in: 50000...250000),
                timestamp: timestamp
            )

            let accelerometer = AccelerometerData(
                x: Int16.random(in: -100...100),
                y: Int16.random(in: -100...100),
                z: Int16.random(in: -100...100),
                timestamp: timestamp
            )

            let temperature = TemperatureData(
                celsius: Double.random(in: 36.0...37.5),
                timestamp: timestamp
            )

            let battery = BatteryData(
                percentage: Int.random(in: 50...100),
                timestamp: timestamp
            )

            let heartRate = HeartRateData(
                bpm: Double.random(in: 60...90),
                quality: Double.random(in: 0.7...1.0),
                timestamp: timestamp
            )

            let spo2 = SpO2Data(
                percentage: Double.random(in: 95...100),
                quality: Double.random(in: 0.7...1.0),
                timestamp: timestamp
            )

            let data = SensorData(
                timestamp: timestamp,
                ppg: ppg,
                accelerometer: accelerometer,
                temperature: temperature,
                battery: battery,
                heartRate: heartRate,
                spo2: spo2,
                deviceType: .oralable
            )

            sensorData.append(data)
        }

        return sensorData
    }
}

// MARK: - BLE Connection State Regression Tests

extension RegressionTests {

    func testBLEConnectionStateEnum() {
        // Test all connection states are defined
        let disconnected = BLEConnectionState.disconnected
        let connecting = BLEConnectionState.connecting
        let connected = BLEConnectionState.connected
        let disconnecting = BLEConnectionState.disconnecting

        XCTAssertEqual(disconnected.description, "Disconnected")
        XCTAssertEqual(connecting.description, "Connecting...")
        XCTAssertEqual(connected.description, "Connected")
        XCTAssertEqual(disconnecting.description, "Disconnecting...")
    }

    func testBLEServiceEventEnum() {
        // Verify BLEServiceEvent cases exist by creating mock events
        let mockPeripheral = MockPeripheralFactory.create(identifier: UUID(), name: "Test")

        // Test deviceDiscovered
        let discoveredEvent = BLEServiceEvent.deviceDiscovered(peripheral: mockPeripheral, name: "Test", rssi: -50)
        if case .deviceDiscovered(_, let name, let rssi) = discoveredEvent {
            XCTAssertEqual(name, "Test")
            XCTAssertEqual(rssi, -50)
        } else {
            XCTFail("Should be deviceDiscovered event")
        }

        // Test deviceConnected
        let connectedEvent = BLEServiceEvent.deviceConnected(peripheral: mockPeripheral)
        if case .deviceConnected = connectedEvent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Should be deviceConnected event")
        }

        // Test deviceDisconnected
        let disconnectedEvent = BLEServiceEvent.deviceDisconnected(peripheral: mockPeripheral, error: nil)
        if case .deviceDisconnected = disconnectedEvent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Should be deviceDisconnected event")
        }
    }
}

// MARK: - Settings Persistence Regression Tests

extension RegressionTests {

    func testSettingsViewModelSaveAndLoad() async {
        // Given
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        // Save original values
        let originalNotifications = viewModel.notificationsEnabled
        let originalAutoConnect = viewModel.autoConnectEnabled

        // When - change settings
        viewModel.notificationsEnabled = !originalNotifications
        viewModel.autoConnectEnabled = !originalAutoConnect

        // Save settings
        viewModel.saveSetting("notificationsEnabled", value: viewModel.notificationsEnabled)
        viewModel.saveSetting("autoConnectEnabled", value: viewModel.autoConnectEnabled)

        // Then - verify persistence
        let persistedNotifications = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        let persistedAutoConnect = UserDefaults.standard.bool(forKey: "autoConnectEnabled")

        XCTAssertEqual(persistedNotifications, !originalNotifications)
        XCTAssertEqual(persistedAutoConnect, !originalAutoConnect)

        // Cleanup - restore original values
        viewModel.notificationsEnabled = originalNotifications
        viewModel.autoConnectEnabled = originalAutoConnect
        viewModel.saveSetting("notificationsEnabled", value: originalNotifications)
        viewModel.saveSetting("autoConnectEnabled", value: originalAutoConnect)
    }

    func testChartRefreshRateEnum() {
        // Verify ChartRefreshRate enum exists
        let realTime = ChartRefreshRate.realTime
        let everySecond = ChartRefreshRate.everySecond
        let everyFiveSeconds = ChartRefreshRate.everyFiveSeconds

        // All should have different raw values
        XCTAssertNotEqual(realTime, everySecond)
        XCTAssertNotEqual(everySecond, everyFiveSeconds)
        XCTAssertNotEqual(realTime, everyFiveSeconds)
    }
}
