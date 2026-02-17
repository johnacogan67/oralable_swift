//
//  OralableDevice+Statistics.swift
//  OralableApp
//
//  Created: February 2026
//
//  Statistics and diagnostics for OralableDevice.
//  Includes sample rate tracking, packet loss statistics,
//  and diagnostic reporting methods.
//

import Foundation

// MARK: - SampleRateStats

/// Tracks packet timing statistics for sample rate verification
struct SampleRateStats {
    var firstPacketTime: Date?
    var lastPacketTime: Date?
    var packetCount: Int = 0
    var frameCounterFirst: UInt32?
    var frameCounterLast: UInt32?
    var intervalSum: Double = 0
    var intervalCount: Int = 0
    var minInterval: Double = Double.greatestFiniteMagnitude
    var maxInterval: Double = 0
    var recentIntervals: [Double] = []
    let maxRecentIntervals = 100

    mutating func reset() {
        firstPacketTime = nil
        lastPacketTime = nil
        packetCount = 0
        frameCounterFirst = nil
        frameCounterLast = nil
        intervalSum = 0
        intervalCount = 0
        minInterval = Double.greatestFiniteMagnitude
        maxInterval = 0
        recentIntervals.removeAll()
    }

    mutating func recordPacket(time: Date, frameCounter: UInt32) {
        if firstPacketTime == nil {
            firstPacketTime = time
            frameCounterFirst = frameCounter
        }
        if let lastTime = lastPacketTime {
            let interval = time.timeIntervalSince(lastTime)
            intervalSum += interval
            intervalCount += 1
            minInterval = min(minInterval, interval)
            maxInterval = max(maxInterval, interval)
            recentIntervals.append(interval)
            if recentIntervals.count > maxRecentIntervals {
                recentIntervals.removeFirst()
            }
        }
        lastPacketTime = time
        frameCounterLast = frameCounter
        packetCount += 1
    }

    var averageInterval: Double {
        guard intervalCount > 0 else { return 0 }
        return intervalSum / Double(intervalCount)
    }

    var recentAverageInterval: Double {
        guard !recentIntervals.isEmpty else { return 0 }
        return recentIntervals.reduce(0, +) / Double(recentIntervals.count)
    }

    var packetsPerSecond: Double {
        guard averageInterval > 0 else { return 0 }
        return 1.0 / averageInterval
    }

    var recentPacketsPerSecond: Double {
        guard recentAverageInterval > 0 else { return 0 }
        return 1.0 / recentAverageInterval
    }

    var totalDuration: Double {
        guard let first = firstPacketTime, let last = lastPacketTime else { return 0 }
        return last.timeIntervalSince(first)
    }
}

// MARK: - Statistics & Diagnostics

extension OralableDevice {

    /// Get current packet loss statistics
    var packetLossStats: (ppgLost: Int, accelLost: Int) {
        return (ppgPacketsLost, accelPacketsLost)
    }

    /// Reset packet loss counters
    func resetPacketLossStats() {
        ppgPacketsLost = 0
        accelPacketsLost = 0
        lastPPGFrameCounter = nil
        lastAccelFrameCounter = nil
    }

    /// Get comprehensive sample rate statistics
    func getSampleRateStatistics() -> (
        packetsPerSecond: Double,
        recentPacketsPerSecond: Double,
        totalPackets: Int,
        totalDuration: Double,
        minInterval: Double,
        maxInterval: Double,
        ppgSamples: Int,
        ppgPacketsLost: Int,
        accelPacketsLost: Int
    ) {
        return (
            packetsPerSecond: sampleRateStats.packetsPerSecond,
            recentPacketsPerSecond: sampleRateStats.recentPacketsPerSecond,
            totalPackets: sampleRateStats.packetCount,
            totalDuration: sampleRateStats.totalDuration,
            minInterval: sampleRateStats.minInterval == Double.greatestFiniteMagnitude ? 0 : sampleRateStats.minInterval,
            maxInterval: sampleRateStats.maxInterval,
            ppgSamples: ppgSampleCount,
            ppgPacketsLost: ppgPacketsLost,
            accelPacketsLost: accelPacketsLost
        )
    }

    /// Reset all sample rate statistics
    func resetSampleRateStatistics() {
        sampleRateStats.reset()
        packetsReceived = 0
        bytesReceived = 0
        ppgSampleCount = 0
        lastPacketTime = nil
        resetPacketLossStats()
    }
}
