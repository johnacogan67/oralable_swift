//
//  HistoricalTimeRangeService.swift
//  OralableApp
//
//  Service responsible for time range navigation and formatting
//  in the historical view. Manages time range selection, offset navigation,
//  and display text generation.
//
//  Extracted from HistoricalViewModel.swift for better separation of concerns.
//
//  Created: February 2026
//

import Foundation

/// Service that manages time range state, navigation, and formatting
/// for the historical view.
@MainActor
class HistoricalTimeRangeService: ObservableObject {

    // MARK: - Published Properties

    /// Current offset from present time (0 = current period, -1 = previous period, etc.)
    @Published var timeRangeOffset: Int = 0

    // MARK: - Computed Properties

    /// Whether the selected time range is the current period (today/this week/this month)
    func isCurrentTimeRange(isSessionPlaybackMode: Bool) -> Bool {
        if isSessionPlaybackMode {
            return true  // Session playback doesn't support time range navigation
        }
        return timeRangeOffset == 0
    }

    // MARK: - Time Range Navigation

    /// Select a specific time range (resets offset)
    /// - Parameters:
    ///   - range: The time range to select
    ///   - selectedTimeRange: Binding to update on the caller
    ///   - isSessionPlaybackMode: Whether session playback is active
    ///   - onRangeChanged: Callback for when the range actually changes
    func selectTimeRange(_ range: TimeRange, isSessionPlaybackMode: Bool) {
        if isSessionPlaybackMode { return }  // Disabled in session playback
        // The caller (HistoricalViewModel) is responsible for updating selectedTimeRange
    }

    /// Move to next time range (forward in time, toward present)
    /// - Parameters:
    ///   - isSessionPlaybackMode: Whether session playback is active
    ///   - onOffsetChanged: Callback when offset changes, for triggering metrics update
    func selectNextTimeRange(isSessionPlaybackMode: Bool, onOffsetChanged: (() -> Void)? = nil) {
        if isSessionPlaybackMode { return }
        if timeRangeOffset < 0 {
            timeRangeOffset += 1
            onOffsetChanged?()
        }
    }

    /// Move to previous time range (backward in time)
    /// - Parameters:
    ///   - isSessionPlaybackMode: Whether session playback is active
    ///   - onOffsetChanged: Callback when offset changes, for triggering metrics update
    func selectPreviousTimeRange(isSessionPlaybackMode: Bool, onOffsetChanged: (() -> Void)? = nil) {
        if isSessionPlaybackMode { return }
        timeRangeOffset -= 1
        onOffsetChanged?()
    }

    // MARK: - Display Text

    /// Time range display text
    func timeRangeText(
        selectedTimeRange: TimeRange,
        isSessionPlaybackMode: Bool,
        loadedSession: RecordingSession?
    ) -> String {
        if isSessionPlaybackMode {
            if let session = loadedSession {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "Session: \(formatter.string(from: session.startTime))"
            }
            return "Session Playback"
        }

        if timeRangeOffset == 0 {
            switch selectedTimeRange {
            case .minute: return "This Minute"
            case .hour: return "This Hour"
            case .day: return "Today"
            case .week: return "This Week"
            case .month: return "This Month"
            }
        } else if timeRangeOffset == -1 {
            switch selectedTimeRange {
            case .minute: return "Last Minute"
            case .hour: return "Last Hour"
            case .day: return "Yesterday"
            case .week: return "Last Week"
            case .month: return "Last Month"
            }
        } else {
            let absoluteOffset = abs(timeRangeOffset)
            switch selectedTimeRange {
            case .minute: return "\(absoluteOffset) Minutes Ago"
            case .hour: return "\(absoluteOffset) Hours Ago"
            case .day: return "\(absoluteOffset) Days Ago"
            case .week: return "\(absoluteOffset) Weeks Ago"
            case .month: return "\(absoluteOffset) Months Ago"
            }
        }
    }

    /// Date range text for display
    func dateRangeText(
        isSessionPlaybackMode: Bool,
        loadedSession: RecordingSession?,
        currentMetrics: HistoricalMetrics?
    ) -> String {
        if isSessionPlaybackMode {
            guard let session = loadedSession else { return "No session" }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let start = formatter.string(from: session.startTime)
            if let endTime = session.endTime {
                let end = formatter.string(from: endTime)
                return "\(start) - \(end)"
            }
            return "Started: \(start)"
        }

        guard let metrics = currentMetrics else {
            return "No data"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none

        let start = formatter.string(from: metrics.startDate)
        let end = formatter.string(from: metrics.endDate)

        return "\(start) - \(end)"
    }

    // MARK: - Formatting Helpers

    /// Format a data point's timestamp based on context
    func formatTimestamp(
        _ date: Date,
        selectedTimeRange: TimeRange,
        isSessionPlaybackMode: Bool
    ) -> String {
        let formatter = DateFormatter()

        if isSessionPlaybackMode {
            // For session playback, show full time
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: date)
        }

        switch selectedTimeRange {
        case .minute:
            formatter.dateFormat = "HH:mm:ss"
        case .hour, .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "EEE"
        case .month:
            formatter.dateFormat = "MMM d"
        }

        return formatter.string(from: date)
    }

    /// Format temperature value
    func formatTemperature(_ temp: Double) -> String {
        String(format: "%.1f\u{00B0}C", temp)
    }

    /// Format battery value
    func formatBattery(_ battery: Int) -> String {
        "\(battery)%"
    }

    /// Format heart rate value
    func formatHeartRate(_ hr: Double?) -> String {
        guard let hr = hr else { return "--" }
        return String(format: "%.0f bpm", hr)
    }

    /// Format SpO2 value
    func formatSpO2(_ spo2: Double?) -> String {
        guard let spo2 = spo2 else { return "--" }
        return String(format: "%.0f%%", spo2)
    }
}
