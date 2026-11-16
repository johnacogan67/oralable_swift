//
//  FirmwareGateGen2Tests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class FirmwareGateGen2Tests: XCTestCase {
    func testGen2RequiresCompatibilityEvidence() {
        XCTAssertTrue(FirmwareGate.requiresGen2CompatibilityEvidence("2.0.0-gen2-nrfconnect"))
        XCTAssertTrue(FirmwareGate.requiresGen2CompatibilityEvidence("v2.1.0"))
        XCTAssertFalse(FirmwareGate.requiresGen2CompatibilityEvidence("1.0.85"))
        XCTAssertFalse(FirmwareGate.requiresGen2CompatibilityEvidence(nil))
        XCTAssertFalse(FirmwareGate.requiresGen2CompatibilityEvidence("not-a-version"))
    }

    func testGen2RemainsOutsideGen1UpgradeRecommendation() {
        XCTAssertFalse(FirmwareGate.isOralableVersionOutdated("2.0.0"))
        XCTAssertFalse(FirmwareGate.isBelowRecommendedOralableVersion("2.0.0"))
    }
}
