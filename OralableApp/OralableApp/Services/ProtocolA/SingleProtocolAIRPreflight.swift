//
//  SingleProtocolAIRPreflight.swift
//  OralableApp
//
//  IR optical clench-drop preflight (Mac Dual A IR gate).
//  Single-MAM Protocol A Setup uses CouplingGate (`couple`) instead.
//

import Foundation

struct SingleProtocolAIRPreflightStats: Equatable, Sendable {
    var passed: Bool
    /// Required fractional drop of clench trough vs rest median (default 0.08).
    var dropGate: Double
    var restMedian: Double
    var clenchMin: Double
    /// (restMedian - clenchMin) / restMedian when restMedian > 0.
    var dropFraction: Double
}

enum SingleProtocolAIRPreflight {
    static let defaultDropGate: Double = 0.08

    /// Pass when clench IR trough drops by at least `dropGate` relative to rest median.
    static func evaluate(
        restSamples: [Double],
        clenchSamples: [Double],
        dropGate: Double = defaultDropGate
    ) -> SingleProtocolAIRPreflightStats {
        let restMedian = median(restSamples)
        let clenchMin = clenchSamples.min() ?? 0
        let dropFraction: Double
        if restMedian > 0 {
            dropFraction = max(0, (restMedian - clenchMin) / restMedian)
        } else {
            dropFraction = 0
        }
        let passed = restMedian > 0 && !clenchSamples.isEmpty && dropFraction >= dropGate
        return SingleProtocolAIRPreflightStats(
            passed: passed,
            dropGate: dropGate,
            restMedian: restMedian,
            clenchMin: clenchMin,
            dropFraction: dropFraction
        )
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
