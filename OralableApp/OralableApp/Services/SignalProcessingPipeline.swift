//
//  ProcessingResult.swift
//  OralableApp
//
//  Created by John A Cogan on 22/12/2025.
//


import Foundation
import OralableCore

/// A data structure to hold the results from the processing pipeline.
struct ProcessingResult {
    let heartRate: Int
    let spo2: Int
    let activity: ActivityType
}

/// An actor that encapsulates the entire signal processing chain.
///
/// By using an actor, we ensure that all biometric calculations happen off the main thread
/// and that access to its internal state (like history buffers) is synchronized and data-race free.
actor SignalProcessingPipeline {
    private let motionCompensator = MotionCompensator()
    private let activityClassifier = ActivityClassifier()

    // Buffers for placeholder HR/SpO2 algorithms
    private var irSignalBuffer: [Double] = []
    private let bufferSize = 100 // Process every 100 samples for HR/SpO2

    /// Processes raw sensor data to calculate biometrics.
    /// - Parameters:
    ///   - ir: The infrared signal value.
    ///   - red: The red signal value.
    ///   - green: The green signal value.
    ///   - accelerometer: The accelerometer data.
    /// - Returns: A `ProcessingResult` containing calculated biometrics.
    func process(ir: Double, red: Double, green: Double, accelerometer: AccelerometerData) -> ProcessingResult {
        // Calculate magnitude from raw accelerometer data (assuming 16384.0 = 1g)
        let normX = Double(accelerometer.x) / 16384.0
        let normY = Double(accelerometer.y) / 16384.0
        let normZ = Double(accelerometer.z) / 16384.0
        let accMagnitude = sqrt(normX * normX + normY * normY + normZ * normZ)

        // 1. Classify activity to understand the context of the signal.
        let activity = activityClassifier.classify(ir: ir, accMagnitude: accMagnitude)

        // If motion is excessive, the optical signal is unreliable. Return early.
        if activity == .motion {
            return ProcessingResult(heartRate: 0, spo2: 0, activity: activity)
        }

        // 2. Compensate for motion noise in the optical signals.
        let compensatedIR = motionCompensator.filter(signal: ir, noiseReference: accMagnitude)
        let compensatedRed = motionCompensator.filter(signal: red, noiseReference: accMagnitude)

        // 3. Calculate HR and SpO2 (using placeholder logic for demonstration).
        // A real-world implementation would use more sophisticated algorithms (e.g., FFT).
        irSignalBuffer.append(compensatedIR)
        if irSignalBuffer.count > bufferSize {
            irSignalBuffer.removeFirst()
        }

        var calculatedHR = 0
        var calculatedSpO2 = 0

        if irSignalBuffer.count == bufferSize {
            // --- Placeholder HR/SpO2 Calculation ---
            let dcEstimate = irSignalBuffer.reduce(0, +) / Double(bufferSize)
            let amplitude = (irSignalBuffer.max() ?? dcEstimate) - (irSignalBuffer.min() ?? dcEstimate)
            calculatedHR = 60 + Int(amplitude / 500.0) % 40 // Fake HR based on amplitude
            calculatedSpO2 = 98 - Int.random(in: 0...3) // Fake SpO2
            // --- End Placeholder ---

            // Clamp values to a realistic range.
            calculatedHR = max(40, min(180, calculatedHR))
            calculatedSpO2 = max(90, min(100, calculatedSpO2))
        }

        return ProcessingResult(heartRate: calculatedHR, spo2: calculatedSpO2, activity: activity)
    }
}
