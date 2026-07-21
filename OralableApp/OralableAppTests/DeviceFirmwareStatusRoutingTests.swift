import XCTest
@testable import OralableApp

@MainActor
final class DeviceFirmwareStatusRoutingTests: XCTestCase {
    func testSecondaryDeviceStatusDoesNotControlPrimaryRecordingWornState() {
        let primaryId = UUID()
        let secondaryId = UUID()

        XCTAssertFalse(
            DeviceManager.shouldRouteFirmwareWornState(
                from: secondaryId,
                primaryPeripheralId: primaryId
            )
        )
    }

    func testPrimaryDeviceStatusControlsPrimaryRecordingWornState() {
        let primaryId = UUID()

        XCTAssertTrue(
            DeviceManager.shouldRouteFirmwareWornState(
                from: primaryId,
                primaryPeripheralId: primaryId
            )
        )
    }
}
