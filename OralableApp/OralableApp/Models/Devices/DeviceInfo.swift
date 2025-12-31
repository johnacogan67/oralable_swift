//
//  DeviceInfo.swift
//  OralableApp
//
//  Created: November 3, 2025
//  Updated: November 10, 2025 - Fixed Codable conformance and removed duplicate enum
//  Updated: November 10, 2025 - Now uses DeviceConnectionState (from DeviceType.swift) and SensorType (from SensorType.swift)
//  Device information model for multi-device support
//

import Foundation
import CoreBluetooth
import OralableCore

/// Complete device information
struct DeviceInfo: Identifiable, Codable, Equatable {
    
    // MARK: - Properties
    
    /// Unique identifier
    let id: UUID
    
    /// Device type
    let type: DeviceType
    
    /// Device name
    let name: String
    
    /// Bluetooth peripheral identifier
    let peripheralIdentifier: UUID?
    
    /// Connection state
    var connectionState: DeviceConnectionState
    var connectionReadiness: ConnectionReadiness = .disconnected  // ADD THIS LINE

    
    /// Battery level (0-100)
    var batteryLevel: Int?
    
    /// Signal strength (RSSI)
    var signalStrength: Int?
    
    /// Firmware version
    var firmwareVersion: String?
    
    /// Hardware version
    var hardwareVersion: String?
    
    /// Last connection timestamp
    var lastConnected: Date?
    
    /// Supported sensor types
    let supportedSensors: [SensorType]
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        type: DeviceType,
        name: String,
        peripheralIdentifier: UUID? = nil,
        connectionState: DeviceConnectionState = .disconnected,
        batteryLevel: Int? = nil,
        signalStrength: Int? = nil,
        firmwareVersion: String? = nil,
        hardwareVersion: String? = nil,
        lastConnected: Date? = nil,
        supportedSensors: [SensorType]? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.peripheralIdentifier = peripheralIdentifier
        self.connectionState = connectionState
        self.batteryLevel = batteryLevel
        self.signalStrength = signalStrength
        self.firmwareVersion = firmwareVersion
        self.hardwareVersion = hardwareVersion
        self.lastConnected = lastConnected
        self.supportedSensors = supportedSensors ?? type.defaultSensors
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, peripheralIdentifier
        case connectionState, batteryLevel, signalStrength
        case firmwareVersion, hardwareVersion
        case lastConnected, supportedSensors
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(DeviceType.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        
        // Handle optional UUID specially
        if let uuidString = try container.decodeIfPresent(String.self, forKey: .peripheralIdentifier) {
            peripheralIdentifier = UUID(uuidString: uuidString)
        } else {
            peripheralIdentifier = nil
        }
        
        connectionState = try container.decode(DeviceConnectionState.self, forKey: .connectionState)
        batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
        signalStrength = try container.decodeIfPresent(Int.self, forKey: .signalStrength)
        firmwareVersion = try container.decodeIfPresent(String.self, forKey: .firmwareVersion)
        hardwareVersion = try container.decodeIfPresent(String.self, forKey: .hardwareVersion)
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        supportedSensors = try container.decode([SensorType].self, forKey: .supportedSensors)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(peripheralIdentifier?.uuidString, forKey: .peripheralIdentifier)
        try container.encode(connectionState, forKey: .connectionState)
        try container.encodeIfPresent(batteryLevel, forKey: .batteryLevel)
        try container.encodeIfPresent(signalStrength, forKey: .signalStrength)
        try container.encodeIfPresent(firmwareVersion, forKey: .firmwareVersion)
        try container.encodeIfPresent(hardwareVersion, forKey: .hardwareVersion)
        try container.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try container.encode(supportedSensors, forKey: .supportedSensors)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helper Methods

extension DeviceInfo {
    
    /// Whether the device is currently active
    var isActive: Bool {
        connectionState == .connected || connectionState == .connecting
    }
    
    /// Create demo device for testing
    static func demo(type: DeviceType = .oralable) -> DeviceInfo {
        DeviceInfo(
            type: type,
            name: "\(type.displayName) Demo",
            connectionState: .connected,
            batteryLevel: 85,
            signalStrength: -45,
            firmwareVersion: "1.0.0",
            hardwareVersion: "Rev A"
        )
    }
    
    /// Update connection state
    mutating func updateConnectionState(_ state: DeviceConnectionState) {
        connectionState = state
        if state == .connected {
            lastConnected = Date()
        }
    }
    
    /// Update battery level
    mutating func updateBatteryLevel(_ level: Int) {
        batteryLevel = max(0, min(100, level))
    }
    
    /// Update signal strength
    mutating func updateSignalStrength(_ rssi: Int) {
        signalStrength = rssi
    }
}

// MARK: - Collection Extension

extension Array where Element == DeviceInfo {
    
    /// Filter connected devices
    var connected: [DeviceInfo] {
        filter { $0.connectionState == .connected }
    }
    
    /// Filter by device type
    func ofType(_ type: DeviceType) -> [DeviceInfo] {
        filter { $0.type == type }
    }
    
    /// Find device by peripheral identifier
    func device(withPeripheralId id: UUID) -> DeviceInfo? {
        first { $0.peripheralIdentifier == id }
    }
}
