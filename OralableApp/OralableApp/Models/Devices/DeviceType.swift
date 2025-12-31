//
//  DeviceType.swift
//  OralableApp
//
//  Updated: November 10, 2025
//  FIXED: Now using correct TGM Service UUID
//  FIXED: Added DeviceConnectionState enum
//  FIXED: December 5, 2025 - ANR M40 uses Automation IO Service (0x1815) per design guide
//  NOTE: SensorType is defined in SensorType.swift (not here)
//

import Foundation
import CoreBluetooth
import OralableCore

enum DeviceType: String, CaseIterable, Codable {
    case oralable = "Oralable"
    case anr = "ANR Muscle Sense"
    case demo = "Demo Device"

    // MARK: - BLE Configuration

    var serviceUUID: CBUUID {
        switch self {
        case .oralable:
            // FIXED: Using correct TGM Service UUID from firmware
            return CBUUID(string: "3A0FF000-98C4-46B2-94AF-1AEE0FD4C48E")
        case .anr:
            // ANR M40 Design Guide: Automation IO Service for EMG data
            return CBUUID(string: "1815")
        case .demo:
            return CBUUID(string: "00000000-0000-0000-0000-000000000000")
        }
    }
    
    // MARK: - Device Properties
    
    var displayName: String {
        return rawValue
    }
    
    var icon: String {
        switch self {
        case .oralable:
            return "waveform.path.ecg"
        case .anr:
            return "bolt.horizontal.circle"
        case .demo:
            return "questionmark.circle"
        }
    }
    
    var defaultSensors: [SensorType] {
        switch self {
        case .oralable:
            return [
                .heartRate, .spo2, .temperature,
                .ppgRed, .ppgInfrared, .ppgGreen,
                .accelerometerX, .accelerometerY, .accelerometerZ,
                .battery
            ]
        case .anr:
            return [.emg, .muscleActivity, .accelerometerX, .accelerometerY, .accelerometerZ, .battery]
        case .demo:
            return [.heartRate, .spo2, .temperature, .battery]
        }
    }
    
    var supportsMultipleConnections: Bool {
        switch self {
        case .oralable:
            return false  // Single connection for now
        case .anr:
            return false
        case .demo:
            return true
        }
    }
    
    var requiresAuthentication: Bool {
        switch self {
        case .oralable:
            return false  // No pairing required
        case .anr:
            return false
        case .demo:
            return false
        }
    }
    
    // MARK: - Data Configuration
    
    var samplingRate: Int {
        switch self {
        case .oralable:
            return 50  // 50 Hz as per firmware
        case .anr:
            return 100
        case .demo:
            return 10
        }
    }
    
    var ppgSamplesPerFrame: Int {
        switch self {
        case .oralable:
            return 20  // CONFIG_PPG_SAMPLES_PER_FRAME from firmware
        case .anr:
            return 0  // No PPG
        case .demo:
            return 10
        }
    }
    
    var accSamplesPerFrame: Int {
        switch self {
        case .oralable:
            return 25  // CONFIG_ACC_SAMPLES_PER_FRAME from firmware
        case .anr:
            return 50
        case .demo:
            return 10
        }
    }
    
    // MARK: - Helper Methods
    
    static func from(peripheral: CBPeripheral) -> DeviceType? {
        // Determine device type from peripheral name
        if let name = peripheral.name {
            if name.contains("Oralable") {
                return .oralable
            } else if name.contains("ANR") || name.contains("Muscle") {
                return .anr
            } else if name.contains("Demo") {
                return .demo
            }
        }
        
        // Default to Oralable for unknown devices
        return .oralable
    }
}

// MARK: - Device Connection State

/// Represents the connection state of a BLE device
enum DeviceConnectionState: String, Codable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnecting = "Disconnecting"
    case error = "Error"
    
    var description: String {
        return rawValue
    }
    
    var isActive: Bool {
        return self == .connected || self == .connecting
    }
}
