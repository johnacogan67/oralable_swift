//
//  PulseMorphologyAnalyzerTests.swift
//  OralableAppTests
//
//  Created: February 16, 2026
//  Purpose: Unit tests for PulseMorphologyAnalyzer beat detection and feature extraction
//

import XCTest
@testable import OralableApp

final class PulseMorphologyAnalyzerTests: XCTestCase {

    // MARK: - Helpers

    private let sampleRate: Double = 50.0

    /// Generate a synthetic PPG-like signal using a sum of sinusoids.
    /// The fundamental at `fundamentalHz` models the pulse rate.
    /// A second harmonic shapes the waveform to have clear peaks.
    private func generateSyntheticPulse(
        durationSeconds: Double = 6.0,
        fundamentalHz: Double = 1.2,
        dcOffset: Double = 10000.0,
        amplitude: Double = 500.0
    ) -> [Double] {
        let sampleCount = Int(sampleRate * durationSeconds)
        var signal = [Double]()
        signal.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            // Fundamental + second harmonic to create asymmetric pulse shape
            let value = dcOffset
                + amplitude * sin(2.0 * .pi * fundamentalHz * t)
                + (amplitude * 0.3) * sin(2.0 * .pi * 2.0 * fundamentalHz * t)
            signal.append(value)
        }
        return signal
    }

    // MARK: - Tests

    /// A synthetic pulse at 1.2 Hz over 6 seconds should yield at least 5 beats.
    func testBeatDetectionOnSyntheticPulse() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)
        let signal = generateSyntheticPulse()

        let beats = analyzer.detectBeats(signal: signal)

        // 1.2 Hz * 6 seconds = ~7.2 cycles, expect at least 5 detected beats
        XCTAssertGreaterThanOrEqual(
            beats.count, 5,
            "Should detect at least 5 beats in a 6-second signal at 1.2 Hz (got \(beats.count))"
        )
    }

    /// A flat (constant) signal should produce no beats.
    func testBeatDetectionOnFlatSignal() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)
        let signal = [Double](repeating: 1000.0, count: 300)

        let beats = analyzer.detectBeats(signal: signal)

        XCTAssertEqual(beats.count, 0, "A flat signal should produce 0 beats")
    }

    /// A random noise signal with no periodic structure should detect 0 or very few beats.
    func testBeatDetectionOnNoisySignal() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)

        // Deterministic pseudo-random sequence using a linear congruential generator
        var rng: UInt64 = 42
        var signal = [Double]()
        for _ in 0..<300 {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let value = Double(rng % 10000)
            signal.append(value)
        }

        let beats = analyzer.detectBeats(signal: signal)

        XCTAssertLessThanOrEqual(
            beats.count, 3,
            "Random noise should produce very few beats (got \(beats.count))"
        )
    }

    /// All detected beats should have positive rise and fall times.
    func testBeatFeatureTimingPositive() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)
        let signal = generateSyntheticPulse()

        let beats = analyzer.detectBeats(signal: signal)

        XCTAssertFalse(beats.isEmpty, "Should detect at least one beat")
        for (index, beat) in beats.enumerated() {
            XCTAssertGreaterThan(
                beat.riseTimeSeconds, 0,
                "Beat \(index) riseTimeSeconds should be > 0 (got \(beat.riseTimeSeconds))"
            )
            XCTAssertGreaterThan(
                beat.fallTimeSeconds, 0,
                "Beat \(index) fallTimeSeconds should be > 0 (got \(beat.fallTimeSeconds))"
            )
        }
    }

    /// Adjacent peaks should be separated by at least minPeakDistanceSeconds (0.4s).
    func testMinPeakDistanceRespected() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)
        XCTAssertEqual(analyzer.minPeakDistanceSeconds, 0.4, "Default minPeakDistanceSeconds should be 0.4")

        let signal = generateSyntheticPulse()
        let beats = analyzer.detectBeats(signal: signal)

        guard beats.count >= 2 else {
            XCTFail("Need at least 2 beats to check peak distance")
            return
        }

        for i in 1..<beats.count {
            let distanceSamples = beats[i].peakIndex - beats[i - 1].peakIndex
            let distanceSeconds = Double(distanceSamples) / sampleRate

            XCTAssertGreaterThanOrEqual(
                distanceSeconds,
                analyzer.minPeakDistanceSeconds,
                "Peaks \(i-1) and \(i) are only \(distanceSeconds)s apart (min: \(analyzer.minPeakDistanceSeconds)s)"
            )
        }
    }

    /// An empty signal should produce 0 beats.
    func testEmptySignal() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)
        let beats = analyzer.detectBeats(signal: [])
        XCTAssertEqual(beats.count, 0, "Empty signal should produce 0 beats")
    }

    /// A signal with only 2 samples should produce 0 beats (guard requires >= 3).
    func testTooShortSignal() {
        let analyzer = PulseMorphologyAnalyzer(sampleRate: sampleRate)
        let beats = analyzer.detectBeats(signal: [1000.0, 1001.0])
        XCTAssertEqual(beats.count, 0, "A 2-sample signal should produce 0 beats")
    }
}
