//
//  PerformanceTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Performance benchmarks for BLE operations and UI responsiveness
//  Benchmarks scanning, connection times, multi-device reconnection, and data export
//

import XCTest
import Combine
import CoreBluetooth
@testable import MAMDiagnostics

@MainActor
final class PerformanceTests: XCTestCase {

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

    // MARK: - BLE Scanning Performance Benchmarks

    func testBLEScanningStartPerformance() {
        // Benchmark the time to start BLE scanning
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)

        measure(metrics: [XCTClockMetric()]) {
            mockBLEService.startScanning()
            mockBLEService.stopScanning()
        }
    }

    func testBLEDeviceDiscoveryPerformance() async {
        // Benchmark device discovery callback performance
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let expectation = XCTestExpectation(description: "Device discovered")

        // Add multiple devices
        for i in 0..<10 {
            mockBLEService.addDiscoverableDevice(
                id: UUID(),
                name: "Test Device \(i)"
            )
        }

        var discoveredCount = 0
        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceDiscovered = event {
                    discoveredCount += 1
                    if discoveredCount >= 10 {
                        expectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Trigger discovery simulation
        mockBLEService.startScanning()

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 2.0, "Device discovery should complete quickly")

        mockBLEService.stopScanning()
    }

    // MARK: - BLE Connection Time Benchmarks

    func testBLEConnectionTimePerformance() async {
        // Benchmark single device connection time
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")

        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!
        let expectation = XCTestExpectation(description: "Device connected")

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceConnected = event {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()
        mockBLEService.connect(to: peripheral)

        await fulfillment(of: [expectation], timeout: 5.0)

        let connectionTime = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(connectionTime, 1.0, "Connection should complete within 1 second")

        // Cleanup
        mockBLEService.disconnect(from: peripheral)
    }

    func testBLEServiceDiscoveryPerformance() async {
        // Benchmark service discovery time after connection
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")

        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!
        let connectExpectation = XCTestExpectation(description: "Device connected")
        let servicesExpectation = XCTestExpectation(description: "Services discovered")

        mockBLEService.eventPublisher
            .sink { event in
                switch event {
                case .deviceConnected:
                    connectExpectation.fulfill()
                case .servicesDiscovered:
                    servicesExpectation.fulfill()
                default:
                    break
                }
            }
            .store(in: &cancellables)

        mockBLEService.connect(to: peripheral)
        await fulfillment(of: [connectExpectation], timeout: 3.0)

        let startTime = CFAbsoluteTimeGetCurrent()
        mockBLEService.discoverServices(on: peripheral)

        await fulfillment(of: [servicesExpectation], timeout: 5.0)

        let discoveryTime = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(discoveryTime, 2.0, "Service discovery should complete within 2 seconds")

        // Cleanup
        mockBLEService.disconnect(from: peripheral)
    }

    // MARK: - Multi-Device Reconnection Stress Benchmarks

    func testMultiDeviceReconnectionPerformance() async {
        // Benchmark reconnection of multiple devices under stress
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.05,
            maxReconnectionDelay: 0.2,
            jitterFactor: 0.0,
            connectionTimeout: 1.0,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)
        worker.configure(bleService: mockBLEService)

        let deviceCount = 5
        var deviceIds: [UUID] = []

        // Add multiple devices
        for i in 0..<deviceCount {
            let deviceId = UUID()
            deviceIds.append(deviceId)
            mockBLEService.addDiscoverableDevice(id: deviceId, name: "Device \(i)")
        }

        var reconnectionAttempts = 0
        let expectation = XCTestExpectation(description: "Multiple reconnections attempted")
        expectation.expectedFulfillmentCount = deviceCount

        worker.eventPublisher
            .sink { event in
                if case .reconnectionAttemptStarted = event {
                    reconnectionAttempts += 1
                    if reconnectionAttempts <= deviceCount {
                        expectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Start worker and schedule all reconnections
        worker.start()
        for deviceId in deviceIds {
            let peripheral = mockBLEService.discoveredPeripherals[deviceId]!
            worker.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: true)
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(totalTime, 5.0, "Multi-device reconnection should complete within 5 seconds")

        // Cleanup
        worker.stop()
    }

    func testReconnectionConfigPerformance() {
        // Benchmark config creation performance
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<100 {
                _ = BLEBackgroundWorkerConfig(
                    maxReconnectionAttempts: 10,
                    baseReconnectionDelay: 0.1,
                    maxReconnectionDelay: 5.0,
                    jitterFactor: 0.1,
                    connectionTimeout: 2.0,
                    pauseOnBluetoothOff: true
                )
            }
        }
    }

    // MARK: - DashboardView Rendering Benchmarks

    func testSensorDataCreationPerformance() {
        // Benchmark creation of 100+ sensor data objects
        measure(metrics: [XCTClockMetric()]) {
            // Simulate processing many data points
            for _ in 0..<100 {
                _ = PPGData(
                    red: Int32.random(in: 50000...250000),
                    ir: Int32.random(in: 50000...250000),
                    green: Int32.random(in: 50000...250000),
                    timestamp: Date()
                )
            }
        }
    }

    func testHistoricalDataManagerCreationPerformance() {
        // Benchmark historical data manager creation
        let processor = SensorDataProcessor.shared

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<10 {
                _ = HistoricalDataManager(sensorDataProcessor: processor)
            }
        }
    }

    func testChartDataPreparationPerformance() {
        // Benchmark chart data preparation for visualization
        let sensorData = createMockSensorData(count: 100)

        measure(metrics: [XCTClockMetric()]) {
            // Simulate chart data preparation
            let ppgValues = sensorData.map { $0.ppg.ir }
            let timestamps = sensorData.map { $0.timestamp }

            // Process for chart display
            _ = zip(timestamps, ppgValues).map { (timestamp: $0, value: $1) }
        }
    }

    func testAutomaticRecordingSessionReactiveUpdatePerformance() async {
        // Benchmark AutomaticRecordingSession published updates (dashboard recording derives from these)
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Updates processed")

        session.$isSessionActive
            .dropFirst()
            .sink { _ in
                updateCount += 1
                if updateCount >= 20 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Rapid connect → endSession cycles (each cycle publishes isSessionActive true then false)
        for _ in 0..<10 {
            session.onDeviceConnected()
            session.endSession()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 1.0, "Session publisher updates should process quickly")
    }

    // MARK: - SettingsView Responsiveness Benchmarks

    func testSettingsViewModelTogglePerformance() async {
        // Benchmark rapid settings toggling
        let viewModel = SettingsViewModel(sensorDataProcessor: nil)

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Settings updated")

        viewModel.$notificationsEnabled
            .dropFirst()
            .sink { _ in
                updateCount += 1
                if updateCount >= 50 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Rapid toggle
        for _ in 0..<50 {
            viewModel.notificationsEnabled.toggle()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 2.0, "Settings toggle should be responsive")
    }

    func testThresholdSettingsUpdatePerformance() async {
        // Benchmark threshold settings updates
        let settings = ThresholdSettings.shared
        let originalValue = settings.movementThreshold

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Thresholds updated")

        settings.$movementThreshold
            .dropFirst()
            .sink { _ in
                updateCount += 1
                if updateCount >= 100 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Rapid updates
        for i in 0..<100 {
            settings.movementThreshold = originalValue + Double(i)
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 2.0, "Threshold updates should be fast")

        // Cleanup
        settings.movementThreshold = originalValue
    }

    func testFeatureFlagsTogglePerformance() async {
        // Benchmark feature flag toggling
        let flags = FeatureFlags.shared
        let originalValue = flags.showHeartRateCard

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Flags updated")

        flags.$showHeartRateCard
            .dropFirst()
            .sink { _ in
                updateCount += 1
                if updateCount >= 50 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Rapid toggle
        for _ in 0..<50 {
            flags.showHeartRateCard.toggle()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 1.0, "Feature flag updates should be instant")

        // Cleanup
        flags.showHeartRateCard = originalValue
    }

    // MARK: - Data Export Throughput Benchmarks

    func testCSVExportSmallDatasetPerformance() {
        // Benchmark export of small dataset
        let manager = CSVExportManager()
        let sensorData = createMockSensorData(count: 50)
        let logs = createMockLogs(count: 10)

        measure(metrics: [XCTClockMetric()]) {
            let exportURL = manager.exportData(sensorData: sensorData, logs: logs)
            if let url = exportURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func testCSVExportMediumDatasetPerformance() {
        // Benchmark export of medium dataset
        let manager = CSVExportManager()
        let sensorData = createMockSensorData(count: 500)
        let logs = createMockLogs(count: 100)

        measure(metrics: [XCTClockMetric()]) {
            let exportURL = manager.exportData(sensorData: sensorData, logs: logs)
            if let url = exportURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func testCSVExportLargeDatasetPerformance() {
        // Benchmark export of large dataset (1000+ records)
        let manager = CSVExportManager()
        let sensorData = createMockSensorData(count: 1000)
        let logs = createMockLogs(count: 200)

        let startTime = CFAbsoluteTimeGetCurrent()
        let exportURL = manager.exportData(sensorData: sensorData, logs: logs)
        let exportTime = CFAbsoluteTimeGetCurrent() - startTime

        // Verify export completed
        XCTAssertNotNil(exportURL, "Export should succeed")
        XCTAssertLessThan(exportTime, 5.0, "Large export should complete within 5 seconds")

        // Verify file size
        if let url = exportURL {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int {
                XCTAssertGreaterThan(fileSize, 0, "Exported file should have content")
                print("Export file size: \(fileSize) bytes")
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testExportSizeEstimationPerformance() {
        // Benchmark size estimation calculation
        let manager = CSVExportManager()

        measure(metrics: [XCTClockMetric()]) {
            // Benchmark estimation for various sizes
            for count in stride(from: 100, through: 10000, by: 100) {
                _ = manager.estimateExportSize(sensorDataCount: count, logCount: count / 10)
            }
        }
    }

    func testExportSummaryCalculationPerformance() {
        // Benchmark summary calculation for large datasets
        let manager = CSVExportManager()
        let sensorData = createMockSensorData(count: 1000)
        let logs = createMockLogs(count: 100)

        measure(metrics: [XCTClockMetric()]) {
            _ = manager.getExportSummary(sensorData: sensorData, logs: logs)
        }
    }

    // MARK: - Memory and Resource Benchmarks

    func testSensorDataMemoryFootprint() {
        // Benchmark memory usage when creating large datasets
        let count = 1000
        var sensorData: [SensorData] = []

        measure(metrics: [XCTMemoryMetric()]) {
            sensorData = createMockSensorData(count: count)
        }

        XCTAssertEqual(sensorData.count, count, "Should create all sensor data points")
    }

    func testCombinePublisherMemoryPerformance() async {
        // Benchmark memory usage of Combine publishers under load
        let settings = ThresholdSettings.shared
        let originalValue = settings.movementThreshold

        measure(metrics: [XCTMemoryMetric()]) {
            var tempCancellables = Set<AnyCancellable>()

            // Create multiple subscriptions
            for _ in 0..<10 {
                settings.$movementThreshold
                    .sink { _ in }
                    .store(in: &tempCancellables)
            }

            // Rapid updates
            for i in 0..<100 {
                settings.movementThreshold = originalValue + Double(i)
            }

            // Cancel all
            tempCancellables.removeAll()
        }

        // Cleanup
        settings.movementThreshold = originalValue
    }

    // MARK: - BLE Background Worker Performance

    func testBLEBackgroundWorkerStartStopPerformance() {
        // Benchmark worker start/stop cycle
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.1,
            maxReconnectionDelay: 1.0,
            jitterFactor: 0.0,
            connectionTimeout: 2.0,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<10 {
                worker.start()
                worker.stop()
            }
        }
    }

    func testBLEBackgroundWorkerEventPublishingPerformance() async {
        // Benchmark event publishing performance
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.01,
            maxReconnectionDelay: 0.1,
            jitterFactor: 0.0,
            connectionTimeout: 0.5,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)
        worker.configure(bleService: mockBLEService)

        var eventCount = 0
        let expectation = XCTestExpectation(description: "Events received")

        worker.eventPublisher
            .sink { _ in
                eventCount += 1
                if eventCount >= 10 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        worker.start()

        // Add devices and trigger events
        for i in 0..<5 {
            let deviceId = UUID()
            mockBLEService.addDiscoverableDevice(id: deviceId, name: "Device \(i)")
            let peripheral = mockBLEService.discoveredPeripherals[deviceId]!
            worker.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: true)
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 2.0, "Event publishing should be fast")

        worker.stop()
    }

    // MARK: - Automatic Recording Session Performance

    func testAutomaticRecordingSessionLifecyclePerformance() async {
        // Benchmark connect / endSession lifecycle updates
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<20 {
                session.onDeviceConnected()
                session.endSession()
            }
        }
    }

    func testAutomaticRecordingSessionDurationPerformance() async {
        // Benchmark computed sessionDuration during an active session
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        session.onDeviceConnected()
        XCTAssertTrue(session.isSessionActive && !session.isSessionPaused)

        measure(metrics: [XCTClockMetric()]) {
            // Access computed duration multiple times (not a publisher)
            for _ in 0..<1000 {
                _ = session.sessionDuration
            }
        }
    }

    /// Isolated session: no CloudKit sync, caller must endSession in cleanup.
    private func makeIsolatedAutomaticRecordingSession() -> AutomaticRecordingSession {
        let session = AutomaticRecordingSession()
        session.syncOnDisconnect = false
        return session
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

    private func createMockLogs(count: Int) -> [String] {
        var logs: [String] = []

        for i in 0..<count {
            logs.append("[\(Date())] Log entry \(i): Sample log message with timestamp and details")
        }

        return logs
    }
}

// MARK: - BLE Multi-Device Performance Extension

extension PerformanceTests {

    func testConcurrentDeviceConnectionPerformance() async {
        // Benchmark connecting to multiple devices concurrently
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)

        let deviceCount = 5
        var deviceIds: [UUID] = []
        var peripherals: [CBPeripheral] = []

        for i in 0..<deviceCount {
            let deviceId = UUID()
            deviceIds.append(deviceId)
            mockBLEService.addDiscoverableDevice(id: deviceId, name: "Device \(i)")
            peripherals.append(mockBLEService.discoveredPeripherals[deviceId]!)
        }

        let expectation = XCTestExpectation(description: "All devices connected")
        expectation.expectedFulfillmentCount = deviceCount

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceConnected = event {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Connect all devices concurrently
        for peripheral in peripherals {
            mockBLEService.connect(to: peripheral)
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = totalTime / Double(deviceCount)

        XCTAssertLessThan(totalTime, 5.0, "All connections should complete within 5 seconds")
        XCTAssertLessThan(averageTime, 1.0, "Average connection time should be under 1 second")

        // Cleanup
        for peripheral in peripherals {
            mockBLEService.disconnect(from: peripheral)
        }
    }

    func testRapidConnectionDisconnectionPerformance() async {
        // Benchmark rapid connect/disconnect cycles
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        let cycleCount = 10
        var completedCycles = 0
        let expectation = XCTestExpectation(description: "Cycles completed")

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceDisconnected = event {
                    completedCycles += 1
                    if completedCycles >= cycleCount {
                        expectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<cycleCount {
            mockBLEService.connect(to: peripheral)
            // Small delay to allow connection
            try? await Task.sleep(nanoseconds: 50_000_000)
            mockBLEService.disconnect(from: peripheral)
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(totalTime, 5.0, "Rapid connection cycles should complete quickly")
    }
}

// MARK: - UI Data Binding Performance Extension

extension PerformanceTests {

    func testMultiplePublisherCombinePerformance() async {
        // Benchmark combining AutomaticRecordingSession with settings/flags publishers
        let session = makeIsolatedAutomaticRecordingSession()
        defer { session.endSession() }

        let settings = ThresholdSettings.shared
        let flags = FeatureFlags.shared

        let originalThreshold = settings.movementThreshold
        let originalFlag = flags.showHeartRateCard

        var combinedUpdateCount = 0
        let expectation = XCTestExpectation(description: "Combined updates")

        // Combine real published properties (sessionDuration is computed, not published)
        Publishers.CombineLatest3(
            session.$isSessionActive,
            settings.$movementThreshold,
            flags.$showHeartRateCard
        )
        .dropFirst()
        .sink { _, _, _ in
            combinedUpdateCount += 1
            if combinedUpdateCount >= 30 {
                expectation.fulfill()
            }
        }
        .store(in: &cancellables)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Trigger updates from multiple sources (connect → end replaces toggle)
        for i in 0..<10 {
            session.onDeviceConnected()
            session.endSession()
            settings.movementThreshold = originalThreshold + Double(i)
            flags.showHeartRateCard.toggle()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(duration, 2.0, "Combined publisher updates should be fast")

        // Cleanup
        settings.movementThreshold = originalThreshold
        flags.showHeartRateCard = originalFlag
    }
}
