import SwiftUI
import Charts
import Foundation

// NOTE: MetricType enum is centralized in
// OralableApp/OralableApp/Views/Components/Historical/HistoricalMetricType.swift
// Do not redeclare it here.

// NOTE: HistoricalAppMode enum is centralized in
// OralableApp/OralableApp/Views/Components/Historical/HistoricalAppMode.swift
// Do not redeclare it here.

// MARK: - Data Sharing Service
class DataSharingService: ObservableObject {
    enum ShareFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case pdf = "PDF Report"

        /// Returns only export formats enabled via feature flags
        static var availableCases: [ShareFormat] {
            var cases: [ShareFormat] = [.csv, .json]
            if FeatureFlags.shared.showPDFExport {
                cases.append(.pdf)
            }
            return cases
        }

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            case .pdf: return "pdf"
            }
        }
    }

    func shareData(
        _ data: [SensorData],
        metricType: MetricType,
        format: ShareFormat,
        timeRange: TimeRange
    ) -> URL? {
        switch format {
        case .csv:
            return createCSVFile(data, metricType: metricType, timeRange: timeRange)
        case .json:
            return createJSONFile(data, metricType: metricType, timeRange: timeRange)
        case .pdf:
            return createPDFReport(data, metricType: metricType, timeRange: timeRange)
        }
    }

    private func createCSVFile(_ data: [SensorData], metricType: MetricType, timeRange: TimeRange) -> URL? {
        var csvContent = metricType.csvHeader() + "\n"

        for sample in data {
            let row = metricType.csvRow(for: sample)
            csvContent += "\(row)\n"
        }

        return saveToFile(content: csvContent, filename: "oralable_\(metricType.rawValue)_\(timeRange.rawValue).csv")
    }

    private func createJSONFile(_ data: [SensorData], metricType: MetricType, timeRange: TimeRange) -> URL? {
        let exportData = HistoricalDataExport(
            metricType: metricType,
            timeRange: timeRange,
            exportDate: Date(),
            dataCount: data.count,
            samples: data.map { HistoricalSample(from: $0, metricType: metricType) }
        )

        do {
            let jsonData = try JSONEncoder().encode(exportData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            return saveToFile(content: jsonString, filename: "oralable_\(metricType.rawValue)_\(timeRange.rawValue).json")
        } catch {
            Logger.shared.error("[HistoricalDetailView] creating JSON: \(error)")
            return nil
        }
    }

    private func createPDFReport(_ data: [SensorData], metricType: MetricType, timeRange: TimeRange) -> URL? {
        Logger.shared.info("[HistoricalDetailView] PDF report creation not implemented yet")
        return nil
    }

    private func saveToFile(content: String, filename: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Logger.shared.error("[HistoricalDetailView] saving file: \(error)")
            return nil
        }
    }
}

// MARK: - Data Models for Export
struct HistoricalDataExport: Codable {
    let metricType: String
    let timeRange: String
    let exportDate: Date
    let dataCount: Int
    let samples: [HistoricalSample]

    init(metricType: MetricType, timeRange: TimeRange, exportDate: Date, dataCount: Int, samples: [HistoricalSample]) {
        self.metricType = metricType.rawValue
        self.timeRange = timeRange.rawValue
        self.exportDate = exportDate
        self.dataCount = dataCount
        self.samples = samples
    }
}

struct HistoricalSample: Codable {
    let timestamp: Date
    let value: Double
    let additionalData: [String: Double]?

