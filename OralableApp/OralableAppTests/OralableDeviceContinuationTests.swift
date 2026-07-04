//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//
//  Regression coverage for BLE read continuations introduced by the nRF-aligned flow.
//

import CoreBluetooth
import XCTest
@testable import OralableApp

final class OralableDeviceContinuationTests: XCTestCase {

    func testCancelPendingContinuationsResumesFirmwareConfigStateRead() async {
        let device = makeDevice()
        let assigned = expectation(description: "Firmware config-state continuation assigned")

        let task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                device.firmwareConfigStateReadContinuation = continuation
                assigned.fulfill()
            }
        }

        await fulfillment(of: [assigned], timeout: 1.0)
        device.cancelPendingContinuations()

        do {
            _ = try await task.value
            XCTFail("Expected pending firmware config-state read to be cancelled")
        } catch {
            XCTAssertNil(device.firmwareConfigStateReadContinuation)
        }
    }

    func testCancelPendingContinuationsResumesDeviceIdRead() async {
        let device = makeDevice()
        let assigned = expectation(description: "Device ID continuation assigned")

        let task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt64, Error>) in
                device.deviceIdReadContinuation = continuation
                assigned.fulfill()
            }
        }

        await fulfillment(of: [assigned], timeout: 1.0)
        device.cancelPendingContinuations()

        do {
            _ = try await task.value
            XCTFail("Expected pending Device ID read to be cancelled")
        } catch {
            XCTAssertNil(device.deviceIdReadContinuation)
        }
    }

    func testAccelerometerNotificationSetupThrowsWhenCharacteristicMissing() async {
        let device = makeDevice()

        do {
            try await device.enableAccelerometerNotifications()
            XCTFail("Expected missing accelerometer characteristic to fail discovery")
        } catch DeviceError.characteristicNotFound(let message) {
            XCTAssertTrue(message.contains("Accelerometer"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeDevice() -> OralableDevice {
        let peripheral = MockPeripheralFactory.create(identifier: UUID(), name: "Oralable Test")
        return OralableDevice(peripheral: peripheral)
    }
}
