//
//  OvernightStateClassifierTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class OvernightStateClassifierTests: XCTestCase {

    func testClassifyTonicPhasicRescueRecovery() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [NightReportSample] = []

        // 0–20s quiet baseline (high IR, high SpO2, still)
        for i in 0..<200 {
            let t = t0.addingTimeInterval(Double(i) * 0.1)
            samples.append(
                NightReportSample(
                    timestamp: t,
                    ir: 200_000,
                    accelX: 0,
                    accelY: 0,
                    accelZ: 16_384,
                    spo2: 98
                )
            )
        }
        // 20–30s tonic: IR drop, stable motion, SpO2 ok
        for i in 200..<300 {
            let t = t0.addingTimeInterval(Double(i) * 0.1)
            samples.append(
                NightReportSample(
                    timestamp: t,
                    ir: 100_000,
                    accelX: 100,
                    accelY: 0,
                    accelZ: 16_384,
                    spo2: 97
                )
            )
        }
        // 30–40s phasic: high motion
        for i in 300..<400 {
            let t = t0.addingTimeInterval(Double(i) * 0.1)
            let wobble = Double((i % 5) - 2) * 8_000
            samples.append(
                NightReportSample(
                    timestamp: t,
                    ir: 180_000,
                    accelX: wobble,
                    accelY: wobble * 0.5,
                    accelZ: 16_384,
                    spo2: 96
                )
            )
        }
        // 40–50s rescue: IR drop + low SpO2
        for i in 400..<500 {
            let t = t0.addingTimeInterval(Double(i) * 0.1)
            samples.append(
                NightReportSample(
                    timestamp: t,
                    ir: 90_000,
                    accelX: 50,
                    accelY: 0,
                    accelZ: 16_384,
                    spo2: 88
                )
            )
        }
        // 50–60s settle toward baseline
        for i in 500..<600 {
            let t = t0.addingTimeInterval(Double(i) * 0.1)
            samples.append(
                NightReportSample(
                    timestamp: t,
                    ir: 170_000 + Double(i - 500) * 200,
                    accelX: 0,
                    accelY: 0,
                    accelZ: 16_384,
                    spo2: 95
                )
            )
        }

        guard let analysis = OvernightStateClassifier.analyze(samples, classifyHz: 10, timelineHz: 2) else {
            XCTFail("Expected analysis")
            return
        }

        let states = Set(analysis.timeline.map(\.state))
        XCTAssertTrue(states.contains(.tonic) || analysis.kpis.tonicMin > 0, "Expected tonic load")
        XCTAssertTrue(states.contains(.phasic) || analysis.kpis.phasicMin > 0, "Expected phasic load")
        XCTAssertTrue(analysis.kpis.rescueCount > 0 || states.contains(.rescue), "Expected rescue")
        XCTAssertGreaterThan(analysis.kpis.sashb, 0, "Expected SASHB from SpO2 < 90")
        XCTAssertFalse(analysis.bouts.isEmpty)

        let csv = OvernightStateClassifier.eventCSV(from: analysis)
        XCTAssertTrue(csv.contains("start_s,end_s,duration_s,type"))
        XCTAssertTrue(csv.contains("tonic") || csv.contains("phasic") || csv.contains("rescue"))
    }

    func testResearchCSVRoundTrip() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_100)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = fmt.string(from: t0)
        let csv = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override
        oralable,\(ts),1000,200000,200000,800,0,0,16384,36.5,90,72,98,0
        oralable,\(fmt.string(from: t0.addingTimeInterval(0.1))),1000,150000,150000,800,200,0,16384,36.5,90,72,91,0
        """
        let start = t0.addingTimeInterval(-1)
        let end = t0.addingTimeInterval(2)
        let samples = NightReportSampleLoader.parseResearchCSV(content: csv, start: start, end: end)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].ir, 200_000, accuracy: 0.1)
        XCTAssertEqual(samples[1].spo2, 91, accuracy: 0.1)
        XCTAssertEqual(samples[1].accelZ, 16_384, accuracy: 0.1)
    }

    func testLoaderMergesLiveHistory() {
        let t0 = Date()
        let live = (0..<20).map { i -> SensorData in
            let ts = t0.addingTimeInterval(Double(i) * 0.1)
            return SensorData(
                timestamp: ts,
                ppg: PPGData(red: 1000, ir: 180_000, green: 800, timestamp: ts),
                accelerometer: AccelerometerData(x: 0, y: 0, z: 16384, timestamp: ts),
                temperature: TemperatureData(celsius: 36.5, timestamp: ts),
                battery: BatteryData(percentage: 90, timestamp: ts),
                heartRate: nil,
                spo2: SpO2Data(percentage: 97, quality: 0.9, timestamp: ts),
                deviceType: .oralable
            )
        }
        // Empty flush dir: use temp
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("night_loader_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let samples = NightReportSampleLoader.load(
            sessionStart: t0.addingTimeInterval(-1),
            sessionEnd: t0.addingTimeInterval(5),
            liveHistory: live,
            sessionFileURL: nil,
            flushDirectory: tmp
        )
        XCTAssertEqual(samples.count, 20)
        XCTAssertNotNil(OvernightStateClassifier.analyze(samples))
    }
}
