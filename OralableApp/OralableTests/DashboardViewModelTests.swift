//
//  DashboardViewModelTests.swift
//  OralableApp
//
//  Created by John A Cogan on 07/11/2025.
//


//
//  DashboardViewModelTests.swift
//  OralableAppTests
//
//  Created: November 7, 2025
//  Testing DashboardViewModel functionality
//

import XCTest
import Combine
@testable import MAMDiagnostics

class DashboardViewModelTests: XCTestCase {
    
    var viewModel: DashboardViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        viewModel = DashboardViewModel()
        cancellables = []
    }
    
    override func tearDown() {
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        // Test all initial values are correct
        XCTAssertFalse(viewModel.isConnected, "Should start disconnected")
        XCTAssertFalse(viewModel.isScanning, "Should not be scanning initially")
        XCTAssertEqual(viewModel.deviceName, "No Device")
        XCTAssertEqual(viewModel.batteryLevel, 0)
        XCTAssertNil(viewModel.currentHeartRate)
        XCTAssertNil(viewModel.currentSpO2)
        XCTAssertEqual(viewModel.currentTemperature, 36.0)
        XCTAssertEqual(viewModel.connectionStatus, "Disconnected")
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertTrue(viewModel.batteryHistory.isEmpty)
        XCTAssertTrue(viewModel.heartRateHistory.isEmpty)
    }
    
    // MARK: - Connection State Tests
    
    func testConnectionStateChanges() {
        // Given
        let expectation = XCTestExpectation(description: "Connection state updates")
        
        // When
        viewModel.$isConnected
            .dropFirst()
            .sink { isConnected in
                XCTAssertTrue(isConnected)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.isConnected = true
        viewModel.connectionStatus = "Connected"
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.isConnected)
        XCTAssertEqual(viewModel.connectionStatus, "Connected")
    }
    
    func testScanningStateToggle() {
        // Test startScanning
        viewModel.startScanning()
        XCTAssertTrue(viewModel.isScanning)
        
        // Test stopScanning
        viewModel.stopScanning()
        XCTAssertFalse(viewModel.isScanning)
    }
    
    // MARK: - Device Connection Tests
    
    func testDeviceNameUpdate() {
        // Given
        let expectedName = "Oralable-001"
        
        // When
        viewModel.deviceName = expectedName
        
        // Then
        XCTAssertEqual(viewModel.deviceName, expectedName)
    }
    
    func testConnectionWithDevice() {
        // Given
        let deviceName = "Oralable-Test"
        
        // When
        viewModel.connectToDevice(named: deviceName)
        
        // Then
        XCTAssertEqual(viewModel.deviceName, deviceName)
        XCTAssertEqual(viewModel.connectionStatus, "Connecting...")
    }
    
    func testDisconnection() {
        // Given - connected state
        viewModel.isConnected = true
        viewModel.deviceName = "Oralable-001"
        viewModel.connectionStatus = "Connected"
        
        // When
        viewModel.disconnect()
        
        // Then
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertEqual(viewModel.connectionStatus, "Disconnected")
        XCTAssertEqual(viewModel.deviceName, "No Device")
        XCTAssertEqual(viewModel.batteryLevel, 0)
    }
    
    // MARK: - Sensor Data Tests
    
    func testBatteryLevelUpdate() {
        // Test valid battery levels
        viewModel.updateBatteryLevel(75)
        XCTAssertEqual(viewModel.batteryLevel, 75)
        
        // Test boundary values
        viewModel.updateBatteryLevel(0)
        XCTAssertEqual(viewModel.batteryLevel, 0)
        
        viewModel.updateBatteryLevel(100)
        XCTAssertEqual(viewModel.batteryLevel, 100)
        
        // Test invalid values (should clamp)
        viewModel.updateBatteryLevel(-10)
        XCTAssertEqual(viewModel.batteryLevel, 0)
        
        viewModel.updateBatteryLevel(150)
        XCTAssertEqual(viewModel.batteryLevel, 100)
    }
    
    func testHeartRateUpdate() {
        // Test normal heart rate
        viewModel.updateHeartRate(72.5)
        XCTAssertEqual(viewModel.currentHeartRate, 72.5)
        
        // Test boundary values
        viewModel.updateHeartRate(40.0) // Low but valid
        XCTAssertEqual(viewModel.currentHeartRate, 40.0)
        
        viewModel.updateHeartRate(200.0) // High but possible
        XCTAssertEqual(viewModel.currentHeartRate, 200.0)
        
        // Test invalid values (should reject)
        viewModel.updateHeartRate(0)
        XCTAssertNil(viewModel.currentHeartRate)
        
        viewModel.updateHeartRate(-50)
        XCTAssertNil(viewModel.currentHeartRate)
    }
    
    func testSpO2Update() {
        // Test normal SpO2
        viewModel.updateSpO2(98.5)
        XCTAssertEqual(viewModel.currentSpO2, 98.5)
        
        // Test boundary values
        viewModel.updateSpO2(95.0) // Lower normal limit
        XCTAssertEqual(viewModel.currentSpO2, 95.0)
        
        viewModel.updateSpO2(100.0)
        XCTAssertEqual(viewModel.currentSpO2, 100.0)
        
        // Test invalid values
        viewModel.updateSpO2(50.0) // Too low to be valid
        XCTAssertNil(viewModel.currentSpO2)
        
        viewModel.updateSpO2(105.0) // Above 100%
        XCTAssertNil(viewModel.currentSpO2)
    }
    
    func testTemperatureUpdate() {
        // Test normal temperature
        viewModel.updateTemperature(36.6)
        XCTAssertEqual(viewModel.currentTemperature, 36.6, accuracy: 0.1)
        
        // Test fever
        viewModel.updateTemperature(38.5)
        XCTAssertEqual(viewModel.currentTemperature, 38.5, accuracy: 0.1)
        
        // Test boundary values
        viewModel.updateTemperature(35.0) // Hypothermia threshold
        XCTAssertEqual(viewModel.currentTemperature, 35.0, accuracy: 0.1)
        
        viewModel.updateTemperature(42.0) // Hyperthermia
        XCTAssertEqual(viewModel.currentTemperature, 42.0, accuracy: 0.1)
    }
    
    // MARK: - Recording Tests
    
    func testStartRecording() {
        // Given
        XCTAssertFalse(viewModel.isRecording)
        
        // When
        viewModel.startRecording()
        
        // Then
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertNotNil(viewModel.recordingStartTime)
    }
    
    func testStopRecording() {
        // Given - start recording first
        viewModel.startRecording()
        XCTAssertTrue(viewModel.isRecording)
        
        // When
        viewModel.stopRecording()
        
        // Then
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.recordingStartTime)
    }
    
    // MARK: - Historical Data Tests
    
    func testBatteryHistoryUpdate() {
        // Given
        let initialCount = viewModel.batteryHistory.count
        
        // When
        viewModel.addBatteryReading(level: 85, timestamp: Date())
        
        // Then
        XCTAssertEqual(viewModel.batteryHistory.count, initialCount + 1)
        XCTAssertEqual(viewModel.batteryHistory.last?.level, 85)
    }
    
    func testHeartRateHistoryUpdate() {
        // Given
        let timestamp = Date()
        
        // When
        viewModel.addHeartRateReading(bpm: 75.0, timestamp: timestamp)
        
        // Then
        XCTAssertFalse(viewModel.heartRateHistory.isEmpty)
        XCTAssertEqual(viewModel.heartRateHistory.last?.bpm, 75.0)
        XCTAssertEqual(viewModel.heartRateHistory.last?.timestamp, timestamp)
    }
    
    func testHistoryDataLimits() {
        // Test that history arrays don't grow indefinitely
        // Add 1000 readings
        for i in 0..<1000 {
            viewModel.addHeartRateReading(bpm: Double(60 + i % 40), timestamp: Date())
        }
        
        // Should limit to reasonable amount (e.g., 500)
        XCTAssertLessThanOrEqual(viewModel.heartRateHistory.count, 500)
    }
    
    // MARK: - Computed Properties Tests
    
    func testShowSensorData() {
        // When disconnected
        viewModel.isConnected = false
        XCTAssertFalse(viewModel.showSensorData)
        
        // When connected
        viewModel.isConnected = true
        XCTAssertTrue(viewModel.showSensorData)
    }
    
    // MARK: - Data Clearing Tests
    
    func testClearHistoricalData() {
        // Given - add some data
        viewModel.addBatteryReading(level: 80, timestamp: Date())
        viewModel.addHeartRateReading(bpm: 70, timestamp: Date())
        viewModel.addSpO2Reading(percentage: 98, timestamp: Date())
        
        // When
        viewModel.clearAllHistory()
        
        // Then
        XCTAssertTrue(viewModel.batteryHistory.isEmpty)
        XCTAssertTrue(viewModel.heartRateHistory.isEmpty)
        XCTAssertTrue(viewModel.spo2History.isEmpty)
        XCTAssertTrue(viewModel.temperatureHistory.isEmpty)
        XCTAssertTrue(viewModel.accelerometerHistory.isEmpty)
        XCTAssertTrue(viewModel.ppgHistory.isEmpty)
    }
    
    // MARK: - Error Handling Tests
    
    func testConnectionError() {
        // When connection fails
        viewModel.handleConnectionError("Device not found")
        
        // Then
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertEqual(viewModel.connectionStatus, "Error: Device not found")
        XCTAssertFalse(viewModel.isScanning)
    }
    
    // MARK: - Async Tests
    
    func testAsyncDataUpdate() {
        // Test that published properties trigger UI updates
        let expectation = XCTestExpectation(description: "Battery update triggers publish")
        
        viewModel.$batteryLevel
            .dropFirst()
            .sink { level in
                XCTAssertEqual(level, 50)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.updateBatteryLevel(50)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfDataUpdate() {
        measure {
            // Measure performance of updating multiple sensors
            for _ in 0..<100 {
                viewModel.updateBatteryLevel(Int.random(in: 0...100))
                viewModel.updateHeartRate(Double.random(in: 60...100))
                viewModel.updateSpO2(Double.random(in: 95...100))
                viewModel.updateTemperature(Double.random(in: 36...37))
            }
        }
    }
}
