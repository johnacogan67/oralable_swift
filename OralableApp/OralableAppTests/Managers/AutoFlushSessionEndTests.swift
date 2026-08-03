//
//  AutoFlushSessionEndTests.swift
//  OralableAppTests
//
//  Guards disconnect / pause-expiry spill of the trailing unflushed sensor window.
//

import XCTest
@testable import OralableApp
import OralableCore

@MainActor
final class AutoFlushSessionEndTests: XCTestCase {

    override func tearDown() async throws {
        // Best-effort cleanup of flush CSVs written by these tests.
        let dir = ApplicationSupportPaths.memoryFlushDirectory
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) {
            for url in urls where url.lastPathComponent.contains("oralable_") {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try await super.tearDown()
    }

    func testFlushNowForcePersistsUnifiedBufferAfterSessionEnds() async throws {
        let dm = DeviceManager(bleService: MockBLEService())
        let proc = SensorDataProcessor()
        AutoFlushService.shared.start(deviceManager: dm, sensorDataProcessor: proc)

        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = SensorData(
            timestamp: ts,
            ppg: PPGData(red: 1000, ir: 50_000, green: 1000, timestamp: ts),
            accelerometer: AccelerometerData(x: 0, y: 0, z: 16_384, timestamp: ts),
            temperature: TemperatureData(celsius: 36.5, timestamp: ts),
            battery: BatteryData(percentage: 80, timestamp: ts),
            heartRate: nil,
            spo2: nil,
            deviceType: .oralable
        )
        await dm.unifiedSensorDataBuffer.append(sample)
        XCTAssertEqual(await dm.unifiedSensorDataBuffer.count, 1)

        // Simulate pause-expiry end: session inactive, trailing samples still only in RAM.
        dm.automaticRecordingSession?.endSession()
        XCTAssertEqual(dm.automaticRecordingSession?.isSessionActive, false)

        let before = try FileManager.default.contentsOfDirectory(
            at: ApplicationSupportPaths.memoryFlushDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "csv" }.count

        // Hourly tick would no-op here (isSessionActive == false). force must still spill.
        await AutoFlushService.shared.flushNow(force: true)

        let afterURLs = try FileManager.default.contentsOfDirectory(
            at: ApplicationSupportPaths.memoryFlushDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "csv" }
        XCTAssertGreaterThan(afterURLs.count, before, "force flush must write a MemoryFlush CSV after session end")
        XCTAssertEqual(await dm.unifiedSensorDataBuffer.count, 0, "unified buffer must be cleared after successful spill")

        let newest = try XCTUnwrap(afterURLs.max(by: { $0.lastPathComponent < $1.lastPathComponent }))
        let content = try String(contentsOf: newest, encoding: .utf8)
        XCTAssertTrue(content.contains("50000"), "flushed CSV must contain the trailing IR sample")
    }

    func testFlushNowWithoutForceSkipsWhenSessionInactive() async throws {
        let dm = DeviceManager(bleService: MockBLEService())
        let proc = SensorDataProcessor()
        AutoFlushService.shared.start(deviceManager: dm, sensorDataProcessor: proc)

        let ts = Date()
        let sample = SensorData(
            timestamp: ts,
            ppg: PPGData(red: 1000, ir: 42_042, green: 1000, timestamp: ts),
            accelerometer: AccelerometerData(x: 0, y: 0, z: 16_384, timestamp: ts),
            temperature: TemperatureData(celsius: 36.5, timestamp: ts),
            battery: BatteryData(percentage: 80, timestamp: ts),
            heartRate: nil,
            spo2: nil,
            deviceType: .oralable
        )
        await dm.unifiedSensorDataBuffer.append(sample)
        dm.automaticRecordingSession?.endSession()

        await AutoFlushService.shared.flushNow(force: false)
        XCTAssertEqual(
            await dm.unifiedSensorDataBuffer.count,
            1,
            "Non-force flush must not clear buffer when automatic session is inactive"
        )
    }
}
