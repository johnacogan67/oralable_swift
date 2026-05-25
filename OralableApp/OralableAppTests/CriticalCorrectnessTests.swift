//
//  CriticalCorrectnessTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class CriticalCorrectnessTests: XCTestCase {
    func testCalibrationActiveTimeTrackerIgnoresInactiveWallClockTime() {
        let start = Date(timeIntervalSince1970: 0)
        var tracker = CalibrationActiveTimeTracker(totalSeconds: 90)

        tracker.start(at: start, isActive: true)

        XCTAssertEqual(tracker.tick(at: start.addingTimeInterval(30), isActive: true), 30)
        XCTAssertEqual(tracker.tick(at: start.addingTimeInterval(120), isActive: false), 30)
        XCTAssertFalse(tracker.isComplete)

        XCTAssertEqual(tracker.tick(at: start.addingTimeInterval(121), isActive: true), 30)
        XCTAssertFalse(tracker.isComplete)
    }

    func testCalibrationActiveTimeTrackerCompletesAfterActiveTimeOnly() {
        let start = Date(timeIntervalSince1970: 0)
        var tracker = CalibrationActiveTimeTracker(totalSeconds: 90)

        tracker.start(at: start, isActive: true)
        _ = tracker.tick(at: start.addingTimeInterval(30), isActive: true)
        _ = tracker.tick(at: start.addingTimeInterval(120), isActive: false)
        _ = tracker.tick(at: start.addingTimeInterval(121), isActive: true)

        XCTAssertEqual(tracker.tick(at: start.addingTimeInterval(181), isActive: true), 90)
        XCTAssertTrue(tracker.isComplete)
    }

    func testSharedDataUploadDecisionDefersRequestsDuringInFlightSync() {
        let decision = SharedDataUploadDecision.evaluate(
            now: Date(timeIntervalSince1970: 100),
            isSyncing: true,
            lastSyncDate: nil,
            coalesceInterval: 20
        )

        XCTAssertEqual(decision, .deferUpload(0.5))
    }

    func testSharedDataUploadDecisionDefersRecentSyncUntilCoalesceWindow() {
        let now = Date(timeIntervalSince1970: 100)
        let decision = SharedDataUploadDecision.evaluate(
            now: now,
            isSyncing: false,
            lastSyncDate: now.addingTimeInterval(-5),
            coalesceInterval: 20
        )

        guard case .deferUpload(let delay) = decision else {
            XCTFail("Expected recent sync request to be deferred")
            return
        }
        XCTAssertEqual(delay, 15, accuracy: 0.001)
    }

    func testSharedDataUploadDecisionUploadsWhenOutsideCoalesceWindow() {
        let now = Date(timeIntervalSince1970: 100)
        let decision = SharedDataUploadDecision.evaluate(
            now: now,
            isSyncing: false,
            lastSyncDate: now.addingTimeInterval(-21),
            coalesceInterval: 20
        )

        XCTAssertEqual(decision, .uploadNow)
    }
}
