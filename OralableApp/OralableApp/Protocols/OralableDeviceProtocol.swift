//
//  OralableDeviceProtocol.swift
//  OralableApp
//
//  Universal hardware contract for Oralable ecosystem devices (REV10, ANR Muscle Sense,
//  future intraoral). `BLEDeviceProtocol` keeps `batteryLevel: Int?` / `firmwareVersion: String?`;
//  adapters implement this surface without Swift member type clashes.
//

import Foundation
import OralableCore

/// App-level hardware abstraction for discovery, onboarding, and capability gating.
protocol OralableDeviceProtocol: AnyObject {
    var connectionStatus: DeviceConnectionState { get }
    var batteryLevel: Double { get }
    var firmwareVersion: String { get }
    /// Nominal stream sample rate (REV10 = 50 Hz per product spec; ANR uses `DeviceType.anr.samplingRate`).
    var nominalSamplingRateHz: Int { get }
    var isStreaming: Bool { get }
    func startStreaming()
    /// TFI / Temporalis / SpO2 clinical block — only REV10-style primaries.
    var supportsTemporalisClinicalDashboard: Bool { get }
}

// MARK: - REV10

/// Bridges `OralableDevice` to `OralableDeviceProtocol`.
final class OralableClinicalDeviceAdapter: OralableDeviceProtocol {
    private weak var oralable: OralableDevice?

    init(wrapping oralable: OralableDevice) {
        self.oralable = oralable
    }

    var connectionStatus: DeviceConnectionState {
        oralable?.deviceInfo.connectionState ?? .disconnected
    }

    var batteryLevel: Double {
        guard let o = oralable else { return 0 }
        if let g = o.batteryLevel { return Double(g) }
        if let b = o.deviceInfo.batteryLevel { return Double(b) }
        return 0
    }

    var firmwareVersion: String {
        guard let o = oralable else { return "—" }
        return o.deviceInfo.firmwareVersion ?? o.firmwareVersion ?? "—"
    }

    var nominalSamplingRateHz: Int {
        DeviceType.oralable.samplingRate
    }

    var supportsTemporalisClinicalDashboard: Bool { true }

    var isStreaming: Bool {
        guard let o = oralable else { return false }
        return o.isConnectionReady && o.isConnected
    }

    func startStreaming() {
        guard let o = oralable else { return }
        Task {
            try? await o.startDataStream()
        }
    }
}

// MARK: - ANR Muscle Sense

/// Bridges `ANRMuscleSenseDevice` to the universal contract (no Temporalis clinical dashboard).
@MainActor
final class ANRMuscleClinicalDeviceAdapter: OralableDeviceProtocol {
    private weak var device: ANRMuscleSenseDevice?

    init(wrapping device: ANRMuscleSenseDevice) {
        self.device = device
    }

    var connectionStatus: DeviceConnectionState {
        device?.deviceInfo.connectionState ?? .disconnected
    }

    var batteryLevel: Double {
        guard let d = device else { return 0 }
        if let b = d.batteryLevel { return Double(b) }
        if let i = d.deviceInfo.batteryLevel { return Double(i) }
        return 0
    }

    var firmwareVersion: String {
        guard let d = device else { return "—" }
        return d.deviceInfo.firmwareVersion ?? d.firmwareVersion ?? "—"
    }

    var nominalSamplingRateHz: Int {
        DeviceType.anr.samplingRate
    }

    var supportsTemporalisClinicalDashboard: Bool { false }

    var isStreaming: Bool {
        guard let d = device else { return false }
        return d.isConnected
    }

    func startStreaming() {
        guard let d = device else { return }
        Task {
            try? await d.startDataStream()
        }
    }
}

// MARK: - Gating

enum OralableClinicalMetricsGate {

    /// Builds the appropriate adapter for supported BLE device types.
    static func hardwareAdapter(from primary: BLEDeviceProtocol?) -> OralableDeviceProtocol? {
        guard let primary else { return nil }
        if let o = primary as? OralableDevice {
            return OralableClinicalDeviceAdapter(wrapping: o)
        }
        if let anr = primary as? ANRMuscleSenseDevice {
            return ANRMuscleClinicalDeviceAdapter(wrapping: anr)
        }
        return nil
    }

    /// Dashboard "Clinical Metrics" (TFI, Temporalis chart, gated SpO2) — primary must be connected REV10.
    static func shouldShowTemporalisClinicalDashboard(primaryBLE: BLEDeviceProtocol?) -> Bool {
        guard let p = primaryBLE, p.connectionState == .connected else { return false }
        return hardwareAdapter(from: p)?.supportsTemporalisClinicalDashboard ?? false
    }
}
