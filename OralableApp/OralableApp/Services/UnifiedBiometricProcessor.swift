//
//  UnifiedBiometricProcessor.swift
//  OralableApp
//
//  Created: December 24, 2025
//  Purpose: Unified biometric processor combining HR, SpO2, motion compensation,
//           and activity detection from all PPG channels and accelerometer.
//

import Foundation
import OralableCore

// MARK: - Result Types

/// Source of heart rate calculation
enum HRSource: String, Codable {
    case ir           // Primary: Infrared channel peak detection
    case green        // Fallback: Green channel peak detection
    case fft          // Fallback: FFT frequency analysis
    case unavailable  // No valid signal detected
}

/// Signal strength classification
enum SignalStrength: String, Codable {
    case none      // No signal detected (PI < 0.05%)
    case weak      // Weak signal (PI 0.05% - 0.2%)
    case moderate  // Moderate signal (PI 0.2% - 0.5%)
    case strong    // Strong signal (PI > 0.5%)

    init(perfusionIndex: Double) {
        switch perfusionIndex {
        case ..<0.0005: self = .none
        case 0.0005..<0.002: self = .weak
        case 0.002..<0.005: self = .moderate
        default: self = .strong
        }
    }
}

/// Processing method used
enum ProcessingMethod: String, Codable {
    case realtime  // Sample-by-sample processing
    case batch     // Array-based processing
}

/// Comprehensive biometric result from unified processor
struct BiometricResult {
    // Heart Rate
    let heartRate: Int                    // BPM (0 if unavailable)
    let heartRateQuality: Double          // 0.0 to 1.0
    let heartRateSource: HRSource         // Which channel/method produced HR

    // SpO2
    let spo2: Double                      // Percentage (0 if unavailable)
    let spo2Quality: Double               // 0.0 to 1.0

    // Signal Quality
    let perfusionIndex: Double            // AC/DC ratio (higher = better signal)
    let isWorn: Bool                      // Device on skin detection

    // Activity
    let activity: ActivityType            // From ActivityClassifier
    let motionLevel: Double               // 0.0 to 1.0 (accelerometer magnitude deviation)

    // Diagnostics
    let signalStrength: SignalStrength    // Derived from perfusion index
    let processingMethod: ProcessingMethod

    /// Empty result for when processing cannot produce valid output
    static let empty = BiometricResult(
        heartRate: 0,
        heartRateQuality: 0,
        heartRateSource: .unavailable,
        spo2: 0,
        spo2Quality: 0,
        perfusionIndex: 0,
        isWorn: false,
        activity: .relaxed,
        motionLevel: 0,
        signalStrength: .none,
        processingMethod: .realtime
    )
}

// MARK: - Configuration

/// Configuration for the biometric processor
struct BiometricConfiguration {
    // Sample rate (must match device)
    let sampleRate: Double

    // Window sizes in seconds
    let hrWindowSeconds: Double
    let spo2WindowSeconds: Double

    // Quality thresholds
    let minPerfusionIndex: Double    // For worn detection
    let minHRQuality: Double         // For valid HR output
    let minSpO2Quality: Double       // For valid SpO2 output

    // Motion threshold (in G, 1.0 = stationary)
    let motionThresholdG: Double

    // Physiological bounds
    let minBPM: Double
    let maxBPM: Double
    let minSpO2: Double
    let maxSpO2: Double

    // Filter coefficients
    let alphaLP: Double              // Low-pass smoothing
    let alphaHP: Double              // High-pass baseline tracking

    /// Default configuration for Oralable device (50 Hz)
    static let oralable = BiometricConfiguration(
        sampleRate: 50.0,
        hrWindowSeconds: 3.0,
        spo2WindowSeconds: 3.0,
        minPerfusionIndex: 0.001,
        minHRQuality: 0.5,
        minSpO2Quality: 0.6,
        motionThresholdG: 0.15,
        minBPM: 40,
        maxBPM: 180,
        minSpO2: 70,
        maxSpO2: 100,
        alphaLP: 0.15,
        alphaHP: 0.05
    )

