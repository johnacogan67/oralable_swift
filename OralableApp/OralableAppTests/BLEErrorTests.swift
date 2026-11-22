//
//  BLEErrorTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Unit tests for BLEError enum covering all error cases and properties
//

import XCTest
import CoreBluetooth
@testable import MAMDiagnostics

final class BLEErrorTests: XCTestCase {

    // MARK: - Bluetooth State Error Tests

    func testBluetoothNotReadyErrorDescription() {
        // Given
        let error = BLEError.bluetoothNotReady(state: .poweredOff)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not ready"))
        XCTAssertTrue(error.errorDescription!.contains("Powered Off"))
    }

    func testBluetoothUnauthorizedErrorDescription() {
        // Given
        let error = BLEError.bluetoothUnauthorized

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not authorized"))
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion!.contains("Settings"))
    }

    func testBluetoothUnsupportedErrorDescription() {
        // Given
        let error = BLEError.bluetoothUnsupported

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not supported"))
    }

    func testBluetoothResettingErrorDescription() {
        // Given
        let error = BLEError.bluetoothResetting

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("resetting"))
    }

    // MARK: - Connection Error Tests

    func testConnectionFailedErrorDescription() {
        // Given
        let peripheralId = UUID()
        let reason = "Device not responding"
        let error = BLEError.connectionFailed(peripheralId: peripheralId, reason: reason)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Connection failed"))
        XCTAssertTrue(error.errorDescription!.contains(reason))
    }

    func testConnectionFailedWithNilReason() {
        // Given
        let peripheralId = UUID()
        let error = BLEError.connectionFailed(peripheralId: peripheralId, reason: nil)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Unknown reason"))
    }

    func testConnectionTimeoutErrorDescription() {
        // Given
        let peripheralId = UUID()
        let timeout: TimeInterval = 15.0
        let error = BLEError.connectionTimeout(peripheralId: peripheralId, timeoutSeconds: timeout)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("timed out"))
        XCTAssertTrue(error.errorDescription!.contains("15"))
    }

    func testUnexpectedDisconnectionErrorDescription() {
        // Given
        let peripheralId = UUID()
        let reason = "Connection lost"
        let error = BLEError.unexpectedDisconnection(peripheralId: peripheralId, reason: reason)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("unexpectedly"))
        XCTAssertTrue(error.errorDescription!.contains(reason))
    }

    func testPeripheralNotFoundErrorDescription() {
        // Given
        let peripheralId = UUID()
        let error = BLEError.peripheralNotFound(peripheralId: peripheralId)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not found"))
    }

    func testPeripheralNotConnectedErrorDescription() {
        // Given
        let peripheralId = UUID()
        let error = BLEError.peripheralNotConnected(peripheralId: peripheralId)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not connected"))
    }

    func testMaxReconnectionAttemptsExceededErrorDescription() {
        // Given
        let peripheralId = UUID()
        let attempts = 5
        let error = BLEError.maxReconnectionAttemptsExceeded(peripheralId: peripheralId, attempts: attempts)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("5"))
        XCTAssertTrue(error.errorDescription!.contains("reconnect"))
    }

    // MARK: - Discovery Error Tests

    func testServiceNotFoundErrorDescription() {
        // Given
        let serviceUUID = CBUUID(string: "180D")
        let peripheralId = UUID()
        let error = BLEError.serviceNotFound(serviceUUID: serviceUUID, peripheralId: peripheralId)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("service not found"))
        XCTAssertTrue(error.errorDescription!.contains("180D"))
    }

    func testCharacteristicNotFoundErrorDescription() {
        // Given
        let characteristicUUID = CBUUID(string: "2A37")
        let serviceUUID = CBUUID(string: "180D")
        let error = BLEError.characteristicNotFound(characteristicUUID: characteristicUUID, serviceUUID: serviceUUID)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("characteristic not found"))
        XCTAssertTrue(error.errorDescription!.contains("2A37"))
    }

    func testServiceDiscoveryFailedErrorDescription() {
        // Given
        let peripheralId = UUID()
        let reason = "Timeout during discovery"
        let error = BLEError.serviceDiscoveryFailed(peripheralId: peripheralId, reason: reason)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Service discovery failed"))
        XCTAssertTrue(error.errorDescription!.contains(reason))
    }

    // MARK: - Data Transfer Error Tests

    func testWriteFailedErrorDescription() {
        // Given
        let characteristicUUID = CBUUID(string: "2A37")
        let reason = "Permission denied"
        let error = BLEError.writeFailed(characteristicUUID: characteristicUUID, reason: reason)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Write"))
        XCTAssertTrue(error.errorDescription!.contains(reason))
    }

    func testReadFailedErrorDescription() {
        // Given
        let characteristicUUID = CBUUID(string: "2A37")
        let reason = "Not readable"
        let error = BLEError.readFailed(characteristicUUID: characteristicUUID, reason: reason)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Read"))
        XCTAssertTrue(error.errorDescription!.contains(reason))
    }

    func testDataCorruptedErrorDescription() {
        // Given
        let description = "Invalid checksum"
        let error = BLEError.dataCorrupted(description: description)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("corrupted"))
        XCTAssertTrue(error.errorDescription!.contains(description))
    }

    func testDataValidationFailedErrorDescription() {
        // Given
        let expected = "32 bytes"
        let received = "16 bytes"
        let error = BLEError.dataValidationFailed(expected: expected, received: received)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(expected))
        XCTAssertTrue(error.errorDescription!.contains(received))
    }

    func testInvalidDataFormatErrorDescription() {
        // Given
        let description = "Expected UTF-8 string"
        let error = BLEError.invalidDataFormat(description: description)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid data format"))
        XCTAssertTrue(error.errorDescription!.contains(description))
    }

    // MARK: - Operation Error Tests

    func testTimeoutErrorDescription() {
        // Given
        let operation = "Service discovery"
        let timeout: TimeInterval = 10.0
        let error = BLEError.timeout(operation: operation, timeoutSeconds: timeout)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(operation))
        XCTAssertTrue(error.errorDescription!.contains("10"))
    }

    func testCancelledErrorDescription() {
        // Given
        let operation = "Data transfer"
        let error = BLEError.cancelled(operation: operation)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(operation))
        XCTAssertTrue(error.errorDescription!.contains("cancelled"))
    }

    func testOperationNotPermittedErrorDescription() {
        // Given
        let operation = "Write"
        let currentState = "disconnected"
        let error = BLEError.operationNotPermitted(operation: operation, currentState: currentState)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(operation))
        XCTAssertTrue(error.errorDescription!.contains(currentState))
    }

    func testAlreadyScanningErrorDescription() {
        // Given
        let error = BLEError.alreadyScanning

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Already scanning"))
    }

    func testNotScanningErrorDescription() {
        // Given
        let error = BLEError.notScanning

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Not currently scanning"))
    }

    // MARK: - Internal Error Tests

    func testInternalErrorDescription() {
        // Given
        let reason = "Unexpected state"
        let underlyingError = NSError(domain: "TestDomain", code: -1)
        let error = BLEError.internalError(reason: reason, underlyingError: underlyingError)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Internal error"))
        XCTAssertTrue(error.errorDescription!.contains(reason))
    }

    func testUnknownErrorDescription() {
        // Given
        let description = "Something went wrong"
        let error = BLEError.unknown(description: description)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(description))
    }

    // MARK: - Error Classification Tests

    func testIsRecoverableProperty() {
        // Recoverable errors
        XCTAssertTrue(BLEError.connectionTimeout(peripheralId: UUID(), timeoutSeconds: 10).isRecoverable)
        XCTAssertTrue(BLEError.unexpectedDisconnection(peripheralId: UUID(), reason: nil).isRecoverable)
        XCTAssertTrue(BLEError.timeout(operation: "test", timeoutSeconds: 10).isRecoverable)
        XCTAssertTrue(BLEError.bluetoothResetting.isRecoverable)
        XCTAssertTrue(BLEError.dataCorrupted(description: "test").isRecoverable)

        // Non-recoverable errors
        XCTAssertFalse(BLEError.bluetoothUnauthorized.isRecoverable)
        XCTAssertFalse(BLEError.bluetoothUnsupported.isRecoverable)
        XCTAssertFalse(BLEError.maxReconnectionAttemptsExceeded(peripheralId: UUID(), attempts: 5).isRecoverable)
        XCTAssertFalse(BLEError.cancelled(operation: "test").isRecoverable)
    }

    func testShouldTriggerReconnectionProperty() {
        // Should trigger reconnection
        XCTAssertTrue(BLEError.unexpectedDisconnection(peripheralId: UUID(), reason: nil).shouldTriggerReconnection)
        XCTAssertTrue(BLEError.connectionTimeout(peripheralId: UUID(), timeoutSeconds: 10).shouldTriggerReconnection)

        // Should NOT trigger reconnection
        XCTAssertFalse(BLEError.bluetoothUnauthorized.shouldTriggerReconnection)
        XCTAssertFalse(BLEError.bluetoothNotReady(state: .poweredOff).shouldTriggerReconnection)
        XCTAssertFalse(BLEError.dataCorrupted(description: "test").shouldTriggerReconnection)
    }

    func testSeverityProperty() {
        // Info severity
        XCTAssertEqual(BLEError.alreadyScanning.severity, .info)
        XCTAssertEqual(BLEError.notScanning.severity, .info)
        XCTAssertEqual(BLEError.cancelled(operation: "test").severity, .info)

        // Warning severity
        XCTAssertEqual(BLEError.bluetoothResetting.severity, .warning)
        XCTAssertEqual(BLEError.timeout(operation: "test", timeoutSeconds: 10).severity, .warning)
        XCTAssertEqual(BLEError.connectionTimeout(peripheralId: UUID(), timeoutSeconds: 10).severity, .warning)

        // Error severity
        XCTAssertEqual(BLEError.bluetoothNotReady(state: .poweredOff).severity, .error)
        XCTAssertEqual(BLEError.connectionFailed(peripheralId: UUID(), reason: nil).severity, .error)
        XCTAssertEqual(BLEError.unexpectedDisconnection(peripheralId: UUID(), reason: nil).severity, .error)
        XCTAssertEqual(BLEError.dataCorrupted(description: "test").severity, .error)

        // Critical severity
        XCTAssertEqual(BLEError.bluetoothUnauthorized.severity, .critical)
        XCTAssertEqual(BLEError.bluetoothUnsupported.severity, .critical)
        XCTAssertEqual(BLEError.internalError(reason: "test", underlyingError: nil).severity, .critical)
    }

    // MARK: - Recovery Suggestion Tests

    func testRecoverySuggestionsExist() {
        // Errors with recovery suggestions
        XCTAssertNotNil(BLEError.bluetoothNotReady(state: .poweredOff).recoverySuggestion)
        XCTAssertNotNil(BLEError.bluetoothUnauthorized.recoverySuggestion)
        XCTAssertNotNil(BLEError.connectionFailed(peripheralId: UUID(), reason: nil).recoverySuggestion)
        XCTAssertNotNil(BLEError.connectionTimeout(peripheralId: UUID(), timeoutSeconds: 10).recoverySuggestion)
        XCTAssertNotNil(BLEError.peripheralNotFound(peripheralId: UUID()).recoverySuggestion)
        XCTAssertNotNil(BLEError.maxReconnectionAttemptsExceeded(peripheralId: UUID(), attempts: 5).recoverySuggestion)
        XCTAssertNotNil(BLEError.dataCorrupted(description: "test").recoverySuggestion)
    }

    func testRecoverySuggestionContent() {
        // Bluetooth authorization suggestion should mention Settings
        let authError = BLEError.bluetoothUnauthorized
        XCTAssertTrue(authError.recoverySuggestion!.contains("Settings"))

        // Connection failed suggestion should mention trying again
        let connError = BLEError.connectionFailed(peripheralId: UUID(), reason: nil)
        XCTAssertTrue(connError.recoverySuggestion!.contains("try again"))
    }

    // MARK: - Failure Reason Tests

    func testFailureReasonExists() {
        XCTAssertNotNil(BLEError.bluetoothNotReady(state: .poweredOff).failureReason)
        XCTAssertNotNil(BLEError.bluetoothUnauthorized.failureReason)
        XCTAssertNotNil(BLEError.connectionTimeout(peripheralId: UUID(), timeoutSeconds: 10).failureReason)
        XCTAssertNotNil(BLEError.dataCorrupted(description: "test").failureReason)
    }

    // MARK: - Equatable Tests

    func testEquatableForBluetoothErrors() {
        // Same errors should be equal
        XCTAssertEqual(BLEError.bluetoothUnauthorized, BLEError.bluetoothUnauthorized)
        XCTAssertEqual(BLEError.bluetoothUnsupported, BLEError.bluetoothUnsupported)
        XCTAssertEqual(BLEError.bluetoothResetting, BLEError.bluetoothResetting)
        XCTAssertEqual(BLEError.alreadyScanning, BLEError.alreadyScanning)
        XCTAssertEqual(BLEError.notScanning, BLEError.notScanning)

        // Same state should be equal
        XCTAssertEqual(
            BLEError.bluetoothNotReady(state: .poweredOff),
            BLEError.bluetoothNotReady(state: .poweredOff)
        )

        // Different states should not be equal
        XCTAssertNotEqual(
            BLEError.bluetoothNotReady(state: .poweredOff),
            BLEError.bluetoothNotReady(state: .unauthorized)
        )
    }

    func testEquatableForConnectionErrors() {
        let id1 = UUID()
        let id2 = UUID()

        // Same peripheral ID should be equal (reason ignored for equality)
        XCTAssertEqual(
            BLEError.connectionFailed(peripheralId: id1, reason: "reason1"),
            BLEError.connectionFailed(peripheralId: id1, reason: "reason2")
        )

        // Different peripheral IDs should not be equal
        XCTAssertNotEqual(
            BLEError.connectionFailed(peripheralId: id1, reason: nil),
            BLEError.connectionFailed(peripheralId: id2, reason: nil)
        )
    }

    func testEquatableForTimeoutErrors() {
        // Same operation should be equal (timeout ignored for equality)
        XCTAssertEqual(
            BLEError.timeout(operation: "scan", timeoutSeconds: 10),
            BLEError.timeout(operation: "scan", timeoutSeconds: 20)
        )

        // Different operations should not be equal
        XCTAssertNotEqual(
            BLEError.timeout(operation: "scan", timeoutSeconds: 10),
            BLEError.timeout(operation: "connect", timeoutSeconds: 10)
        )
    }

    // MARK: - Error Severity Comparison Tests

    func testSeverityComparison() {
        XCTAssertTrue(BLEErrorSeverity.info < BLEErrorSeverity.warning)
        XCTAssertTrue(BLEErrorSeverity.warning < BLEErrorSeverity.error)
        XCTAssertTrue(BLEErrorSeverity.error < BLEErrorSeverity.critical)
        XCTAssertFalse(BLEErrorSeverity.critical < BLEErrorSeverity.info)
    }

    // MARK: - LocalizedError Conformance Tests

    func testConformsToLocalizedError() {
        let error: LocalizedError = BLEError.connectionFailed(peripheralId: UUID(), reason: "test")

        XCTAssertNotNil(error.errorDescription)
        // failureReason and recoverySuggestion may or may not be present depending on error type
    }

    // MARK: - Type Alias Tests

    func testBLEServiceErrorAlias() {
        // BLEServiceError should be an alias for BLEError
        let error: BLEServiceError = .bluetoothUnauthorized
        XCTAssertEqual(error, BLEError.bluetoothUnauthorized)
    }
}
