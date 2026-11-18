//
//  DualProtocolACues.swift
//  OralableApp
//
//  Mac-parity Protocol A cue table (scripts/run_protocol_a_session.py PROTOCOL_A_CUES).
//

import Foundation

/// One cue interval: [startSeconds, endSeconds).
struct DualProtocolACue: Equatable, Sendable {
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
}

enum DualProtocolACues {
    /// Total Protocol A duration (seconds). Mac: SESSION_DURATION_S = 360.
    static let sessionDurationSeconds: TimeInterval = 360

    /// Preflight: rest → hard clench → rest (Mac PREFLIGHT_*).
    static let preflightRestSeconds: TimeInterval = 10
    static let preflightClenchSeconds: TimeInterval = 10
    /// Dual A stack often lands ~70–90 raw; Mac default matches eng pack gate.
    static let defaultEmgGate: Double = 70

    /// Copy of Mac `PROTOCOL_A_CUES`.
    static let protocolA: [DualProtocolACue] = [
        DualProtocolACue(startSeconds: 0, endSeconds: 60, text: "REST quiet — stay still, jaw relaxed"),
        DualProtocolACue(startSeconds: 60, endSeconds: 70, text: "FIVE sync taps — firm, rhythmic taps on housing"),
        DualProtocolACue(startSeconds: 70, endSeconds: 120, text: "REST — settle after taps"),
        DualProtocolACue(startSeconds: 120, endSeconds: 130, text: "MAX TONIC clench — hold hard 10 s"),
        DualProtocolACue(startSeconds: 130, endSeconds: 180, text: "REST recovery — release, stay still"),
        DualProtocolACue(startSeconds: 180, endSeconds: 200, text: "PHASIC grind — rhythmic jaw motion 20 s"),
        DualProtocolACue(startSeconds: 200, endSeconds: 240, text: "REST — accel baseline"),
        DualProtocolACue(startSeconds: 240, endSeconds: 260, text: "BREATH HOLD (simulated apnea) — hold breath 20 s"),
        DualProtocolACue(startSeconds: 260, endSeconds: 270, text: "TONIC RESCUE clench — clench hard 10 s (still holding or just after)"),
        DualProtocolACue(startSeconds: 270, endSeconds: 360, text: "FINAL recovery — stillness 90 s")
    ]

    static func cue(at elapsed: TimeInterval) -> DualProtocolACue {
        for cue in protocolA where elapsed >= cue.startSeconds && elapsed < cue.endSeconds {
            return cue
        }
        return protocolA.last ?? DualProtocolACue(
            startSeconds: 270,
            endSeconds: 360,
            text: "FINAL recovery — stillness"
        )
    }

    static func formatMMSS(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Settle → cue-clock handoff. A delayed callback must not start cues after cancel,
/// link drop, or a newer settle.
enum ProtocolASettleGate {
    /// Wall-clock pause between seat QC and the cue clock. Tests shorten this.
    static var delay: TimeInterval = 2

    static func shouldStartCues(
        isSettling: Bool,
        scheduledGeneration: UInt,
        currentGeneration: UInt
    ) -> Bool {
        isSettling && scheduledGeneration == currentGeneration
    }
}