    init(from sensorData: SensorData, metricType: MetricType) {
        self.timestamp = sensorData.timestamp

        switch metricType {
        case .ppg:
            self.value = Double(sensorData.ppg.ir)
            self.additionalData = [
                "red": Double(sensorData.ppg.red),
                "green": Double(sensorData.ppg.green)
            ]
        case .temperature:
            self.value = sensorData.temperature.celsius
            self.additionalData = nil
        case .battery:
            self.value = Double(sensorData.battery.percentage)
            self.additionalData = nil
        case .accelerometer:
            self.value = sensorData.accelerometer.magnitude
            self.additionalData = [
                "x": Double(sensorData.accelerometer.x),
                "y": Double(sensorData.accelerometer.y),
                "z": Double(sensorData.accelerometer.z)
            ]
        case .heartRate:
            if let heartRate = sensorData.heartRate {
                self.value = heartRate.bpm
                self.additionalData = [
                    "quality": heartRate.quality
                ]
            } else {
                self.value = 0
                self.additionalData = nil
            }
        case .spo2:
            if let spo2 = sensorData.spo2 {
                self.value = spo2.percentage
                self.additionalData = [
                    "quality": spo2.quality
                ]
            } else {
                self.value = 0
                self.additionalData = nil
            }
        }
    }
}

// MARK: - Historical Detail View (Refactored to use components)
struct HistoricalDetailView: View {
    @EnvironmentObject var ppgNormalizationService: PPGNormalizationService
    @ObservedObject var sensorDataProcessor: SensorDataProcessor
    let metricType: MetricType

    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var sizeClass

    @State private var selectedTimeRange: TimeRange = .day
    @State private var selectedDate = Date()

    @State private var appMode: HistoricalAppMode = .subscription

    @State private var processor: HistoricalDataProcessor?

    // Debounced reprocess task to avoid invoking processing on every single packet
    @State private var reprocessTask: Task<Void, Never>?

    private var chartHeight: CGFloat {
        DesignSystem.Layout.isIPad ? 400 : 300
    }

    private func getProcessor() -> HistoricalDataProcessor {
        if let existing = processor {
            return existing
        }
        let new = HistoricalDataProcessor(normalizationService: ppgNormalizationService)
        processor = new
        return new
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HistoricalTimeRangePicker(selectedRange: $selectedTimeRange)
                        .padding()
                        .onChange(of: selectedTimeRange) { _, _ in
                            selectedDate = Date()
                            refreshProcessing()
                        }

                    HistoricalDateNavigation(selectedDate: $selectedDate, timeRange: selectedTimeRange)
                        .padding(.horizontal)
                        .onChange(of: selectedDate) { _, _ in
                            refreshProcessing()
                        }

                    // DEBUG: Quick counters to help trace where data is present
                    HStack {
                        Text("Raw samples: \(sensorDataProcessor.sensorDataHistory.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Processed: \(getProcessor().processedData?.statistics.sampleCount ?? 0)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 20) {
                        HistoricalChartView(
                            metricType: metricType,
                            timeRange: selectedTimeRange,
                            selectedDataPoint: Binding(
                                get: { getProcessor().selectedDataPoint },
                                set: { getProcessor().selectedDataPoint = $0 }
                            ),
                            processed: getProcessor().processedData
                        )
                        .frame(height: chartHeight)

                        HistoricalStatisticsCard(
                            metricType: metricType,
                            processed: getProcessor().processedData
                        )

                        if metricType == .ppg && appMode.allowsAdvancedAnalytics {
                            PPGDebugCard(
                                sensorDataProcessor: sensorDataProcessor,
                                timeRange: selectedTimeRange,
                                selectedDate: selectedDate
                            )
                        }
                    }
                    .padding(DesignSystem.Layout.edgePadding)
                    .frame(maxWidth: DesignSystem.Layout.contentWidth)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("\(metricType.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            Logger.shared.info("[HistoricalDetailView] .task starting - sensor count: \(sensorDataProcessor.sensorDataHistory.count)")
            await getProcessor().processData(
                from: sensorDataProcessor,
                metricType: metricType,
                timeRange: selectedTimeRange,
                selectedDate: selectedDate,
                appMode: appMode
            )
            Logger.shared.info("[HistoricalDetailView] .task finished - processed count: \(getProcessor().processedData?.statistics.sampleCount ?? 0)")
        }
        .onChange(of: sensorDataProcessor.sensorDataHistory.count) { _, _ in
            refreshProcessing()
        }
    }

    private func refreshProcessing() {
        // Debounce/cancel previous processing task to avoid running processData for each incoming packet
        reprocessTask?.cancel()
        reprocessTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            guard !Task.isCancelled else { return }
            Logger.shared.debug("[HistoricalDetailView] refreshProcessing() - sensor count: \(sensorDataProcessor.sensorDataHistory.count)")
            await getProcessor().processData(
                from: sensorDataProcessor,
                metricType: metricType,
                timeRange: selectedTimeRange,
                selectedDate: selectedDate,
                appMode: appMode
            )
            Logger.shared.debug("[HistoricalDetailView] refreshProcessing() done - processed count: \(getProcessor().processedData?.statistics.sampleCount ?? 0)")
        }
    }
}

