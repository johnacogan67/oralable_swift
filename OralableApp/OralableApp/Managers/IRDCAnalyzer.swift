//
//  IRDCAnalyzer.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: IR DC baseline analysis for occlusion detection
//  Reference: cursor_oralable/src/analysis/features.py compute_filters(), _ir_dc_shift_5s()
//

import Foundation

/// Analyzes IR DC baseline for blood volume and occlusion detection
public class IRDCAnalyzer {

    // MARK: - Configuration

    /// Sample rate in Hz
    public let sampleRate: Double

    /// Lowpass filter cutoff for DC extraction (Hz)
    /// Python uses 0.8 Hz
    public var lowpassCutoffHz: Double = 0.8

    /// Window size for rolling mean (seconds)
    public var rollingWindowSeconds: Double = 5.0

    /// Reference window for baseline (seconds)
    /// Used to calculate IR DC shift
    public var referenceWindowSeconds: Double = 1.0

    // MARK: - Filter

    private var lowpassFilter: ButterworthFilter?

    // MARK: - Buffer

    private var irDCBuffer: [Double] = []
    private let maxBufferSize: Int

    // MARK: - Initialization

    public init(sampleRate: Double = 50.0) {
        self.sampleRate = sampleRate
        self.maxBufferSize = Int(sampleRate * 60)  // 1 minute max

        self.lowpassFilter = ButterworthFilter(
            type: .lowpass,
            cutoffLow: lowpassCutoffHz,
            sampleRate: sampleRate,
            order: 4
        )
    }

    // MARK: - DC Extraction

    /// Extract IR DC baseline from raw IR signal
    /// - Parameter irSignal: Raw IR values
    /// - Returns: DC component (low-frequency baseline)
    public func extractDC(from irSignal: [Double]) -> [Double] {
        guard let filter = lowpassFilter else {
            return irSignal
        }

        return filter.filtfilt(irSignal)
    }

    /// Calculate rolling mean of IR DC
    /// - Parameters:
    ///   - irDC: DC-extracted IR signal
    ///   - windowSeconds: Window size in seconds (default 5s)
    /// - Returns: Rolling mean values
    public func rollingMean(
        _ irDC: [Double],
        windowSeconds: Double? = nil
    ) -> [Double] {

        let windowSamples = Int((windowSeconds ?? rollingWindowSeconds) * sampleRate)
        let halfWindow = windowSamples / 2

        var result = [Double](repeating: 0, count: irDC.count)

        for i in 0..<irDC.count {
            let start = max(0, i - halfWindow)
            let end = min(irDC.count, i + halfWindow + 1)
            let window = Array(irDC[start..<end])
            result[i] = window.reduce(0, +) / Double(window.count)
        }

        return result
    }

    /// Calculate IR DC shift over a window
    /// Positive value = baseline drops (occlusion/muscle contraction)
    /// - Parameter irDC: DC values for the window
    /// - Returns: Shift value (baseline - window mean)
    public func calculateShift(_ irDC: [Double]) -> Double {
        guard irDC.count >= 10 else { return 0 }

        // Reference: first 1 second
        let refSamples = min(Int(referenceWindowSeconds * sampleRate), irDC.count)
        let baseline = Array(irDC[0..<refSamples]).reduce(0, +) / Double(refSamples)

        // Window mean
        let windowMean = irDC.reduce(0, +) / Double(irDC.count)

        // Positive = baseline dropped (occlusion)
        return baseline - windowMean
    }

    // MARK: - Real-Time Processing

    /// Process a single IR sample and return current DC estimate
    /// - Parameter irValue: Raw IR value
    /// - Returns: Current IR DC value
    public func process(irValue: Double) -> Double {
        guard let filter = lowpassFilter else {
            return irValue
        }

        // Single-sample lowpass
        let dc = filter.processSample(irValue)

        // Update buffer
        irDCBuffer.append(dc)
        if irDCBuffer.count > maxBufferSize {
            irDCBuffer.removeFirst()
        }

        return dc
    }

    /// Get current 5-second rolling mean
    public var currentRollingMean: Double {
        let windowSamples = Int(rollingWindowSeconds * sampleRate)
        let recentSamples = Array(irDCBuffer.suffix(windowSamples))
        guard !recentSamples.isEmpty else { return 0 }
        return recentSamples.reduce(0, +) / Double(recentSamples.count)
    }

    /// Get current IR DC shift (last 5 seconds)
    public var currentShift: Double {
        let windowSamples = Int(rollingWindowSeconds * sampleRate)
        let recentSamples = Array(irDCBuffer.suffix(windowSamples))
        return calculateShift(recentSamples)
    }

    /// Reset analyzer state
    public func reset() {
        irDCBuffer.removeAll()
        lowpassFilter?.reset()
    }
}

// MARK: - IR DC Result

/// Result from IR DC analysis
public struct IRDCResult: Sendable {
    /// Current DC value
    public let dcValue: Double

    /// 5-second rolling mean
    public let rollingMean5s: Double

    /// DC shift (positive = occlusion)
    public let shift5s: Double

    /// Whether shift indicates muscle activity
    /// Threshold: > 1000 ADC units typically indicates occlusion
    public var indicatesActivity: Bool {
        shift5s > 1000
    }

    public init(dcValue: Double, rollingMean5s: Double, shift5s: Double) {
        self.dcValue = dcValue
        self.rollingMean5s = rollingMean5s
        self.shift5s = shift5s
    }
}
