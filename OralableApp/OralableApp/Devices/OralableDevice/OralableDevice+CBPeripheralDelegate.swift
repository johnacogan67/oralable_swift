//
//  OralableDevice+CBPeripheralDelegate.swift
//  OralableApp
//
//  Created: February 2026
//
//  CBPeripheralDelegate conformance for OralableDevice.
//  Handles BLE service/characteristic discovery, notification state changes,
//  write confirmations, and routing incoming data to the appropriate parsers.
//

import Foundation
import CoreBluetooth
import OralableCore

// MARK: - CBPeripheralDelegate

extension OralableDevice: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Service discovery failed: \(error.localizedDescription)")
            serviceDiscoveryContinuation?.resume(throwing: error)
            serviceDiscoveryContinuation = nil
            return
        }

        guard let services = peripheral.services else {
            Logger.shared.error("[OralableDevice] ❌ No services found")
            serviceDiscoveryContinuation?.resume(throwing: DeviceError.serviceNotFound("No services found"))
            serviceDiscoveryContinuation = nil
            return
        }

        Logger.shared.info("[OralableDevice] Found \(services.count) services:")

        for service in services {
            Logger.shared.info("[OralableDevice]   - \(service.uuid.uuidString)")

            if service.uuid == tgmServiceUUID {
                tgmService = service
                Logger.shared.info("[OralableDevice] ✅ TGM service found")
            } else if service.uuid == batteryServiceUUID {
                Logger.shared.info("[OralableDevice] 🔋 Battery service found - discovering characteristics...")
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
            }
        }

        if tgmService != nil {
            serviceDiscoveryContinuation?.resume()
            serviceDiscoveryContinuation = nil
        } else {
            Logger.shared.error("[OralableDevice] ❌ TGM service not found")
            serviceDiscoveryContinuation?.resume(throwing: DeviceError.serviceNotFound("TGM service not found"))
            serviceDiscoveryContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Characteristic discovery failed: \(error.localizedDescription)")
            characteristicDiscoveryContinuation?.resume(throwing: error)
            characteristicDiscoveryContinuation = nil
            return
        }

        guard let characteristics = service.characteristics else {
            Logger.shared.warning("[OralableDevice] ⚠️ No characteristics found for service \(service.uuid.uuidString)")
            return
        }

        // Handle Battery Service characteristics separately
        if service.uuid == batteryServiceUUID {
            for characteristic in characteristics {
                if characteristic.uuid == batteryLevelCharUUID {
                    batteryLevelCharacteristic = characteristic
                    Logger.shared.info("[OralableDevice] 🔋 Battery Level characteristic found")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                }
            }
            return
        }

        Logger.shared.info("[OralableDevice] Found \(characteristics.count) characteristics for TGM service:")

        var foundCount = 0

        for characteristic in characteristics {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                sensorDataCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Sensor Data characteristic found (3A0FF001)")
                foundCount += 1

            case commandCharUUID:
                commandCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Command characteristic found (3A0FF003)")
                foundCount += 1

            case accelerometerCharUUID:
                accelerometerCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Accelerometer characteristic found (3A0FF002)")
                foundCount += 1

            case tgmBatteryCharUUID:
                tgmBatteryCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] 🔋 TGM Battery characteristic found (3A0FF004)")
                peripheral.setNotifyValue(true, for: characteristic)
                foundCount += 1

            default:
                Logger.shared.debug("[OralableDevice] Other characteristic: \(characteristic.uuid.uuidString)")
            }
        }

        if foundCount >= 1 {
            Logger.shared.info("[OralableDevice] ✅ Found \(foundCount)/4 expected characteristics")
            characteristicDiscoveryContinuation?.resume()
            characteristicDiscoveryContinuation = nil
        } else {
            Logger.shared.error("[OralableDevice] ❌ Required characteristics not found")
            characteristicDiscoveryContinuation?.resume(throwing: DeviceError.characteristicNotFound("Required characteristics not found (found \(foundCount)/4)"))
            characteristicDiscoveryContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Notification state update failed: \(error.localizedDescription)")

            if characteristic.uuid == sensorDataCharUUID {
                notificationEnableContinuation?.resume(throwing: error)
                notificationEnableContinuation = nil
            } else if characteristic.uuid == accelerometerCharUUID {
                accelerometerNotificationContinuation?.resume(throwing: error)
                accelerometerNotificationContinuation = nil
            }
            return
        }

        let charName = characteristic.uuid.uuidString.prefix(12)
        Logger.shared.info("[OralableDevice] ✅ Notification \(characteristic.isNotifying ? "enabled" : "disabled") for \(charName)...")

        if characteristic.isNotifying {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.insert(.ppgData)
                Logger.shared.info("[OralableDevice] 📡 PPG notifications confirmed ready")
                notificationEnableContinuation?.resume()
                notificationEnableContinuation = nil

            case accelerometerCharUUID:
                notificationReadiness.insert(.accelerometer)
                Logger.shared.info("[OralableDevice] 📡 Accelerometer notifications confirmed ready")
                accelerometerNotificationContinuation?.resume()
                accelerometerNotificationContinuation = nil

            case commandCharUUID:
                notificationReadiness.insert(.temperature)
                Logger.shared.info("[OralableDevice] 📡 Temperature notifications confirmed ready")

            case batteryLevelCharUUID, tgmBatteryCharUUID:
                notificationReadiness.insert(.battery)
                Logger.shared.info("[OralableDevice] 📡 Battery notifications confirmed ready")

            default:
                Logger.shared.debug("[OralableDevice] 📡 Unknown characteristic notifications enabled: \(charName)")
            }

            Logger.shared.info("[OralableDevice] Readiness state: \(notificationReadiness) (need: \(NotificationReadiness.allRequired))")

            if isConnectionReady {
                Logger.shared.info("[OralableDevice] 🎉 Connection fully ready - all required notifications enabled")

                if let continuation = connectionReadyContinuation {
                    connectionReadyContinuation = nil
                    continuation.resume()
                }
            }
        } else {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.remove(.ppgData)
            case accelerometerCharUUID:
                notificationReadiness.remove(.accelerometer)
            case commandCharUUID:
                notificationReadiness.remove(.temperature)
            case batteryLevelCharUUID, tgmBatteryCharUUID:
                notificationReadiness.remove(.battery)
            default:
                break
            }
            Logger.shared.warning("[OralableDevice] ⚠️ Notifications disabled for \(charName)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Write failed for \(characteristic.uuid.uuidString.prefix(12)): \(error.localizedDescription)")
            writeCompletionContinuation?.resume(throwing: error)
            writeCompletionContinuation = nil
        } else {
            Logger.shared.debug("[OralableDevice] ✅ Write succeeded for \(characteristic.uuid.uuidString.prefix(12))")
            writeCompletionContinuation?.resume()
            writeCompletionContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Value update error: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            Logger.shared.warning("[OralableDevice] ⚠️ Received nil data from characteristic")
            return
        }

        // Route data based on characteristic UUID
        switch characteristic.uuid {
        case sensorDataCharUUID:
            // PPG data (244 bytes typically: 4 + 20x12)
            #if DEBUG
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on PPG characteristic")
            #endif
            parseSensorData(data)

        case accelerometerCharUUID:
            // Accelerometer data (154 bytes typically: 4 + 25x6)
            #if DEBUG
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on accelerometer characteristic")
            #endif
            parseAccelerometerData(data)

        case commandCharUUID:
            // Temperature data (6 bytes typically: 4 + 2)
            #if DEBUG
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on temperature characteristic")
            #endif
            parseTemperature(data)

        case batteryLevelCharUUID:
            // Standard battery level (1 byte, 0-100%)
            parseStandardBatteryLevel(data)

        case tgmBatteryCharUUID:
            // TGM Battery (4 bytes, millivolts)
            parseBatteryData(data)

        default:
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on unknown characteristic: \(characteristic.uuid.uuidString)")
        }
    }
}
