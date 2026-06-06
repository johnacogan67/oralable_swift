//
//  UnifiedBiometricProcessorSpO2Tests.swift
//  OralableAppTests
//
//  Regression tests for live SpO2 processing.
//

import XCTest
@testable import OralableApp

final class UnifiedBiometricProcessorSpO2Tests: XCTestCase {

    /// A realistic live red/IR waveform should produce a non-zero SpO2 estimate.
    func testSpO2UsesRawIRSignalForRatioCalculation() async {
        let processor = UnifiedBiometricProcessor()
        let sampleRate = 50.0
        let sampleCount = 300
        let frequencyHz = 1.2

        var irSamples = [Double]()
        var redSamples = [Double]()
        var greenSamples = [Double]()
        var accelX = [Double]()
        var accelY = [Double]()
        var accelZ = [Double]()

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            irSamples.append(10_000.0 + 500.0 * sin(2.0 * .pi * frequencyHz * t))
            redSamples.append(10_000.0 + 300.0 * sin(2.0 * .pi * frequencyHz * t))
            greenSamples.append(10_000.0 + 200.0 * sin(2.0 * .pi * frequencyHz * t))
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

        XCTAssertGreaterThan(result.spo2, 90, "SpO2 should be calculated from raw red/IR AC/DC ratios")
        XCTAssertLessThanOrEqual(result.spo2, 100)
        XCTAssertGreaterThan(result.spo2Quality, 0)
    }
}
