//
//  SpO2CalculatorTests.swift
//  OralableAppTests
//
//  Created: November 11, 2025
//  Purpose: Unit tests for SpO2Calculator pulse oximetry algorithm
//

import XCTest
@testable import MAMDiagnostics

class SpO2CalculatorTests: XCTestCase {

    var calculator: SpO2Calculator!

    override func setUp() {
        super.setUp()
        calculator = SpO2Calculator()
    }

    override func tearDown() {
        calculator = nil
        super.tearDown()
    }

    // MARK: - Input Validation Tests

    func testCalculateSpO2WithInsufficientData() {
        // Given - Less than minimum required samples (150)
        let redSamples = [Int32](repeating: 50000, count: 100)
        let irSamples = [Int32](repeating: 50000, count: 100)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNil(result, "Should return nil for insufficient data")
    }

    func testCalculateSpO2WithMismatchedArrayLengths() {
        // Given - Different lengths for red and IR
        let redSamples = [Int32](repeating: 50000, count: 150)
        let irSamples = [Int32](repeating: 50000, count: 100)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNil(result, "Should return nil for mismatched array lengths")
    }

    func testCalculateSpO2WithZeroValues() {
        // Given - All zero values
        let redSamples = [Int32](repeating: 0, count: 150)
        let irSamples = [Int32](repeating: 0, count: 150)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNil(result, "Should return nil for zero values")
    }

    // MARK: - Simulated PPG Signal Tests

