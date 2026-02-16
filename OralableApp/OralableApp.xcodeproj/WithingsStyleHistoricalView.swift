import SwiftUI
import Charts

struct WithingsStyleHistoricalView: View {
    @ObservedObject var ble: OralableBLE
    let metricType: MetricType
    let initialDate: Date?
    
    @Environment(\.dismiss) var dismiss
    @State private var selectedTimeRange: WithingsTimeRange = .day
    @State private var currentDate = Date()
    @State private var showingDataInfo = false
    
    // Initialize with the clicked time or current date
    init(ble: OralableBLE, metricType: MetricType, initialDate: Date? = nil) {
        self.ble = ble
        self.metricType = metricType
        self.initialDate = initialDate
        self._currentDate = State(initialValue: initialDate ?? Date())
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Withings-style header with time range picker
                TimeRangeHeader(
                    selectedRange: $selectedTimeRange,
                    metricType: metricType
                )
                
                // Date navigation (Day view shows specific date, Week/Month show ranges)
                DateNavigationBar(
                    currentDate: $currentDate,
                    timeRange: selectedTimeRange
                )
                
                // Main content area
                ScrollView {
                    VStack(spacing: 20) {
                        // Main chart view (similar to Withings)
                        WithingsStyleChartView(
                            ble: ble,
                            metricType: metricType,
                            timeRange: selectedTimeRange,
                            currentDate: currentDate
                        )
                        
                        // Statistics section (like Withings heart rate averages)
                        StatisticsSection(
                            ble: ble,
                            metricType: metricType,
                            timeRange: selectedTimeRange,
                            currentDate: currentDate
                        )
                        
                        // Context information section
                        if metricType == .ppg {
                            ContextSection()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(metricType.title.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingDataInfo = true }) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingDataInfo) {
            DataInfoSheet(ble: ble, metricType: metricType)
        }
    }
}

// MARK: - Withings Time Range (Day/Week/Month)
enum WithingsTimeRange: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    
    var seconds: TimeInterval {
        switch self {
        case .day: return 86400 // 24 hours
        case .week: return 604800 // 7 days  
        case .month: return 2592000 // 30 days
        }
    }
    
    var chartPoints: Int {
        switch self {
        case .day: return 24 // Hourly points
        case .week: return 7 // Daily points
        case .month: return 30 // Daily points
        }
    }
}

// MARK: - Time Range Header (Withings style)
struct TimeRangeHeader: View {
    @Binding var selectedRange: WithingsTimeRange
    let metricType: MetricType
    
