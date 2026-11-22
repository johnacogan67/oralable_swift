//
//  DevicesViewModelTests.swift
//  OralableApp
//
//  Created by John A Cogan on 07/11/2025.
//


//
//  DevicesViewModelTests.swift
//  OralableAppTests
//
//  Created: November 7, 2025
//  Testing DevicesViewModel functionality
//

import XCTest
import Combine
import CoreBluetooth
@testable import MAMDiagnostics

class DevicesViewModelTests: XCTestCase {
    
    var viewModel: DevicesViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        viewModel = DevicesViewModel()
        cancellables = []
    }
    
    override func tearDown() {
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertTrue(viewModel.discoveredDevices.isEmpty)
        XCTAssertNil(viewModel.selectedDevice)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(viewModel.isConnecting)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertTrue(viewModel.pairedDevices.isEmpty)
    }
    
    // MARK: - Device Discovery Tests
    
    func testStartScanning() {
        // When
        viewModel.startScanning()
        
        // Then
        XCTAssertTrue(viewModel.isScanning)
        XCTAssertEqual(viewModel.scanningStatus, "Scanning...")
    }
    
    func testStopScanning() {
        // Given
        viewModel.startScanning()
        
        // When
        viewModel.stopScanning()
        
        // Then
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertEqual(viewModel.scanningStatus, "Not scanning")
    }
    
    func testDeviceDiscovered() {
        // Given
        let deviceInfo = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -45,
            advertisementData: [:],
            deviceType: .oralable
        )
        
        // When
        viewModel.addDiscoveredDevice(deviceInfo)
        
        // Then
        XCTAssertEqual(viewModel.discoveredDevices.count, 1)
        XCTAssertEqual(viewModel.discoveredDevices.first?.name, "Oralable-001")
        XCTAssertEqual(viewModel.discoveredDevices.first?.rssi, -45)
    }
    
    func testDuplicateDeviceNotAdded() {
        // Given
        let deviceInfo = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -45,
            advertisementData: [:],
            deviceType: .oralable
        )
        
        // When
        viewModel.addDiscoveredDevice(deviceInfo)
        viewModel.addDiscoveredDevice(deviceInfo) // Add same device again
        
        // Then
        XCTAssertEqual(viewModel.discoveredDevices.count, 1, "Duplicate device should not be added")
    }
    
    func testDeviceRSSIUpdate() {
        // Given
        let deviceId = UUID()
        let initialDevice = DiscoveredDevice(
            id: deviceId,
            name: "Oralable-001",
            rssi: -45,
            advertisementData: [:],
            deviceType: .oralable
        )
        viewModel.addDiscoveredDevice(initialDevice)
        
        // When - update with better signal
        let updatedDevice = DiscoveredDevice(
            id: deviceId,
            name: "Oralable-001",
            rssi: -30,
            advertisementData: [:],
            deviceType: .oralable
        )
        viewModel.updateDeviceRSSI(updatedDevice)
        
        // Then
        XCTAssertEqual(viewModel.discoveredDevices.first?.rssi, -30)
    }
    
    // MARK: - Device Connection Tests
    
    func testSelectDevice() {
        // Given
        let device = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-Test",
            rssi: -50,
            advertisementData: [:],
            deviceType: .oralable
        )
        viewModel.addDiscoveredDevice(device)
        
        // When
        viewModel.selectDevice(device)
        
        // Then
        XCTAssertEqual(viewModel.selectedDevice?.id, device.id)
        XCTAssertEqual(viewModel.connectionState, .connecting)
        XCTAssertTrue(viewModel.isConnecting)
    }
    
    func testConnectToDevice() {
        // Given
        let device = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -40,
            advertisementData: [:],
            deviceType: .oralable
        )
        
        // When
        viewModel.connectToDevice(device)
        
        // Then
        XCTAssertEqual(viewModel.selectedDevice?.id, device.id)
        XCTAssertTrue(viewModel.isConnecting)
        XCTAssertEqual(viewModel.connectionState, .connecting)
        XCTAssertFalse(viewModel.isScanning, "Should stop scanning when connecting")
    }
    
    func testDisconnectDevice() {
        // Given - connected state
        let device = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -40,
            advertisementData: [:],
            deviceType: .oralable
        )
        viewModel.selectedDevice = device
        viewModel.connectionState = .connected
        viewModel.isConnecting = false
        
        // When
        viewModel.disconnectDevice()
        
        // Then
        XCTAssertNil(viewModel.selectedDevice)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertFalse(viewModel.isConnecting)
    }
    
    func testConnectionStateTransitions() {
        // Test disconnected -> connecting
        viewModel.updateConnectionState(.connecting)
        XCTAssertEqual(viewModel.connectionState, .connecting)
        XCTAssertTrue(viewModel.isConnecting)
        
        // Test connecting -> connected
        viewModel.updateConnectionState(.connected)
        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertFalse(viewModel.isConnecting)
        
        // Test connected -> disconnecting
        viewModel.updateConnectionState(.disconnecting)
        XCTAssertEqual(viewModel.connectionState, .disconnecting)
        
        // Test disconnecting -> disconnected
        viewModel.updateConnectionState(.disconnected)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertFalse(viewModel.isConnecting)
    }
    
    // MARK: - Device Type Tests
    
    func testDeviceTypeIdentification() {
        // Test Oralable device
        let oralable = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -45,
            advertisementData: [:],
            deviceType: .oralable
        )
        XCTAssertEqual(viewModel.identifyDeviceType(oralable), .oralable)
        
        // Test ANR device
        let anr = DiscoveredDevice(
            id: UUID(),
            name: "ANRMuscleSense",
            rssi: -50,
            advertisementData: [:],
            deviceType: .anrMuscleSense
        )
        XCTAssertEqual(viewModel.identifyDeviceType(anr), .anrMuscleSense)
        
        // Test unknown device
        let unknown = DiscoveredDevice(
            id: UUID(),
            name: "Unknown-Device",
            rssi: -60,
            advertisementData: [:],
            deviceType: .unknown
        )
        XCTAssertEqual(viewModel.identifyDeviceType(unknown), .unknown)
    }
    
    func testSupportedDevicesFilter() {
        // Add mix of devices
        let oralable = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -45,
            advertisementData: [:],
            deviceType: .oralable
        )
        
        let unknown = DiscoveredDevice(
            id: UUID(),
            name: "Random-BLE",
            rssi: -60,
            advertisementData: [:],
            deviceType: .unknown
        )
        
        viewModel.addDiscoveredDevice(oralable)
        viewModel.addDiscoveredDevice(unknown)
        
        // Filter supported devices
        let supported = viewModel.supportedDevices
        XCTAssertEqual(supported.count, 1)
        XCTAssertEqual(supported.first?.deviceType, .oralable)
    }
    
    // MARK: - Paired Devices Tests
    
    func testAddPairedDevice() {
        // Given
        let device = PairedDevice(
            id: UUID(),
            name: "Oralable-001",
            deviceType: .oralable,
            lastConnected: Date()
        )
        
        // When
        viewModel.addPairedDevice(device)
        
        // Then
        XCTAssertEqual(viewModel.pairedDevices.count, 1)
        XCTAssertEqual(viewModel.pairedDevices.first?.name, "Oralable-001")
    }
    
    func testRemovePairedDevice() {
        // Given
        let device = PairedDevice(
            id: UUID(),
            name: "Oralable-001",
            deviceType: .oralable,
            lastConnected: Date()
        )
        viewModel.addPairedDevice(device)
        
        // When
        viewModel.removePairedDevice(device)
        
        // Then
        XCTAssertTrue(viewModel.pairedDevices.isEmpty)
    }
    
    func testAutoConnectToPairedDevice() {
        // Given
        let pairedDevice = PairedDevice(
            id: UUID(),
            name: "Oralable-001",
            deviceType: .oralable,
            lastConnected: Date()
        )
        viewModel.addPairedDevice(pairedDevice)
        
        // When - discover the same device
        let discoveredDevice = DiscoveredDevice(
            id: pairedDevice.id,
            name: pairedDevice.name,
            rssi: -45,
            advertisementData: [:],
            deviceType: pairedDevice.deviceType
        )
        viewModel.addDiscoveredDevice(discoveredDevice)
        
        // Then - should auto-select for connection
        XCTAssertTrue(viewModel.shouldAutoConnect(to: discoveredDevice))
    }
    
    // MARK: - Sorting and Filtering Tests
    
    func testDeviceSortingByRSSI() {
        // Add devices with different RSSI
        let device1 = DiscoveredDevice(id: UUID(), name: "Device1", rssi: -60, advertisementData: [:], deviceType: .oralable)
        let device2 = DiscoveredDevice(id: UUID(), name: "Device2", rssi: -30, advertisementData: [:], deviceType: .oralable)
        let device3 = DiscoveredDevice(id: UUID(), name: "Device3", rssi: -45, advertisementData: [:], deviceType: .oralable)
        
        viewModel.addDiscoveredDevice(device1)
        viewModel.addDiscoveredDevice(device2)
        viewModel.addDiscoveredDevice(device3)
        
        // Sort by signal strength
        let sorted = viewModel.devicesSortedBySignalStrength
        
        XCTAssertEqual(sorted[0].rssi, -30, "Strongest signal should be first")
        XCTAssertEqual(sorted[1].rssi, -45, "Medium signal should be second")
        XCTAssertEqual(sorted[2].rssi, -60, "Weakest signal should be last")
    }
    
    // MARK: - Error Handling Tests
    
    func testConnectionTimeout() {
        // Given
        let device = DiscoveredDevice(
            id: UUID(),
            name: "Oralable-001",
            rssi: -45,
            advertisementData: [:],
            deviceType: .oralable
        )
        viewModel.connectToDevice(device)
        
        // When
        viewModel.handleConnectionTimeout()
        
        // Then
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertFalse(viewModel.isConnecting)
        XCTAssertEqual(viewModel.errorMessage, "Connection timeout")
        XCTAssertNil(viewModel.selectedDevice)
    }
    
    func testConnectionError() {
        // When
        viewModel.handleConnectionError("Failed to connect: Device not found")
        
        // Then
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertFalse(viewModel.isConnecting)
        XCTAssertEqual(viewModel.errorMessage, "Failed to connect: Device not found")
    }
    
    func testClearError() {
        // Given
        viewModel.errorMessage = "Some error"
        
        // When
        viewModel.clearError()
        
        // Then
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Async Tests
    
    func testScanTimeout() {
        let expectation = XCTestExpectation(description: "Scan stops after timeout")
        
        viewModel.startScanningWithTimeout(duration: 0.5)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertFalse(self.viewModel.isScanning, "Scanning should stop after timeout")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfDeviceListUpdate() {
        measure {
            // Add and remove many devices
            for i in 0..<100 {
                let device = DiscoveredDevice(
                    id: UUID(),
                    name: "Device-\(i)",
                    rssi: Int.random(in: -80...-30),
                    advertisementData: [:],
                    deviceType: .oralable
                )
                viewModel.addDiscoveredDevice(device)
            }
            viewModel.clearDiscoveredDevices()
        }
    }
}
