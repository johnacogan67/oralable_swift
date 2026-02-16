//
//  ButterworthFilter.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: Butterworth IIR filter implementation
//  Reference: cursor_oralable/src/analysis/features.py _butter_bandpass(), _butter_lowpass()
//

import Foundation
import Accelerate

/// Filter type
public enum FilterType {
    case lowpass
    case highpass
    case bandpass
}

/// Butterworth IIR filter
public class ButterworthFilter {

    // MARK: - Properties

    public let type: FilterType
    public let cutoffLow: Double
    public let cutoffHigh: Double?
    public let sampleRate: Double
    public let order: Int

    // Filter coefficients
    private var b: [Double] = []
    private var a: [Double] = []

    // State for real-time processing
    private var state: [Double] = []

    // MARK: - Initialization

    public init(
        type: FilterType,
        cutoffLow: Double,
        cutoffHigh: Double? = nil,
        sampleRate: Double,
        order: Int = 4
    ) {
        self.type = type
        self.cutoffLow = cutoffLow
        self.cutoffHigh = cutoffHigh
        self.sampleRate = sampleRate
        self.order = order

        computeCoefficients()
        resetState()
    }

    // MARK: - Coefficient Computation

    private func computeCoefficients() {
        let nyquist = sampleRate / 2.0

        switch type {
        case .lowpass:
            let normalizedCutoff = cutoffLow / nyquist
            (b, a) = designLowpass(normalizedCutoff: normalizedCutoff, order: order)

        case .highpass:
            let normalizedCutoff = cutoffLow / nyquist
            (b, a) = designHighpass(normalizedCutoff: normalizedCutoff, order: order)

        case .bandpass:
            guard let high = cutoffHigh else {
                fatalError("Bandpass filter requires cutoffHigh")
            }
            let normalizedLow = cutoffLow / nyquist
            let normalizedHigh = high / nyquist
            (b, a) = designBandpass(lowNorm: normalizedLow, highNorm: normalizedHigh, order: order)
        }

        state = [Double](repeating: 0, count: max(b.count, a.count))
    }

    // MARK: - Filter Design (Simplified Butterworth)

    private func designLowpass(normalizedCutoff: Double, order: Int) -> ([Double], [Double]) {
        // Second-order section cascade for stability
        // For simplicity, using bilinear transform of analog Butterworth

        let wc = tan(.pi * normalizedCutoff)
        let k = wc * wc

        // For order 4, cascade two second-order sections
        // Simplified implementation for common case

        // Single second-order section coefficients
        let q = sqrt(2.0)  // Q factor for Butterworth
        let norm = 1.0 / (1.0 + wc / q + k)

        let b0 = k * norm
        let b1 = 2.0 * b0
        let b2 = b0
        let a1 = 2.0 * (k - 1.0) * norm
        let a2 = (1.0 - wc / q + k) * norm

        return ([b0, b1, b2], [1.0, a1, a2])
    }

    private func designHighpass(normalizedCutoff: Double, order: Int) -> ([Double], [Double]) {
        let wc = tan(.pi * normalizedCutoff)
        let k = wc * wc
        let q = sqrt(2.0)
        let norm = 1.0 / (1.0 + wc / q + k)

        let b0 = norm
        let b1 = -2.0 * norm
        let b2 = norm
        let a1 = 2.0 * (k - 1.0) * norm
        let a2 = (1.0 - wc / q + k) * norm

        return ([b0, b1, b2], [1.0, a1, a2])
    }

    private func designBandpass(lowNorm: Double, highNorm: Double, order: Int) -> ([Double], [Double]) {
        // Bandpass = cascade of highpass and lowpass
        // Simplified implementation

        let wcLow = tan(.pi * lowNorm)
        let wcHigh = tan(.pi * highNorm)
        let bw = wcHigh - wcLow
        let w0 = sqrt(wcLow * wcHigh)

        let q = w0 / bw
        let k = w0 * w0
        let norm = 1.0 / (1.0 + w0 / q + k)

        let b0 = (w0 / q) * norm
        let b1 = 0.0
        let b2 = -b0
        let a1 = 2.0 * (k - 1.0) * norm
        let a2 = (1.0 - w0 / q + k) * norm

        return ([b0, b1, b2], [1.0, a1, a2])
    }

    // MARK: - Filtering

    /// Process a single sample (real-time)
    public func processSample(_ input: Double) -> Double {
        guard !b.isEmpty && !a.isEmpty else { return input }

        // Direct Form II Transposed
        let output = b[0] * input + state[0]

        for i in 0..<(state.count - 1) {
            let bCoeff = i + 1 < b.count ? b[i + 1] : 0
            let aCoeff = i + 1 < a.count ? a[i + 1] : 0
            state[i] = bCoeff * input - aCoeff * output + state[i + 1]
        }
        state[state.count - 1] = 0

        return output
    }

    /// Process array (batch)
    public func process(_ input: [Double]) -> [Double] {
        return input.map { processSample($0) }
    }

    /// Forward-backward filtering (like scipy filtfilt)
    /// Zero-phase filtering, no phase distortion
    public func filtfilt(_ input: [Double]) -> [Double] {
        guard input.count > 3 else { return input }

        // Forward pass
        reset()
        let forward = process(input)

        // Backward pass (reverse, filter, reverse)
        reset()
        let reversed = Array(forward.reversed())
        let backward = process(reversed)

        return Array(backward.reversed())
    }

    /// Reset filter state
    public func reset() {
        state = [Double](repeating: 0, count: state.count)
    }

    func resetState() {
        state = [Double](repeating: 0, count: max(b.count, a.count))
    }
}
