//
//  HistoricalViewModelTests.swift
//  OralableAppTests
//
//  Created: Refactoring Phase 1
//  Purpose: Unit tests for HistoricalViewModel using protocol-based DI
//

import XCTest
import Combine
@testable import MAMDiagnostics

@MainActor
final class HistoricalViewModelTests: XCTestCase {
    var mockHistoricalDataManager: MockHistoricalDataManager!
    var viewModel: HistoricalViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockHistoricalDataManager = MockHistoricalDataManager()
        viewModel = HistoricalViewModel(historicalDataManager: mockHistoricalDataManager)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockHistoricalDataManager = nil
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        // Then
        XCTAssertEqual(viewModel.selectedTimeRange, .minute, "Should default to minute range")
        XCTAssertNil(viewModel.minuteMetrics, "Minute metrics should be nil initially")
        XCTAssertNil(viewModel.hourMetrics, "Hour metrics should be nil initially")
        XCTAssertNil(viewModel.dayMetrics, "Day metrics should be nil initially")
        XCTAssertNil(viewModel.weekMetrics, "Week metrics should be nil initially")
        XCTAssertNil(viewModel.monthMetrics, "Month metrics should be nil initially")
        XCTAssertFalse(viewModel.isUpdating, "Should not be updating initially")
        XCTAssertNil(viewModel.lastUpdateTime, "Last update time should be nil initially")
    }

    // MARK: - Metrics Update Tests

    func testUpdateAllMetrics() {
        // Given
        XCTAssertFalse(mockHistoricalDataManager.updateAllMetricsCalled)

        // When
        viewModel.updateAllMetrics()

        // Then
        XCTAssertTrue(mockHistoricalDataManager.updateAllMetricsCalled, "Should call updateAllMetrics on manager")
    }

    func testUpdateCurrentRangeMetrics() {
        // Given
        viewModel.selectedTimeRange = .week

        // When
        viewModel.updateCurrentRangeMetrics()

        // Then
        XCTAssertTrue(mockHistoricalDataManager.updateMetricsCalled.contains(.week), "Should call updateMetrics for current range")
    }

    func testRefresh() {
        // Given
        viewModel.selectedTimeRange = .hour

        // When
        viewModel.refresh()

        // Then
        XCTAssertTrue(mockHistoricalDataManager.updateMetricsCalled.contains(.hour), "Should update metrics on refresh")
    }

    func testClearAllMetrics() {
        // Given
        XCTAssertFalse(mockHistoricalDataManager.clearAllMetricsCalled)

        // When
        viewModel.clearAllMetrics()

        // Then
        XCTAssertTrue(mockHistoricalDataManager.clearAllMetricsCalled, "Should call clearAllMetrics on manager")
        XCTAssertNil(viewModel.currentMetrics, "Should clear current metrics")
    }

    // MARK: - Metrics Publishing Tests

    func testHourMetricsUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "Hour metrics updates")
        let mockMetrics = createMockMetrics(range: .hour, pointCount: 5)

        viewModel.$hourMetrics
            .dropFirst()  // Skip initial nil
            .sink { metrics in
                XCTAssertNotNil(metrics, "Hour metrics should not be nil")
                XCTAssertEqual(metrics?.dataPoints.count, 5, "Should have 5 data points")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockHistoricalDataManager.simulateMetrics(for: .hour, metrics: mockMetrics)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testDayMetricsUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "Day metrics updates")
        let mockMetrics = createMockMetrics(range: .day, pointCount: 10)

        viewModel.$dayMetrics
            .dropFirst()  // Skip initial nil
            .sink { metrics in
                XCTAssertNotNil(metrics, "Day metrics should not be nil")
                XCTAssertEqual(metrics?.dataPoints.count, 10, "Should have 10 data points")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockHistoricalDataManager.simulateMetrics(for: .day, metrics: mockMetrics)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testIsUpdatingUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "isUpdating updates")

        viewModel.$isUpdating
            .dropFirst()  // Skip initial false
            .sink { isUpdating in
                if isUpdating {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockHistoricalDataManager.isUpdating = true

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testLastUpdateTimeUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "lastUpdateTime updates")
        let now = Date()

        viewModel.$lastUpdateTime
            .dropFirst()  // Skip initial nil
            .sink { updateTime in
                XCTAssertNotNil(updateTime, "Last update time should not be nil")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockHistoricalDataManager.lastUpdateTime = now

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Time Range Selection Tests

    func testTimeRangeChange() {
        // Given - default is now .minute
        XCTAssertEqual(viewModel.selectedTimeRange, .minute)

        // When
        viewModel.selectedTimeRange = .week

        // Then
        XCTAssertEqual(viewModel.selectedTimeRange, .week, "Time range should update")
    }

    func testTimeRangeText() {
        // Today
        viewModel.selectedTimeRange = .day
        viewModel.timeRangeOffset = 0
        XCTAssertEqual(viewModel.timeRangeText, "Today")

        // Yesterday
        viewModel.timeRangeOffset = -1
        XCTAssertEqual(viewModel.timeRangeText, "Yesterday")

        // This Week
        viewModel.selectedTimeRange = .week
        viewModel.timeRangeOffset = 0
        XCTAssertEqual(viewModel.timeRangeText, "This Week")

        // Last Week
        viewModel.timeRangeOffset = -1
        XCTAssertEqual(viewModel.timeRangeText, "Last Week")
    }

    // MARK: - Computed Properties Tests

    func testHasAnyMetrics() {
        // Given - No metrics
        XCTAssertFalse(viewModel.hasAnyMetrics, "Should not have any metrics initially")

        // When - Add day metrics
        let mockMetrics = createMockMetrics(range: .day, pointCount: 5)
        mockHistoricalDataManager.simulateMetrics(for: .day, metrics: mockMetrics)

        // Wait for update
        let expectation = XCTestExpectation(description: "Metrics update")
        viewModel.$dayMetrics
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(viewModel.hasAnyMetrics, "Should have metrics after update")
    }

    func testDataPointsCount() async {
        // Given - No metrics
        XCTAssertEqual(viewModel.dataPoints.count, 0, "Should have 0 data points initially")

        // When - Add metrics for selected range (day)
        viewModel.selectedTimeRange = .day
        let mockMetrics = createMockMetrics(range: .day, pointCount: 15)
        mockHistoricalDataManager.simulateMetrics(for: .day, metrics: mockMetrics)

        // Wait for day metrics to propagate
        let dayMetricsExpectation = XCTestExpectation(description: "Day metrics update")
        viewModel.$dayMetrics
            .dropFirst()
            .sink { metrics in
                if metrics != nil {
                    dayMetricsExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [dayMetricsExpectation], timeout: 2.0)

        // Verify day metrics were set
        XCTAssertNotNil(viewModel.dayMetrics, "Day metrics should be set")
        XCTAssertEqual(viewModel.dayMetrics?.dataPoints.count, 15, "Day metrics should have 15 data points")
    }

    func testAverageHeartRateText() async {
        // Given - No metrics
        XCTAssertEqual(viewModel.averageHeartRateText, "--", "Should show -- when no metrics")

        // When - Set time range to day and add metrics with heart rate data
        viewModel.selectedTimeRange = .day
        let mockMetrics = createMockMetrics(range: .day, pointCount: 3, avgHeartRate: 75.0)
        mockHistoricalDataManager.simulateMetrics(for: .day, metrics: mockMetrics)

        // Wait for day metrics to propagate
        let expectation = XCTestExpectation(description: "Metrics update")
        viewModel.$dayMetrics
            .dropFirst()
            .sink { metrics in
                if metrics != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)

        // Verify metrics were set and have heart rate data
        XCTAssertNotNil(viewModel.dayMetrics, "Day metrics should be set")
        XCTAssertEqual(viewModel.dayMetrics?.dataPoints.count, 3, "Should have 3 data points")

        // Check that the data points have heart rate values
        let hrValues = viewModel.dayMetrics?.dataPoints.compactMap { $0.averageHeartRate } ?? []
        XCTAssertFalse(hrValues.isEmpty, "Data points should have heart rate values")
    }

    // MARK: - Helper Methods

    private func createMockMetrics(range: TimeRange, pointCount: Int, avgHeartRate: Double? = 72.0, avgSpO2: Double? = 98.0) -> HistoricalMetrics {
        let now = Date()
        let startDate: Date
        let endDate = now

        // Calculate start date based on range
        switch range {
        case .minute:
            startDate = Calendar.current.date(byAdding: .minute, value: -1, to: now)!
        case .hour:
            startDate = Calendar.current.date(byAdding: .hour, value: -1, to: now)!
        case .day:
            startDate = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        case .week:
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        case .month:
            startDate = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        }

        // Create data points
        var dataPoints: [HistoricalDataPoint] = []
        let interval = endDate.timeIntervalSince(startDate) / Double(pointCount)

        for i in 0..<pointCount {
            let timestamp = startDate.addingTimeInterval(interval * Double(i))
            let point = HistoricalDataPoint(
                timestamp: timestamp,
                averageHeartRate: avgHeartRate,
                averageSpO2: avgSpO2,
                averageTemperature: 36.5,
                averageBattery: 80,
                movementIntensity: 0.5,
                grindingEvents: 0
            )
            dataPoints.append(point)
        }

        return HistoricalMetrics(
            timeRange: range.rawValue,
            startDate: startDate,
            endDate: endDate,
            totalSamples: pointCount * 100,
            dataPoints: dataPoints,
            temperatureTrend: 0.0,
            batteryTrend: 0.0,
            activityTrend: 0.0,
            avgTemperature: 36.5,
            avgBatteryLevel: 80.0,
            totalGrindingEvents: 0,
            totalGrindingDuration: 0
        )
    }
}
