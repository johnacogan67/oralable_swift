//
//  HeartRateCalculatorTests.swift
//  OralableAppTests
//
//  Created: November 11, 2025
//  Purpose: Unit tests for HeartRateCalculator signal processing algorithm
//

import XCTest
@testable import MAMDiagnostics

class HeartRateCalculatorTests: XCTestCase {

    var calculator: HeartRateCalculator!

    override func setUp() {
        super.setUp()
        calculator = HeartRateCalculator()
    }

    override func tearDown() {
        calculator = nil
        super.tearDown()
    }

    // MARK: - Input Validation Tests

    func testCalculateHeartRateWithEmptyArray() {
        // Given
        let emptySamples: [UInt32] = []

        // When
        let result = calculator.calculateHeartRate(irSamples: emptySamples)

        // Then
        XCTAssertNil(result, "Should return nil for empty array")
    }

    func testCalculateHeartRateWithZeroValues() {
        // Given
        let zeroSamples = [UInt32](repeating: 0, count: 150)

        // When
        let result = calculator.calculateHeartRate(irSamples: zeroSamples)

        // Then
        XCTAssertNil(result, "Should return nil for all zero values")
    }

    func testCalculateHeartRateWithSaturatedValues() {
        // Given - saturated values (over 500000)
        let saturatedSamples = [UInt32](repeating: 524287, count: 150)

        // When
        let result = calculator.calculateHeartRate(irSamples: saturatedSamples)

        // Then
        XCTAssertNil(result, "Should return nil for saturated values")
    }

    func testCalculateHeartRateWithInsufficientValidSamples() {
        // Given - only 50 valid samples out of 150 (33%)
        var samples: [UInt32] = []
        samples.append(contentsOf: [UInt32](repeating: 50000, count: 50))
        samples.append(contentsOf: [UInt32](repeating: 0, count: 100))

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        XCTAssertNil(result, "Should return nil when less than 80% samples are valid")
    }

    func testCalculateHeartRateWithLowVariability() {
        // Given - constant signal (no variability)
        let constantSamples = [UInt32](repeating: 100000, count: 150)

        // When
        let result = calculator.calculateHeartRate(irSamples: constantSamples)

        // Then
        XCTAssertNil(result, "Should return nil for constant signal (no variability)")
    }

    // MARK: - Simulated PPG Signal Tests

