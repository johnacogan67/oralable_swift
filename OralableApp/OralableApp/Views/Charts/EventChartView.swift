//
//  EventChartView.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Chart views for displaying muscle activity events
//  Rest events: Green | Activity events: Red
//

import SwiftUI
import Charts
import OralableCore

/// Chart view that displays muscle activity events with IR values
/// - Rest events: Green
/// - Activity events: Red
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
                .foregroundStyle(event.eventType.color)
                .opacity(0.8)
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
                LegendItem(color: .green, label: "Rest")
                LegendItem(color: .red, label: "Activity")
            }
        }
    }
}

/// Timeline view showing events as colored segments
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
                .foregroundStyle(event.eventType.color)
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
struct EventPointChartView: View {

    let events: [MuscleActivityEvent]

    var body: some View {
        Chart {
            ForEach(events) { event in
                PointMark(
                    x: .value("Time", event.startTimestamp),
                    y: .value("Duration", event.durationMs)
                )
                .foregroundStyle(event.eventType.color)
                .symbolSize(event.eventType == .activity ? 100 : 60)
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

/// Combined chart showing event distribution by type
struct EventDistributionView: View {

    let events: [MuscleActivityEvent]

    private var activityEvents: [MuscleActivityEvent] {
        events.filter { $0.eventType == .activity }
    }

    private var restEvents: [MuscleActivityEvent] {
        events.filter { $0.eventType == .rest }
    }

    private var activityDuration: Int {
        activityEvents.reduce(0) { $0 + $1.durationMs }
    }

    private var restDuration: Int {
        restEvents.reduce(0) { $0 + $1.durationMs }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Pie/Bar chart for distribution
            HStack(spacing: 20) {
                VStack {
                    Text("\(activityEvents.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("Activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(activityDuration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(restEvents.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Rest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(restDuration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar showing ratio
            GeometryReader { geometry in
                let total = activityDuration + restDuration
                let activityRatio = total > 0 ? CGFloat(activityDuration) / CGFloat(total) : 0.5

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * activityRatio)

                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * (1 - activityRatio))
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

#Preview("Event Timeline") {
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
            isValid: true
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
            heartRate: 72,
            spO2: 98,
            sleepState: .awake,
            isValid: true
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
            isValid: true
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
            temperature: 34.25,
            heartRate: 68,
            spO2: 97,
            sleepState: .awake,
            isValid: true
        )
    ]

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
    }
    .padding()
}