    var body: some View {
        VStack(spacing: 16) {
            // Time range picker
            HStack(spacing: 0) {
                ForEach(WithingsTimeRange.allCases, id: \.rawValue) { range in
                    Button(action: {
                        selectedRange = range
                    }) {
                        Text(range.rawValue)
                            .font(.system(size: 16, weight: selectedRange == range ? .semibold : .regular))
                            .foregroundColor(selectedRange == range ? .blue : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            
            Divider()
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }
}

// MARK: - Date Navigation Bar
struct DateNavigationBar: View {
    @Binding var currentDate: Date
    let timeRange: WithingsTimeRange
    
    private var dateString: String {
        let formatter = DateFormatter()
        
        switch timeRange {
        case .day:
            formatter.dateFormat = "EEEE, dd MMMM"
            return formatter.string(from: currentDate)
        case .week:
            let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? currentDate
            formatter.dateFormat = "dd MMM"
            return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: currentDate)
        }
    }
    
    var body: some View {
        HStack {
            Button(action: navigateBackward) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            
            Spacer()
            
            Text(dateString)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: navigateForward) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(.systemGray6)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func navigateBackward() {
        switch timeRange {
        case .day:
            currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        case .week:
            currentDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentDate) ?? currentDate
        case .month:
            currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        }
    }
    
    private func navigateForward() {
        switch timeRange {
        case .day:
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        case .week:
            currentDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? currentDate
        case .month:
            currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        }
    }
}

// MARK: - Withings Style Chart View
struct WithingsStyleChartView: View {
    @ObservedObject var ble: OralableBLE
    let metricType: MetricType
    let timeRange: WithingsTimeRange
    let currentDate: Date
    
    private var filteredData: [SensorData] {
        let startDate: Date
        let endDate: Date
        
        switch timeRange {
        case .day:
            startDate = Calendar.current.startOfDay(for: currentDate)
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? Date()
        case .week:
            let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: currentDate)
            startDate = weekInterval?.start ?? currentDate
            endDate = weekInterval?.end ?? Date()
        case .month:
            let monthInterval = Calendar.current.dateInterval(of: .month, for: currentDate)
            startDate = monthInterval?.start ?? currentDate
            endDate = monthInterval?.end ?? Date()
        }
        
        return ble.historicalData.filter { data in
            data.timestamp >= startDate && data.timestamp < endDate
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    private var chartData: [(Date, Double)] {
        return filteredData.compactMap { data in
            let value: Double
            switch metricType {
            case .ppg:
                // Show IR values as requested
                value = Double(data.ppg.ir)
            case .accelerometer:
                // Show magnitude as requested
                value = data.accelerometer.magnitude
            case .temperature:
                value = data.temperature
            case .battery:
                value = Double(data.batteryLevel)
            }
            return (data.timestamp, value)
        }
    }
    
    private var yAxisRange: ClosedRange<Double> {
        guard !chartData.isEmpty else { return 0...100 }
        
        let values = chartData.map { $0.1 }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        let padding = (maxValue - minValue) * 0.1
        
        return (minValue - padding)...(maxValue + padding)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current value indicator (like Withings shows current reading)
            if let latestData = chartData.last {
                CurrentValueIndicator(
                    metricType: metricType,
                    value: latestData.1,
                    timestamp: latestData.0
                )
            }
            
            // Main chart area
            Chart {
                ForEach(Array(chartData.enumerated()), id: \.offset) { index, dataPoint in
                    let (timestamp, value) = dataPoint
                    
                    LineMark(
                        x: .value("Time", timestamp),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(metricType.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    // Add point markers for individual readings
                    PointMark(
                        x: .value("Time", timestamp),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(metricType.color)
                    .symbolSize(30)
                }
            }
            .frame(height: 200)
            .chartYScale(domain: yAxisRange)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: timeAxisFormat)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .overlay(
                // Data gaps indicator (like Withings shows missing data)
                DataGapsOverlay(
                    data: chartData,
                    timeRange: timeRange,
                    currentDate: currentDate
                )
            )
            
            // Data availability info
            DataAvailabilityInfo(dataCount: chartData.count, timeRange: timeRange)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var timeAxisFormat: Date.FormatStyle {
        switch timeRange {
        case .day:
            return .dateTime.hour()
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.day()
        }
    }
}

// MARK: - Current Value Indicator
struct CurrentValueIndicator: View {
    let metricType: MetricType
    let value: Double
    let timestamp: Date
    
    private var displayValue: String {
        switch metricType {
        case .ppg:
            return String(format: "%.0f", value)
        case .accelerometer:
            return String(format: "%.1f g", value / 1000) // Convert to g-force
        case .temperature:
            return String(format: "%.1f°C", value)
        case .battery:
            return String(format: "%.0f%%", value)
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(timeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack {
                Text(displayValue)
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(metricType.color)
                
                Image(systemName: metricType.icon)
                    .foregroundColor(metricType.color)
                
                Spacer()
            }
        }
        .padding()
        .background(metricType.color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Data Gaps Overlay
struct DataGapsOverlay: View {
    let data: [(Date, Double)]
    let timeRange: WithingsTimeRange
    let currentDate: Date
    
    var body: some View {
        // This would show dashed lines or different styling for missing data periods
        // Similar to how Withings shows gaps in heart rate data
        EmptyView() // Placeholder for now - would need more complex implementation
    }
}

// MARK: - Data Availability Info
struct DataAvailabilityInfo: View {
    let dataCount: Int
    let timeRange: WithingsTimeRange
    
    var body: some View {
        HStack {
            Image(systemName: dataCount > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(dataCount > 0 ? .green : .orange)
            
            Text("\(dataCount) data points for this \(timeRange.rawValue.lowercased())")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Statistics Section (like Withings averages)
struct StatisticsSection: View {
    @ObservedObject var ble: OralableBLE
    let metricType: MetricType
    let timeRange: WithingsTimeRange
    let currentDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(metricType.title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Context is key to getting a better understanding of your \(metricType.title.lowercased()).")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Statistics cards (similar to Withings Awake avg / Sleep avg)
            HStack(spacing: 16) {
                StatCard(
                    title: "Average",
                    value: calculateAverage(),
                    metricType: metricType,
                    status: .normal
                )
                
                StatCard(
                    title: timeRange == .day ? "Maximum" : "Peak",
                    value: calculateMaximum(),
                    metricType: metricType,
                    status: .elevated
                )
            }
            
            if timeRange == .day {
                HStack(spacing: 16) {
                    StatCard(
                        title: "Minimum",
                        value: calculateMinimum(),
                        metricType: metricType,
                        status: .low
                    )
                    
                    StatCard(
                        title: "Range",
                        value: calculateRange(),
                        metricType: metricType,
                        status: .normal
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func calculateAverage() -> String {
        // Implementation would calculate average from filtered data
        return "-- "
    }
    
    private func calculateMaximum() -> String {
        // Implementation would find maximum from filtered data
        return "-- "
    }
    
    private func calculateMinimum() -> String {
        // Implementation would find minimum from filtered data  
        return "-- "
    }
    
    private func calculateRange() -> String {
        // Implementation would calculate range from filtered data
        return "-- "
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let metricType: MetricType
    let status: StatStatus
    
    enum StatStatus {
        case normal, elevated, low
        
        var color: Color {
            switch self {
            case .normal: return .primary
            case .elevated: return .orange
            case .low: return .blue
            }
        }
        
        var icon: String? {
            switch self {
            case .normal: return nil
            case .elevated: return "arrow.up.circle.fill"
            case .low: return "arrow.down.circle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let icon = status.icon {
                    Image(systemName: icon)
                        .foregroundColor(status.color)
                        .font(.caption)
                }
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(status.color)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Context Section
struct ContextSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Other measurements")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Other measurements are measurements that were taken with a device capable of single PPG measurements.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Data Info Sheet
struct DataInfoSheet: View {
    @ObservedObject var ble: OralableBLE
    let metricType: MetricType
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Data Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Total data points: \(ble.historicalData.count)")
                    
                    if let earliest = ble.historicalData.first?.timestamp,
                       let latest = ble.historicalData.last?.timestamp {
                        Text("Data range: \(earliest, style: .date) - \(latest, style: .date)")
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}