//
//  HRVAnalyzer.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: HRV analysis with SVD biomarkers for bruxism detection
//  Reference: cursor_oralable/src/analysis/features.py _hrv_svd_5s()
//
//  The SVD ratio (s1/s2) of RR intervals is a gold-standard 2025 biomarker
//  for distinguishing sleep bruxism from simple arousals.
//

import Foundation
import Accelerate

/// Analyzes heart rate variability with SVD biomarkers
public class HRVAnalyzer {

    // MARK: - Configuration

    /// Embedding dimension for delay-embedding
    /// Python uses 3
    public var embeddingDimension: Int = 3

    /// Window size for analysis (seconds)
    public var windowSeconds: Double = 5.0

    // MARK: - Buffer

    private var peakTimes: [Date] = []
    private let maxPeaks: Int = 100

    // MARK: - Initialization

    public init() {}

    // MARK: - Peak Time Management

    /// Add a detected peak time
    public func addPeakTime(_ time: Date) {
        peakTimes.append(time)
        peakTimes.sort()

        // Trim old peaks (keep last 100)
        if peakTimes.count > maxPeaks {
            peakTimes.removeFirst(peakTimes.count - maxPeaks)
        }
    }

    /// Add multiple peak times from beats
    public func addBeats(_ beats: [BeatFeature]) {
        for beat in beats {
            addPeakTime(beat.peakTime)
        }
    }

    /// Clear all peak times
    public func reset() {
        peakTimes.removeAll()
    }

    // MARK: - RR Interval Calculation

    /// Get RR intervals in the specified window
    /// - Parameters:
    ///   - windowStart: Start of analysis window
    ///   - windowEnd: End of analysis window
    /// - Returns: Array of RR intervals in seconds
    public func getRRIntervals(
        from windowStart: Date,
        to windowEnd: Date
    ) -> [Double] {

        // Get peaks in window (include one before and after for complete intervals)
        let inWindow = peakTimes.filter { $0 >= windowStart && $0 < windowEnd }
        guard inWindow.count >= 2 else { return [] }

        // Include previous peak if available
        var relevantPeaks = inWindow
        if let prevPeak = peakTimes.last(where: { $0 < windowStart }) {
            relevantPeaks.insert(prevPeak, at: 0)
        }

        // Include next peak if available
        if let nextPeak = peakTimes.first(where: { $0 >= windowEnd }) {
            relevantPeaks.append(nextPeak)
        }

        // Calculate RR intervals
        var rrIntervals: [Double] = []
        for i in 1..<relevantPeaks.count {
            let interval = relevantPeaks[i].timeIntervalSince(relevantPeaks[i - 1])

            // Filter physiological range (0.33s = 180 BPM to 1.5s = 40 BPM)
            if interval >= 0.33 && interval <= 1.5 {
                rrIntervals.append(interval)
            }
        }

        return rrIntervals
    }

    // MARK: - Basic HRV Metrics

    /// Calculate SDNN (standard deviation of NN intervals)
    public func calculateSDNN(_ rrIntervals: [Double]) -> Double {
        guard rrIntervals.count >= 2 else { return 0 }

        let mean = rrIntervals.reduce(0, +) / Double(rrIntervals.count)
        let sumSquaredDiff = rrIntervals.map { pow($0 - mean, 2) }.reduce(0, +)
        return sqrt(sumSquaredDiff / Double(rrIntervals.count - 1)) * 1000  // Convert to ms
    }

    /// Calculate RMSSD (root mean square of successive differences)
    public func calculateRMSSD(_ rrIntervals: [Double]) -> Double {
        guard rrIntervals.count >= 2 else { return 0 }

        var sumSquaredDiff: Double = 0
        for i in 1..<rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSquaredDiff += diff * diff
        }

