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

    func testEvaluableWearRequiresOneHour() {
        XCTAssertEqual(OvernightNightReportBuilder.evaluableWearSeconds, 1 * 3600)
        XCTAssertEqual(OvernightNightReportBuilder.beaconFeasibleWearSeconds, 4 * 3600)
        XCTAssertEqual(OvernightNightReportBuilder.figureWearSeconds, 6 * 3600)
    }

    func testFourHourNightIsBeaconFeasibleWithoutFigureQuality() {
        let window = OvernightNightReportBuilder.SessionWindow(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 4 * 3600),
            sessionFileURL: nil
        )
        let kpis = OvernightKPIs(
            wearS: 4 * 3600,
            tonicMin: 1,
            phasicMin: 1,
            rescueMin: 0,
            recoveryMin: 0,
            quietMin: 200,
            longestTonicS: 10,
            phasicBoutCount: 1,
            rescueCount: 0,
            rescueTotalS: 0,
            recoveryMedianS: 0,
            recoveryMaxS: 0,
            sashb: 10,
            spo2Mean: 96,
            spo2Min: 92
        )
        let analysis = OvernightNightAnalysis(
            kpis: kpis,
            bouts: [],
            hourly: [],
            timeline: [
                OvernightTimelinePoint(elapsedS: 0, state: .quiet, ir: 1, spo2: 97, motionPower: 0)
            ],
            sampleCount: 1
        )
        let result = OvernightNightReportBuilder.Result(
            window: window,
            samples: [],
            analysis: analysis,
            hourlySegments: [],
            tfiPercent: 40
        )
        XCTAssertTrue(result.isEvaluable)
        XCTAssertTrue(result.isBeaconFeasible)
        XCTAssertFalse(result.isFigureQuality)
        XCTAssertEqual(OvernightBandCalculator.chips(from: result).filter { $0.level == .insufficient }.count, 0)
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

    func testMemoryFlushNamesDoNotCollideInTheSameSecond() {
        let directory = FileManager.default.temporaryDirectory
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ResearchRawDataExport.memoryFlushFileURL(
            prefix: "oralable_unified_flush",
            directory: directory,
            at: date,
            unique: "a"
        )
        let second = ResearchRawDataExport.memoryFlushFileURL(
            prefix: "oralable_unified_flush",
            directory: directory,
            at: date,
            unique: "b"
        )
        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertTrue(first.lastPathComponent.contains("1700000000"))
        XCTAssertTrue(second.lastPathComponent.contains("1700000000"))
    }

    func testNightReportCSVWritesHeaderAndRow() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            NightReportSample(timestamp: t0, ir: 200_000, accelX: 1, accelY: 2, accelZ: 16_384, spo2: 97, temperature: 36.5)
        ]
        let url = try ResearchRawDataExport.writeNightReportCSV(samples: samples, nightDate: t0)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("iso8601_timestamp"))
        XCTAssertTrue(text.contains("200000.0") || text.contains("200000"))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Oralable_NIGHT_"))
        XCTAssertGreaterThan(text.split(whereSeparator: \.isNewline).count, 1)
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
