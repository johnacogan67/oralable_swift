//
//  TemporalisIRDCPlacementModel.swift
//  OralableApp
//
//  Maps REV10 IR raw counts to an estimated IR-DC rail voltage for fit-check UI.
//  Supports both documented bands (see docs/IR_DC_ADC_FORMAT.md):
//  - 19-bit / charge-ADC scale: ~30k–400k
//  - 32-bit BLE scale: ~10M–70M
//

import Foundation

enum TemporalisIRDCPlacementState: Equatable {
    case noSignal
    case tooLow
    case good
    case lightLeak
}

enum TemporalisIRDCVoltageEstimator {

    /// Counts at or above this use the 32-bit (10M–70M) voltage map.
    private static let rawScaleThreshold: Double = 10_000_000

    private static let rawMin32: Double = 10_000_000
    private static let rawMax32: Double = 70_000_000

    /// 19-bit firmware / documented coupling window for sub-threshold raw counts.
    private static let rawMin19: Double = 30_000
    private static let rawMax19: Double = 400_000

    private static let voltsAtMin: Double = 1.0
    private static let voltsAtMax: Double = 3.0

    static let placementGoodLowerVolts: Double = 1.5
    static let placementGoodUpperVolts: Double = 2.5

    /// Below this estimated voltage (strict) counts as light leak before a stable baseline exists.
    static let lightLeakThresholdStrict: Double = 2.8
    /// After stable coupling is established, allow up to this voltage before calling light leak (clench / transient lift).
    static let lightLeakThresholdRelaxed: Double = 4.5

    /// Monotonic map from reported IR (firmware raw) to a representative DC voltage for UX thresholds.
    static func estimateVolts(fromIRRaw raw: Double) -> Double {
        guard raw > 0 else { return 0 }
        if raw < rawScaleThreshold {
            let clamped = min(max(raw, rawMin19), rawMax19)
            let t = (clamped - rawMin19) / (rawMax19 - rawMin19)
            return voltsAtMin + t * (voltsAtMax - voltsAtMin)
        }
        let clamped = min(max(raw, rawMin32), rawMax32)
        let t = (clamped - rawMin32) / (rawMax32 - rawMin32)
        return voltsAtMin + t * (voltsAtMax - voltsAtMin)
    }

    static func placementState(irRaw: Double, lightLeakThreshold: Double = lightLeakThresholdStrict) -> TemporalisIRDCPlacementState {
        let v = estimateVolts(fromIRRaw: irRaw)
        if irRaw <= 0 || v <= 0 { return .noSignal }
        if v < placementGoodLowerVolts { return .tooLow }
        if v > lightLeakThreshold { return .lightLeak }
        if v <= placementGoodUpperVolts { return .good }
        return .tooLow
    }
}
