//
//  DeferredConnParamUpdateTests.swift
//  OralableAppTests
//
//  Ensures deferred firmware conn-param Tasks cannot fire into a later
//  discovery CCC window after disconnect / rediscovery cleanup.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

final class DeferredConnParamUpdateTests: XCTestCase {

    override func tearDown() {
        MockPeripheralFactory.reset()
        super.tearDown()
    }

    func testDeferredConnParamCancelledByCancelPendingContinuations() async throws {
        let peripheral = MockPeripheralFactory.create(identifier: UUID(), name: "Oralable")
        let device = OralableDevice(peripheral: peripheral)

        let fired = ExpectationBox()
        device.scheduleDeferredConnParamUpdate(
            delayNanoseconds: 150_000_000,
            traceId: "test",
            onFire: { fired.value = true }
        )

        device.cancelPendingContinuations()

        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(fired.value, "Cancelled deferred conn-param Task must not fire after cleanup")
    }

    func testRescheduleCancelsPriorDeferredConnParamTask() async throws {
        let peripheral = MockPeripheralFactory.create(identifier: UUID(), name: "Oralable")
        let device = OralableDevice(peripheral: peripheral)

        let first = ExpectationBox()
        let second = ExpectationBox()

        device.scheduleDeferredConnParamUpdate(
            delayNanoseconds: 200_000_000,
            onFire: { first.value = true }
        )
        device.scheduleDeferredConnParamUpdate(
            delayNanoseconds: 200_000_000,
            onFire: { second.value = true }
        )

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(first.value, "First deferred conn-param Task must be cancelled by reschedule")
        XCTAssertTrue(second.value, "Latest deferred conn-param Task should fire")
    }
}

/// Mutable box so escaping closures can flip a flag without capturing inout.
private final class ExpectationBox: @unchecked Sendable {
    var value = false
}
