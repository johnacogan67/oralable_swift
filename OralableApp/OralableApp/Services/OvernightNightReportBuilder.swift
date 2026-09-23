//
//  OvernightNightReportBuilder.swift
//  OralableApp
//
//  Shared path for Share PDF + in-app state hypnogram (FIG-CO-025 adaptation).
//

import Foundation

/// Builds overnight analysis from the current / latest recording window.
enum OvernightNightReportBuilder {
    /// Minimum wear for evaluable overnight bands / morning card (OVERNIGHT_NIGHT_REPORT).
    nonisolated static let evaluableWearSeconds: TimeInterval = 6 * 3600

    struct SessionWindow: Sendable, Equatable {
        var start: Date
        var end: Date
        var sessionFileURL: URL?
    }

    struct Result: Sendable {
        var window: SessionWindow
        var samples: [NightReportSample]
        var analysis: OvernightNightAnalysis?
        var hourlySegments: [HourlyTemporalisSegment]
        var tfiPercent: Double

        var wearSeconds: TimeInterval {
            analysis?.kpis.wearS ?? max(0, window.end.timeIntervalSince(window.start))
        }

        var isEvaluable: Bool {
            wearSeconds >= OvernightNightReportBuilder.evaluableWearSeconds
        }
    }

    static func resolveSessionWindow(
        currentSession: RecordingSession?,
        automaticSessionStart: Date?,
        sessions: [RecordingSession],
        liveHistory: [SensorData]
    ) -> SessionWindow {
        let start: Date = {
            if let t = currentSession?.startTime { return t }
            if let t = automaticSessionStart { return t }
            if let last = sessions.max(by: { $0.startTime < $1.startTime }) {
                return last.startTime
            }
            if let first = liveHistory.first?.timestamp { return first }
            return Calendar.current.startOfDay(for: Date())
        }()
        let end: Date = {
            if let end = currentSession?.endTime { return end }
            if let last = liveHistory.last?.timestamp { return max(last, Date()) }
            return Date()
        }()
        let file = currentSession?.dataFilePath
            ?? sessions
                .filter { $0.dataFilePath != nil }
                .max(by: { $0.startTime < $1.startTime })?
                .dataFilePath
        return SessionWindow(start: start, end: end, sessionFileURL: file)
    }

    /// Prefer overnight hourly mean TFI over live gauge (which resets to 50 on disconnect).
    nonisolated static func resolveReportTFI(
        liveTFI: Double,
        hourlySegments: [HourlyTemporalisSegment],
        lastSessionMeanTFI: Double? = nil
    ) -> Double {
        let fromHourly = hourlySegments.map(\.tfiPercent).filter { $0 > 0 }
        if !fromHourly.isEmpty {
            return fromHourly.reduce(0, +) / Double(fromHourly.count)
        }
        if let last = lastSessionMeanTFI, last > 0 {
            return last
        }
        return liveTFI
    }

    nonisolated static func build(
        window: SessionWindow,
        liveHistory: [SensorData],
        hourlySegments: [HourlyTemporalisSegment],
        tfiPercent: Double,
        lastSessionMeanTFI: Double? = nil
    ) -> Result {
        let samples = NightReportSampleLoader.load(
            sessionStart: window.start.addingTimeInterval(-2),
            sessionEnd: window.end.addingTimeInterval(2),
            liveHistory: liveHistory,
            sessionFileURL: window.sessionFileURL
        )
        let analysis = OvernightStateClassifier.analyze(samples)
        let resolvedTFI = resolveReportTFI(
            liveTFI: tfiPercent,
            hourlySegments: hourlySegments,
            lastSessionMeanTFI: lastSessionMeanTFI
        )
        return Result(
            window: window,
            samples: samples,
            analysis: analysis,
            hourlySegments: hourlySegments,
            tfiPercent: resolvedTFI
        )
    }

