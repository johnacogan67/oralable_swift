//
//  IRDCProcessor.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: IR DC baseline extraction and shift detection
//  Reference: cursor_oralable/src/analysis/features.py compute_filters(), _ir_dc_shift_5s()
//

import Foundation

/// Processes IR signal to extract DC baseline for occlusion detection
public class IRDCProcessor {

    // MARK: - Configuration

    /// Sample rate in Hz
    public let sampleRate: Double

    /// Lowpass filter for DC extraction
    private let lowpassFilter: ButterworthFilter

    /// Rolling window size in samples
    private let rollingWindowSamples: Int

    /// Reference window size in samples
    private let referenceWindowSamples: Int

    // MARK: - Buffers

    /// DC value buffer
    private var dcBuffer: [Double] = []

    /// Maximum buffer size
    private let maxBufferSize: Int

    // MARK: - Current Values

    /// Latest DC value
    public private(set) var currentDC: Double = 0

    /// Current rolling mean
    public private(set) var rollingMean: Double = 0

    /// Current DC shift
    public private(set) var dcShift: Double = 0

    // MARK: - Initialization

    public init(sampleRate: Double = AlgorithmSpec.ppgSampleRate) {
        self.sampleRate = sampleRate
        self.maxBufferSize = Int(sampleRate * 60)  // 1 minute
        self.rollingWindowSamples = Int(AlgorithmSpec.irDCRollingWindowSeconds * sampleRate)
        self.referenceWindowSamples = Int(AlgorithmSpec.irDCReferenceWindowSeconds * sampleRate)

        // Lowpass <1 Hz for DC extraction
        self.lowpassFilter = ButterworthFilter(
            type: .lowpass,
            cutoffLow: AlgorithmSpec.irDCLowpassCutoff,
            sampleRate: sampleRate,
            order: AlgorithmSpec.filterOrder
        )
    }

    // MARK: - Processing

    /// Process a single IR sample
    /// - Parameter sample: PPGData sample
    /// - Returns: Current IR DC result
    public func process(_ sample: PPGData) -> IRDCResult {
        return processSample(Double(sample.ir))
    }

    /// Process a raw IR value
    /// - Parameter irValue: Raw IR signal value
    /// - Returns: Current IR DC result
    public func processSample(_ irValue: Double) -> IRDCResult {
        // Apply lowpass filter
        let dc = lowpassFilter.processSample(irValue)
        currentDC = dc

        // Add to buffer
        dcBuffer.append(dc)
        if dcBuffer.count > maxBufferSize {
            dcBuffer.removeFirst()
        }

        // Calculate rolling mean
        updateRollingMean()

        // Calculate shift
        updateShift()

        return IRDCResult(
            dcValue: currentDC,
            rollingMean5s: rollingMean,
            shift5s: dcShift
        )
    }

    /// Process batch of samples
    /// - Parameter samples: Array of PPGData
    /// - Returns: Latest IR DC result
    public func processBatch(_ samples: [PPGData]) -> IRDCResult {
        var result = IRDCResult(dcValue: 0, rollingMean5s: 0, shift5s: 0)

        for sample in samples {
            result = processSample(Double(sample.ir))
        }

        return result
    }

    // MARK: - Calculations

    private func updateRollingMean() {
        let window = Array(dcBuffer.suffix(rollingWindowSamples))
        guard !window.isEmpty else {
            rollingMean = 0
            return
        }
        rollingMean = window.reduce(0, +) / Double(window.count)
    }

    private func updateShift() {
        let window = Array(dcBuffer.suffix(rollingWindowSamples))
        guard window.count >= referenceWindowSamples else {
            dcShift = 0
            return
        }

        // Reference: first N samples of window
        let refSamples = Array(window.prefix(referenceWindowSamples))
        let baseline = refSamples.reduce(0, +) / Double(refSamples.count)

        // Window mean
        let windowMean = window.reduce(0, +) / Double(window.count)

        // Positive = baseline dropped (occlusion/muscle activity)
        dcShift = baseline - windowMean
    }

    // MARK: - Activity Detection

    /// Check if current shift indicates muscle activity
    /// - Parameter threshold: ADC units threshold (default 1000)
    /// - Returns: True if significant shift detected
    public func hasSignificantShift(threshold: Double = 1000) -> Bool {
        return dcShift > threshold
    }

    // MARK: - Reset

    /// Reset processor state
    public func reset() {
        dcBuffer.removeAll()
        currentDC = 0
        rollingMean = 0
        dcShift = 0
        lowpassFilter.reset()
    }
}
