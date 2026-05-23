//
//  DeviceManagerTimeoutTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

@MainActor
final class DeviceManagerTimeoutTests: XCTestCase {

    func testWithTimeoutRunsTimeoutHandlerForContinuationBackedOperation() async {
        let sut = DeviceManager(bleService: MockBLEService(bluetoothState: .poweredOn))
        let state = TimeoutContinuationState()

        do {
            try await sut.withTimeout(seconds: 0.1, onTimeout: {
                let continuation = state.markTimedOutAndTakeContinuation()
                continuation?.resume(throwing: DeviceError.timeout)
            }) {
                try await withCheckedThrowingContinuation { continuation in
                    state.store(continuation)
                }
            }

            XCTFail("Expected the operation to time out")
        } catch {
            XCTAssertTrue(state.didTimeOut)
            XCTAssertTrue(state.isCleared)
        }
    }
}

private final class TimeoutContinuationState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.oralable.tests.with-timeout-state")
    private var pendingContinuation: CheckedContinuation<Void, Error>?
    private var timeoutHandlerCalled = false

    var didTimeOut: Bool {
        queue.sync { timeoutHandlerCalled }
    }

    var isCleared: Bool {
        queue.sync { pendingContinuation == nil }
    }

    func store(_ continuation: CheckedContinuation<Void, Error>) {
        queue.sync {
            pendingContinuation = continuation
        }
    }

    func markTimedOutAndTakeContinuation() -> CheckedContinuation<Void, Error>? {
        queue.sync {
            timeoutHandlerCalled = true
            let continuation = pendingContinuation
            pendingContinuation = nil
            return continuation
        }
    }
}
