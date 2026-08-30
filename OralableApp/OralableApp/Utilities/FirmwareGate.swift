//
//  FirmwareGate.swift
//  OralableApp
//
//  Research safety: block streaming when REV10 firmware is below the trial minimum.
//

import Foundation

enum FirmwareGate {
    /// Phase 0 vitals pilot hard minimum: LED policy 1.0.63, connect probe off, opcode 0x0A.
    /// Kept below recommended so shipped 1.0.66 kits still connect.
    static let minRequiredVersion = "1.0.63"

    /// Alias for UI copy and existing call sites.
    static let minimumOralableSemanticVersion = minRequiredVersion

    /// Latest Gen1 target: sense on BLE, green pad LEDs, 5% floor, IR-pulse worn,
    /// pad/zombie recover, desk/bench abandon (worn=0 + ACC flat 10 min).
    static let recommendedOralableSemanticVersion = "1.0.84"

    /// Firmware with explicit user device mode opcode (`00B` 0x09).
    static let minimumPlacementModeVersion = "1.0.62"

    /// Firmware that interprets CHRSTS as LTC4124 STAT activity (blink / taper / undock).
    static let minimumChrstsStatActivityVersion = "1.0.70"

    static func supportsPlacementMode(_ reported: String) -> Bool {
        !compare(reported, isLessThan: minimumPlacementModeVersion)
    }

    /// Automatic on-dock via STAT blink/taper (FW ≥ 1.0.70). Older kits should use manual placement.
    static func supportsAutomaticDockDetect(_ reported: String?) -> Bool {
        guard let reported, !reported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !compare(reported, isLessThan: minimumChrstsStatActivityVersion)
    }

    /// Soft upgrade hint: connect allowed, but below recommended Gen1 build.
    static func isBelowRecommendedOralableVersion(_ reported: String?) -> Bool {
        guard let reported, !reported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if isOralableVersionOutdated(reported) { return false }
        return compare(reported, isLessThan: recommendedOralableSemanticVersion)
    }

    /// `true` iff `reported` is **strictly less than** `minRequiredVersion`.
    static func isOralableVersionOutdated(_ reported: String) -> Bool {
        compare(reported, isLessThan: minRequiredVersion)
    }

    /// Lexicographic numeric semver compare (major.minor.patch); ignores common pre-release suffix after '-'.
    static func compare(_ a: String, isLessThan b: String) -> Bool {
        let pa = numericParts(a)
        let pb = numericParts(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va < vb { return true }
            if va > vb { return false }
        }
        return false
    }

    private static func numericParts(_ s: String) -> [Int] {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let head = t.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? t
        return head.split(separator: ".").compactMap { Int($0) }
    }
}
