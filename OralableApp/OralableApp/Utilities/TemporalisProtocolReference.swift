//
//  TemporalisProtocolReference.swift
//  OralableApp
//
//  Canonical timing and sync-tap thresholds aligned with
//  docs/TEMPORALIS_COLLECTION_PROTOCOL.md and latest validation review.
//

import Foundation

enum TemporalisProtocolReference {
    // Phase windows in seconds from session start.
    static let restBaseline: ClosedRange<Double> = 0.0...60.0
    static let syncTaps: ClosedRange<Double> = 60.0...70.0
    static let restPostSync: ClosedRange<Double> = 70.0...120.0
    static let maxTonicClench: ClosedRange<Double> = 120.0...130.0
    static let restAfterTonic: ClosedRange<Double> = 130.0...180.0
    static let phasicGrinding: ClosedRange<Double> = 180.0...200.0
    static let restAfterPhasic: ClosedRange<Double> = 200.0...240.0
    static let simulatedApnea: ClosedRange<Double> = 240.0...260.0
    static let tonicRescue: ClosedRange<Double> = 260.0...270.0
    static let finalRecovery: ClosedRange<Double> = 270.0...360.0

    // Plot A apnea + rescue validation window.
    static let apneaPlotWindow: ClosedRange<Double> = 240.0...270.0

    // Sync tap detector values derived from latest validation.
    static let syncTapMotionThresholdG: Double = 0.15
    static let syncTapMinSeparationS: Double = 0.20
    static let expectedSyncTapCount: Int = 5
}
