//
//  ActivityType.swift
//  OralableApp
//
//  Created by John A Cogan on 22/12/2025.
//


import Foundation

enum ActivityType {
    case relaxed
    case clenching
    case grinding
    case motion
}

class ActivityClassifier {
    private let historySize = 32
    private var irHistory: [Double]
    private var baseline: Double = 0.0
    private var isBaselineInitialized = false

    // Thresholds
    private let motionThreshold: Double = 1.15
    private let deviationThreshold: Double = 5000.0
    private let grindingVarianceThreshold: Double

    /// Initializes the ActivityClassifier.
    /// - Parameter grindingVarianceThreshold: The variance threshold to distinguish grinding from clenching. Defaults to 1000.0.
    init(grindingVarianceThreshold: Double = 1000.0) {
        self.grindingVarianceThreshold = grindingVarianceThreshold
        self.irHistory = []
        self.irHistory.reserveCapacity(historySize)
    }

    /// Classifies the current activity based on IR and Accelerometer data.
    /// - Parameters:
    ///   - ir: The infrared signal value.
    ///   - accMagnitude: The magnitude of the accelerometer vector.
    /// - Returns: The detected ActivityType.
    func classify(ir: Double, accMagnitude: Double) -> ActivityType {
        // Initialize baseline with the first sample if needed
        if !isBaselineInitialized {
            baseline = ir
            isBaselineInitialized = true
        }

        // Update IR history for variance calculation
        if irHistory.count >= historySize {
            irHistory.removeFirst()
        }
        irHistory.append(ir)

        // 1. Check for Motion
        if accMagnitude > motionThreshold {
            return .motion
        }

        // 2. Check for Deviation from Baseline
        let deviation = abs(ir - baseline)

        if deviation > deviationThreshold {
            // Calculate variance of the signal history
            let mean = irHistory.reduce(0, +) / Double(irHistory.count)
            let variance = irHistory.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(irHistory.count)

            // High variance indicates grinding; low variance indicates clenching
            if variance > grindingVarianceThreshold {
                return .grinding
            } else {
                return .clenching
            }
        } else {
            // 3. Relaxed State
            // Slowly adapt baseline to account for drift
            baseline = (baseline * 0.95) + (ir * 0.05)
            return .relaxed
        }
    }
}
