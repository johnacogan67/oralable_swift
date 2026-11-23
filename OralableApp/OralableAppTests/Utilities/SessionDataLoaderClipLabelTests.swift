//
//  SessionDataLoaderClipLabelTests.swift
//  OralableAppTests
//

import XCTest
@testable import MAMDiagnostics

final class SessionDataLoaderClipLabelTests: XCTestCase {

    func testLegacyOralableRowsStayInIRAndTemperature() {
        let csv = """
        Timestamp,Device_Type,EMG,PPG_IR,PPG_Red,PPG_Green,Temperature
        2026-11-01T02:00:00Z,Oralable,0,120000,100,80,36.5
        2026-11-01T02:00:01Z,MAM,0,130000,110,90,36.6
        2026-11-01T02:00:02Z,ANR M40,50,0,0,0,0
        """

        let loader = SessionDataLoader.shared
        let ir = loader.parseShareViewExport(content: csv, metricType: "IR Activity")
        let temperature = loader.parseShareViewExport(content: csv, metricType: "Temperature")
        let emg = loader.parseShareViewExport(content: csv, metricType: "EMG Activity")

        XCTAssertEqual(ir.count, 2)
        XCTAssertEqual(ir.map { $0.averagePPGIR ?? 0 }, [120000, 130000])
        XCTAssertEqual(temperature.count, 2)
        XCTAssertEqual(temperature[0].averageTemperature, 36.5, accuracy: 0.001)
        XCTAssertEqual(temperature[1].averageTemperature, 36.6, accuracy: 0.001)
        XCTAssertEqual(emg.count, 1)
        XCTAssertEqual(emg.first?.averagePPGIR, 50)
    }

    func testClipLabelDoesNotTreatANRAsTheClip() {
        XCTAssertTrue(SessionDataLoader.exportDeviceType("Oralable", matches: "MAM"))
        XCTAssertTrue(SessionDataLoader.exportDeviceType("MAM", matches: "MAM"))
        XCTAssertFalse(SessionDataLoader.exportDeviceType("ANR M40", matches: "MAM"))
        XCTAssertTrue(SessionDataLoader.exportDeviceType("ANR M40", matches: "ANR M40"))
    }
}
