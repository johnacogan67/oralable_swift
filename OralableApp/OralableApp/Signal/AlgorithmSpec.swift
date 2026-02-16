//
//  AlgorithmSpec.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: Algorithm constants matching Python reference
//  Reference: cursor_oralable/src/analysis/features.py
//

import Foundation

/// Algorithm specification constants for signal processing
/// Matches Python reference implementation
public enum AlgorithmSpec {

    // MARK: - Sample Rates

    /// PPG sample rate in Hz
    public static let ppgSampleRate: Double = 50.0

    /// Accelerometer sample rate in Hz
    public static let accelSampleRate: Double = 100.0

    /// Sample interval for PPG in seconds
    public static let ppgSampleInterval: Double = 1.0 / ppgSampleRate  // 20ms

    /// Sample interval for accelerometer in seconds
    public static let accelSampleInterval: Double = 1.0 / accelSampleRate  // 10ms

    // MARK: - Packet Sizes

    /// Frame counter size in bytes
    public static let frameCounterBytes: Int = 4

    /// Bytes per PPG sample (Red + IR + Green, each UInt32)
    public static let bytesPerPPGSample: Int = 12

    /// Bytes per accelerometer sample (X + Y + Z, each Int16)
    public static let bytesPerAccelSample: Int = 6

    /// Default PPG samples per packet (firmware CONFIG_PPG_SAMPLES_PER_FRAME)
    public static let ppgSamplesPerPacket: Int = 20

    /// Default accelerometer samples per packet
    public static let accelSamplesPerPacket: Int = 25

    // MARK: - Filter Parameters

    /// Heart rate bandpass filter low cutoff (Hz)
    public static let hrBandpassLow: Double = 0.5

    /// Heart rate bandpass filter high cutoff (Hz)
    public static let hrBandpassHigh: Double = 8.0

    /// IR DC baseline lowpass cutoff (Hz)
    public static let irDCLowpassCutoff: Double = 0.8

    /// Filter order for Butterworth filters
    public static let filterOrder: Int = 4

    // MARK: - Heart Rate Detection

    /// Minimum valid heart rate (BPM)
    public static let minHeartRate: Double = 40.0

    /// Maximum valid heart rate (BPM)
    public static let maxHeartRate: Double = 180.0

    /// Minimum peak distance in seconds (based on maxHeartRate)
    public static let minPeakDistanceSeconds: Double = 0.4  // ~150 BPM max

    /// Peak prominence multiplier (relative to signal std dev)
    public static let peakProminenceMultiplier: Double = 0.5

    // MARK: - IR DC Analysis

    /// Rolling window for IR DC mean (seconds)
    public static let irDCRollingWindowSeconds: Double = 5.0

    /// Reference window for IR DC shift baseline (seconds)
    public static let irDCReferenceWindowSeconds: Double = 1.0

    // MARK: - Validation Windows

    /// Validation window for event positioning (seconds)
    public static let validationWindowSeconds: Double = 180.0  // 3 minutes

    // MARK: - Channel Order

    /// PPG channel order in firmware packet
    /// Each sample: [Red, IR, Green] at byte offsets [0, 4, 8]
    public enum PPGChannelOrder {
        case redFirst  // Red at offset 0, IR at 4, Green at 8 (current firmware)

        /// Byte offset for Red channel
        public var redOffset: Int { 0 }

        /// Byte offset for IR channel
        public var irOffset: Int { 4 }

        /// Byte offset for Green channel
        public var greenOffset: Int { 8 }
    }

    /// Default channel order
    public static let defaultChannelOrder: PPGChannelOrder = .redFirst
}
