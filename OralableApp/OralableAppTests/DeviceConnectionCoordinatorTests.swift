//
//  DeviceConnectionCoordinatorTests.swift
//  OralableAppTests
//
//  Regression tests for BLE connection timeout coordination.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

@MainActor
final class DeviceConnectionCoordinatorTests: XCTestCase {

    private var sut: DeviceManager!
    private var mockBLEService: MockBLEService!

    override func setUp() async throws {
        try await super.setUp()
        mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        sut = DeviceManager(bleService: mockBLEService)
    }

    override func tearDown() async throws {
        sut = nil
        mockBLEService = nil
        try await super.tearDown()
    }

    func testWithTimeoutRunsTimeoutHandlerBeforeThrowing() async {
        var pendingContinuation: CheckedContinuation<Void, Error>?
        var handlerCalled = false
        let operationStarted = expectation(description: "operation started")

        let timeoutTask = Task {
            try await sut.withTimeout(seconds: 0.05, timeoutHandler: {
                handlerCalled = true
                pendingContinuation?.resume(throwing: DeviceError.timeout)
                pendingContinuation = nil
            }) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    pendingContinuation = continuation
                    operationStarted.fulfill()
                }
            }
        }

        await fulfillment(of: [operationStarted], timeout: 1.0)

        do {
            try await timeoutTask.value
            XCTFail("Expected timeout to throw")
        } catch {
            XCTAssertTrue(handlerCalled)
            XCTAssertEqual(error.localizedDescription, DeviceError.timeout.localizedDescription)
        }
    }
}
