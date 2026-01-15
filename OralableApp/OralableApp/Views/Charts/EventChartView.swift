//
//  EventChartView.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 15, 2026 - Color by validation status (valid=green, invalid=black)
//
//  Chart views for displaying muscle activity events
//  Valid events: Green | Invalid events: Black
//

import SwiftUI
import Charts
import OralableCore

/// Chart view that displays muscle activity events with IR values
/// - Valid events: Green
/// - Invalid events: Black
struct EventChartView: View {
    let events: [MuscleActivityEvent]

    var body: some View {
        Chart {
            ForEach(events) { event in
                // Bar for each event showing duration and IR level
                RectangleMark(
                    xStart: .value("Start", event.startTimestamp),
                    xEnd: .value("End", event.endTimestamp),
                    y: .value("IR", event.averageIR)
                )
                .foregroundStyle(event.displayColor)
                .opacity(event.isValid ? 0.8 : 0.6)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ir = value.as(Double.self) {
                        Text("\(Int(ir / 1000))k")
                    }
                }
            }
        }
        .chartLegend(position: .bottom) {
            HStack(spacing: 20) {
                LegendItem(color: .green, label: "Valid")
                LegendItem(color: .black, label: "Invalid")
            }
        }
    }
}

/// Timeline view showing events as colored segments
/// Valid: Green | Invalid: Black
struct EventTimelineView: View {
    let events: [MuscleActivityEvent]

    var body: some View {
        Chart {
            ForEach(events) { event in
                RectangleMark(
                    xStart: .value("Start", event.startTimestamp),
                    xEnd: .value("End", event.endTimestamp),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", 1)
                )
                .foregroundStyle(event.displayColor)
                .opacity(event.isValid ? 0.8 : 0.6)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 60)
    }
}

/// Point chart showing event durations over time
/// Valid: Green | Invalid: Black
struct EventPointChartView: View {
    let events: [MuscleActivityEvent]

    var body: some View {
        Chart {
            ForEach(events) { event in
                PointMark(
                    x: .value("Time", event.startTimestamp),
                    y: .value("Duration", event.durationMs)
                )
                .foregroundStyle(event.displayColor)
                .symbolSize(event.isValid ? 100 : 60)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ms = value.as(Int.self) {
                        if ms >= 1000 {
                            Text("\(ms / 1000)s")
                        } else {
                            Text("\(ms)ms")
                        }
                    }
                }
            }
        }
    }
}

/// Combined chart showing event distribution by validation status
struct EventDistributionView: View {
    let events: [MuscleActivityEvent]

    private var validEvents: [MuscleActivityEvent] {
        events.filter { $0.isValid }
    }

    private var invalidEvents: [MuscleActivityEvent] {
        events.filter { !$0.isValid }
    }

    private var validDuration: Int {
        validEvents.reduce(0) { $0 + $1.durationMs }
    }

    private var invalidDuration: Int {
        invalidEvents.reduce(0) { $0 + $1.durationMs }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Summary stats
            HStack(spacing: 20) {
                VStack {
                    Text("\(validEvents.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Valid")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(validDuration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(invalidEvents.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    Text("Invalid")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(invalidDuration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar showing ratio
            GeometryReader { geometry in
                let total = validEvents.count + invalidEvents.count
                let validRatio = total > 0 ? CGFloat(validEvents.count) / CGFloat(total) : 0.5

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * validRatio)

                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: geometry.size.width * (1 - validRatio))
                }
                .cornerRadius(4)
            }
            .frame(height: 20)
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            return String(format: "%.1fm", seconds / 60.0)
        }
    }
}

/// Legend item helper
struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Event Charts - Valid/Invalid") {
    let sampleEvents = [
        MuscleActivityEvent(
            eventNumber: 1,
            eventType: .rest,
            startTimestamp: Date().addingTimeInterval(-3700),
            endTimestamp: Date().addingTimeInterval(-3600),
            startIR: 120000,
            endIR: 155000,
            averageIR: 130000,
            accelX: -5600,
            accelY: 15200,
            accelZ: -1760,
            temperature: 34.0,
            heartRate: 70,
            spO2: 98,
            sleepState: .awake,
            isValid: true  // VALID - green
        ),
        MuscleActivityEvent(
            eventNumber: 2,
            eventType: .activity,
            startTimestamp: Date().addingTimeInterval(-3600),
            endTimestamp: Date().addingTimeInterval(-3599.5),
            startIR: 285000,
            endIR: 162000,
            averageIR: 245000,
            accelX: -5608,
            accelY: 15180,
            accelZ: -1756,
            temperature: 34.0,
            heartRate: nil,  // No HR
            spO2: nil,       // No SpO2
            sleepState: nil,
            isValid: false   // INVALID - black
        ),
        MuscleActivityEvent(
            eventNumber: 3,
            eventType: .rest,
            startTimestamp: Date().addingTimeInterval(-3599.5),
            endTimestamp: Date().addingTimeInterval(-3500),
            startIR: 162000,
            endIR: 148000,
            averageIR: 95000,
            accelX: -5600,
            accelY: 15200,
            accelZ: -1760,
            temperature: 34.1,
            heartRate: 70,
            spO2: 98,
            sleepState: .awake,
            isValid: true  // VALID - green
        ),
        MuscleActivityEvent(
            eventNumber: 4,
            eventType: .activity,
            startTimestamp: Date().addingTimeInterval(-3500),
            endTimestamp: Date().addingTimeInterval(-3499),
            startIR: 312000,
            endIR: 158000,
            averageIR: 278000,
            accelX: -4200,
            accelY: 12500,
            accelZ: -2100,
            temperature: 30.0,  // Cold temp - invalid
            heartRate: nil,
            spO2: nil,
            sleepState: nil,
            isValid: false  // INVALID - black
        )
    ]

    ScrollView {
        VStack(spacing: 20) {
            Text("Event Timeline")
                .font(.headline)

            EventTimelineView(events: sampleEvents)
                .padding()

            Text("Event Duration Chart")
                .font(.headline)

            EventPointChartView(events: sampleEvents)
                .frame(height: 200)
                .padding()

            Text("Event Distribution")
                .font(.headline)

            EventDistributionView(events: sampleEvents)
                .padding()

            Text("Event IR Chart")
                .font(.headline)

            EventChartView(events: sampleEvents)
                .frame(height: 200)
                .padding()
        }
        .padding()
    }
}
