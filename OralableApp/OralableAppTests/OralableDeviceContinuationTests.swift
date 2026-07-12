//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//
//  Regression coverage for BLE async continuation cleanup.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

@MainActor
final class OralableDeviceContinuationTests: XCTestCase {

    override func tearDown() async throws {
        MockPeripheralFactory.reset()
        try await super.tearDown()
    }

    func testCancelPendingContinuationsResumesFirmwareConfigStateRead() async throws {
        let device = OralableDevice(peripheral: MockPeripheralFactory.create(identifier: UUID(), name: "Oralable"))

        let readTask = Task<Data, Error> {
            try await withCheckedThrowingContinuation { continuation in
                device.firmwareConfigStateReadContinuation = continuation
            }
        }

        await yieldUntil(device.firmwareConfigStateReadContinuation != nil)
        guard device.firmwareConfigStateReadContinuation != nil else {
            readTask.cancel()
            XCTFail("Expected the test to install a pending config-state continuation")
            return
        }

        device.cancelPendingContinuations()

        XCTAssertNil(device.firmwareConfigStateReadContinuation)
        do {
            _ = try await readTask.value
            XCTFail("Expected cancellation to fail the pending config-state read")
        } catch DeviceError.connectionFailed(let reason) {
            XCTAssertTrue(reason.contains("disconnected"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAccelerometerNotificationsMissingCharacteristicThrows() async {
        let device = OralableDevice(peripheral: MockPeripheralFactory.create(identifier: UUID(), name: "Oralable"))

        do {
            try await device.enableAccelerometerNotifications()
            XCTFail("Missing accelerometer characteristic must fail readiness setup")
        } catch DeviceError.characteristicNotFound(let reason) {
            XCTAssertTrue(reason.contains("Accelerometer characteristic"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func yieldUntil(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<10 where !condition() {
            await Task.yield()
        }
    }
}
