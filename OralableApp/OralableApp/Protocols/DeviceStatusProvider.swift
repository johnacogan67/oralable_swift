//
//  DeviceStatusProvider.swift
//  OralableApp
//
//  Created: Refactoring Phase 3 - Breaking Down God Objects
//  Purpose: Protocol for device status information, reducing OralableBLE's responsibilities
//

import Foundation
import Combine
import OralableCore

/// Protocol for providing device status and diagnostic information
/// Extracts status/logging responsibilities from OralableBLE
@MainActor
protocol DeviceStatusProvider: AnyObject {
    // MARK: - Device State

    /// Current device operational state
    var deviceState: DeviceStateResult? { get }

    /// List of discovered BLE services
    var discoveredServices: [String] { get }

    // MARK: - Recording Status

    /// Whether device is currently recording data
    var isRecording: Bool { get }

    /// Number of packets received in current session
    var packetsReceived: Int { get }

    // MARK: - Diagnostics

    /// Log messages from BLE operations
    var logMessages: [LogMessage] { get }

    /// Last error message, if any
    var lastError: String? { get }

    // MARK: - Publishers for Reactive UI

    var deviceStatePublisher: Published<DeviceStateResult?>.Publisher { get }
    var discoveredServicesPublisher: Published<[String]>.Publisher { get }
    var isRecordingPublisher: Published<Bool>.Publisher { get }
    var packetsReceivedPublisher: Published<Int>.Publisher { get }
    var logMessagesPublisher: Published<[LogMessage]>.Publisher { get }
    var lastErrorPublisher: Published<String?>.Publisher { get }
}
