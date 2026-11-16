//
//  OvernightNightReportBuilder.swift
//  OralableApp
//
//  Shared path for Share PDF + in-app state hypnogram (FIG-CO-025 adaptation).
//

import Foundation

/// Builds overnight analysis from the current / latest recording window.
enum OvernightNightReportBuilder {
    /// Minimum wear for overnight **bands** on the morning card.
    nonisolated static let evaluableWearSeconds: TimeInterval = 1 * 3600
    /// Beacon feasibility night (Ed / Paper A wear QC). Do not treat as “insufficient.”
    nonisolated static let beaconFeasibleWearSeconds: TimeInterval = 4 * 3600
    /// Hypnogram figure / band recalibration (Paper A stretch).
    nonisolated static let figureWearSeconds: TimeInterval = 6 * 3600

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
        /// Developer script. Not a recorded night.
        var isSimulated: Bool = false

        var wearSeconds: TimeInterval {
            analysis?.kpis.wearS ?? max(0, window.end.timeIntervalSince(window.start))
        }

        var isEvaluable: Bool {
            wearSeconds >= OvernightNightReportBuilder.evaluableWearSeconds
        }

        var isBeaconFeasible: Bool {
            wearSeconds >= OvernightNightReportBuilder.beaconFeasibleWearSeconds
        }

        var isFigureQuality: Bool {
            wearSeconds >= OvernightNightReportBuilder.figureWearSeconds
        }

        var wearHoursText: String {
            String(format: "%.1f h worn", wearSeconds / 3600.0)
        }
    }

    static func resolveSessionWindow(
        currentSession: RecordingSession?,
        automaticSessionStart: Date?,
        sessions: [RecordingSession],
        liveHistory: [SensorData]
    ) -> SessionWindow {
        let simulated = sessions
            .filter {
                $0.status == .completed
                    && $0.tags.contains(SimulatedWornNight.sessionTag)
                    && $0.dataFilePath != nil
                    && $0.endTime != nil
            }
            .max { ($0.endTime ?? $0.startTime) < ($1.endTime ?? $1.startTime) }
        if let simulated, let end = simulated.endTime, let file = simulated.dataFilePath {
            let liveStartedAfter = currentSession.map { $0.startTime > end } ?? false
            if !liveStartedAfter {
                return SessionWindow(start: simulated.startTime, end: end, sessionFileURL: file)
            }
        }
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

    nonisolated static func build(
        window: SessionWindow,
        liveHistory: [SensorData],
        hourlySegments: [HourlyTemporalisSegment],
        tfiPercent: Double
    ) -> Result {
        let samples = NightReportSampleLoader.load(
            sessionStart: window.start.addingTimeInterval(-2),
            sessionEnd: window.end.addingTimeInterval(2),
            liveHistory: liveHistory,
            sessionFileURL: window.sessionFileURL
        )
        let analysis = OvernightStateClassifier.analyze(samples)
        return Result(
            window: window,
            samples: samples,
            analysis: analysis,
            hourlySegments: hourlySegments,
            tfiPercent: tfiPercent
        )
    }

    @MainActor
    static func build(
        recordingSessionManager: RecordingSessionManager,
        automaticSessionStart: Date?,
        liveHistory: [SensorData],
        sessionHistoryStore: SessionHistoryStore,
        tfiPercent: Double
    ) -> Result {
        let current = recordingSessionManager.currentSession
        let sessions = recordingSessionManager.sessions
        let hourly = Array(sessionHistoryStore.segmentByHour.values).sorted { $0.hourIndex < $1.hourIndex }
        let window = resolveSessionWindow(
            currentSession: current,
            automaticSessionStart: automaticSessionStart,
            sessions: sessions,
            liveHistory: liveHistory
        )
        var result = build(
            window: window,
            liveHistory: liveHistory,
            hourlySegments: hourly,
            tfiPercent: tfiPercent
        )
        result.isSimulated = sessions.contains { session in
            session.tags.contains(SimulatedWornNight.sessionTag)
                && session.dataFilePath == result.window.sessionFileURL
        }
        return result
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
