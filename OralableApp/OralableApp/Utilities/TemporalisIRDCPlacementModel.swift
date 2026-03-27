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

    private static let placementGoodLower: Double = 1.5
    private static let placementGoodUpper: Double = 2.5
    private static let lightLeakThreshold: Double = 2.8

    /// Monotonic map from reported IR (firmware raw) to a representative DC voltage for UX thresholds.
    static func estimateVolts(fromIRRaw raw: Double) -> Double {
        guard raw > 0 else { return 0 }
        let clamped = min(max(raw, rawMin), rawMax)
        let t = (clamped - rawMin) / (rawMax - rawMin)
        return voltsAtMin + t * (voltsAtMax - voltsAtMin)
    }

    static func placementState(irRaw: Double) -> TemporalisIRDCPlacementState {
        let v = estimateVolts(fromIRRaw: irRaw)
        if irRaw <= 0 || v <= 0 { return .noSignal }
        if v < placementGoodLower { return .tooLow }
        if v > lightLeakThreshold { return .lightLeak }
        if v <= placementGoodUpper { return .good }
        return .tooLow
    }
}
