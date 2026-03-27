//
//  DeviceManagerFactory.swift
//  OralableApp
//
//  Modular manager selection: REV10 / Temporalis, ANR Muscle Sense, future intraoral slot.
//  Clinical hardware surface uses `OralableClinicalDeviceAdapter` / `ANRMuscleClinicalDeviceAdapter`.
//

import Foundation
import OralableCore

/// Core BLE transport used for Oralable REV10 / Temporalis (alias for app `BLECentralManager`).
typealias OralableBLEManager = BLECentralManager

/// Stub transport for ANR Muscle Sense — shares the unified `SensorDataBuffer` with `DeviceManager`.
@MainActor
final class ANRMuscleManager: ObservableObject {
    let sensorDataBuffer: SensorDataBuffer
    private(set) var lastHandshakeAt: Date?

    init(sensorDataBuffer: SensorDataBuffer) {
        self.sensorDataBuffer = sensorDataBuffer
    }

    func noteHandshakeStarted() {
        lastHandshakeAt = Date()
    }
}

enum DeviceManagerFactory {

    enum Product: String, CaseIterable, Identifiable {
        case temporalisHeadband
        case anrMuscleSense
        case intraoralBand

        var id: String { rawValue }

        /// Shown on discovery; future intraoral is visible but not pairable yet.
        var isAvailableForPairing: Bool {
            switch self {
            case .intraoralBand: return false
            default: return true
            }
        }

        var cardTitle: String {
            switch self {
            case .temporalisHeadband: return "Temporalis Headband"
            case .anrMuscleSense: return "ANR Muscle Sense"
            case .intraoralBand: return "Intraoral (coming soon)"
            }
        }

        var subtitle: String {
            switch self {
            case .temporalisHeadband: return "Oralable REV10 · 50 Hz"
            case .anrMuscleSense: return "Research EMG path"
            case .intraoralBand: return "Modular placeholder"
            }
        }

        var systemIcon: String {
            switch self {
            case .temporalisHeadband: return "waveform.path.ecg"
            case .anrMuscleSense: return "bolt.horizontal.circle"
            case .intraoralBand: return "mouth"
            }
        }

        var coreDeviceType: DeviceType {
            switch self {
            case .temporalisHeadband, .intraoralBand: return .oralable
            case .anrMuscleSense: return .anr
            }
        }
    }

    enum ManagedCore {
        case oralable(OralableBLEManager)
        case anr(ANRMuscleManager)
    }

    // MARK: - Clinical adapter (type-collision safe)

    /// Resolves `OralableDeviceProtocol` for the current primary BLE device, if supported.
    @MainActor
    static func makeClinicalAdapter(for primary: BLEDeviceProtocol?) -> OralableDeviceProtocol? {
        OralableClinicalMetricsGate.hardwareAdapter(from: primary)
    }

    /// Factory switch: Oralable central vs ANR stub (shared buffer ownership lives on `DeviceManager`).
    @MainActor
    static func makeManagedCore(for product: Product, deviceManager: DeviceManager) -> ManagedCore {
        switch product {
        case .temporalisHeadband, .intraoralBand:
            guard let central = deviceManager.bleManager else {
                Logger.shared.error("[DeviceManagerFactory] Missing OralableBLEManager — unexpected fallback")
                return .oralable(OralableBLEManager())
            }
            return .oralable(central)
        case .anrMuscleSense:
            return .anr(deviceManager.anrMuscleManager)
        }
    }

    /// Withings-style handshake: select transport + register intent before `DeviceManager.connect`.
    @MainActor
    static func performHandshake(for product: Product, deviceManager: DeviceManager) {
        guard product.isAvailableForPairing else {
            Logger.shared.info("[DeviceManagerFactory] Handshake skipped — product not yet available (\(product.rawValue))")
            return
        }
        deviceManager.preferredDiscoveryProduct = product
        _ = makeManagedCore(for: product, deviceManager: deviceManager)
        switch product {
        case .temporalisHeadband:
            Logger.shared.info("[DeviceManagerFactory] Handshake: Oralable REV10 · adapter: OralableClinicalDeviceAdapter")
        case .anrMuscleSense:
            deviceManager.anrMuscleManager.noteHandshakeStarted()
            Logger.shared.info("[DeviceManagerFactory] Handshake: ANR Muscle Sense · adapter: ANRMuscleClinicalDeviceAdapter")
        case .intraoralBand:
            break
        }
    }
}
