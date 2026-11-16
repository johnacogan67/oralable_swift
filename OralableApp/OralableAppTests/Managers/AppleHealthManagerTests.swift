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
}