    func testCalculateHeartRateWithSimulated60BPM() {
        // Given - Simulated PPG signal at 60 BPM (1 Hz)
        // 50 Hz sampling rate, 3 seconds of data = 150 samples
        // 60 BPM = 1 beat per second = 1 Hz
        let samples = generateSimulatedPPGSignal(bpm: 60, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        XCTAssertNotNil(result, "Should calculate heart rate for simulated signal")
        if let result = result {
            XCTAssertTrue(result.bpm >= 50 && result.bpm <= 70, "BPM should be around 60, got \(result.bpm)")
            XCTAssertTrue(result.isReliable, "Should be reliable signal")
            XCTAssertTrue(result.quality > 0.3, "Quality should be above minimum threshold")
        }
    }

    func testCalculateHeartRateWithSimulated72BPM() {
        // Given - Simulated PPG signal at 72 BPM (1.2 Hz)
        let samples = generateSimulatedPPGSignal(bpm: 72, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        XCTAssertNotNil(result, "Should calculate heart rate for simulated signal")
        if let result = result {
            XCTAssertTrue(result.bpm >= 65 && result.bpm <= 80, "BPM should be around 72, got \(result.bpm)")
            XCTAssertTrue(result.isReliable, "Should be reliable signal")
        }
    }

    func testCalculateHeartRateWithSimulated100BPM() {
        // Given - Simulated PPG signal at 100 BPM (1.67 Hz)
        let samples = generateSimulatedPPGSignal(bpm: 100, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        XCTAssertNotNil(result, "Should calculate heart rate for simulated signal")
        if let result = result {
            XCTAssertTrue(result.bpm >= 90 && result.bpm <= 110, "BPM should be around 100, got \(result.bpm)")
        }
    }

    // MARK: - Boundary Value Tests

    func testCalculateHeartRateWithMinimumPhysiologicalBPM() {
        // Given - 40 BPM (minimum physiological limit)
        let samples = generateSimulatedPPGSignal(bpm: 40, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        if let result = result {
            XCTAssertTrue(result.bpm >= 40, "BPM should not be below physiological minimum")
            XCTAssertTrue(result.bpm <= 180, "BPM should not be above physiological maximum")
        }
    }

    func testCalculateHeartRateWithMaximumPhysiologicalBPM() {
        // Given - 180 BPM (maximum physiological limit)
        let samples = generateSimulatedPPGSignal(bpm: 180, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 3000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        if let result = result {
            XCTAssertTrue(result.bpm >= 40, "BPM should not be below physiological minimum")
            XCTAssertTrue(result.bpm <= 180, "BPM should not be above physiological maximum")
        }
    }

    // MARK: - Quality Assessment Tests

    func testQualityLevelForGoodSignal() {
        // Given - High quality signal
        let samples = generateSimulatedPPGSignal(bpm: 72, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then
        if let result = result {
            XCTAssertEqual(result.qualityLevel, .good, "Should detect good quality signal")
            XCTAssertTrue(result.quality >= 0.6, "Quality should be >= 0.6 for good signal")
        }
    }

    func testQualityLevelForNoisySignal() {
        // Given - Noisy signal with added random noise
        var samples = generateSimulatedPPGSignal(bpm: 72, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)
        samples = addNoise(to: samples, noiseLevel: 2000)

        // When
        let result = calculator.calculateHeartRate(irSamples: samples)

        // Then - May return nil or lower quality
        if let result = result {
            XCTAssertTrue(result.quality < 1.0, "Quality should be reduced for noisy signal")
        }
    }

    // MARK: - Reset Tests

    func testResetClearsInternalState() {
        // Given - Calculate with some data first
        let samples = generateSimulatedPPGSignal(bpm: 72, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)
        _ = calculator.calculateHeartRate(irSamples: samples)

        // When
        calculator.reset()

        // Then - Next calculation should work as fresh instance
        let result = calculator.calculateHeartRate(irSamples: samples)
        XCTAssertNotNil(result, "Should work after reset")
    }

    // MARK: - Trend Analysis Tests

    func testUnrealisticJumpDetection() {
        // Given - First reading at 70 BPM
        let samples1 = generateSimulatedPPGSignal(bpm: 70, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)
        _ = calculator.calculateHeartRate(irSamples: samples1)

        // When - Second reading jumps to 140 BPM (100% increase)
        let samples2 = generateSimulatedPPGSignal(bpm: 140, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)
        let result = calculator.calculateHeartRate(irSamples: samples2)

        // Then - Should reduce quality due to unrealistic jump
        if let result = result {
            XCTAssertTrue(result.quality < 0.9, "Quality should be reduced for unrealistic jump")
        }
    }

    // MARK: - Performance Tests

    func testPerformanceOfHeartRateCalculation() {
        // Given
        let samples = generateSimulatedPPGSignal(bpm: 72, duration: 3.0, samplingRate: 50.0, baselineOffset: 100000, amplitude: 5000)

        // When/Then
        measure {
            for _ in 0..<100 {
                _ = calculator.calculateHeartRate(irSamples: samples)
            }
        }
    }

    // MARK: - Helper Methods

    /// Generate a simulated PPG signal with specified parameters
    private func generateSimulatedPPGSignal(
        bpm: Double,
        duration: Double,
        samplingRate: Double,
        baselineOffset: Double,
        amplitude: Double
    ) -> [UInt32] {
        let totalSamples = Int(duration * samplingRate)
        let heartRateHz = bpm / 60.0
        var samples: [UInt32] = []

        for i in 0..<totalSamples {
            let time = Double(i) / samplingRate
            // Simulate PPG waveform as sine wave with baseline offset
            let signal = baselineOffset + amplitude * sin(2 * .pi * heartRateHz * time)
            samples.append(UInt32(max(0, signal)))
        }

        return samples
    }

    /// Add random noise to a signal
    private func addNoise(to samples: [UInt32], noiseLevel: Double) -> [UInt32] {
        return samples.map { sample in
            let noise = Double.random(in: -noiseLevel...noiseLevel)
            let newValue = Double(sample) + noise
            return UInt32(max(0, min(500000, newValue)))
        }
    }
}
