//
//  AppleHealthManagerTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class AppleHealthManagerTests: XCTestCase {

    func testDownsampleKeepsOneSamplePerInterval() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [(Date, Double)] = []
        for i in 0..<20 {
            samples.append((t0.addingTimeInterval(Double(i)), Double(60 + i)))
        }
        let down = AppleHealthManager.downsample(samples, interval: 5)
        XCTAssertEqual(down.count, 4)
        XCTAssertEqual(down.first?.1, 64, accuracy: 0.01) // last in first 5 s bucket (t=0..4)
        XCTAssertEqual(down.last?.1, 79, accuracy: 0.01)
    }

    func testDownsampleEmpty() {
        XCTAssertTrue(AppleHealthManager.downsample([]).isEmpty)
    }

    func testSpO2SeriesUsesOneSecondWindows() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let starts = [t0, t0.addingTimeInterval(5), t0.addingTimeInterval(10)]
        let ends = starts.map {
            AppleHealthManager.spo2SampleEnd(start: $0, sampleCount: starts.count)
        }
        XCTAssertEqual(ends[0], t0.addingTimeInterval(1))
        XCTAssertEqual(ends[1], t0.addingTimeInterval(6))
        XCTAssertEqual(ends[2], t0.addingTimeInterval(11))
        XCTAssertLessThan(ends[0], starts[1])
    }

    func testSingleSessionMeanSpO2CanSpanTheSession() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = start.addingTimeInterval(8 * 3600)
        let end = AppleHealthManager.spo2SampleEnd(start: start, sampleCount: 1, sessionEnd: sessionEnd)
        XCTAssertEqual(end, sessionEnd)
    }
}
