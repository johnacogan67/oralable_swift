//
//  ChartDataPoint.swift
//  OralableApp
//
//  Represents a single point on a chart with a timestamp and value.
//  Extracted from HistoricalViewModel.swift for better separation of concerns.
//
//  Created: February 2026
//

import Foundation

/// Represents a single point on a chart
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}
