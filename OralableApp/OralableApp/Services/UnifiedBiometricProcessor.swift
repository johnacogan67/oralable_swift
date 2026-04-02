//
//  UnifiedBiometricProcessor.swift
//  OralableApp
//
//  Created: December 24, 2025
//  Purpose: Unified biometric processor combining HR, SpO2, motion compensation,
//           and activity detection from all PPG channels and accelerometer.
//

import Foundation
import Accelerate
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

    /// Temporalis Fatigue Index (0–100%) — matches research `tanh` composite from IR-DC / AC trends.
    let tfiPercent: Double

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
        processingMethod: .realtime,
        tfiPercent: 50
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

    /// Default configuration for Oralable device (50 Hz)
    static let oralable = BiometricConfiguration(
        sampleRate: 50.0,
        hrWindowSeconds: 3.0,
        spo2WindowSeconds: 3.0,
        minPerfusionIndex: 0.001,
        minHRQuality: 0.5,
        minSpO2Quality: 0.6,
        motionThresholdG: TemporalisProtocolReference.syncTapMotionThresholdG,
        minBPM: 40,
        maxBPM: 180,
        minSpO2: 70,
        maxSpO2: 100
    )

    /// Configuration for ANR device (if different sample rate)
    static let anr = BiometricConfiguration(
        sampleRate: 100.0,
        hrWindowSeconds: 3.0,
        spo2WindowSeconds: 3.0,
        minPerfusionIndex: 0.001,
        minHRQuality: 0.5,
        minSpO2Quality: 0.6,
        motionThresholdG: TemporalisProtocolReference.syncTapMotionThresholdG,
        minBPM: 40,
        maxBPM: 180,
        minSpO2: 70,
        maxSpO2: 100
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

    // MARK: - Signal Buffers (CircularBuffer for O(1) append)

    private var irBuffer: CircularBuffer<Double>
    private var redBuffer: CircularBuffer<Double>
    private var greenBuffer: CircularBuffer<Double>
    private var accelMagnitudeBuffer: CircularBuffer<Double>

    // MARK: - PPG filtering (AlgorithmSpec HR bandpass 0.5–8 Hz, real-time `processSample`)

    private let irFilter: ButterworthFilter
    private let redFilter: ButterworthFilter
    private let greenFilter: ButterworthFilter

    /// IR DC / occlusion track (low-pass per `AlgorithmSpec`, scipy `(b,a)` via `TransferFunctionFilter`).
    private let irdcProcessor: IRDCProcessor

    // MARK: - Temporalis MAM inference

    private let mamInferenceManager: MAMInferenceManager
    private let greenTemporalisBandpass = TransferFunctionFilter.temporalisACBandpass()
    private let redTemporalisBandpass = TransferFunctionFilter.temporalisACBandpass()

    // MARK: - Temporalis Fatigue Index (session trend, 5 s decimation)

    private var lastIRDCForTFI: Double = 0
    private var lastGreenACForTFI: Double = 0
    private var tfiDecimationCounter: Int = 0
    private var tfiSliceIR: [Double] = []
    private var tfiSliceGreenAC: [Double] = []
    private var tfiTimeSeconds: [Double] = []
    private var tfiDCMeans: [Double] = []
    private var tfiACRMS: [Double] = []
    private var tfiNextTimeStamp: Double = 0
    private let tfiDecimationSamples: Int = 250 // 5 s @ 50 Hz
    private let tfiMaxPoints: Int = 720 // up to 1 h of 5 s bins

    // MARK: - Baseline State

    private var irBaseline: Double = 0
    private var isBaselineInitialized: Bool = false
    private var lastStableSpO2: Double?

    // MARK: - FFT Setup (cached for reuse; creating FFT plans is expensive)

    /// Cached FFT setup for heart rate frequency analysis.
    /// The log2n value corresponds to a 256-point FFT (log2(256) = 8), which gives
    /// ~5.12 seconds of data at 50 Hz and frequency resolution of ~0.195 Hz (~11.7 BPM).
    private var fftSetup: FFTSetupD?
    /// The log2 of the FFT size currently allocated.
    private var fftLog2n: vDSP_Length = 0

    // MARK: - Initialization

    /// Initialize with configuration
    /// - Parameter config: Biometric configuration (default: Oralable 50 Hz)
    init(config: BiometricConfiguration = .oralable) {
        self.config = config

        // Initialize sub-processors
        self.motionCompensator = MotionCompensator()
        self.activityClassifier = ActivityClassifier()

        // Initialize circular buffers with fixed capacity (O(1) append, no removeFirst)
        let capacity = config.hrWindowSize
        self.irBuffer = CircularBuffer<Double>(capacity: capacity)
        self.redBuffer = CircularBuffer<Double>(capacity: capacity)
        self.greenBuffer = CircularBuffer<Double>(capacity: capacity)
        self.accelMagnitudeBuffer = CircularBuffer<Double>(capacity: capacity)
        self.mamInferenceManager = MAMInferenceManager()

        let fs = config.sampleRate
        self.irFilter = ButterworthFilter.hrBandpass(sampleRate: fs)
        self.redFilter = ButterworthFilter.hrBandpass(sampleRate: fs)
        self.greenFilter = ButterworthFilter.hrBandpass(sampleRate: fs)
        self.irdcProcessor = IRDCProcessor(sampleRate: fs)
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
        let (motionLevel, activity) = ingestSample(
            ir: ir,
            red: red,
            green: green,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ
        )
        return computeSummaryResult(activity: activity, motionLevel: motionLevel, processingMethod: .realtime)
    }

    // MARK: - Batch Processing

    /// Process arrays of samples (e.g. CSV import with `resetState: true`, or live 100 ms windows with `resetState: false`).
    /// Runs filters and buffers for every sample, then computes HR / SpO2 / TFI once at the end.
    func processBatch(
        irSamples: [Double],
        redSamples: [Double],
        greenSamples: [Double],
        accelX: [Double],
        accelY: [Double],
        accelZ: [Double],
        resetState: Bool = true
    ) -> BiometricResult {
        if resetState {
            reset()
        }

        let count = min(
            irSamples.count,
            redSamples.count,
            greenSamples.count,
            accelX.count,
            accelY.count,
            accelZ.count
        )

        var lastMotion: Double = 0
        var lastActivity: ActivityType = .relaxed

        for i in 0..<count {
            let (m, a) = ingestSample(
                ir: irSamples[i],
                red: redSamples[i],
                green: greenSamples[i],
                accelX: accelX[i],
                accelY: accelY[i],
                accelZ: accelZ[i]
            )
            lastMotion = m
            lastActivity = a
        }

        let method: ProcessingMethod = resetState ? .batch : .realtime
        return computeSummaryResult(activity: lastActivity, motionLevel: lastMotion, processingMethod: method)
    }

    // MARK: - Temporalis streaming hook

    func setOnTemporalisProbabilities(_ handler: (@Sendable (TemporalisProbabilities) -> Void)?) {
        mamInferenceManager.onTemporalisProbabilities = handler
    }

    // MARK: - Reset

    /// Reset all internal state (call when device reconnects or starting new session)
    func reset() {
        irBuffer.removeAll()
        redBuffer.removeAll()
        greenBuffer.removeAll()
        accelMagnitudeBuffer.removeAll()

        irBaseline = 0
        isBaselineInitialized = false
        lastStableSpO2 = nil

        motionCompensator.reset()
        irFilter.reset()
        redFilter.reset()
        greenFilter.reset()
        irdcProcessor.reset()
        greenTemporalisBandpass.reset()
        redTemporalisBandpass.reset()
        mamInferenceManager.reset()

        lastIRDCForTFI = 0
        lastGreenACForTFI = 0
        tfiDecimationCounter = 0
        tfiSliceIR.removeAll(keepingCapacity: false)
        tfiSliceGreenAC.removeAll(keepingCapacity: false)
        tfiTimeSeconds.removeAll(keepingCapacity: false)
        tfiDCMeans.removeAll(keepingCapacity: false)
        tfiACRMS.removeAll(keepingCapacity: false)
        tfiNextTimeStamp = 0

        // Note: FFT setup is intentionally NOT destroyed on reset.
        // It is reused across sessions since the FFT size rarely changes.
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetupD(setup)
            fftSetup = nil
            fftLog2n = 0
        }
    }

    // MARK: - Private: Sample ingestion & summary

    /// Per-sample pipeline: motion, compensation, activity, buffers, TFI decimation — no HR/SpO2.
    private func ingestSample(
        ir: Double,
        red: Double,
        green: Double,
        accelX: Double,
        accelY: Double,
        accelZ: Double
    ) -> (motionLevel: Double, activity: ActivityType) {
        let (motionLevel, accelMagnitude, isMoving) = calculateMotion(x: accelX, y: accelY, z: accelZ)

        let compensatedIR = motionCompensator.filter(signal: ir, noiseReference: motionLevel)
        let compensatedRed = motionCompensator.filter(signal: red, noiseReference: motionLevel)
        let compensatedGreen = motionCompensator.filter(signal: green, noiseReference: motionLevel)

        let activity = activityClassifier.classify(ir: compensatedIR, accMagnitude: motionLevel + 1.0)

        updateBuffers(
            ir: compensatedIR,
            red: compensatedRed,
            green: compensatedGreen,
            motion: motionLevel,
            accelMagnitude: accelMagnitude,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ
        )
        appendTFISegmentFromLiveSample()
        _ = isMoving

        return (motionLevel, activity)
    }

    private func computeSummaryResult(
        activity: ActivityType,
        motionLevel: Double,
        processingMethod: ProcessingMethod
    ) -> BiometricResult {
        let tfiNow = computeTFIPercent()
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
                processingMethod: processingMethod,
                tfiPercent: tfiNow
            )
        }

        let perfusionIndex = calculatePerfusionIndex(signal: irBuffer.all)
        let signalStrength = SignalStrength(perfusionIndex: perfusionIndex)

        var heartRate = 0
        var heartRateQuality = 0.0
        var heartRateSource = HRSource.unavailable

        if activity != .motion {
            (heartRate, heartRateQuality, heartRateSource) = calculateHeartRate()
        }

        var spo2 = 0.0
        var spo2Quality = 0.0

        if activity != .motion && signalStrength != .none && signalStrength != .weak {
            (spo2, spo2Quality) = calculateSpO2()
            spo2 = stabilizeSpO2Estimate(raw: spo2, quality: spo2Quality, motionLevel: motionLevel)
        }

        let isWorn = perfusionIndex > config.minPerfusionIndex &&
            heartRate > 0 &&
            heartRateQuality > config.minHRQuality

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
            processingMethod: processingMethod,
            tfiPercent: tfiNow
        )
    }

    // MARK: - Private: Motion Detection

    private func calculateMotion(x: Double, y: Double, z: Double) -> (level: Double, magnitude: Double, isMoving: Bool) {
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

        return (motionLevel, magnitude, isMoving)
    }

    // MARK: - Private: TFI (Python `calculate_tfi` parity — decimated regression)

    private func appendTFISegmentFromLiveSample() {
        tfiDecimationCounter += 1
        tfiSliceIR.append(lastIRDCForTFI)
        tfiSliceGreenAC.append(lastGreenACForTFI)
        guard tfiDecimationCounter >= tfiDecimationSamples else { return }
        tfiDecimationCounter = 0
        guard !tfiSliceIR.isEmpty else { return }
        let dcMean = tfiSliceIR.reduce(0, +) / Double(tfiSliceIR.count)
        let ms = tfiSliceGreenAC.map { $0 * $0 }.reduce(0, +) / Double(tfiSliceGreenAC.count)
        let acRms = sqrt(max(0, ms))
        tfiSliceIR.removeAll(keepingCapacity: true)
        tfiSliceGreenAC.removeAll(keepingCapacity: true)
        tfiTimeSeconds.append(tfiNextTimeStamp)
        tfiNextTimeStamp += 5.0
        tfiDCMeans.append(dcMean)
        tfiACRMS.append(acRms)
        while tfiTimeSeconds.count > tfiMaxPoints {
            tfiTimeSeconds.removeFirst()
            tfiDCMeans.removeFirst()
            tfiACRMS.removeFirst()
        }
    }

    private func computeTFIPercent() -> Double {
        guard tfiTimeSeconds.count >= 12 else { return 50.0 }
        let dcSlope = linearSlope(x: tfiTimeSeconds, y: tfiDCMeans)
        let acSlope = linearSlope(x: tfiTimeSeconds, y: tfiACRMS)
        let dcScale = robustScale(tfiDCMeans)
        let acScale = robustScale(tfiACRMS)
        let dur = (tfiTimeSeconds.last ?? 0) - (tfiTimeSeconds.first ?? 0)
        guard dur > 1, dcScale > 0, acScale > 0 else { return 50.0 }
        let dcContrib = -(dcSlope * dur) / dcScale
        let acContrib = -(acSlope * dur) / acScale
        let combined = 0.5 * dcContrib + 0.5 * acContrib
        return BiometricProcessor.temporalisFatigueIndex(driftCombined: combined)
    }

    private func linearSlope(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            num += dx * (y[i] - meanY)
            den += dx * dx
        }
        guard den > 1e-12 else { return 0 }
        return num / den
    }

    private func robustScale(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 1 }
        let s = values.sorted()
        let i5 = min(s.count - 1, max(0, (s.count * 5) / 100))
        let i95 = min(s.count - 1, max(0, (s.count * 95) / 100))
        let spread = abs(s[i95] - s[i5])
        if spread < 1e-9 {
            let mean = s.reduce(0, +) / Double(s.count)
            let varsum = s.map { pow($0 - mean, 2) }.reduce(0, +) / Double(s.count)
            return sqrt(varsum) + 1e-9
        }
        return spread
    }

    // MARK: - Private: Buffer Management

    private func updateBuffers(ir: Double, red: Double, green: Double, motion: Double, accelMagnitude: Double, accelX: Double, accelY: Double, accelZ: Double) {
        let irBP = irFilter.processSample(ir)
        let greenBP = greenFilter.processSample(green)
        _ = redFilter.processSample(red)

        let irDCFiltered = irdcProcessor.processSample(ir).dcValue

        irBuffer.append(irBP)
        redBuffer.append(red)
        greenBuffer.append(greenBP)
        accelMagnitudeBuffer.append(motion)

        let greenAC = greenTemporalisBandpass.processSample(green)
        let redAC = redTemporalisBandpass.processSample(red)
        lastIRDCForTFI = irDCFiltered
        lastGreenACForTFI = greenAC
        let scale = 16384.0
        mamInferenceManager.addSample(
            greenAC: greenAC,
            irDC: irDCFiltered,
            redAC: redAC,
            accelX: accelX / scale,
            accelY: accelY / scale,
            accelZ: accelZ / scale
        )
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
        // Try IR channel first (primary peak detection)
        let irSignal = irBuffer.all
        if let (peakBpm, peakQuality) = calculateHeartRateFromSignal(irSignal) {
            if peakQuality >= config.minHRQuality {
                // Cross-validate with FFT if we have enough samples
                let (fftBpm, _) = calculateHeartRateFFT(from: irSignal, sampleRate: config.sampleRate)
                if fftBpm > 0 && abs(peakBpm - fftBpm) > 15 {
                    // FFT disagrees significantly with peak detection — prefer FFT
                    // as it is more robust to noise and irregular peak shapes
                    Logger.shared.debug("[BiometricProcessor] HR: FFT cross-validation override — peak=\(peakBpm) fft=\(fftBpm), using FFT")
                    return (fftBpm, peakQuality * 0.8, .fft)
                }
                return (peakBpm, peakQuality, .ir)
            }
        }

        // Try Green channel (backup peak detection)
        let greenSignal = greenBuffer.all
        if let (peakBpm, peakQuality) = calculateHeartRateFromSignal(greenSignal) {
            if peakQuality >= config.minHRQuality {
                // Cross-validate with FFT on green channel
                let (fftBpm, _) = calculateHeartRateFFT(from: greenSignal, sampleRate: config.sampleRate)
                if fftBpm > 0 && abs(peakBpm - fftBpm) > 15 {
                    Logger.shared.debug("[BiometricProcessor] HR: FFT cross-validation override (green) — peak=\(peakBpm) fft=\(fftBpm), using FFT")
                    return (fftBpm, peakQuality * 0.8, .fft)
                }
                return (peakBpm, peakQuality, .green)
            }
        }

        // FFT fallback: peak detection failed on both channels, try FFT on IR
        let (fftBpmIR, fftQualityIR) = calculateHeartRateFFT(from: irSignal, sampleRate: config.sampleRate)
        if fftBpmIR > 0 && fftQualityIR >= config.minHRQuality * 0.7 {
            Logger.shared.debug("[BiometricProcessor] HR: FFT fallback on IR — bpm=\(fftBpmIR) quality=\(String(format: "%.2f", fftQualityIR))")
            return (fftBpmIR, fftQualityIR, .fft)
        }

        // FFT fallback on Green channel
        let (fftBpmGreen, fftQualityGreen) = calculateHeartRateFFT(from: greenSignal, sampleRate: config.sampleRate)
        if fftBpmGreen > 0 && fftQualityGreen >= config.minHRQuality * 0.7 {
            Logger.shared.debug("[BiometricProcessor] HR: FFT fallback on Green — bpm=\(fftBpmGreen) quality=\(String(format: "%.2f", fftQualityGreen))")
            return (fftBpmGreen, fftQualityGreen, .fft)
        }

        return (0, 0, .unavailable)
    }

    private func calculateHeartRateFromSignal(_ signal: [Double]) -> (bpm: Int, quality: Double)? {
        guard signal.count >= config.hrWindowSize else { return nil }
        return PPGProcessor.heartRateFromBandpassedSignal(
            signal,
            sampleRate: config.sampleRate,
            minBPM: config.minBPM,
            maxBPM: config.maxBPM
        )
    }

    // MARK: - Private: FFT Heart Rate Calculation

    /// Calculate heart rate using FFT frequency analysis on a bandpass-filtered PPG signal.
    ///
    /// This method performs spectral analysis to find the dominant frequency in the
    /// cardiac range (0.67-3.0 Hz, corresponding to 40-180 BPM). It uses a Hann window
    /// to reduce spectral leakage and finds the peak magnitude in the frequency domain.
    ///
    /// - Parameters:
    ///   - signal: Bandpass-filtered PPG signal (Double array)
    ///   - sampleRate: Sample rate in Hz (e.g. 50.0)
    /// - Returns: Heart rate in BPM, or 0 if no valid dominant frequency is found.
    ///           Returns a quality estimate as a second value (0.0 to 1.0).
    private func calculateHeartRateFFT(
        from signal: [Double],
        sampleRate: Double
    ) -> (bpm: Int, quality: Double) {
        guard signal.count >= 128 else { return (0, 0) }
        let (minV, maxV) = (signal.min() ?? 0, signal.max() ?? 0)
        guard maxV - minV > 0.05 else { return (0, 0) }

        // Determine FFT size: next power of 2 >= signal.count
        let log2n = vDSP_Length(ceil(log2(Double(signal.count))))
        let fftSize = Int(1 << log2n)
        let halfN = fftSize / 2

        // Create or reuse FFT setup (only reallocate if size changed)
        if fftSetup == nil || fftLog2n != log2n {
            if let existing = fftSetup {
                vDSP_destroy_fftsetupD(existing)
            }
            guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
                return (0, 0)
            }
            fftSetup = setup
            fftLog2n = log2n
        }

        guard let setup = fftSetup else { return (0, 0) }

        // Step 1: Remove DC offset (subtract mean)
        var meanValue: Double = 0
        vDSP_meanvD(signal, 1, &meanValue, vDSP_Length(signal.count))

        var dcRemoved = signal.map { $0 - meanValue }

        // Step 2: Apply Hann window to reduce spectral leakage
        var window = [Double](repeating: 0, count: signal.count)
        vDSP_hann_windowD(&window, vDSP_Length(signal.count), Int32(vDSP_HANN_NORM))

        // Multiply signal by window
        vDSP_vmulD(dcRemoved, 1, window, 1, &dcRemoved, 1, vDSP_Length(signal.count))

        // Step 3: Zero-pad to FFT size
        var paddedSignal = [Double](repeating: 0, count: fftSize)
        paddedSignal.replaceSubrange(0..<signal.count, with: dcRemoved)

        // Step 4: Set up split complex arrays for FFT
        var realPart = [Double](repeating: 0, count: halfN)
        var imagPart = [Double](repeating: 0, count: halfN)

        // Convert real signal to split complex (even/odd interleaving)
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPDoubleSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Pack real data into split complex format
                paddedSignal.withUnsafeBufferPointer { signalBuf in
                    signalBuf.baseAddress!.withMemoryRebound(
                        to: DSPDoubleComplex.self,
                        capacity: halfN
                    ) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }

                // Step 5: Perform forward FFT (in-place)
                vDSP_fft_zripD(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Step 6: Calculate magnitude spectrum: sqrt(real² + imag²)
                // Scale by 1/(2*fftSize) for proper normalization
                var scale = 1.0 / Double(2 * fftSize)
                vDSP_vsmulD(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(halfN))
                vDSP_vsmulD(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(halfN))
            }
        }

        // Step 7: Compute magnitude spectrum
        var magnitudes = [Double](repeating: 0, count: halfN)
        for i in 0..<halfN {
            let re = realPart[i]
            let im = imagPart[i]
            magnitudes[i] = sqrt(re * re + im * im)
        }

        // Step 8: Find dominant frequency in cardiac range (0.67 Hz - 3.0 Hz = 40-180 BPM)
        let freqResolution = sampleRate / Double(fftSize)
        let minFreq = config.minBPM / 60.0  // 0.667 Hz for 40 BPM
        let maxFreq = config.maxBPM / 60.0  // 3.0 Hz for 180 BPM

        let minBin = max(1, Int(ceil(minFreq / freqResolution)))
        let maxBin = min(halfN - 1, Int(floor(maxFreq / freqResolution)))

        guard minBin < maxBin else { return (0, 0) }

        // Find peak magnitude and its bin index within the cardiac range
        var peakMagnitude: Double = 0
        var peakBin = minBin

        for bin in minBin...maxBin {
            if magnitudes[bin] > peakMagnitude {
                peakMagnitude = magnitudes[bin]
                peakBin = bin
            }
        }

        // Ensure the peak is meaningful (not just noise floor)
        guard peakMagnitude > 0 else { return (0, 0) }

        // Step 9: Parabolic interpolation for sub-bin frequency accuracy
        // Uses the peak bin and its two neighbors to refine the frequency estimate
        var refinedBin = Double(peakBin)
        if peakBin > minBin && peakBin < maxBin {
            let alpha = magnitudes[peakBin - 1]
            let beta = magnitudes[peakBin]
            let gamma = magnitudes[peakBin + 1]
            let denominator = alpha - 2.0 * beta + gamma
            if abs(denominator) > 1e-10 {
                let correction = 0.5 * (alpha - gamma) / denominator
                refinedBin = Double(peakBin) + correction
            }
        }

        let dominantFrequency = refinedBin * freqResolution
        let bpm = Int(round(dominantFrequency * 60.0))

        // Validate BPM range
        guard bpm >= Int(config.minBPM) && bpm <= Int(config.maxBPM) else { return (0, 0) }

        // Step 10: Calculate quality as peak-to-average ratio (spectral SNR)
        // Sum all magnitudes in the cardiac range
        var totalMagnitude: Double = 0
        for bin in minBin...maxBin {
            totalMagnitude += magnitudes[bin]
        }
        let avgMagnitude = totalMagnitude / Double(maxBin - minBin + 1)

        // SNR: how much the peak stands out from the average
        let snr = avgMagnitude > 0 ? peakMagnitude / avgMagnitude : 0
        // Normalize SNR to 0-1 quality (SNR of 5+ is very good, 2 is marginal)
        let quality = min(1.0, max(0, (snr - 1.0) / 4.0))

        return (bpm, quality)
    }

    // MARK: - Private: SpO2 Calculation

    private func calculateSpO2() -> (spo2: Double, quality: Double) {
        guard redBuffer.count >= config.spo2WindowSize,
              irBuffer.count >= config.spo2WindowSize else {
            return (0, 0)
        }

        // Snapshot buffers to arrays for efficient multi-pass calculation
        let redValues = redBuffer.all
        let irValues = irBuffer.all

        // DC components (mean)
        let dcRed = redValues.reduce(0, +) / Double(redValues.count)
        let dcIR = irValues.reduce(0, +) / Double(irValues.count)

        guard dcRed > 0, dcIR > 0 else { return (0, 0) }

        // AC components (peak-to-peak)
        let acRed = (redValues.max() ?? 0) - (redValues.min() ?? 0)
        let acIR = (irValues.max() ?? 0) - (irValues.min() ?? 0)

        guard acRed > 0, acIR > 0 else { return (0, 0) }

        // R value (ratio of ratios)
        let ratioRed = acRed / dcRed
        let ratioIR = acIR / dcIR

        guard ratioRed > 1e-6, ratioIR > 1e-6 else { return (0, 0) }

        let rValue = ratioRed / ratioIR

        // Validate R-value bounds (physiological range: 0.4 to 3.4)
        // R < 0.4 implies SpO2 > 100% (impossible), R > 3.4 implies SpO2 < 0% (impossible)
        // Values outside this range indicate noise or motion artifact
        guard rValue >= 0.4 && rValue <= 3.4 else { return (0, 0) }

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

    /// Damp abrupt low-quality jumps in SpO2 around sync-tap/motion transitions.
    private func stabilizeSpO2Estimate(raw: Double, quality: Double, motionLevel: Double) -> Double {
        guard raw > 0 else {
            lastStableSpO2 = nil
            return raw
        }
        guard let previous = lastStableSpO2 else {
            lastStableSpO2 = raw
            return raw
        }

        // Around sync taps (>0.15 g), clamp low-quality step changes per update.
        let inSyncTapMotion = motionLevel > TemporalisProtocolReference.syncTapMotionThresholdG
        let maxStep = inSyncTapMotion ? 0.5 : 2.0
        if quality < 0.75, abs(raw - previous) > maxStep {
            let adjusted = previous + (raw > previous ? maxStep : -maxStep)
            lastStableSpO2 = adjusted
            return adjusted
        }

        lastStableSpO2 = raw
        return raw
    }
}