// MARK: - PPG Debug Card (uses shared DeviceState)
struct PPGDebugCard: View {
    @EnvironmentObject var ppgNormalizationService: PPGNormalizationService
    @ObservedObject var sensorDataProcessor: SensorDataProcessor
    let timeRange: TimeRange
    let selectedDate: Date

    @State private var normalizationMethod: NormalizationMethod = .contextAware
    @State private var detectedSegments: [DataSegment] = []
    @State private var currentSegmentIndex: Int = 0
    @State private var deviceContext: DeviceContext?
    @State private var lastStateChange: Date = Date()
    @State private var stateHistory: [DeviceState] = []

    enum NormalizationMethod: String, CaseIterable {
        case none = "Raw Values"
        case zScore = "Z-Score"
        case minMax = "Min-Max (0-1)"
        case percentage = "Percentage"
        case baseline = "Baseline Corrected"
        case adaptive = "Adaptive (Auto-Recalibrate)"
        case contextAware = "Context-Aware (Smart)"
    }

    struct DeviceContext {
        let state: DeviceState
        let confidence: Double
        let timeInState: TimeInterval
        let temperatureChange: Double
        let movementVariation: Double
        let isStabilized: Bool

        var shouldNormalize: Bool {
            return isStabilized && timeInState >= state.expectedStabilizationTime
        }
    }

    struct DataSegment: Equatable {
        let id = UUID()
        let startIndex: Int
        let endIndex: Int
        let timestamp: Date
        let isStable: Bool
        let averageVariation: Double

        static func == (lhs: DataSegment, rhs: DataSegment) -> Bool {
            lhs.id == rhs.id
        }
    }

