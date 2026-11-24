//
//  ResearchRawDataExportTests.swift
//  OralableAppTests
//

import XCTest
@testable import MAMDiagnostics

final class ResearchRawDataExportTests: XCTestCase {

    func testCSVNumberUsesDotDecimal() {
        XCTAssertEqual(ResearchRawDataExport.csvNumber(36.5, fractionDigits: 3), "36.500")
        XCTAssertEqual(ResearchRawDataExport.csvNumber(72.4, fractionDigits: 1), "72.4")
        XCTAssertEqual(ResearchRawDataExport.csvNumber(97, fractionDigits: 0), "97")
        let french = String(format: "%.3f", locale: Locale(identifier: "fr_FR"), 36.5)
        XCTAssertEqual(french, "36,500")
        XCTAssertNotEqual(ResearchRawDataExport.csvNumber(36.5, fractionDigits: 3), french)
    }

    func testFlushCSVRoundTripKeepsSpO2() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_300)
        let sample = SensorData(
            timestamp: timestamp,
            ppg: PPGData(red: 1000, ir: 200_000, green: 800, timestamp: timestamp),
            accelerometer: AccelerometerData(x: 0, y: 0, z: 16_384, timestamp: timestamp),
            temperature: TemperatureData(celsius: 36.5, timestamp: timestamp),
            battery: BatteryData(percentage: 80, timestamp: timestamp),
            heartRate: HeartRateData(bpm: 72.4, quality: 0.9, timestamp: timestamp, hrvMs: 41.2),
            spo2: SpO2Data(percentage: 97, quality: 0.9, timestamp: timestamp),
            deviceType: .oralable
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flush-locale-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try ResearchRawDataExport.writeOralableRaw50HzCSV(samples: [sample], to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false)
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, header.count)
        XCTAssertEqual(fields[9], "36.500")
        XCTAssertEqual(fields[11], "72.4")
        XCTAssertEqual(fields[12], "97")
        XCTAssertEqual(fields[14], "41.2")
        XCTAssertFalse(lines[1].contains("36,500"))
        XCTAssertFalse(lines[1].contains("72,4"))

        let samples = NightReportSampleLoader.parseResearchCSV(
            content: text,
            start: timestamp.addingTimeInterval(-1),
            end: timestamp.addingTimeInterval(1)
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].spo2, 97, accuracy: 0.1)
        XCTAssertEqual(samples[0].heartRateBpm, 72.4, accuracy: 0.1)
        XCTAssertEqual(samples[0].temperature, 36.5, accuracy: 0.001)
        XCTAssertEqual(samples[0].hrvMs, 41.2, accuracy: 0.1)
    }

    /// A row already written with decimal commas cannot be repaired. SpO₂ lands on the heart-rate integer.
    func testLoaderReadsDecimalCommaRowAsHeartRate() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_400)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let csv = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override,hrv_ms
        oralable,\(fmt.string(from: timestamp)),1,2,2,3,0,0,16384,36,500,80,72,4,97,0,41,2
        """
        let samples = NightReportSampleLoader.parseResearchCSV(
            content: csv,
            start: timestamp.addingTimeInterval(-1),
            end: timestamp.addingTimeInterval(1)
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].spo2, 72, accuracy: 0.1)
        XCTAssertEqual(samples[0].heartRateBpm, 80, accuracy: 0.1)
    }
}
