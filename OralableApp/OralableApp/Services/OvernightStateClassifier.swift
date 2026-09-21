//
//  OvernightStateClassifier.swift
//  OralableApp
//
//  Python overnight_states.py parity: quiet / tonic / phasic / rescue / recovery.
//  Device-inferred wellness labels — not a medical diagnosis.
//

import Foundation
import OralableCore

enum OvernightMamState: String, CaseIterable, Sendable {
    case quiet
    case tonic
    case phasic
    case rescue
    case recovery

    var displayName: String {
        switch self {
        case .quiet: return "Quiet"
        case .tonic: return "Tonic"
        case .phasic: return "Phasic"
        case .rescue: return "Rescue"
        case .recovery: return "Recovery"
        }
    }
}

struct NightReportSample: Sendable, Equatable {
    var timestamp: Date
    var ir: Double
    var accelX: Double
    var accelY: Double
    var accelZ: Double
    var spo2: Double
}

struct OvernightBout: Sendable, Equatable {
    var state: OvernightMamState
    var startS: Double
    var endS: Double
    var durationS: Double
    var minSpo2: Double
    var deltaSpo2: Double
    var peakMotion: Double
    var recoveryS: Double
}

struct OvernightKPIs: Sendable, Equatable {
    var wearS: Double
    var tonicMin: Double
    var phasicMin: Double
    var rescueMin: Double
    var recoveryMin: Double
    var quietMin: Double
    var longestTonicS: Double
    var phasicBoutCount: Int
    var rescueCount: Int
    var rescueTotalS: Double
    var recoveryMedianS: Double
    var recoveryMaxS: Double
    var sashb: Double
    var spo2Mean: Double
    var spo2Min: Double
}

struct OvernightHourlyBurden: Sendable, Equatable {
    var hourIndex: Int
    var quietMin: Double
    var tonicMin: Double
    var phasicMin: Double
    var rescueMin: Double
    var recoveryMin: Double
    var sashbDelta: Double
}

struct OvernightTimelinePoint: Sendable, Equatable {
    var elapsedS: Double
    var state: OvernightMamState
    var ir: Double
    var spo2: Double
    var motionPower: Double
}

struct OvernightNightAnalysis: Sendable, Equatable {
    var kpis: OvernightKPIs
    var bouts: [OvernightBout]
    var hourly: [OvernightHourlyBurden]
    /// Downsampled for PDF (~1 Hz).
    var timeline: [OvernightTimelinePoint]
    var sampleCount: Int
}

enum OvernightStateClassifier {
    static let motionStableThresholdG = 0.15
    static let irDcDropThresholdPct = 15.0
    static let rescueSpo2Threshold = 92.0
    static let recoveryMaxS = 30.0
    static let recoveryDropPctMax = 8.0
    static let spo2HypoxiaThreshold = 90.0
    /// Wall-clock gap above this splits bouts / hypnogram runs (BLE disconnects, flush holes).
    /// Matches the 1s cap used by `stateMinutes` / SASHB so disconnect time is not credited.
    static let maxContiguousGapS = 1.0