    /// Configuration for ANR device (if different sample rate)
    static let anr = BiometricConfiguration(
        sampleRate: 100.0,
        hrWindowSeconds: 3.0,
        spo2WindowSeconds: 3.0,
        minPerfusionIndex: 0.001,
        minHRQuality: 0.5,
        minSpO2Quality: 0.6,
        motionThresholdG: 0.15,
        minBPM: 40,
        maxBPM: 180,
        minSpO2: 70,
        maxSpO2: 100,
        alphaLP: 0.15,
        alphaHP: 0.05
    )

    /// Computed window size in samples
    var hrWindowSize: Int {
        Int(sampleRate * hrWindowSeconds)
    }

    var spo2WindowSize: Int {
        Int(sampleRate * spo2WindowSeconds)
    }
}

// MARK: - Unified Biometric Processor

/// Thread-safe biometric processor using Swift actors.
/// Processes PPG (IR, Red, Green) and accelerometer data to calculate:
/// - Heart rate with quality score
/// - SpO2 with quality score
/// - Activity classification (relaxed, clenching, grinding, motion)
/// - Worn detection via perfusion index
actor UnifiedBiometricProcessor {

    // MARK: - Configuration

    private let config: BiometricConfiguration

    // MARK: - Sub-processors

    private let motionCompensator: MotionCompensator
    private let activityClassifier: ActivityClassifier

    // MARK: - Signal Buffers

    private var irBuffer: [Double]
    private var redBuffer: [Double]
    private var greenBuffer: [Double]
    private var accelMagnitudeBuffer: [Double]

    // MARK: - Filter State (for real-time processing)

    private var irLowPass: Double = 0
    private var irHighPass: Double = 0
    private var greenLowPass: Double = 0
    private var greenHighPass: Double = 0

    // MARK: - Baseline State

    private var irBaseline: Double = 0
    private var isBaselineInitialized: Bool = false

    // MARK: - Initialization

    /// Initialize with configuration
    /// - Parameter config: Biometric configuration (default: Oralable 50 Hz)
    init(config: BiometricConfiguration = .oralable) {
        self.config = config

        // Initialize sub-processors
        self.motionCompensator = MotionCompensator()
        self.activityClassifier = ActivityClassifier()

        // Initialize buffers with capacity
        let capacity = config.hrWindowSize
        self.irBuffer = []
        self.redBuffer = []
        self.greenBuffer = []
        self.accelMagnitudeBuffer = []

        irBuffer.reserveCapacity(capacity)
        redBuffer.reserveCapacity(capacity)
        greenBuffer.reserveCapacity(capacity)
        accelMagnitudeBuffer.reserveCapacity(capacity)
    }

    // MARK: - Real-time Processing

    /// Process a single frame of sensor data (called at sample rate, e.g., 50 Hz)
    /// - Parameters:
    ///   - ir: Infrared PPG value (primary HR source)
    ///   - red: Red PPG value (for SpO2)
    ///   - green: Green PPG value (backup HR source)
    ///   - accelX: Accelerometer X (raw, ~16384 = 1g)
    ///   - accelY: Accelerometer Y (raw)
    ///   - accelZ: Accelerometer Z (raw)
    /// - Returns: BiometricResult with all calculated values
    func process(
        ir: Double,
        red: Double,
        green: Double,
        accelX: Double,
        accelY: Double,
        accelZ: Double
    ) -> BiometricResult {

        // Stage 1: Motion detection
        let (motionLevel, isMoving) = calculateMotion(x: accelX, y: accelY, z: accelZ)

        // Stage 2: Motion compensation
        let compensatedIR = motionCompensator.filter(signal: ir, noiseReference: motionLevel)
        let compensatedRed = motionCompensator.filter(signal: red, noiseReference: motionLevel)
        let compensatedGreen = motionCompensator.filter(signal: green, noiseReference: motionLevel)

        // Stage 3: Activity classification
        let activity = activityClassifier.classify(ir: compensatedIR, accMagnitude: motionLevel + 1.0)

        // Stage 4: Update buffers with filtered values
        updateBuffers(ir: compensatedIR, red: compensatedRed, green: compensatedGreen, motion: motionLevel)

        // Stage 5: Check if we have enough data
        guard irBuffer.count >= config.hrWindowSize else {
            return BiometricResult(
                heartRate: 0,
                heartRateQuality: 0,
                heartRateSource: .unavailable,
                spo2: 0,
                spo2Quality: 0,
                perfusionIndex: 0,
                isWorn: false,
                activity: activity,
                motionLevel: motionLevel,
                signalStrength: .none,
                processingMethod: .realtime
            )
        }

        // Stage 6: Calculate perfusion index
        let perfusionIndex = calculatePerfusionIndex(signal: irBuffer)
        let signalStrength = SignalStrength(perfusionIndex: perfusionIndex)

        // Stage 7: Calculate heart rate (skip if too much motion)
        var heartRate = 0
        var heartRateQuality = 0.0
        var heartRateSource = HRSource.unavailable

        if activity != .motion {
            (heartRate, heartRateQuality, heartRateSource) = calculateHeartRate()
        }

        // Stage 8: Calculate SpO2 (skip if too much motion or weak signal)
        var spo2 = 0.0
        var spo2Quality = 0.0

        if activity != .motion && signalStrength != .none && signalStrength != .weak {
            (spo2, spo2Quality) = calculateSpO2()
        }

        // Stage 9: Determine worn status
        let isWorn = perfusionIndex > config.minPerfusionIndex &&
                     heartRate > 0 &&
                     heartRateQuality > config.minHRQuality

        // Suppress unused variable warning
        _ = isMoving

        return BiometricResult(
            heartRate: heartRate,
            heartRateQuality: heartRateQuality,
            heartRateSource: heartRateSource,
            spo2: spo2,
            spo2Quality: spo2Quality,
            perfusionIndex: perfusionIndex,
            isWorn: isWorn,
            activity: activity,
            motionLevel: motionLevel,
            signalStrength: signalStrength,
            processingMethod: .realtime
        )
    }

    // MARK: - Batch Processing

    /// Process arrays of samples (for historical data or CSV import)
    /// - Parameters:
    ///   - irSamples: Array of IR values
    ///   - redSamples: Array of Red values
    ///   - greenSamples: Array of Green values
    ///   - accelX: Array of accelerometer X values
    ///   - accelY: Array of accelerometer Y values
    ///   - accelZ: Array of accelerometer Z values
    /// - Returns: BiometricResult for the entire batch
    func processBatch(
        irSamples: [Double],
        redSamples: [Double],
        greenSamples: [Double],
        accelX: [Double],
        accelY: [Double],
        accelZ: [Double]
    ) -> BiometricResult {

        // Reset state for batch processing
        reset()

        // Process all samples
        var lastResult = BiometricResult.empty

        let count = min(irSamples.count, redSamples.count, greenSamples.count, accelX.count, accelY.count, accelZ.count)

        for i in 0..<count {
            lastResult = process(
                ir: irSamples[i],
                red: redSamples[i],
                green: greenSamples[i],
                accelX: accelX[i],
                accelY: accelY[i],
                accelZ: accelZ[i]
            )
        }

        // Return with batch processing method
        return BiometricResult(
            heartRate: lastResult.heartRate,
            heartRateQuality: lastResult.heartRateQuality,
            heartRateSource: lastResult.heartRateSource,
            spo2: lastResult.spo2,
            spo2Quality: lastResult.spo2Quality,
            perfusionIndex: lastResult.perfusionIndex,
            isWorn: lastResult.isWorn,
            activity: lastResult.activity,
            motionLevel: lastResult.motionLevel,
            signalStrength: lastResult.signalStrength,
            processingMethod: .batch
        )
    }

    // MARK: - Reset

    /// Reset all internal state (call when device reconnects or starting new session)
    func reset() {
        irBuffer.removeAll(keepingCapacity: true)
        redBuffer.removeAll(keepingCapacity: true)
        greenBuffer.removeAll(keepingCapacity: true)
        accelMagnitudeBuffer.removeAll(keepingCapacity: true)

        irLowPass = 0
        irHighPass = 0
        greenLowPass = 0
        greenHighPass = 0
        irBaseline = 0
        isBaselineInitialized = false

        motionCompensator.reset()
    }

    // MARK: - Private: Motion Detection

    private func calculateMotion(x: Double, y: Double, z: Double) -> (level: Double, isMoving: Bool) {
        // Normalize accelerometer values (16384 LSB/g for LIS2DTW12 at ±2g)
        let normX = x / 16384.0
        let normY = y / 16384.0
        let normZ = z / 16384.0

        // Calculate magnitude (should be ~1.0 when stationary due to gravity)
        let magnitude = sqrt(normX * normX + normY * normY + normZ * normZ)

        // Motion level is deviation from 1.0 (stationary)
        let motionLevel = abs(magnitude - 1.0)

        // Is moving if motion exceeds threshold
        let isMoving = motionLevel > config.motionThresholdG

        return (motionLevel, isMoving)
    }

    // MARK: - Private: Buffer Management

    private func updateBuffers(ir: Double, red: Double, green: Double, motion: Double) {
        // Apply bandpass filtering for IR
        let previousIR = irBuffer.last ?? ir
        irHighPass = config.alphaHP * (irHighPass + ir - previousIR)
        irLowPass = irLowPass + config.alphaLP * (irHighPass - irLowPass)

        // Apply bandpass filtering for Green
        let previousGreen = greenBuffer.last ?? green
        greenHighPass = config.alphaHP * (greenHighPass + green - previousGreen)
        greenLowPass = greenLowPass + config.alphaLP * (greenHighPass - greenLowPass)

        // Append filtered values
        irBuffer.append(irLowPass)
        redBuffer.append(red)  // Red uses raw for SpO2 AC/DC calculation
        greenBuffer.append(greenLowPass)
        accelMagnitudeBuffer.append(motion)

        // Trim to window size
        if irBuffer.count > config.hrWindowSize {
            irBuffer.removeFirst()
            redBuffer.removeFirst()
            greenBuffer.removeFirst()
            accelMagnitudeBuffer.removeFirst()
        }
    }

    // MARK: - Private: Perfusion Index

    private func calculatePerfusionIndex(signal: [Double]) -> Double {
        guard !signal.isEmpty else { return 0 }

        // DC component (mean)
        let dc = signal.reduce(0, +) / Double(signal.count)
        guard dc > 0 else { return 0 }

        // AC component (peak-to-peak)
        let maxVal = signal.max() ?? 0
        let minVal = signal.min() ?? 0
        let ac = maxVal - minVal

        // Perfusion Index = AC / DC
        return ac / dc
    }

    // MARK: - Private: Heart Rate Calculation

    private func calculateHeartRate() -> (bpm: Int, quality: Double, source: HRSource) {
        // Try IR channel first (primary)
        if let (bpm, quality) = calculateHeartRateFromSignal(irBuffer) {
            if quality >= config.minHRQuality {
                return (bpm, quality, .ir)
            }
        }

        // Try Green channel (backup)
        if let (bpm, quality) = calculateHeartRateFromSignal(greenBuffer) {
            if quality >= config.minHRQuality {
                return (bpm, quality, .green)
            }
        }

        // TODO: Add FFT fallback in future version

        return (0, 0, .unavailable)
    }

    private func calculateHeartRateFromSignal(_ signal: [Double]) -> (bpm: Int, quality: Double)? {
        guard signal.count >= config.hrWindowSize else { return nil }

        // Calculate statistics
        let mean = signal.reduce(0, +) / Double(signal.count)
        let sumSquaredDiff = signal.map { pow($0 - mean, 2) }.reduce(0, +)
        let stdDev = sqrt(sumSquaredDiff / Double(signal.count))

        // Signal too flat = poor quality
        guard stdDev > 1.0 else { return nil }

        // Adaptive threshold for peak detection
        let threshold = mean + (stdDev * 0.6)

        // Find peaks
        var peaks: [Int] = []
        for i in 2..<(signal.count - 2) {
            let current = signal[i]
            if current > signal[i-1] && current > signal[i+1] && current > threshold {
                // Ensure minimum distance between peaks (max 180 BPM)
                if let lastPeak = peaks.last {
                    let intervalSamples = i - lastPeak
                    let intervalSeconds = Double(intervalSamples) / config.sampleRate
                    if intervalSeconds < 0.33 { continue }  // 180 BPM limit
                }
                peaks.append(i)
            }
        }

        guard peaks.count >= 2 else { return nil }

        // Calculate inter-beat intervals
        var intervals: [Double] = []
        for j in 1..<peaks.count {
            let intervalSamples = Double(peaks[j] - peaks[j-1])
            let intervalSeconds = intervalSamples / config.sampleRate

            // Filter by physiological bounds
            if intervalSeconds > (60.0 / config.maxBPM) && intervalSeconds < (60.0 / config.minBPM) {
                intervals.append(intervalSeconds)
            }
        }

        guard !intervals.isEmpty else { return nil }

        // Use median interval (robust to outliers)
        let sortedIntervals = intervals.sorted()
        let medianInterval = sortedIntervals[sortedIntervals.count / 2]

        let bpm = Int(60.0 / medianInterval)

        // Validate BPM
        guard bpm >= Int(config.minBPM) && bpm <= Int(config.maxBPM) else { return nil }

        // Calculate quality score
        // Higher AC/DC ratio and more consistent intervals = higher quality
        let acdc = min(1.0, stdDev / max(1.0, abs(mean)))
        let peakFactor = min(1.0, Double(intervals.count) / 10.0)
        let quality = 0.6 * acdc + 0.4 * peakFactor

        return (bpm, max(0, min(1.0, quality)))
    }

    // MARK: - Private: SpO2 Calculation

    private func calculateSpO2() -> (spo2: Double, quality: Double) {
        guard redBuffer.count >= config.spo2WindowSize,
              irBuffer.count >= config.spo2WindowSize else {
            return (0, 0)
        }

        // Use raw (unfiltered) red buffer for SpO2
        // Note: We're using redBuffer which stores raw values

        // DC components (mean)
        let dcRed = redBuffer.reduce(0, +) / Double(redBuffer.count)
        let dcIR = irBuffer.reduce(0, +) / Double(irBuffer.count)

        guard dcRed > 0, dcIR > 0 else { return (0, 0) }

        // AC components (peak-to-peak)
        let acRed = (redBuffer.max() ?? 0) - (redBuffer.min() ?? 0)
        let acIR = (irBuffer.max() ?? 0) - (irBuffer.min() ?? 0)

        guard acRed > 0, acIR > 0 else { return (0, 0) }

        // R value (ratio of ratios)
        let ratioRed = acRed / dcRed
        let ratioIR = acIR / dcIR

        guard ratioIR > 0 else { return (0, 0) }

        let rValue = ratioRed / ratioIR

        // Empirical calibration curve
        // SpO2 = -45.060 * R^2 + 30.354 * R + 94.845
        let spo2 = -45.060 * pow(rValue, 2) + 30.354 * rValue + 94.845

        // Validate range
        guard spo2 >= config.minSpO2, spo2 <= config.maxSpO2 else { return (0, 0) }

        // Calculate quality from SNR
        let snrRed = ratioRed
        let snrIR = ratioIR
        let avgSNR = (snrRed + snrIR) / 2.0
        let quality = min(1.0, avgSNR / 0.1)

        return (round(spo2 * 10) / 10, max(0, min(1.0, quality)))
    }
}
