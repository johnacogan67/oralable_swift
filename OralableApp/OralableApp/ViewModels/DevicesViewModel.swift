//
//  DevicesViewModel.swift
//  OralableApp
//
//  ViewModel for device discovery and connection management.
//
//  Responsibilities:
//  - Manages BLE scanning state
//  - Tracks discovered and connected devices
//  - Handles device connection/disconnection
//  - Manages device settings (LED brightness, sample rate)
//
//  Published Properties:
//  - isConnected, isScanning: Connection state
//  - discoveredDevices: List of found BLE devices
//  - connectedDevice: Currently connected device info
//  - autoConnect, ledBrightness, sampleRate: Settings
//
//  Uses BLEManagerProtocol for testable dependency injection.
//

import Foundation
import Combine
import CoreBluetooth

@MainActor
class DevicesViewModel: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var deviceName: String = "Oralable-001"
    @Published var batteryLevel: Int = 85
    @Published var signalStrength: Int = -45
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var connectedDevice: ConnectedDeviceInfo?
    
    // Settings
    @Published var autoConnect: Bool = true
    @Published var ledBrightness: Double = 0.5
    @Published var sampleRate: Int = 50
    
    // Device info
    var serialNumber: String { "ORA-2025-001" }
    var firmwareVersion: String { "1.0.0" }
    var lastSyncTime: String { "Just now" }

    private let bleManager: BLEManagerProtocol  // ✅ Now uses protocol for dependency injection
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize with injected dependencies (preferred)
    /// - Parameter bleManager: BLE manager conforming to protocol (allows mocking for tests)
    init(bleManager: BLEManagerProtocol) {
        self.bleManager = bleManager
        setupBindings()
    }

    private func setupBindings() {
        // Using protocol publishers for better testability
        bleManager.isConnectedPublisher
            .assign(to: &$isConnected)

        bleManager.isScanningPublisher
            .assign(to: &$isScanning)

        bleManager.deviceNamePublisher
            .assign(to: &$deviceName)
    }
    
    func toggleScanning() {
        if isScanning {
            bleManager.stopScanning()
        } else {
            bleManager.startScanning()
        }
    }
    
    func connect(to device: DiscoveredDevice) {
        // Implement connection logic
        Logger.shared.info("[DevicesViewModel] Connecting to \(device.name)")
    }
    
    func disconnect() {
        bleManager.disconnect()
    }
}

// Supporting types
struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let name: String
    let rssi: Int
    let isOralable: Bool
}

struct ConnectedDeviceInfo {
    let name: String
    let model: String
    let firmware: String
}