    /// Classify at ~classifyHz, return analysis with ~timelineHz for charts.
    static func analyze(
        _ samples: [NightReportSample],
        classifyHz: Double = 10.0,
        timelineHz: Double = 1.0
    ) -> OvernightNightAnalysis? {
        guard samples.count >= 10 else { return nil }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let t0 = sorted[0].timestamp
        let elapsedAll = sorted.map { $0.timestamp.timeIntervalSince(t0) }

        let classifyStride = max(1, Int((inferFs(elapsedAll) / max(1.0, classifyHz)).rounded()))
        var idx: [Int] = []
        var i = 0
        while i < sorted.count {
            idx.append(i)
            i += classifyStride
        }
        if idx.last != sorted.count - 1 {
            idx.append(sorted.count - 1)
        }

        let n = idx.count
        var elapsed = [Double](repeating: 0, count: n)
        var ir = [Double](repeating: 0, count: n)
        var spo2 = [Double](repeating: 0, count: n)
        var ax = [Double](repeating: 0, count: n)
        var ay = [Double](repeating: 0, count: n)
        var az = [Double](repeating: 0, count: n)
        for (k, src) in idx.enumerated() {
            let s = sorted[src]
            elapsed[k] = elapsedAll[src]
            ir[k] = s.ir
            spo2[k] = s.spo2.isFinite && s.spo2 > 0 ? min(100, max(85, s.spo2)) : 97.0
            ax[k] = s.accelX
            ay[k] = s.accelY
            az[k] = s.accelZ
        }

        let irV = normalizeIrDcToVolts(ir)
        let fs = inferFs(elapsed)
        let irLp = movingAverage(irV, window: max(3, Int((0.8 * fs).rounded())))
        let motionG = zip(zip(ax, ay), az).map { pair, z -> Double in
            let (x, y) = pair
            let mag = sqrt(x * x + y * y + z * z) / 16384.0
            return abs(mag - 1.0)
        }
        let motionPower = rmsWindow(motionG, window: max(3, Int((0.5 * fs).rounded())))

        var (states, dropPct) = classifyStates(
            elapsedS: elapsed,
            irDcV: irLp,
            spo2Pct: spo2,
            motionPower: motionPower
        )
        states = applyRecovery(
            states: states,
            elapsedS: elapsed,
            dropPct: dropPct,
            motionPower: motionPower
        )

        let bouts = extractBouts(states: states, elapsedS: elapsed, spo2: spo2, motion: motionPower)
        let kpis = computeKPIs(
            states: states,
            elapsedS: elapsed,
            spo2: spo2,
            bouts: bouts
        )
        let hourly = hourlyBurden(states: states, elapsedS: elapsed, spo2: spo2)

        let timelineStride = max(1, Int((classifyHz / max(1.0, timelineHz)).rounded()))
        var timeline: [OvernightTimelinePoint] = []
        timeline.reserveCapacity((n / timelineStride) + 1)
        var t = 0
        while t < n {
            timeline.append(
                OvernightTimelinePoint(
                    elapsedS: elapsed[t],
                    state: states[t],
                    ir: ir[t],
                    spo2: spo2[t],
                    motionPower: motionPower[t]
                )
            )
            t += timelineStride
        }

        return OvernightNightAnalysis(
            kpis: kpis,
            bouts: bouts,
            hourly: hourly,
            timeline: timeline,
            sampleCount: sorted.count
        )
    }

