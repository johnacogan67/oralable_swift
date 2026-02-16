//
//  HRVAnalyzerTests.swift
//  OralableAppTests
//
//  Created: February 16, 2026
//  Purpose: Unit tests for HRVAnalyzer HRV metrics and SVD biomarkers
//

import XCTest
@testable import OralableApp

final class HRVAnalyzerTests: XCTestCase {

    // MARK: - Helpers

    /// Known RR intervals used across multiple tests (in seconds).
    private let knownIntervals: [Double] = [0.8, 0.85, 0.75, 0.9, 0.82]

    // MARK: - SDNN Tests

    /// SDNN is the sample standard deviation of NN intervals, converted to milliseconds.
    /// For [0.8, 0.85, 0.75, 0.9, 0.82]:
    ///   mean  = 0.824
    ///   var_s = sum((xi - mean)^2) / (N - 1)
    ///         = ((0.8-0.824)^2 + (0.85-0.824)^2 + (0.75-0.824)^2 + (0.9-0.824)^2 + (0.82-0.824)^2) / 4
    ///         = (0.000576 + 0.000676 + 0.005476 + 0.005776 + 0.000016) / 4
    ///         = 0.01252 / 4
    ///         = 0.00313
    ///   sdnn  = sqrt(0.00313) * 1000 ~= 55.946 ms
    func testSDNNCalculation() {
        let analyzer = HRVAnalyzer()
        let sdnn = analyzer.calculateSDNN(knownIntervals)

        let mean = knownIntervals.reduce(0, +) / Double(knownIntervals.count)
        let sumSqDiff = knownIntervals.map { pow($0 - mean, 2) }.reduce(0, +)
        let expected = sqrt(sumSqDiff / Double(knownIntervals.count - 1)) * 1000.0

        XCTAssertEqual(sdnn, expected, accuracy: 0.1, "SDNN should match manual calculation within 0.1 ms")
    }

    /// RMSSD is root mean square of successive differences, in milliseconds.
    /// Successive diffs: [0.05, -0.10, 0.15, -0.08]
    /// Squared: [0.0025, 0.01, 0.0225, 0.0064]
    /// Mean of squared: 0.0414 / 4 = 0.01035
    /// RMSSD = sqrt(0.01035) * 1000 ~= 101.735 ms
    ///
    /// Note: The implementation divides by (count - 1) where count is the number of intervals,
    /// so the divisor is (5 - 1) = 4 for the successive diffs sum.
    func testRMSSDCalculation() {
        let analyzer = HRVAnalyzer()
        let rmssd = analyzer.calculateRMSSD(knownIntervals)

        // Compute expected value matching the implementation
        var sumSquaredDiff: Double = 0
        for i in 1..<knownIntervals.count {
            let diff = knownIntervals[i] - knownIntervals[i - 1]
            sumSquaredDiff += diff * diff
        }
        let expected = sqrt(sumSquaredDiff / Double(knownIntervals.count - 1)) * 1000.0

        XCTAssertEqual(rmssd, expected, accuracy: 0.1, "RMSSD should match manual calculation within 0.1 ms")
    }

    /// A single interval should yield SDNN == 0 (need at least 2 for standard deviation).
    func testSDNNWithSingleInterval() {
        let analyzer = HRVAnalyzer()
        let sdnn = analyzer.calculateSDNN([0.8])
        XCTAssertEqual(sdnn, 0, "SDNN with a single interval should be 0")
    }

    // MARK: - SVD Tests

    /// With 10 RR intervals and embeddingDimension = 3, SVD should produce non-nil results.
    func testSVDWithSufficientData() {
        let analyzer = HRVAnalyzer()
        let intervals: [Double] = [0.8, 0.85, 0.75, 0.9, 0.82, 0.78, 0.88, 0.81, 0.84, 0.79]
        let result = analyzer.calculateSVDBiomarker(intervals)

        XCTAssertNotNil(result.s1, "s1 should be non-nil with 10 intervals")
        XCTAssertNotNil(result.ratio, "ratio should be non-nil with 10 intervals")
    }

    /// With only 3 intervals and embeddingDimension = 3, we need at least 4.
    /// So 3 intervals should be insufficient.
    func testSVDWithInsufficientData() {
        let analyzer = HRVAnalyzer()
        XCTAssertEqual(analyzer.embeddingDimension, 3, "Default embedding dimension should be 3")

        let intervals: [Double] = [0.8, 0.85, 0.75]
        let result = analyzer.calculateSVDBiomarker(intervals)

        XCTAssertNil(result.ratio, "ratio should be nil with fewer than embeddingDimension + 1 intervals")
    }

    /// With exactly 4 intervals (embeddingDimension + 1 = 4), SVD should work.
    func testSVDWith4Intervals() {
        let analyzer = HRVAnalyzer()
        let intervals: [Double] = [0.8, 0.85, 0.75, 0.9]
        let result = analyzer.calculateSVDBiomarker(intervals)

        XCTAssertNotNil(result.s1, "s1 should be non-nil with exactly embeddingDimension + 1 intervals")
    }

    // MARK: - RR Interval Filtering Tests

    /// Peak times producing intervals outside 0.33-1.5s should be filtered out.
    func testRRIntervalPhysiologicalFiltering() {
        let analyzer = HRVAnalyzer()

        let baseTime = Date()

        // Create peak times with varying intervals:
        // 0.0s, 0.8s (valid 0.8s), 1.0s (valid 0.2s -> too short, filtered), 2.6s (1.6s -> too long, filtered), 3.4s (valid 0.8s)
        let peakOffsets: [TimeInterval] = [0.0, 0.8, 1.0, 2.6, 3.4]
        for offset in peakOffsets {
            analyzer.addPeakTime(baseTime.addingTimeInterval(offset))
        }

        let rrIntervals = analyzer.getRRIntervals(
            from: baseTime.addingTimeInterval(-0.1),
            to: baseTime.addingTimeInterval(4.0)
        )

        // Only intervals in [0.33, 1.5] seconds should survive
        for interval in rrIntervals {
            XCTAssertGreaterThanOrEqual(interval, 0.33, "RR interval \(interval) should be >= 0.33s")
            XCTAssertLessThanOrEqual(interval, 1.5, "RR interval \(interval) should be <= 1.5s")
        }
    }

    // MARK: - Reset Tests

    /// After reset, analyzeWindow should return rrCount == 0.
    func testResetClearsPeaks() {
        let analyzer = HRVAnalyzer()

        let baseTime = Date()
        for i in 0..<10 {
            analyzer.addPeakTime(baseTime.addingTimeInterval(Double(i) * 0.8))
        }

        analyzer.reset()

        let result = analyzer.analyzeWindow(windowSeconds: 60.0)
        XCTAssertEqual(result.rrCount, 0, "After reset, rrCount should be 0")
    }
}
