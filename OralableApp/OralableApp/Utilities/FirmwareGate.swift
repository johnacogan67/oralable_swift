//
//  FirmwareGate.swift
//  OralableApp
//
//  Research safety: block streaming when REV10 firmware is below the trial minimum.
//

import Foundation

enum FirmwareGate {
    /// Minimum REV10 semantic version for trial capture. Blocked only when reported is strictly below this (so `1.0.0` is allowed).
    static let minRequiredVersion = "1.0.0"

    /// Alias for UI copy and existing call sites.
    static let minimumOralableSemanticVersion = minRequiredVersion

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
