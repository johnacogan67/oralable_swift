//
//  OvernightNightReportBuilderTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class OvernightNightReportBuilderTests: XCTestCase {

    func testAnalyzeFixtureProducesTimelineForHypnogram() {
        let samples = Self.makeFixtureSamples(hours: 0.02) // ~72 s — enough for classifier
        let analysis = OvernightStateClassifier.analyze(samples)
        XCTAssertNotNil(analysis)
        XCTAssertFalse(analysis!.timeline.isEmpty)

        let window = OvernightNightReportBuilder.SessionWindow(
            start: samples.first!.timestamp,
            end: samples.last!.timestamp,
            sessionFileURL: nil
        )
        let result = OvernightNightReportBuilder.build(
            window: window,
            liveHistory: [],
            hourlySegments: [],
            tfiPercent: 40
        )
        // Without live history / files, sample load is empty — analysis nil.
        // Builder still returns a Result with window; classify path validated above.
        XCTAssertEqual(result.window.start, window.start)
        XCTAssertFalse(result.isEvaluable)
    }

    func testEvaluableWearRequiresSixHours() {
        XCTAssertEqual(OvernightNightReportBuilder.evaluableWearSeconds, 6 * 3600)
    }

    func testResolveSessionWindowExpandsCollapsedRAMHistoryWithFlushBounds() {
        let now = Date(timeIntervalSince1970: 1_700_050_000)
        let historyFirst = now.addingTimeInterval(-180)
        let historyLast = now.addingTimeInterval(-1)
        let liveHistory = [historyFirst, historyLast].map { ts in
            SensorData(
                timestamp: ts,
                ppg: PPGData(red: 1000, ir: 180_000, green: 800, timestamp: ts),
                accelerometer: AccelerometerData(x: 0, y: 0, z: 16384, timestamp: ts),
                temperature: TemperatureData(celsius: 36.5, timestamp: ts),
                battery: BatteryData(percentage: 90, timestamp: ts),
                heartRate: nil,
                spo2: SpO2Data(percentage: 97, quality: 0.9, timestamp: ts),
                deviceType: .oralable
            )
        }
        let flushStart = now.addingTimeInterval(-9 * 3600)
        let flushEnd = now.addingTimeInterval(-30 * 60)

        let window = OvernightNightReportBuilder.resolveSessionWindow(
            currentSession: nil,
            automaticSessionStart: nil,
            sessions: [],
            liveHistory: liveHistory,
            lastCompletedAutoStart: nil,
            lastCompletedAutoEnd: nil,
            flushBounds: (flushStart, flushEnd),
            now: now
        )

        XCTAssertEqual(window.start, flushStart)
        XCTAssertEqual(window.end, now)
    }

    func testResolveSessionWindowUsesLastCompletedWhenMorningSessionIsActive() {
        let now = Date(timeIntervalSince1970: 1_700_060_000)
        let morningStart = now.addingTimeInterval(-90 * 60)
        let nightStart = now.addingTimeInterval(-11 * 3600)
        let nightEnd = now.addingTimeInterval(-2 * 3600)

        let window = OvernightNightReportBuilder.resolveSessionWindow(
            currentSession: nil,
            automaticSessionStart: morningStart,
            sessions: [],
            liveHistory: [],
            lastCompletedAutoStart: nightStart,
            lastCompletedAutoEnd: nightEnd,
            flushBounds: nil,
            now: now
        )

        XCTAssertEqual(window.start, nightStart)
        XCTAssertEqual(window.end, now)
    }

    func testBandChipsInsufficientWhenNotEvaluable() {
        let window = OvernightNightReportBuilder.SessionWindow(
            start: Date(),
            end: Date().addingTimeInterval(3600),
            sessionFileURL: nil
        )
        let result = OvernightNightReportBuilder.Result(
            window: window,
            samples: [],
            analysis: nil,
            hourlySegments: [],
            tfiPercent: 0
        )
        let chips = OvernightBandCalculator.chips(from: result)
        XCTAssertEqual(chips.count, 3)
        XCTAssertTrue(chips.allSatisfy { $0.level == .insufficient })
    }

    func testBandChipsFromLongWearKPIs() {
        let kpis = OvernightKPIs(
            wearS: 7 * 3600,
            tonicMin: 10,
            phasicMin: 5,
            rescueMin: 2,
            recoveryMin: 1,
            quietMin: 400,
            longestTonicS: 60,
            phasicBoutCount: 3,
            rescueCount: 4,
            rescueTotalS: 120,
            recoveryMedianS: 10,
            recoveryMaxS: 20,
            sashb: 700,
            spo2Mean: 96,
            spo2Min: 90
        )
        let analysis = OvernightNightAnalysis(
            kpis: kpis,
            bouts: [],
            hourly: [],
            timeline: [
                OvernightTimelinePoint(elapsedS: 0, state: .quiet, ir: 1, spo2: 97, motionPower: 0),
                OvernightTimelinePoint(elapsedS: 100, state: .tonic, ir: 1, spo2: 96, motionPower: 0)
            ],
            sampleCount: 2
        )
        let window = OvernightNightReportBuilder.SessionWindow(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 7 * 3600),
            sessionFileURL: nil
        )
        let result = OvernightNightReportBuilder.Result(
            window: window,
            samples: [],
            analysis: analysis,
            hourlySegments: [],
            tfiPercent: 50
        )
        XCTAssertTrue(result.isEvaluable)
        let chips = OvernightBandCalculator.chips(from: result)
        XCTAssertEqual(chips[0].level, .moderate) // TFI 50
        XCTAssertEqual(chips[1].level, .moderate) // ~100 %·s/h
        XCTAssertEqual(chips[2].level, .low) // ~0.57 /h
    }

    private static func makeFixtureSamples(hours: Double) -> [NightReportSample] {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let n = max(20, Int(hours * 3600 * 10))
        var samples: [NightReportSample] = []
        for i in 0..<n {
            samples.append(
                NightReportSample(
                    timestamp: t0.addingTimeInterval(Double(i) * 0.1),
                    ir: 200_000,
                    accelX: 0,
                    accelY: 0,
                    accelZ: 16_384,
                    spo2: 98
                )
            )
        }
        return samples
    }
}