    /// Gather MainActor-bound inputs for an off-main `build(window:...)`.
    @MainActor
    static func makeBuildInputs(
        recordingSessionManager: RecordingSessionManager,
        automaticSessionStart: Date?,
        liveHistory: [SensorData],
        sessionHistoryStore: SessionHistoryStore,
        liveTFI: Double,
        lastSessionMeanTFI: Double? = nil
    ) -> (
        window: SessionWindow,
        liveHistory: [SensorData],
        hourlySegments: [HourlyTemporalisSegment],
        liveTFI: Double,
        lastSessionMeanTFI: Double?
    ) {
        let current = recordingSessionManager.currentSession
        let sessions = recordingSessionManager.sessions
        let hourly = Array(sessionHistoryStore.segmentByHour.values).sorted { $0.hourIndex < $1.hourIndex }
        let window = resolveSessionWindow(
            currentSession: current,
            automaticSessionStart: automaticSessionStart,
            sessions: sessions,
            liveHistory: liveHistory
        )
        return (window, liveHistory, hourly, liveTFI, lastSessionMeanTFI)
    }

    @MainActor
    static func build(
        recordingSessionManager: RecordingSessionManager,
        automaticSessionStart: Date?,
        liveHistory: [SensorData],
        sessionHistoryStore: SessionHistoryStore,
        tfiPercent: Double,
        lastSessionMeanTFI: Double? = nil
    ) -> Result {
        let inputs = makeBuildInputs(
            recordingSessionManager: recordingSessionManager,
            automaticSessionStart: automaticSessionStart,
            liveHistory: liveHistory,
            sessionHistoryStore: sessionHistoryStore,
            liveTFI: tfiPercent,
            lastSessionMeanTFI: lastSessionMeanTFI
        )
        return build(
            window: inputs.window,
            liveHistory: inputs.liveHistory,
            hourlySegments: inputs.hourlySegments,
            tfiPercent: inputs.liveTFI,
            lastSessionMeanTFI: inputs.lastSessionMeanTFI
        )
    }
}

// MARK: - Provisional bands (OVERNIGHT_NIGHT_REPORT §2)

enum OvernightBandLevel: String, Sendable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case insufficient = "Insufficient data"
}

struct OvernightBandChip: Sendable, Equatable, Identifiable {
    var id: String { label }
    var label: String
    var valueText: String
    var level: OvernightBandLevel
}

enum OvernightBandCalculator {
    nonisolated static func chips(from result: OvernightNightReportBuilder.Result) -> [OvernightBandChip] {
        guard result.isEvaluable, let kpis = result.analysis?.kpis else {
            return [
                OvernightBandChip(label: "Jaw load", valueText: "—", level: .insufficient),
                OvernightBandChip(label: "Oxygen burden", valueText: "—", level: .insufficient),
                OvernightBandChip(label: "Rescue pattern", valueText: "—", level: .insufficient)
            ]
        }
        let wearH = max(1e-6, kpis.wearS / 3600.0)
        let tfi = result.tfiPercent > 0 ? result.tfiPercent : 0
        let sashbPerH = kpis.sashb / wearH
        let rescuePerH = Double(kpis.rescueCount) / wearH

        let tfiLevel: OvernightBandLevel = tfi < 35 ? .low : (tfi <= 65 ? .moderate : .high)
        let sashbLevel: OvernightBandLevel = sashbPerH < 50 ? .low : (sashbPerH <= 200 ? .moderate : .high)
        let rescueLevel: OvernightBandLevel = rescuePerH < 1 ? .low : (rescuePerH <= 3 ? .moderate : .high)

        return [
            OvernightBandChip(
                label: "Jaw load",
                valueText: String(format: "TFI %.0f", tfi),
                level: tfiLevel
            ),
            OvernightBandChip(
                label: "Oxygen burden",
                valueText: String(format: "%.0f %%·s/h", sashbPerH),
                level: sashbLevel
            ),
            OvernightBandChip(
                label: "Rescue pattern",
                valueText: String(format: "%.1f /h", rescuePerH),
                level: rescueLevel
            )
        ]
    }
}
