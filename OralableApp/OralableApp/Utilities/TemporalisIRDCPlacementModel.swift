//
//  TemporalisIRDCPlacementModel.swift
//  OralableApp
//
//  Maps REV10 IR raw counts to an estimated IR-DC rail voltage for fit-check UI.
//  Uses the documented 10M–70M raw coupling band (see docs/IR_DC_ADC_FORMAT.md).
//

import Foundation

enum TemporalisIRDCPlacementState: Equatable {
    case noSignal
    case tooLow
    case good
    case lightLeak
}

enum TemporalisIRDCVoltageEstimator {

    private static let rawMin: Double = 10_000_000
    private static let rawMax: Double = 70_000_000
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
        let clamped = min(max(raw, rawMin), rawMax)
        let t = (clamped - rawMin) / (rawMax - rawMin)
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
