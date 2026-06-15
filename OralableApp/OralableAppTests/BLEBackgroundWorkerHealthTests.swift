import XCTest
import CoreBluetooth
@testable import OralableApp

@MainActor
final class BLEBackgroundWorkerHealthTests: XCTestCase {

    func testGenericCharacteristicUpdatesDoNotResetSensorHealth() async {
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let worker = BLEBackgroundWorker(bleService: mockBLEService)

        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        worker.start()
        mockBLEService.simulateCharacteristicDataReceived(peripheral: peripheral, data: Data([0x01]))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(
            worker.connectionHealth[deviceId],
            "Status/battery/diagnostic GATT traffic must not reset sensor-stream health"
        )

        worker.recordDataReceived(from: deviceId)
        XCTAssertEqual(worker.connectionHealth[deviceId], .healthy)

        worker.stop()
    }
}
