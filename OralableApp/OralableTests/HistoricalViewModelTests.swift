//
//  HistoricalViewModelTests.swift
//  OralableApp
//
//  Created by John A Cogan on 07/11/2025.
//


//
//  HistoricalViewModelTests.swift
//  OralableAppTests
//
//  Created: November 7, 2025
//  Testing HistoricalViewModel functionality
//

import XCTest
import Combine
@testable import MAMDiagnostics

class HistoricalViewModelTests: XCTestCase {
    
    var viewModel: HistoricalViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        viewModel = HistoricalViewModel()
        cancellables = []
    }
    
    override func tearDown() {
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.selectedSession)
        XCTAssertEqual(viewModel.selectedDateRange, .week)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isExporting)
        XCTAssertTrue(viewModel.filteredSessions.isEmpty)
    }
    
    // MARK: - Session Management Tests
    
    func testAddSession() {
        // Given
        let session = RecordingSession(
            id: UUID(),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            deviceName: "Oralable-001",
            dataPoints: 1000
        )
        
        // When
        viewModel.addSession(session)
        
        // Then
        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions.first?.id, session.id)
        XCTAssertEqual(viewModel.sessions.first?.deviceName, "Oralable-001")
    }
    
    func testDeleteSession() {
        // Given
        let session = RecordingSession(
            id: UUID(),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            deviceName: "Oralable-001",
            dataPoints: 1000
        )
        viewModel.addSession(session)
        
        // When
        viewModel.deleteSession(session)
        
        // Then
        XCTAssertTrue(viewModel.sessions.isEmpty)
    }
    
    func testSelectSession() {
        // Given
        let session = RecordingSession(
            id: UUID(),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            deviceName: "Oralable-001",
            dataPoints: 1000
        )
        viewModel.addSession(session)
        
        // When
        viewModel.selectSession(session)
        
        // Then
        XCTAssertEqual(viewModel.selectedSession?.id, session.id)
        XCTAssertTrue(viewModel.isLoadingSessionData)
    }
    
    // MARK: - Date Range Filter Tests
    
    func testDateRangeFilter() {
        // Add sessions across different dates
        let today = Date()
        let yesterday = today.addingTimeInterval(-86400)
        let lastWeek = today.addingTimeInterval(-604800)
        let lastMonth = today.addingTimeInterval(-2592000)
        
        let session1 = RecordingSession(id: UUID(), startDate: today, endDate: today.addingTimeInterval(3600), deviceName: "Device1", dataPoints: 100)
        let session2 = RecordingSession(id: UUID(), startDate: yesterday, endDate: yesterday.addingTimeInterval(3600), deviceName: "Device2", dataPoints: 200)
        let session3 = RecordingSession(id: UUID(), startDate: lastWeek, endDate: lastWeek.addingTimeInterval(3600), deviceName: "Device3", dataPoints: 300)
        let session4 = RecordingSession(id: UUID(), startDate: lastMonth, endDate: lastMonth.addingTimeInterval(3600), deviceName: "Device4", dataPoints: 400)
        
        viewModel.addSession(session1)
        viewModel.addSession(session2)
        viewModel.addSession(session3)
        viewModel.addSession(session4)
        
        // Test day filter
        viewModel.selectedDateRange = .day
        viewModel.applyDateFilter()
        XCTAssertEqual(viewModel.filteredSessions.count, 1)
        
        // Test week filter
        viewModel.selectedDateRange = .week
        viewModel.applyDateFilter()
        XCTAssertEqual(viewModel.filteredSessions.count, 3)
        
        // Test month filter
        viewModel.selectedDateRange = .month
        viewModel.applyDateFilter()
        XCTAssertEqual(viewModel.filteredSessions.count, 4)
        
        // Test all filter
        viewModel.selectedDateRange = .all
        viewModel.applyDateFilter()
        XCTAssertEqual(viewModel.filteredSessions.count, 4)
    }
    
    func testCustomDateRange() {
        // Given
        let startDate = Date().addingTimeInterval(-172800) // 2 days ago
        let endDate = Date()
        
        // Add sessions
        let session1 = RecordingSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), deviceName: "Device1", dataPoints: 100)
        let session2 = RecordingSession(id: UUID(), startDate: Date().addingTimeInterval(-86400), endDate: Date().addingTimeInterval(-82800), deviceName: "Device2", dataPoints: 200)
        let session3 = RecordingSession(id: UUID(), startDate: Date().addingTimeInterval(-259200), endDate: Date().addingTimeInterval(-255600), deviceName: "Device3", dataPoints: 300) // 3 days ago
        
        viewModel.addSession(session1)
        viewModel.addSession(session2)
        viewModel.addSession(session3)
        
        // When
        viewModel.setCustomDateRange(start: startDate, end: endDate)
        
        // Then
        XCTAssertEqual(viewModel.filteredSessions.count, 2, "Should only include sessions within custom range")
    }
    
    // MARK: - Data Loading Tests
    
    func testLoadSessionData() {
        // Given
        let session = RecordingSession(
            id: UUID(),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            deviceName: "Oralable-001",
            dataPoints: 1000
        )
        
        // When
        viewModel.loadSessionData(for: session)
        
        // Then
        XCTAssertTrue(viewModel.isLoadingSessionData)
        XCTAssertNotNil(viewModel.currentSessionData)
    }
    
    func testDataAggregation() {
        // Given - session with data
        let sessionData = SessionData(
            heartRateData: [70, 72, 75, 73, 71],
            spo2Data: [98, 97, 98, 99, 98],
            temperatureData: [36.5, 36.6, 36.5, 36.7, 36.6],
            accelerometerData: []
        )
        
        // When
        let aggregated = viewModel.aggregateSessionData(sessionData)
        
        // Then
        XCTAssertEqual(aggregated.averageHeartRate, 72.2, accuracy: 0.1)
        XCTAssertEqual(aggregated.averageSpO2, 98.0, accuracy: 0.1)
        XCTAssertEqual(aggregated.averageTemperature, 36.58, accuracy: 0.01)
        XCTAssertEqual(aggregated.minHeartRate, 70)
        XCTAssertEqual(aggregated.maxHeartRate, 75)
    }
    
    // MARK: - CSV Export Tests
    
    func testCSVExportSingleSession() {
        // Given
        let session = RecordingSession(
            id: UUID(),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            deviceName: "Oralable-001",
            dataPoints: 100
        )
        viewModel.selectedSession = session
        
        // When
        viewModel.exportToCSV()
        
        // Then
        XCTAssertTrue(viewModel.isExporting)
        XCTAssertNotNil(viewModel.exportProgress)
    }
    
    func testCSVExportMultipleSessions() {
        // Given
        for i in 0..<5 {
            let session = RecordingSession(
                id: UUID(),
                startDate: Date().addingTimeInterval(Double(i * -3600)),
                endDate: Date().addingTimeInterval(Double(i * -3600 + 3000)),
                deviceName: "Device-\(i)",
                dataPoints: 100 * (i + 1)
            )
            viewModel.addSession(session)
        }
        
        // When
        viewModel.exportAllSessionsToCSV()
        
        // Then
        XCTAssertTrue(viewModel.isExporting)
        XCTAssertEqual(viewModel.exportQueue.count, 5)
    }
    
    func testCSVFormat() {
        // Given
        let data = SessionData(
            heartRateData: [70.5, 72.3],
            spo2Data: [98.2, 97.8],
            temperatureData: [36.5, 36.6],
            accelerometerData: [(x: 0.1, y: 0.2, z: 0.3)]
        )
        
        // When
        let csv = viewModel.formatAsCSV(data)
        
        // Then
        XCTAssertTrue(csv.contains("Timestamp"))
        XCTAssertTrue(csv.contains("HeartRate"))
        XCTAssertTrue(csv.contains("SpO2"))
        XCTAssertTrue(csv.contains("Temperature"))
        XCTAssertTrue(csv.contains("AccelX"))
        XCTAssertTrue(csv.contains("70.5"))
        XCTAssertTrue(csv.contains("98.2"))
    }
    
    func testExportError() {
        // When
        viewModel.handleExportError("Failed to write file")
        
        // Then
        XCTAssertFalse(viewModel.isExporting)
        XCTAssertEqual(viewModel.exportError, "Failed to write file")
        XCTAssertNil(viewModel.exportProgress)
    }
    
    // MARK: - Statistics Tests
    
    func testSessionStatistics() {
        // Given - multiple sessions
        let session1 = RecordingSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), deviceName: "Device1", dataPoints: 1000)
        let session2 = RecordingSession(id: UUID(), startDate: Date().addingTimeInterval(-3600), endDate: Date(), deviceName: "Device2", dataPoints: 2000)
        let session3 = RecordingSession(id: UUID(), startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-3600), deviceName: "Device3", dataPoints: 1500)
        
        viewModel.addSession(session1)
        viewModel.addSession(session2)
        viewModel.addSession(session3)
        
        // When
        let stats = viewModel.calculateStatistics()
        
        // Then
        XCTAssertEqual(stats.totalSessions, 3)
        XCTAssertEqual(stats.totalDataPoints, 4500)
        XCTAssertEqual(stats.averageSessionDuration, 3600, accuracy: 1)
        XCTAssertEqual(stats.totalRecordingTime, 10800, accuracy: 1)
    }
    
    func testDataTrends() {
        // Test calculating trends over time
        let sessions = createSessionsWithTrend()
        sessions.forEach { viewModel.addSession($0) }
        
        let trend = viewModel.calculateHeartRateTrend()
        XCTAssertTrue(trend.isIncreasing, "Heart rate should show increasing trend")
        XCTAssertEqual(trend.changePercentage, 10.0, accuracy: 1.0)
    }
    
    // MARK: - Sorting Tests
    
    func testSortByDate() {
        // Add sessions in random order
        let session1 = RecordingSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), deviceName: "Device1", dataPoints: 100)
        let session2 = RecordingSession(id: UUID(), startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-3600), deviceName: "Device2", dataPoints: 200)
        let session3 = RecordingSession(id: UUID(), startDate: Date().addingTimeInterval(-3600), endDate: Date(), deviceName: "Device3", dataPoints: 300)
        
        viewModel.addSession(session1)
        viewModel.addSession(session2)
        viewModel.addSession(session3)
        
        // When
        viewModel.sortBy = .date
        viewModel.applySorting()
        
        // Then
        XCTAssertEqual(viewModel.sortedSessions[0].deviceName, "Device1", "Most recent should be first")
        XCTAssertEqual(viewModel.sortedSessions[2].deviceName, "Device2", "Oldest should be last")
    }
    
    func testSortByDuration() {
        // Add sessions with different durations
        let session1 = RecordingSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(1800), deviceName: "Device1", dataPoints: 100) // 30 min
        let session2 = RecordingSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(7200), deviceName: "Device2", dataPoints: 200) // 2 hours
        let session3 = RecordingSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), deviceName: "Device3", dataPoints: 300) // 1 hour
        
        viewModel.addSession(session1)
        viewModel.addSession(session2)
        viewModel.addSession(session3)
        
        // When
        viewModel.sortBy = .duration
        viewModel.applySorting()
        
        // Then
        XCTAssertEqual(viewModel.sortedSessions[0].deviceName, "Device2", "Longest should be first")
        XCTAssertEqual(viewModel.sortedSessions[2].deviceName, "Device1", "Shortest should be last")
    }
    
    // MARK: - Memory Management Tests
    
    func testMemoryCleanup() {
        // Add many sessions
        for i in 0..<100 {
            let session = RecordingSession(
                id: UUID(),
                startDate: Date().addingTimeInterval(Double(i * -3600)),
                endDate: Date().addingTimeInterval(Double(i * -3600 + 3000)),
                deviceName: "Device-\(i)",
                dataPoints: 1000
            )
            viewModel.addSession(session)
        }
        
        // When
        viewModel.clearOldSessions(keepLast: 50)
        
        // Then
        XCTAssertEqual(viewModel.sessions.count, 50, "Should only keep last 50 sessions")
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfLargeDataSet() {
        measure {
            // Create and process large dataset
            for _ in 0..<100 {
                let session = RecordingSession(
                    id: UUID(),
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(3600),
                    deviceName: "Test",
                    dataPoints: 10000
                )
                viewModel.addSession(session)
            }
            
            viewModel.applyDateFilter()
            viewModel.applySorting()
            _ = viewModel.calculateStatistics()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createSessionsWithTrend() -> [RecordingSession] {
        var sessions: [RecordingSession] = []
        for i in 0..<10 {
            let session = RecordingSession(
                id: UUID(),
                startDate: Date().addingTimeInterval(Double(i * -86400)),
                endDate: Date().addingTimeInterval(Double(i * -86400 + 3600)),
                deviceName: "Device",
                dataPoints: 1000,
                averageHeartRate: 60 + Double(i) // Increasing trend
            )
            sessions.append(session)
        }
        return sessions
    }
}
