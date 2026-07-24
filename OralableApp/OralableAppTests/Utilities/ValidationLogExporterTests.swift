//
//  ValidationLogExporterTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp
import OralableCore

final class ValidationLogExporterTests: XCTestCase {

    override func tearDown() {
        NRFConnectBLELogger.shared.clear()
        super.tearDown()
    }

    func testPilotFilenameFormat() {
        let name = ValidationLogExporter.pilotFilename(prefix: "Oralable_PILOT_Ed")
        XCTAssertTrue(name.hasPrefix("Oralable_PILOT_Ed_"))
        XCTAssertTrue(name.hasSuffix(".csv"))
    }

    func testExportNRFConnectLogWritesCSVHeader() throws {
        let logger = NRFConnectBLELogger.shared
        logger.clear()
        logger.connected()
        logger.updatedValue(of: BLEConstants.TGM.sensorDataCharUUID, data: Data(repeating: 0xAB, count: 24))

        let url = try ValidationLogExporter.exportNRFConnectLog(filename: "test_pilot_export.csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("Timestamp,Source,Level,Line\n"))
        XCTAssertTrue(text.contains("Updated Value of Characteristic"))
    }

    func testExportEmptyLogThrows() {
        NRFConnectBLELogger.shared.clear()
        XCTAssertThrowsError(try ValidationLogExporter.exportNRFConnectLog(filename: "empty.csv")) { error in
            XCTAssertTrue(error is ValidationLogExportError)
        }
    }
}
