//
//  ProtocolASettleGateTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class ProtocolASettleGateTests: XCTestCase {

    func testMatchingSettleGenerationCanStart() {
        XCTAssertTrue(
            ProtocolASettleGate.shouldStartCues(
                isSettling: true,
                scheduledGeneration: 2,
                currentGeneration: 2
            )
        )
    }

    func testStaleGenerationDoesNotStartWhileANewerSettleIsActive() {
        XCTAssertFalse(
            ProtocolASettleGate.shouldStartCues(
                isSettling: true,
                scheduledGeneration: 1,
                currentGeneration: 2
            )
        )
    }

    func testCancelPhaseDoesNotStart() {
        XCTAssertFalse(
            ProtocolASettleGate.shouldStartCues(
                isSettling: false,
                scheduledGeneration: 1,
                currentGeneration: 1
            )
        )
    }
}

@MainActor
final class ProtocolASettleContinuationTests: XCTestCase {

    private var priorDelay: TimeInterval = 2
    private var priorThrottle = true

    override func setUp() {
        super.setUp()
        priorDelay = ProtocolASettleGate.delay
        priorThrottle = NRFConnectBLELogger.shared.throttleHighRateNotifications
    }

    override func tearDown() {
        ProtocolASettleGate.delay = priorDelay
        NRFConnectBLELogger.shared.throttleHighRateNotifications = priorThrottle
        super.tearDown()
    }

    func testCancelDuringSettleDoesNotStartSingleProtocolCues() {
        ProtocolASettleGate.delay = 0.05
        let controller = SingleProtocolASessionController()
        defer { controller.cancel() }
        controller.beginSettleThenCues()
        controller.cancel()

        let exp = expectation(description: "settle delay elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        guard case .cancelled = controller.phase else {
            return XCTFail("Expected cancelled, got \(controller.phase)")
        }
        XCTAssertFalse(controller.statusMessage.contains("Protocol A running"))
    }

    func testStaleSettleCallbackDoesNotStartDualProtocolCues() {
        ProtocolASettleGate.delay = 0.25
        let controller = DualProtocolASessionController()
        defer { controller.cancel() }
        controller.beginSettleThenCues()
        controller.cancel()
        ProtocolASettleGate.delay = 30
        controller.beginSettleThenCues()

        let exp = expectation(description: "stale settle callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        guard case .settling = controller.phase else {
            return XCTFail("Stale settle started cues: \(controller.phase) \(controller.statusMessage)")
        }
        XCTAssertEqual(controller.statusMessage, "Settling 2 s before cues…")
    }
}
