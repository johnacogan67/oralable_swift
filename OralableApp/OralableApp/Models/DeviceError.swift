//
//  DeviceError.swift
//  OralableApp
//
//  Created by John A Cogan on 10/11/2025.
//


//
//  DeviceError.swift
//  OralableApp
//
//  Created: November 10, 2025
//  Unified error definitions for all device operations
//

import Foundation

/// Unified device error type for all device-related errors
enum DeviceError: LocalizedError {
    // Connection errors
    case notConnected(String)
    case connectionFailed(String)
    case connectionLost
    case disconnected
    case invalidPeripheral(String)
    case bluetoothUnavailable
    case bluetoothUnauthorized

    // BLE characteristic/service errors
    case characteristicNotFound(String)
    case serviceNotFound(String)
    case characteristicReadFailed
    case characteristicWriteFailed

    // Data errors
    case dataCollectionFailed
    case invalidData
    case parsingError(String)
    case insufficientData

    // Device state errors
    case deviceNotAvailable
    case operationNotSupported
    case timeout
    case deviceBusy

    // Recording errors
    case recordingAlreadyInProgress
    case recordingNotInProgress
    case recordingFailed(String)

    // Authentication errors
    case authenticationRequired
    case authenticationFailed

    // General errors
    case unknownError(String)

    /// REV10 firmware is below the minimum required for research-safe capture.
    case firmwareUpdateRequired(requiredMinimum: String, reported: String?)

    var errorDescription: String? {
        switch self {
        case .invalidPeripheral(let reason):
            return "Invalid or unavailable peripheral: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .connectionLost:
            return "Connection to device was lost"
        case .notConnected(let reason):
            return "Device is not connected: \(reason)"
        case .disconnected:
            return "Device disconnected"
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device"
        case .bluetoothUnauthorized:
            return "Bluetooth access is not authorized. Please enable Bluetooth in Settings."
        case .characteristicNotFound(let uuid):
            return "Characteristic not found: \(uuid)"
        case .serviceNotFound(let uuid):
            return "Service not found: \(uuid)"
        case .characteristicReadFailed:
            return "Failed to read from characteristic"
        case .characteristicWriteFailed:
            return "Failed to write to characteristic"
        case .dataCollectionFailed:
            return "Failed to collect data from device"
        case .invalidData:
            return "Received invalid data from device"
        case .parsingError(let details):
            return "Data parsing error: \(details)"
        case .insufficientData:
            return "Insufficient data received from device"
        case .deviceNotAvailable:
            return "Device is not available"
        case .operationNotSupported:
            return "Operation not supported by this device"
        case .timeout:
            return "Operation timed out"
        case .deviceBusy:
            return "Device is busy with another operation"
        case .recordingAlreadyInProgress:
            return "A recording session is already in progress"
        case .recordingNotInProgress:
            return "No recording session is in progress"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .authenticationRequired:
            return "Please sign in to continue"
        case .authenticationFailed:
            return "Authentication failed. Please try signing in again."
        case .unknownError(let message):
            return "Unknown error: \(message)"
        case .firmwareUpdateRequired(let minimum, let reported):
            let cur = reported ?? "unknown"
            return "Firmware update required: device reports \(cur); minimum \(minimum) for clinical research capture."
        }
    }

    /// Provides user-friendly recovery suggestions for each error type
    var recoverySuggestion: String? {
        switch self {
        case .notConnected, .disconnected:
            return "Try reconnecting to your device from the Devices tab."
        case .connectionFailed, .connectionLost:
            return "Make sure your device is powered on and nearby, then try again."
        case .bluetoothUnavailable:
            return "This app requires Bluetooth. Please use a device with Bluetooth support."
        case .bluetoothUnauthorized:
            return "Go to Settings > Privacy > Bluetooth and enable access for Oralable."
        case .characteristicNotFound, .serviceNotFound:
            return "This device may not be compatible. Try restarting both devices."
        case .dataCollectionFailed, .invalidData, .parsingError:
            return "Try disconnecting and reconnecting your device."
        case .timeout:
            return "The operation took too long. Please try again."
        case .deviceBusy:
            return "Please wait for the current operation to complete."
        case .recordingAlreadyInProgress:
            return "Stop the current recording before starting a new one."
        case .recordingNotInProgress:
            return "Start a recording session first."
        case .authenticationRequired, .authenticationFailed:
            return "Sign in with your Apple ID to access this feature."
        case .firmwareUpdateRequired:
            return "Update your Oralable REV10 to the latest firmware using Oralable’s researcher release channel, then try again."
        case .operationNotSupported:
            return "This feature is not available for your device model."
        default:
            return "Please try again or contact support if the issue persists."
        }
    }

    /// Returns true if the error is recoverable with user action
    var isRecoverable: Bool {
        switch self {
        case .notConnected, .disconnected, .connectionFailed, .connectionLost,
             .timeout, .deviceBusy, .dataCollectionFailed:
            return true
        case .bluetoothUnavailable, .operationNotSupported, .invalidPeripheral, .firmwareUpdateRequired:
            return false
        default:
            return true
        }
    }
}