        return sqrt(sumSquaredDiff / Double(rrIntervals.count - 1)) * 1000  // Convert to ms
    }

    // MARK: - SVD Biomarker (Gold-Standard 2025)

    /// Calculate SVD biomarkers from RR intervals
    /// Uses delay-embedding matrix and singular value decomposition
    /// - Parameter rrIntervals: Array of RR intervals in seconds
    /// - Returns: HRV SVD result with s1 and s1/s2 ratio
    public func calculateSVDBiomarker(_ rrIntervals: [Double]) -> HRVSVDResult {
        guard rrIntervals.count >= embeddingDimension + 1 else {
            return HRVSVDResult(s1: nil, s2: nil, ratio: nil)
        }

        // Build delay-embedding matrix
        // Rows = [RR_i, RR_{i+1}, RR_{i+2}] for embedding dimension 3
        let nRows = rrIntervals.count - embeddingDimension
        guard nRows >= 1 else {
            return HRVSVDResult(s1: nil, s2: nil, ratio: nil)
        }

        var matrix: [[Double]] = []
        for i in 0..<nRows {
            var row: [Double] = []
            for j in 0..<embeddingDimension {
                row.append(rrIntervals[i + j])
            }
            matrix.append(row)
        }

        // Perform SVD using Accelerate framework
        let singularValues = computeSVD(matrix: matrix, rows: nRows, cols: embeddingDimension)

        guard !singularValues.isEmpty else {
            return HRVSVDResult(s1: nil, s2: nil, ratio: nil)
        }

        let s1 = singularValues[0]
        let s2 = singularValues.count > 1 ? singularValues[1] : nil

        let ratio: Double?
        if let s2Val = s2, s2Val > 1e-10 {
            ratio = s1 / s2Val
        } else {
            ratio = nil
        }

        return HRVSVDResult(s1: s1, s2: s2, ratio: ratio)
    }

    /// Analyze HRV for the last N seconds
    public func analyzeWindow(windowSeconds: Double? = nil) -> HRVResult {
        let window = windowSeconds ?? self.windowSeconds
        let windowEnd = Date()
        let windowStart = windowEnd.addingTimeInterval(-window)

        let rrIntervals = getRRIntervals(from: windowStart, to: windowEnd)

        let sdnn = calculateSDNN(rrIntervals)
        let rmssd = calculateRMSSD(rrIntervals)
        let svd = calculateSVDBiomarker(rrIntervals)

        return HRVResult(
            sdnnMs: sdnn,
            rmssdMs: rmssd,
            svdS1: svd.s1,
            svdS1S2Ratio: svd.ratio,
            rrCount: rrIntervals.count,
            windowSeconds: window
        )
    }

    // MARK: - Private SVD Computation

    private func computeSVD(matrix: [[Double]], rows: Int, cols: Int) -> [Double] {
        // Flatten matrix in column-major order for LAPACK
        var flatMatrix: [Double] = []
        for j in 0..<cols {
            for i in 0..<rows {
                flatMatrix.append(matrix[i][j])
            }
        }

        // SVD parameters
        var m = __CLPK_integer(rows)
        var n = __CLPK_integer(cols)
        var lda = m
        var ldu = m
        var ldvt = n

        var singularValues = [Double](repeating: 0, count: min(rows, cols))
        var u = [Double](repeating: 0, count: rows * rows)
        var vt = [Double](repeating: 0, count: cols * cols)
        var work = [Double](repeating: 0, count: max(1, 3 * min(rows, cols) + max(rows, cols)))
        var lwork = __CLPK_integer(work.count)
        var info: __CLPK_integer = 0

        // Call LAPACK dgesvd
        var jobu: Int8 = Int8(UnicodeScalar("S").value)  // Compute first min(m,n) columns of U
        var jobvt: Int8 = Int8(UnicodeScalar("S").value) // Compute first min(m,n) rows of VT

        dgesvd_(&jobu, &jobvt, &m, &n, &flatMatrix, &lda,
                &singularValues, &u, &ldu, &vt, &ldvt,
                &work, &lwork, &info)

        if info != 0 {
            return []
        }

        return singularValues
    }
}

// MARK: - HRV SVD Result

/// Result from SVD analysis of HRV
public struct HRVSVDResult: Sendable {
    /// Leading singular value
    public let s1: Double?

    /// Second singular value
    public let s2: Double?

    /// Ratio s1/s2 (gold-standard bruxism biomarker)
    public let ratio: Double?

    /// Whether this indicates potential bruxism vs simple arousal
    /// Higher ratio suggests bruxism pattern
    /// Threshold TBD from clinical validation
    public var suggestsBruxism: Bool? {
        guard let r = ratio else { return nil }
        // Placeholder threshold - needs clinical validation
        return r > 5.0
    }
}

// MARK: - HRV Result

/// Comprehensive HRV analysis result
public struct HRVResult: Sendable {
    /// SDNN in milliseconds
    public let sdnnMs: Double

    /// RMSSD in milliseconds
    public let rmssdMs: Double

    /// SVD leading singular value
    public let svdS1: Double?

    /// SVD s1/s2 ratio (bruxism biomarker)
    public let svdS1S2Ratio: Double?

    /// Number of RR intervals used
    public let rrCount: Int

    /// Analysis window in seconds
    public let windowSeconds: Double

    /// Whether HRV data is sufficient for analysis
    public var isValid: Bool {
        rrCount >= 3
    }
}