    func testCalculateSpO2WithSimulated98Percent() {
        // Given - Simulated PPG signals for 98% SpO2
        // R value ≈ 0.54 for 98% SpO2 (based on calibration curve)
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 98.0, duration: 3.0, samplingRate: 50.0)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNotNil(result, "Should calculate SpO2 for simulated signal")
        if let (spo2, quality) = result {
            XCTAssertTrue(spo2 >= 95 && spo2 <= 100, "SpO2 should be between 95-100%, got \(spo2)")
            XCTAssertTrue(quality >= 0.6, "Quality should be above threshold for good signal")
        }
    }

    func testCalculateSpO2WithSimulated95Percent() {
        // Given - Simulated PPG signals for 95% SpO2
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 95.0, duration: 3.0, samplingRate: 50.0)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNotNil(result, "Should calculate SpO2 for simulated signal")
        if let (spo2, quality) = result {
            XCTAssertTrue(spo2 >= 90 && spo2 <= 100, "SpO2 should be between 90-100%, got \(spo2)")
            XCTAssertTrue(quality >= 0.6, "Quality should be above threshold")
        }
    }

    // MARK: - Boundary Value Tests

    func testCalculateSpO2RejectsValuesBelowRange() {
        // Given - Simulated signal that would produce SpO2 < 70%
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 65.0, duration: 3.0, samplingRate: 50.0)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then - Should reject values outside valid range (70-100%)
        if let (spo2, _) = result {
            XCTAssertTrue(spo2 >= 70 && spo2 <= 100, "SpO2 should be within valid range 70-100%")
        }
    }

    func testCalculateSpO2RejectsValuesAbove100() {
        // Given - Invalid signal that might produce SpO2 > 100%
        let redSamples = [Int32](repeating: 5000, count: 150)  // Very low red
        let irSamples = [Int32](repeating: 100000, count: 150)  // High IR

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then - Should reject or clamp to valid range
        if let (spo2, _) = result {
            XCTAssertTrue(spo2 <= 100, "SpO2 should not exceed 100%")
        }
    }

    // MARK: - Quality Assessment Tests

    func testQualityAssessmentForGoodSignal() {
        // Given - Good quality signal with sufficient amplitude and low noise
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 98.0, duration: 3.0, samplingRate: 50.0)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNotNil(result)
        if let (_, quality) = result {
            XCTAssertTrue(quality >= 0.6, "Quality should be good for clean signal, got \(quality)")
        }
    }

    func testQualityAssessmentForPoorSignal() {
        // Given - Poor quality signal with high noise
        var (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 98.0, duration: 3.0, samplingRate: 50.0)
        redSamples = addNoise(to: redSamples, noiseLevel: 15000)
        irSamples = addNoise(to: irSamples, noiseLevel: 15000)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then - May return nil or lower quality
        if let (_, quality) = result {
            XCTAssertTrue(quality < 1.0, "Quality should be reduced for noisy signal")
        }
    }

    func testRejectsLowQualitySignal() {
        // Given - Very poor signal quality
        let redSamples = generateConstantWithSmallVariation(baseValue: 50000, variation: 10, count: 150)
        let irSamples = generateConstantWithSmallVariation(baseValue: 50000, variation: 10, count: 150)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNil(result, "Should reject signal with insufficient variability")
    }

    // MARK: - Ratio-of-Ratios Method Tests

    func testRatioOfRatiosCalculation() {
        // Given - Known R value should produce predictable SpO2
        // R = 0.5 should give SpO2 around 99% based on calibration curve
        // SpO2 = -45.060 * R^2 + 30.354 * R + 94.845
        let expectedSpO2 = -45.060 * pow(0.5, 2) + 30.354 * 0.5 + 94.845  // ≈ 99.38%

        // Simulate signal with R ≈ 0.5
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetR: 0.5, duration: 3.0, samplingRate: 50.0)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then
        if let (spo2, _) = result {
            // Allow some tolerance due to signal processing
            XCTAssertTrue(abs(spo2 - expectedSpO2) < 5.0, "SpO2 calculation should match calibration curve")
        }
    }

    // MARK: - Quick Calculation Method Tests

    func testQuickCalculationWithoutQuality() {
        // Given
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 98.0, duration: 3.0, samplingRate: 50.0)

        // When
        let spo2 = calculator.calculateSpO2(redSamples: redSamples, irSamples: irSamples)

        // Then
        XCTAssertNotNil(spo2, "Quick calculation should return SpO2 value")
        if let spo2 = spo2 {
            XCTAssertTrue(spo2 >= 90 && spo2 <= 100, "SpO2 should be in valid range")
        }
    }

    // MARK: - Performance Tests

    func testPerformanceOfSpO2Calculation() {
        // Given
        let (redSamples, irSamples) = generateSimulatedPulseOximetrySignals(targetSpO2: 98.0, duration: 3.0, samplingRate: 50.0)

        // When/Then
        measure {
            for _ in 0..<100 {
                _ = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)
            }
        }
    }

    // MARK: - Signal Component Tests

    func testDCComponentCalculation() {
        // Given - Constant signal should have DC component equal to signal value
        let constantValue: Int32 = 75000
        let redSamples = [Int32](repeating: constantValue, count: 150)
        let irSamples = [Int32](repeating: constantValue, count: 150)

        // When
        let result = calculator.calculateSpO2WithQuality(redSamples: redSamples, irSamples: irSamples)

        // Then - Should return nil (no AC component)
        XCTAssertNil(result, "Should return nil for constant signal (no pulsatile component)")
    }

    // MARK: - Helper Methods

    /// Generate simulated pulse oximetry signals targeting specific SpO2
    private func generateSimulatedPulseOximetrySignals(
        targetSpO2: Double,
        duration: Double,
        samplingRate: Double
    ) -> ([Int32], [Int32]) {
        // Convert target SpO2 to R value using inverse of calibration curve
        // SpO2 = -45.060 * R^2 + 30.354 * R + 94.845
        // Solve for R (simplified approximation)
        let targetR = (110.0 - targetSpO2) / 25.0  // Linear approximation

        return generateSimulatedPulseOximetrySignals(targetR: targetR, duration: duration, samplingRate: samplingRate)
    }

    /// Generate simulated pulse oximetry signals with target R value
    private func generateSimulatedPulseOximetrySignals(
        targetR: Double,
        duration: Double,
        samplingRate: Double
    ) -> ([Int32], [Int32]) {
        let totalSamples = Int(duration * samplingRate)
        let heartRateHz = 1.2  // 72 BPM

        var redSamples: [Int32] = []
        var irSamples: [Int32] = []

        // Signal parameters
        let redDC = 80000.0
        let irDC = 100000.0
        let redAC = targetR * 0.05 * redDC  // AC amplitude based on target R
        let irAC = 0.05 * irDC

        for i in 0..<totalSamples {
            let time = Double(i) / samplingRate

            // Simulate pulsatile signal
            let pulse = sin(2 * .pi * heartRateHz * time)

            let redValue = redDC + redAC * pulse
            let irValue = irDC + irAC * pulse

            redSamples.append(Int32(redValue))
            irSamples.append(Int32(irValue))
        }

        return (redSamples, irSamples)
    }

    /// Generate constant signal with small random variation
    private func generateConstantWithSmallVariation(baseValue: Int32, variation: Int32, count: Int) -> [Int32] {
        return (0..<count).map { _ in
            baseValue + Int32.random(in: -variation...variation)
        }
    }

    /// Add random noise to a signal
    private func addNoise(to samples: [Int32], noiseLevel: Double) -> [Int32] {
        return samples.map { sample in
            let noise = Double.random(in: -noiseLevel...noiseLevel)
            let newValue = Double(sample) + noise
            return Int32(max(0, min(500000, newValue)))
        }
    }
}
