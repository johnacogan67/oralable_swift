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
/// Isolated to MainActor: ANR stack is MainActor; REV10 UI paths resolve adapters on main.
@MainActor
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
@MainActor
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
        if let g = o.batteryLevel { return Self.doublePercent(g) }
        if let b = o.deviceInfo.batteryLevel { return Self.doublePercent(b) }
        return 0
    }

    var firmwareVersion: String {
        guard let o = oralable else { return "—" }
        let raw = o.deviceInfo.firmwareVersion ?? o.firmwareVersion
        return Self.sanitizedFirmwareString(raw)
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

    private static func doublePercent(_ value: Int) -> Double {
        Double(value)
    }

    private static func sanitizedFirmwareString(_ raw: String?) -> String {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return "—"
        }
        return s
    }
}

// MARK: - ANR Muscle Sense

/// Bridges `ANRMuscleSenseDevice` to the universal contract (no Temporalis clinical dashboard).
@MainActor
final class ANRMuscleClinicalDeviceAdapter: OralableDeviceProtocol {
    private weak var device: ANRMuscleSenseDevice?

    /// Peak-normalized EMG (0–100) for REV10 + ANR dual sessions; driven by `DeviceManagerAdapter`.
    static var dashboardEmgActivityPercent: Double = 0

    init(wrapping device: ANRMuscleSenseDevice) {
        self.device = device
    }

    /// Secondary metric for researcher dashboards when ANR is paired with REV10.
    var emgActivityPercent: Double { Self.dashboardEmgActivityPercent }

    var connectionStatus: DeviceConnectionState {
        device?.deviceInfo.connectionState ?? .disconnected
    }

    var batteryLevel: Double {
        guard let d = device else { return 0 }
        if let b = d.batteryLevel { return Self.doublePercent(b) }
        if let i = d.deviceInfo.batteryLevel { return Self.doublePercent(i) }
        return 0
    }

    var firmwareVersion: String {
        guard let d = device else { return "—" }
        let raw = d.deviceInfo.firmwareVersion ?? d.firmwareVersion
        return Self.sanitizedFirmwareString(raw)
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

    private static func doublePercent(_ value: Int) -> Double {
        Double(value)
    }

    private static func sanitizedFirmwareString(_ raw: String?) -> String {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return "—"
        }
        return s
    }
}

// MARK: - Gating

enum OralableClinicalMetricsGate {

    /// Builds the appropriate adapter for supported BLE device types.
    @MainActor
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
    @MainActor
    static func shouldShowTemporalisClinicalDashboard(primaryBLE: BLEDeviceProtocol?) -> Bool {
        guard let p = primaryBLE, p.connectionState == .connected else { return false }
        return hardwareAdapter(from: p)?.supportsTemporalisClinicalDashboard ?? false
    }
}
