//
//  CalibrationCaptureValidationTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class CalibrationCaptureValidationTests: XCTestCase {
    func testCannotPersistWithoutOralableSamples() {
        XCTAssertFalse(
            CalibrationCaptureValidation.canPersistSuccessfulCalibration(
                oralableSampleCount: 0,
                rawCalibrationCSVFileName: "temporalis_cal.csv"
            )
        )
    }

    func testCannotPersistWithoutRawCalibrationCSV() {
        XCTAssertFalse(
            CalibrationCaptureValidation.canPersistSuccessfulCalibration(
                oralableSampleCount: 100,
                rawCalibrationCSVFileName: nil
            )
        )
    }

    func testCanPersistWithSamplesAndRawCalibrationCSV() {
        XCTAssertTrue(
            CalibrationCaptureValidation.canPersistSuccessfulCalibration(
                oralableSampleCount: 100,
                rawCalibrationCSVFileName: "temporalis_cal.csv"
            )
        )
    }
}