    static func eventCSV(from analysis: OvernightNightAnalysis) -> String {
        var lines = ["start_s,end_s,duration_s,type,min_spo2,delta_spo2,peak_motion,recovery_s"]
        for b in analysis.bouts {
            lines.append(
                [
                    String(format: "%.3f", b.startS),
                    String(format: "%.3f", b.endS),
                    String(format: "%.3f", b.durationS),
                    b.state.rawValue,
                    String(format: "%.2f", b.minSpo2),
                    String(format: "%.2f", b.deltaSpo2),
                    String(format: "%.5f", b.peakMotion),
                    String(format: "%.3f", b.recoveryS)
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Core rules

    private static func inferFs(_ elapsed: [Double]) -> Double {
        guard elapsed.count >= 3 else { return 50 }
        var dts: [Double] = []
        for i in 1..<elapsed.count {
            let d = elapsed[i] - elapsed[i - 1]
            if d > 0 { dts.append(d) }
        }
        guard !dts.isEmpty else { return 50 }
        let med = dts.sorted()[dts.count / 2]
        guard med > 0 else { return 50 }
        let fs = 1.0 / med
        return (1...500).contains(fs) ? fs : 50
    }

    private static func normalizeIrDcToVolts(_ ir: [Double]) -> [Double] {
        guard let lo = percentile(ir, 0.01), let hi = percentile(ir, 0.99), hi > lo else {
            return Array(repeating: 2.1, count: ir.count)
        }
        if let mx = ir.max(), let mn = ir.min(), mn >= 0, mx <= 5 {
            return ir
        }
        return ir.map { v in
            let t = min(1, max(0, (v - lo) / (hi - lo)))
            return 1.5 + t * 1.5
        }
    }

    private static func movingAverage(_ x: [Double], window: Int) -> [Double] {
        let w = max(1, window | 1) // odd-ish
        guard x.count > 2 else { return x }
        var out = [Double](repeating: 0, count: x.count)
        let half = w / 2
        for i in 0..<x.count {
            let a = max(0, i - half)
            let b = min(x.count - 1, i + half)
            var s = 0.0
            var c = 0
            for j in a...b {
                s += x[j]
                c += 1
            }
            out[i] = s / Double(max(1, c))
        }
        return out
    }

    private static func rmsWindow(_ x: [Double], window: Int) -> [Double] {
        let w = max(1, window)
        var out = [Double](repeating: 0, count: x.count)
        let half = w / 2
        for i in 0..<x.count {
            let a = max(0, i - half)
            let b = min(x.count - 1, i + half)
            var s = 0.0
            var c = 0
            for j in a...b {
                s += x[j] * x[j]
                c += 1
            }
            out[i] = sqrt(s / Double(max(1, c)))
        }
        return out
    }

    private static func classifyStates(
        elapsedS: [Double],
        irDcV: [Double],
        spo2Pct: [Double],
        motionPower: [Double]
    ) -> ([OvernightMamState], [Double]) {
        let n = elapsedS.count
        guard n > 0 else { return ([], []) }

        var baselineVals: [Double] = []
        for i in 0..<n where elapsedS[i] <= 60 {
            baselineVals.append(irDcV[i])
        }
        if baselineVals.isEmpty { baselineVals = irDcV }
        var baseline = median(baselineVals)
        if !(baseline.isFinite && baseline > 0) { baseline = median(irDcV) }
        baseline = max(1e-6, baseline)

        var dropPct = [Double](repeating: 0, count: n)
        for i in 0..<n {
            dropPct[i] = (baseline - irDcV[i]) / baseline * 100.0
        }

        let p75 = percentile(motionPower, 0.75) ?? motionStableThresholdG
        let phasicThresh = max(motionStableThresholdG, p75)

        var out = [OvernightMamState](repeating: .quiet, count: n)
        for i in 0..<n {
            let drop = dropPct[i] > irDcDropThresholdPct
            let stable = motionPower[i] <= phasicThresh
            let high = motionPower[i] > phasicThresh
            let spo2Ok = spo2Pct[i] >= rescueSpo2Threshold
            if drop && spo2Pct[i] < rescueSpo2Threshold {
                out[i] = .rescue
            } else if high && spo2Ok {
                out[i] = .phasic
            } else if drop && stable && spo2Ok {
                out[i] = .tonic
            }
        }
        return (out, dropPct)
    }

    private static func applyRecovery(
        states: [OvernightMamState],
        elapsedS: [Double],
        dropPct: [Double],
        motionPower: [Double]
    ) -> [OvernightMamState] {
        var out = states
        let n = out.count
        let p75 = percentile(motionPower, 0.75) ?? motionStableThresholdG
        let phasicThresh = max(motionStableThresholdG, p75)
        let active: Set<OvernightMamState> = [.tonic, .phasic, .rescue]

        var i = 0
        while i < n {
            guard active.contains(out[i]) else {
                i += 1
                continue
            }
            var j = i + 1
            while j < n && active.contains(out[j]) { j += 1 }
            if j >= n { break }
            let tEnd = elapsedS[j - 1]
            let dropAtEnd = dropPct[j - 1].isFinite ? dropPct[j - 1] : 0
            var k = j
            while k < n {
                if active.contains(out[k]) || out[k] != .quiet { break }
                let t = elapsedS[k]
                if t - tEnd > recoveryMaxS { break }
                let lowMotion = motionPower[k] <= phasicThresh
                let d = dropPct[k].isFinite ? dropPct[k] : 0
                let easing = d <= dropAtEnd
                let stillSettling = d > 2.0
                let approaching = d <= max(recoveryDropPctMax, dropAtEnd)
                if lowMotion && stillSettling && easing && approaching {
                    out[k] = .recovery
                    k += 1
                    continue
                }
                break
            }
            i = max(k, j)
        }
        return out
    }

    private static func extractBouts(
        states: [OvernightMamState],
        elapsedS: [Double],
        spo2: [Double],
        motion: [Double]
    ) -> [OvernightBout] {
        let wanted: Set<OvernightMamState> = [.tonic, .phasic, .rescue, .recovery]
        var bouts: [OvernightBout] = []
        let n = states.count
        var i = 0
        while i < n {
            guard wanted.contains(states[i]) else {
                i += 1
                continue
            }
            let state = states[i]
            var j = i + 1
            while j < n && states[j] == state && !hasGap(elapsedS, from: j - 1, to: j) {
                j += 1
            }
            let start = elapsedS[i]
            let end = elapsedS[j - 1]
            let winSpo2 = Array(spo2[i..<j]).filter { $0.isFinite }
            let minS = winSpo2.min() ?? .nan
            let first = spo2[i]
            let delta = (minS.isFinite && first.isFinite) ? (minS - first) : .nan
            let peakM = Array(motion[i..<j]).max() ?? .nan

            var recoveryS = 0.0
            if [.tonic, .phasic, .rescue].contains(state), j < n, !hasGap(elapsedS, from: j - 1, to: j) {
                var k = j
                while k < n && states[k] == .recovery && !hasGap(elapsedS, from: k - 1, to: k) {
                    k += 1
                }
                if k > j {
                    recoveryS = elapsedS[k - 1] - elapsedS[j]
                }
            }

            bouts.append(
                OvernightBout(
                    state: state,
                    startS: start,
                    endS: end,
                    durationS: max(0, end - start),
                    minSpo2: minS,
                    deltaSpo2: delta,
                    peakMotion: peakM,
                    recoveryS: recoveryS
                )
            )
            i = j
        }
        return bouts
    }

    /// True when adjacent classify samples are separated by more than `maxContiguousGapS`.
    static func hasGap(_ elapsedS: [Double], from: Int, to: Int) -> Bool {
        guard from >= 0, to < elapsedS.count, to > from else { return false }
        return elapsedS[to] - elapsedS[from] > maxContiguousGapS
    }

    /// Wear / coverage seconds: sum capped adjacent deltas (disconnect holes excluded).
    static func coveredDurationS(_ elapsedS: [Double]) -> Double {
        guard elapsedS.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<elapsedS.count {
            total += min(1.0, max(0, elapsedS[i] - elapsedS[i - 1]))
        }
        return total
    }

    private static func stateMinutes(
        states: [OvernightMamState],
        elapsedS: [Double]
    ) -> [OvernightMamState: Double] {
        var out: [OvernightMamState: Double] = Dictionary(
            uniqueKeysWithValues: OvernightMamState.allCases.map { ($0, 0.0) }
        )
        guard elapsedS.count >= 2 else { return out }
        var dts = [Double](repeating: 0.02, count: elapsedS.count)
        for i in 1..<elapsedS.count {
            dts[i] = min(1.0, max(0, elapsedS[i] - elapsedS[i - 1]))
        }
        let med = dts.dropFirst().sorted()
        if !med.isEmpty {
            dts[0] = med[med.count / 2]
        }
        for i in 0..<states.count {
            out[states[i], default: 0] += dts[i] / 60.0
        }
        return out
    }

    private static func computeKPIs(
        states: [OvernightMamState],
        elapsedS: [Double],
        spo2: [Double],
        bouts: [OvernightBout]
    ) -> OvernightKPIs {
        let minutes = stateMinutes(states: states, elapsedS: elapsedS)
        let wearS = coveredDurationS(elapsedS)
        let tonicBouts = bouts.filter { $0.state == .tonic }
        let phasicBouts = bouts.filter { $0.state == .phasic }
        let rescueBouts = bouts.filter { $0.state == .rescue }
        let recoveryAfter = rescueBouts.map(\.recoveryS).filter { $0 > 0 }
        let spo2Ok = spo2.filter { $0.isFinite }

        var sashb = 0.0
        if elapsedS.count >= 2 {
            for i in 1..<elapsedS.count {
                let dt = min(1.0, max(0, elapsedS[i] - elapsedS[i - 1]))
                let p = spo2[i]
                if p < spo2HypoxiaThreshold {
                    sashb += (spo2HypoxiaThreshold - p) * dt
                }
            }
        }

        return OvernightKPIs(
            wearS: wearS,
            tonicMin: minutes[.tonic] ?? 0,
            phasicMin: minutes[.phasic] ?? 0,
            rescueMin: minutes[.rescue] ?? 0,
            recoveryMin: minutes[.recovery] ?? 0,
            quietMin: minutes[.quiet] ?? 0,
            longestTonicS: tonicBouts.map(\.durationS).max() ?? 0,
            phasicBoutCount: phasicBouts.count,
            rescueCount: rescueBouts.count,
            rescueTotalS: rescueBouts.map(\.durationS).reduce(0, +),
            recoveryMedianS: median(recoveryAfter),
            recoveryMaxS: recoveryAfter.max() ?? 0,
            sashb: sashb,
            spo2Mean: spo2Ok.isEmpty ? .nan : spo2Ok.reduce(0, +) / Double(spo2Ok.count),
            spo2Min: spo2Ok.min() ?? .nan
        )
    }

    private static func hourlyBurden(
        states: [OvernightMamState],
        elapsedS: [Double],
        spo2: [Double]
    ) -> [OvernightHourlyBurden] {
        guard elapsedS.count >= 2 else { return [] }
        var dts = [Double](repeating: 0.02, count: elapsedS.count)
        for i in 1..<elapsedS.count {
            dts[i] = min(1.0, max(0, elapsedS[i] - elapsedS[i - 1]))
        }
        var byHour: [Int: (quiet: Double, tonic: Double, phasic: Double, rescue: Double, recovery: Double, sashb: Double)] = [:]
        for i in 0..<states.count {
            let h = Int(floor(elapsedS[i] / 3600.0))
            var bucket = byHour[h] ?? (0, 0, 0, 0, 0, 0)
            let m = dts[i] / 60.0
            switch states[i] {
            case .quiet: bucket.quiet += m
            case .tonic: bucket.tonic += m
            case .phasic: bucket.phasic += m
            case .rescue: bucket.rescue += m
            case .recovery: bucket.recovery += m
            }
            if spo2[i] < spo2HypoxiaThreshold {
                bucket.sashb += (spo2HypoxiaThreshold - spo2[i]) * dts[i]
            }
            byHour[h] = bucket
        }
        return byHour.keys.sorted().map { h in
            let b = byHour[h]!
            return OvernightHourlyBurden(
                hourIndex: h,
                quietMin: b.quiet,
                tonicMin: b.tonic,
                phasicMin: b.phasic,
                rescueMin: b.rescue,
                recoveryMin: b.recovery,
                sashbDelta: b.sashb
            )
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let v = values.filter(\.isFinite).sorted()
        guard !v.isEmpty else { return 0 }
        return v[v.count / 2]
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double? {
        let v = values.filter(\.isFinite).sorted()
        guard !v.isEmpty else { return nil }
        let idx = Int((Double(v.count - 1) * p).rounded())
        return v[min(v.count - 1, max(0, idx))]
    }
}

extension NightReportSample {
    init(sensor: SensorData) {
        self.init(
            timestamp: sensor.timestamp,
            ir: Double(sensor.ppg.ir),
            accelX: Double(sensor.accelerometer.x),
            accelY: Double(sensor.accelerometer.y),
            accelZ: Double(sensor.accelerometer.z),
            spo2: sensor.spo2?.percentage ?? .nan
        )
    }
}
