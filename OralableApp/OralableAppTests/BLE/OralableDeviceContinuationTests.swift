//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//
//  Regression tests for BLE GATT continuation cleanup.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

final class OralableDeviceContinuationTests: XCTestCase {

    func testCancelPendingContinuationsClearsFirmwareConfigStateRead() async {
        let peripheral = MockPeripheralFactory.create(identifier: UUID(), name: "Test Oralable")
        defer { MockPeripheralFactory.cleanup(peripheral: peripheral) }
        let device = OralableDevice(peripheral: peripheral)
        let resumed = expectation(description: "Firmware config-state read continuation resumed")

        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            Task {
                do {
                    _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                        device.firmwareConfigStateReadContinuation = continuation
                        ready.resume()
                    }
                    XCTFail("Expected cancellation to throw")
                } catch {
                    resumed.fulfill()
                }
            }
        }

        XCTAssertNotNil(device.firmwareConfigStateReadContinuation)
        device.cancelPendingContinuations()

        await fulfillment(of: [resumed], timeout: 1.0)
        XCTAssertNil(device.firmwareConfigStateReadContinuation)
    }
}
