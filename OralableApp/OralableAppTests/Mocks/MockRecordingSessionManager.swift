//
//  MockRecordingSessionManager.swift
//  OralableAppTests
//
//  Created: Refactoring Phase 2
//  Purpose: Mock recording session manager for testing
//

import Foundation
import Combine
@testable import MAMDiagnostics

/// Mock Recording Session Manager for unit testing
/// Allows tests to simulate recording session behavior without actual file operations
@MainActor
class MockRecordingSessionManager: RecordingSessionManagerProtocol {
    // MARK: - Session State
    @Published var currentSession: RecordingSession? = nil
    @Published var sessions: [RecordingSession] = []

    // MARK: - Test Helpers
    var startSessionCalled = false
    var stopSessionCalled = false
    var pauseSessionCalled = false
    var resumeSessionCalled = false
    var recordSensorDataCalled: [String] = []
    var deleteSessionCalled: [RecordingSession] = []
    var lastStartSessionDeviceType: DeviceType?

    var startSessionError: Error?
    var stopSessionError: Error?
    var pauseSessionError: Error?
    var resumeSessionError: Error?

    var mockSession: RecordingSession?

    // MARK: - Session Management
    func startSession(deviceID: String?, deviceName: String?, deviceType: DeviceType?) throws -> RecordingSession {
        startSessionCalled = true
        lastStartSessionDeviceType = deviceType

        if let error = startSessionError {
            throw error
        }

        let session = mockSession ?? RecordingSession(
            deviceID: deviceID,
            deviceName: deviceName,
            deviceType: deviceType
        )

        currentSession = session
        sessions.insert(session, at: 0)

        return session
    }

    func stopSession() throws {
        stopSessionCalled = true

        if let error = stopSessionError {
            throw error
        }

        guard var session = currentSession else {
            throw DeviceError.recordingNotInProgress
        }

        session.endTime = Date()
        session.status = .completed

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }

        currentSession = nil
    }

    func pauseSession() throws {
        pauseSessionCalled = true

        if let error = pauseSessionError {
            throw error
        }

        guard var session = currentSession else {
            throw DeviceError.recordingNotInProgress
        }

        session.status = .paused

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    func resumeSession() throws {
        resumeSessionCalled = true

        if let error = resumeSessionError {
            throw error
        }

        guard var session = currentSession else {
            throw DeviceError.recordingNotInProgress
        }

        session.status = .recording

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    // MARK: - Data Recording
    func recordSensorData(_ data: String) {
        recordSensorDataCalled.append(data)

        guard currentSession != nil, currentSession?.status == .recording else {
            return
        }

        currentSession?.sensorDataCount += 1

        if let session = currentSession,
           let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    // MARK: - Session Management
    func deleteSession(_ session: RecordingSession) {
        deleteSessionCalled.append(session)
        sessions.removeAll { $0.id == session.id }

        if currentSession?.id == session.id {
            currentSession = nil
        }
    }

    // MARK: - Publishers
    var currentSessionPublisher: Published<RecordingSession?>.Publisher { $currentSession }
    var sessionsPublisher: Published<[RecordingSession]>.Publisher { $sessions }

    // MARK: - Test Simulation Methods

    /// Simulate starting a session with a specific session object
    func simulateSession(_ session: RecordingSession) {
        currentSession = session
        sessions.insert(session, at: 0)
    }

    /// Simulate completing the current session
    func simulateSessionCompletion() {
        guard var session = currentSession else { return }

        session.endTime = Date()
        session.status = .completed

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }

        currentSession = nil
    }

    /// Reset all test flags
    func reset() {
        startSessionCalled = false
        stopSessionCalled = false
        pauseSessionCalled = false
        resumeSessionCalled = false
        recordSensorDataCalled = []
        deleteSessionCalled = []
        lastStartSessionDeviceType = nil
        startSessionError = nil
        stopSessionError = nil
        pauseSessionError = nil
        resumeSessionError = nil
        mockSession = nil
        currentSession = nil
        sessions = []
    }
}