    private var filteredData: [SensorData] {
        let calendar = Calendar.current

        switch timeRange {
        case .minute:
            let startOfMinute = calendar.dateInterval(of: .minute, for: selectedDate)?.start ?? selectedDate
            let endOfMinute = calendar.date(byAdding: .minute, value: 1, to: startOfMinute) ?? selectedDate
            return Array(sensorDataProcessor.sensorDataHistory.filter {
                $0.timestamp >= startOfMinute && $0.timestamp < endOfMinute
            }.suffix(20))
        case .hour:
            let startOfHour = calendar.dateInterval(of: .hour, for: selectedDate)?.start ?? selectedDate
            let endOfHour = calendar.date(byAdding: .hour, value: 1, to: startOfHour) ?? selectedDate
            return Array(sensorDataProcessor.sensorDataHistory.filter {
                $0.timestamp >= startOfHour && $0.timestamp < endOfHour
            }.suffix(20))
        case .day:
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return Array(sensorDataProcessor.sensorDataHistory.filter {
                $0.timestamp >= startOfDay && $0.timestamp < endOfDay
            }.suffix(20))
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek) ?? selectedDate
            return Array(sensorDataProcessor.sensorDataHistory.filter {
                $0.timestamp >= startOfWeek && $0.timestamp < endOfWeek
            }.suffix(20))
        case .month:
            let startOfMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? selectedDate
            return Array(sensorDataProcessor.sensorDataHistory.filter {
                $0.timestamp >= startOfMonth && $0.timestamp < endOfMonth
            }.suffix(20))
        }
    }

    private var recentPPGData: [(timestamp: Date, ir: Double, red: Double, green: Double)] {
        let rawData = Array(filteredData.map { data in
            (timestamp: data.timestamp, ir: Double(data.ppg.ir), red: Double(data.ppg.red), green: Double(data.ppg.green))
        })
        let staticData = Array(rawData.suffix(20))

        if normalizationMethod == .none {
            return staticData
        } else {
            let serviceMethod: PPGNormalizationService.Method
            switch normalizationMethod {
            case .none:
                serviceMethod = .raw
            case .zScore, .minMax, .percentage:
                serviceMethod = .dynamicRange
            case .baseline:
                serviceMethod = .adaptiveBaseline
            case .adaptive:
                serviceMethod = .heartRateSimulation
            case .contextAware:
                serviceMethod = .persistent
            }

            return PPGNormalizationService.shared.normalizePPGData(
                staticData,
                method: serviceMethod,
                sensorData: Array(filteredData)
            )
        }
    }

    private func updateSegmentsIfNeeded() {
        if normalizationMethod == .adaptive {
            let rawData = Array(filteredData.map { data in
                (timestamp: data.timestamp, ir: Double(data.ppg.ir), red: Double(data.ppg.red), green: Double(data.ppg.green))
            })
            let newSegments = detectDataSegments(rawData)
            if newSegments != detectedSegments {
                detectedSegments = newSegments
            }
        } else if normalizationMethod == .contextAware {
            updateDeviceContext()
        }
    }

    private func updateDeviceContext() {
        guard !filteredData.isEmpty else { return }

        let context = detectDeviceState(from: filteredData)
        if let context = context {
            deviceContext = context
            if stateHistory.isEmpty || stateHistory.last != context.state {
                stateHistory.append(context.state)
                lastStateChange = Date()
                if stateHistory.count > 10 {
                    stateHistory.removeFirst()
                }
            }
        }
    }

    private func detectDeviceState(from data: [SensorData]) -> DeviceContext? {
        guard data.count >= 5 else { return nil }

        let recentSamples = Array(data.suffix(10))
        let accelerometerVariation = calculateAccelerometerVariation(recentSamples)
        let temperatureChange = calculateTemperatureChange(recentSamples)
        let batteryStatus = recentSamples.last?.battery.percentage ?? 0

        let detectedState = classifyDeviceState(
            accelerometerVariation: accelerometerVariation,
            temperatureChange: temperatureChange,
            batteryLevel: batteryStatus
        )

        let confidence = calculateStateConfidence(detectedState, samples: recentSamples)
        let timeInState = Date().timeIntervalSince(lastStateChange)
        let isStabilized = isDeviceStabilized(detectedState, timeInState: timeInState, confidence: confidence)

        return DeviceContext(
            state: detectedState,
            confidence: confidence,
            timeInState: timeInState,
            temperatureChange: temperatureChange,
            movementVariation: accelerometerVariation,
            isStabilized: isStabilized
        )
    }

    private func calculateAccelerometerVariation(_ samples: [SensorData]) -> Double {
        guard samples.count > 1 else { return 0 }
        let magnitudes = samples.map { $0.accelerometer.magnitude }
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let variance = magnitudes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(magnitudes.count)
        return sqrt(variance)
    }

    private func calculateTemperatureChange(_ samples: [SensorData]) -> Double {
        guard samples.count > 1 else { return 0 }
        let temperatures = samples.map { $0.temperature.celsius }
        return (temperatures.max() ?? 0) - (temperatures.min() ?? 0)
    }

    private func classifyDeviceState(
        accelerometerVariation: Double,
        temperatureChange: Double,
        batteryLevel: Int
    ) -> DeviceState {
        let lowMovementThreshold = 0.1
        let moderateMovementThreshold = 0.5
        let lowTempChangeThreshold = 0.5
        let moderateTempChangeThreshold = 2.0

        if batteryLevel > 95 && accelerometerVariation < lowMovementThreshold {
            return .onChargerStatic
        } else if accelerometerVariation < lowMovementThreshold && temperatureChange < lowTempChangeThreshold {
            return .offChargerStatic
        } else if accelerometerVariation > moderateMovementThreshold {
            return .inMotion
        } else if temperatureChange > moderateTempChangeThreshold && accelerometerVariation < moderateMovementThreshold {
            return .onCheek
        } else {
            return .unknown
        }
    }

    private func calculateStateConfidence(_ state: DeviceState, samples: [SensorData]) -> Double {
        guard samples.count >= 3 else { return 0.5 }
        var consistentSamples = 0

        for i in 1..<samples.count {
            let prevSample = samples[i-1]
            let currentSample = samples[i]

            let accelVariation = abs(currentSample.accelerometer.magnitude - prevSample.accelerometer.magnitude)
            let tempChange = abs(currentSample.temperature.celsius - prevSample.temperature.celsius)

            var isConsistent = false
            switch state {
            case .onChargerStatic, .offChargerStatic:
                isConsistent = accelVariation < 0.2 && tempChange < 1.0
            case .inMotion:
                isConsistent = accelVariation > 0.3
            case .onCheek:
                isConsistent = tempChange > 1.0 && accelVariation < 0.4
            case .unknown:
                isConsistent = true
            }
            if isConsistent { consistentSamples += 1 }
        }

        return Double(consistentSamples) / Double(samples.count - 1)
    }

    private func isDeviceStabilized(_ state: DeviceState, timeInState: TimeInterval, confidence: Double) -> Bool {
        let requiredConfidence: Double = 0.7
        return confidence >= requiredConfidence && timeInState >= state.expectedStabilizationTime
    }

    private func detectDataSegments(_ data: [(timestamp: Date, ir: Double, red: Double, green: Double)]) -> [DataSegment] {
        guard data.count >= 6 else { return [] }

        var segments: [DataSegment] = []
        var currentSegmentStart = 0
        let windowSize = 5
        let movementThreshold: Double = 1000
        let stabilityDuration = 5

        var i = windowSize
        while i < data.count {
            let windowData = Array(data[(i-windowSize)..<i])
            let variation = calculateWindowVariation(windowData)
            let isMovement = variation > movementThreshold

            if isMovement || i == data.count - 1 {
                let segmentEnd = i - windowSize
                if segmentEnd > currentSegmentStart + stabilityDuration {
                    let segmentData = Array(data[currentSegmentStart..<segmentEnd])
                    let avgVariation = calculateWindowVariation(segmentData)
                    let isStable = avgVariation < movementThreshold / 2

                    segments.append(DataSegment(
                        startIndex: currentSegmentStart,
                        endIndex: segmentEnd,
                        timestamp: data[currentSegmentStart].timestamp,
                        isStable: isStable,
                        averageVariation: avgVariation
                    ))
                }
                if isMovement {
                    i += stabilityDuration
                    currentSegmentStart = i
                }
            }
            i += 1
        }

        if currentSegmentStart < data.count - stabilityDuration {
            let segmentData = Array(data[currentSegmentStart..<data.count])
            let avgVariation = calculateWindowVariation(segmentData)
            let isStable = avgVariation < movementThreshold / 2

            segments.append(DataSegment(
                startIndex: currentSegmentStart,
                endIndex: data.count,
                timestamp: data[currentSegmentStart].timestamp,
                isStable: isStable,
                averageVariation: avgVariation
            ))
        }

        return segments
    }

    private func calculateWindowVariation(_ data: [(timestamp: Date, ir: Double, red: Double, green: Double)]) -> Double {
        guard data.count > 1 else { return 0 }
        let irValues = data.map { $0.ir }
        let redValues = data.map { $0.red }
        let greenValues = data.map { $0.green }

        func standardDeviation(_ values: [Double]) -> Double {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
            return sqrt(variance)
        }

        let irStd = standardDeviation(irValues)
        let redStd = standardDeviation(redValues)
        let greenStd = standardDeviation(greenValues)

        return max(irStd, max(redStd, greenStd))
    }

    private func normalizeSegment(_ data: [(timestamp: Date, ir: Double, red: Double, green: Double)], using method: NormalizationMethod) -> [(timestamp: Date, ir: Double, red: Double, green: Double)] {
        guard !data.isEmpty else { return data }

        let irValues = data.map { $0.ir }
        let redValues = data.map { $0.red }
        let greenValues = data.map { $0.green }

        switch method {
        case .minMax:
            let irMin = irValues.min() ?? 0
            let irMax = irValues.max() ?? 1
            let redMin = redValues.min() ?? 0
            let redMax = redValues.max() ?? 1
            let greenMin = greenValues.min() ?? 0
            let greenMax = greenValues.max() ?? 1

            return data.map { sample in
                (
                    timestamp: sample.timestamp,
                    ir: irMax > irMin ? (sample.ir - irMin) / (irMax - irMin) : 0,
                    red: redMax > redMin ? (sample.red - redMin) / (redMax - redMin) : 0,
                    green: greenMax > greenMin ? (sample.green - greenMin) / (greenMax - greenMin) : 0
                )
            }

        case .baseline:
            let irBaseline = data.first?.ir ?? 0
            let redBaseline = data.first?.red ?? 0
            let greenBaseline = data.first?.green ?? 0

            return data.map { sample in
                (
                    timestamp: sample.timestamp,
                    ir: sample.ir - irBaseline,
                    red: sample.red - redBaseline,
                    green: sample.green - greenBaseline
                )
            }

        default:
            return data
        }
    }

    // PPG Debug UI (full layout)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.red)
                Text("PPG Channel Debug")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("Last \(recentPPGData.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Normalization Method")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()
                }

                Picker("Normalization", selection: $normalizationMethod) {
                    ForEach(NormalizationMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: normalizationMethod) { _, _ in
                    updateSegmentsIfNeeded()
                }

                Text(normalizationMethod == .none ? "Raw values only" :
                        "Use \(normalizationMethod.rawValue) normalization")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Channel values preview
            HStack(spacing: 16) {
                VStack {
                    Text("IR")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(recentPPGData.last?.ir ?? 0))")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                VStack {
                    Text("Red")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(recentPPGData.last?.red ?? 0))")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                VStack {
                    Text("Green")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(recentPPGData.last?.green ?? 0))")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Spacer()
            }

            Divider()

            // Mini waveform preview using SwiftUI Chart if available
            Chart {
                ForEach(Array(recentPPGData.enumerated()), id: \.offset) { idx, sample in
                    LineMark(x: .value("idx", idx), y: .value("IR", sample.ir))
                        .foregroundStyle(.red.opacity(0.7))
                    LineMark(x: .value("idx", idx), y: .value("Red", sample.red))
                        .foregroundStyle(.pink.opacity(0.6))
                    LineMark(x: .value("idx", idx), y: .value("Green", sample.green))
                        .foregroundStyle(.green.opacity(0.6))
                }
            }
            .frame(height: 160)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

            Divider()

            // State / context
            if let ctx = deviceContext {
                HStack {
                    Image(systemName: ctx.state.iconName)
                        .foregroundColor(ctx.state.color)
                    VStack(alignment: .leading) {
                        Text(ctx.state.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String(format: "Confidence: %.2f", ctx.confidence))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if ctx.shouldNormalize {
                        Text("Stable")
                            .font(.caption)
                            .padding(6)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(6)
                    } else {
                        Text("Unstable")
                            .font(.caption)
                            .padding(6)
                            .background(Color.yellow.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            } else {
                Text("No device context available")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
        .onAppear {
            updateSegmentsIfNeeded()
        }
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
