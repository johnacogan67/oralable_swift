//
//  UnifiedBiometricProcessorTests.swift
//  OralableAppTests
//
//  Created: February 16, 2026
//  Purpose: Unit tests for UnifiedBiometricProcessor signal processing
//

import XCTest
@testable import OralableApp

final class UnifiedBiometricProcessorTests: XCTestCase {

    // MARK: - Helpers

    /// Feed `count` samples of a constant signal through the processor one at a time.
    /// Stationary accelerometer values (0, 0, 16384) approximate 1g on the Z axis.
    private func feedConstantSamples(
        to processor: UnifiedBiometricProcessor,
        count: Int,
        ir: Double = 1000.0,
        red: Double = 1000.0,
        green: Double = 1000.0
    ) async -> BiometricResult {
        var result = BiometricResult.empty
        for _ in 0..<count {
            result = await processor.process(
                ir: ir, red: red, green: green,
                accelX: 0, accelY: 0, accelZ: 16384
            )
        }
        return result
    }

    // MARK: - Tests

    /// Feeding fewer than 150 samples (hrWindowSize for 50 Hz * 3 s) should yield heartRate == 0.
    func testProcessReturnsZeroHRForInsufficientData() async {
        let processor = UnifiedBiometricProcessor()
        let result = await feedConstantSamples(to: processor, count: 100)
        XCTAssertEqual(result.heartRate, 0, "Heart rate should be 0 when fewer than hrWindowSize samples have been fed")
    }

    /// Generate a 6-second sinusoidal IR signal at 1.2 Hz (72 BPM) and verify detection.
    func testHeartRateWithSyntheticSine() async {
        let processor = UnifiedBiometricProcessor()
        let sampleRate = 50.0
        let durationSeconds = 6.0
        let sampleCount = Int(sampleRate * durationSeconds) // 300
        let frequencyHz = 1.2 // 72 BPM

        var lastResult = BiometricResult.empty
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            // Sinusoidal IR signal with DC offset to stay positive
            let ir = 10000.0 + 500.0 * sin(2.0 * .pi * frequencyHz * t)
            let red = 10000.0 + 300.0 * sin(2.0 * .pi * frequencyHz * t)
            let green = 10000.0 + 200.0 * sin(2.0 * .pi * frequencyHz * t)

            lastResult = await processor.process(
                ir: ir, red: red, green: green,
                accelX: 0, accelY: 0, accelZ: 16384
            )
        }

        // Allow a tolerance of +/-10 BPM around the expected 72 BPM
        let expectedBPM = 72
        XCTAssertTrue(
            lastResult.heartRate >= expectedBPM - 10 && lastResult.heartRate <= expectedBPM + 10,
            "Heart rate \(lastResult.heartRate) should be within +/-10 of \(expectedBPM) BPM"
        )
    }

    /// Extreme Red/IR ratios that produce rValue > 3.4 should result in spo2 == 0.
    func testSpO2RValueBoundsRejectsExtremeValues() async {
        let processor = UnifiedBiometricProcessor()

        // To produce rValue > 3.4, we need (acRed/dcRed) >> (acIR/dcIR).
        // Use very high-amplitude Red with low-amplitude IR.
        let sampleCount = 200
        let sampleRate = 50.0

        var irSamples = [Double]()
        var redSamples = [Double]()
        var greenSamples = [Double]()
        var accelX = [Double]()
        var accelY = [Double]()
        var accelZ = [Double]()

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            let freq = 1.2
            // IR has tiny AC relative to DC -> small ratioIR
            let ir = 10000.0 + 1.0 * sin(2.0 * .pi * freq * t)
            // Red has huge AC relative to DC -> large ratioRed
            let red = 100.0 + 500.0 * sin(2.0 * .pi * freq * t)
            let green = 10000.0 + 200.0 * sin(2.0 * .pi * freq * t)

            irSamples.append(ir)
            redSamples.append(red)
            greenSamples.append(green)
            accelX.append(0)
            accelY.append(0)
            accelZ.append(16384)
        }

        let result = await processor.processBatch(
            irSamples: irSamples,
            redSamples: redSamples,
            greenSamples: greenSamples,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ
        )

        XCTAssertEqual(result.spo2, 0, "SpO2 should be 0 when R-value is outside physiological bounds")
    }

    /// Stationary accelerometer (0, 0, 16384) should produce low motionLevel and activity != .motion.
    func testMotionDetectionStationary() async {
        let processor = UnifiedBiometricProcessor()
        let result = await feedConstantSamples(to: processor, count: 200)

        XCTAssertLessThan(result.motionLevel, 0.1, "Motion level should be small for stationary accel")
        XCTAssertNotEqual(result.activity, .motion, "Activity should not be .motion when stationary")
    }

    /// High accelerometer values should produce elevated motionLevel.
    func testMotionDetectionMoving() async {
        let processor = UnifiedBiometricProcessor()

        var lastResult = BiometricResult.empty
        for _ in 0..<200 {
            lastResult = await processor.process(
                ir: 10000, red: 10000, green: 10000,
                accelX: 16384, accelY: 16384, accelZ: 16384
            )
        }

        // Magnitude = sqrt(3) * 1g ~= 1.732g, deviation from 1g ~= 0.732
        XCTAssertGreaterThan(lastResult.motionLevel, 0, "Motion level should be positive for high accel values")
    }

    /// After reset, insufficient data should yield heartRate == 0.
    func testResetClearsBuffers() async {
        let processor = UnifiedBiometricProcessor()

        // Fill with enough samples to potentially compute HR
        _ = await feedConstantSamples(to: processor, count: 200)

        // Reset internal state
        await processor.reset()

        // Feed only 10 samples (well under the 150 hrWindowSize)
        let result = await feedConstantSamples(to: processor, count: 10)

        XCTAssertEqual(result.heartRate, 0, "Heart rate should be 0 after reset with insufficient new data")
    }
}
