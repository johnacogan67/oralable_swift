//
//  SimulatedWornNightTests.swift
//  OralableAppTests
//

import XCTest
import OralableCore
@testable import MAMDiagnostics

final class SimulatedWornNightTests: XCTestCase {

    func testScriptClassifiesAllStatesAndWearsAtLeastFourHours() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let sensors = SimulatedWornNight.samples(endingAt: end)
        XCTAssertEqual(sensors.count, 144_000)

        let span = sensors.last!.timestamp.timeIntervalSince(sensors.first!.timestamp)
        XCTAssertGreaterThanOrEqual(span, SimulatedWornNight.durationSeconds - 0.2)

        let samples = sensors.map { NightReportSample(sensor: $0) }
        guard let analysis = OvernightStateClassifier.analyze(samples) else {
            XCTFail("Expected analysis")
            return
        }

        let states = Set(analysis.timeline.map(\.state))
        XCTAssertTrue(states.contains(.quiet))
        XCTAssertTrue(states.contains(.tonic))
        XCTAssertTrue(states.contains(.phasic))
        XCTAssertTrue(states.contains(.rescue))
        XCTAssertTrue(states.contains(.recovery))
        XCTAssertGreaterThanOrEqual(analysis.kpis.wearS, 4 * 3600 - 1)
        XCTAssertLessThan(analysis.kpis.wearS, OvernightNightReportBuilder.figureWearSeconds)
    }
}
