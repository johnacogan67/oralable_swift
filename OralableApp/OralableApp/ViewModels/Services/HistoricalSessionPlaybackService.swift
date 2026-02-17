//
//  HistoricalSessionPlaybackService.swift
//  OralableApp
//
//  Service responsible for session playback in the historical view.
//  Manages loading recording sessions, providing session data points,
//  and tracking playback state.
//
//  Extracted from HistoricalViewModel.swift for better separation of concerns.
//
//  Created: February 2026
//

import Foundation
import Combine

/// Service that manages session playback state and data loading
/// for the historical view.
@MainActor
class HistoricalSessionPlaybackService: ObservableObject {

    // MARK: - Published Properties

    /// The loaded recording session (nil = live mode)
    @Published var loadedSession: RecordingSession?

    /// Session data points loaded from CSV file
    @Published private(set) var sessionDataPoints: [HistoricalDataPoint] = []

    // MARK: - Internal Properties

    /// Metric type filter for session data (e.g., "EMG Activity", "Movement", "Temperature")
    private(set) var metricTypeFilter: String = "Movement"

    // MARK: - Computed Properties

    /// Whether we're in session playback mode vs live mode
    var isSessionPlaybackMode: Bool {
        return loadedSession != nil
    }

    // MARK: - Session Playback Methods

    /// Load data from a recording session
    /// - Parameters:
    ///   - session: The recording session to load
    ///   - metricType: The metric type to display (e.g., "EMG Activity", "Movement")
    func loadSession(_ session: RecordingSession, metricType: String) {
        Logger.shared.info("[HistoricalSessionPlaybackService] Loading session: \(session.id) for metric: \(metricType)")

        self.loadedSession = session
        self.metricTypeFilter = metricType

        // Load data points from the session file
        let dataPoints = SessionDataLoader.shared.loadHistoricalDataPoints(from: session, metricType: metricType)
        self.sessionDataPoints = dataPoints

        Logger.shared.info("[HistoricalSessionPlaybackService] Loaded \(dataPoints.count) data points from session")
    }

    /// Load the most recent completed session for the current metric type
    /// - Parameters:
    ///   - sessions: Array of available recording sessions
    ///   - metricType: The metric type to display
    func loadMostRecentSession(from sessions: [RecordingSession], metricType: String) {
        // Determine device type based on metric
        let targetDeviceType: DeviceType? = metricType == "EMG Activity" ? .anr : .oralable

        let session: RecordingSession?
        if let deviceType = targetDeviceType {
            session = SessionDataLoader.shared.getMostRecentCompletedSession(from: sessions, deviceType: deviceType)
        } else {
            session = SessionDataLoader.shared.getMostRecentCompletedSession(from: sessions)
        }

        if let session = session {
            loadSession(session, metricType: metricType)
        } else {
            Logger.shared.warning("[HistoricalSessionPlaybackService] No completed sessions found for metric: \(metricType)")
            // Clear session playback mode
            self.loadedSession = nil
            self.sessionDataPoints = []
        }
    }

    /// Exit session playback mode and return to live data
    func exitSessionPlayback() {
        Logger.shared.info("[HistoricalSessionPlaybackService] Exiting session playback mode")
        self.loadedSession = nil
        self.sessionDataPoints = []
    }
}
