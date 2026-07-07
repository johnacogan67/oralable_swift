//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//
//  Regression coverage for BLE GATT continuation cleanup.
//

import CoreBluetooth
import XCTest
@testable import OralableApp

final class OralableDeviceContinuationTests: XCTestCase {

    override func tearDown() {
        MockPeripheralFactory.reset()
        super.tearDown()
    }

    func testCancelPendingContinuationsFailsFirmwareConfigStateRead() async {
        let device = makeDevice()

        await assertContinuationFails(
            install: { (continuation: CheckedContinuation<Data, Error>) in
                device.firmwareConfigStateReadContinuation = continuation
            },
            trigger: {
                device.cancelPendingContinuations()
            }
        )

        XCTAssertNil(device.firmwareConfigStateReadContinuation)
    }

    func testFailPendingReadContinuationClearsDeviceIdRead() async {
        let device = makeDevice()

        await assertContinuationFails(
            install: { (continuation: CheckedContinuation<UInt64, Error>) in
                device.deviceIdReadContinuation = continuation
            },
            trigger: {
                XCTAssertTrue(device.failPendingReadContinuation(for: device.deviceIdCharUUID, with: DeviceError.invalidData))
            }
        )

        XCTAssertNil(device.deviceIdReadContinuation)
    }

    func testFailPendingReadContinuationClearsFirmwareConfigStateRead() async {
        let device = makeDevice()

        await assertContinuationFails(
            install: { (continuation: CheckedContinuation<Data, Error>) in
                device.firmwareConfigStateReadContinuation = continuation
            },
            trigger: {
                XCTAssertTrue(device.failPendingReadContinuation(for: device.firmwareConfigStateCharUUID, with: DeviceError.invalidData))
            }
        )

        XCTAssertNil(device.firmwareConfigStateReadContinuation)
    }

    private func makeDevice() -> OralableDevice {
        let peripheral = MockPeripheralFactory.create(identifier: UUID(), name: "Oralable Test")
        return OralableDevice(peripheral: peripheral)
    }

    private func assertContinuationFails<T>(
        install: @escaping (CheckedContinuation<T, Error>) -> Void,
        trigger: @escaping () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let continuationExpectation = XCTestExpectation(description: "Continuation failed")

        let task = Task {
            do {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    install(continuation)
                }
                XCTFail("Expected continuation to fail", file: file, line: line)
            } catch {
                continuationExpectation.fulfill()
            }
        }

        await Task.yield()
        trigger()
        await fulfillment(of: [continuationExpectation], timeout: 1.0)
        _ = await task.result
    }
}
