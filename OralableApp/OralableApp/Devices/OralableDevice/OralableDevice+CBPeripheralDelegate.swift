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
        NRFConnectBLELogger.shared.discoveredServices(services.map { $0.uuid.uuidString })

        for service in services {
            Logger.shared.info("[OralableDevice]   - \(service.uuid.uuidString)")

            if service.uuid == tgmServiceUUID {
                tgmService = service
                Logger.shared.info("[OralableDevice] ✅ TGM service found")
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

        Logger.shared.info("[OralableDevice] Found \(characteristics.count) characteristics for TGM service:")

        var foundCount = 0
        var discoveredUUIDs: [String] = []

        for characteristic in characteristics {
            discoveredUUIDs.append(characteristic.uuid.uuidString)
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
                foundCount += 1

            case deviceIdCharUUID:
                deviceIdCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Device ID characteristic found (3A0FF005)")

            case firmwareVersionCharUUID:
                firmwareVersionCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Firmware version characteristic found (3A0FF006)")

            case ppgRegWriteCharUUID:
                ppgRegWriteCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ PPG register write characteristic found (3A0FF008)")

            case statusCharUUID:
                statusCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Status characteristic found (3A0FF009)")
                foundCount += 1

            case firmwareLogCharUUID:
                firmwareLogCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] 🪵 Firmware log characteristic found (3A0FF00A)")

            case firmwareConfigCharUUID:
                firmwareConfigCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ⚙️ Firmware config characteristic found (3A0FF00B)")

            case firmwareConfigStateCharUUID:
                firmwareConfigStateCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ⚙️ Firmware config state characteristic found (3A0FF00C)")

            default:
                Logger.shared.debug("[OralableDevice] Other characteristic: \(characteristic.uuid.uuidString)")
            }

            peripheral.discoverDescriptors(for: characteristic)
        }

        if service.uuid == tgmServiceUUID, !discoveredUUIDs.isEmpty {
            NRFConnectBLELogger.shared.discoveredCharacteristics(discoveredUUIDs, forService: service.uuid.uuidString)
        }

        let hasCoreStreaming = sensorDataCharacteristic != nil
            && accelerometerCharacteristic != nil
            && commandCharacteristic != nil
            && tgmBatteryCharacteristic != nil
            && statusCharacteristic != nil

        if hasCoreStreaming {
            Logger.shared.info("[OralableDevice] ✅ Core TGM characteristics discovered (\(foundCount) notify-capable)")
            characteristicDiscoveryContinuation?.resume()
            characteristicDiscoveryContinuation = nil
        } else {
            Logger.shared.error("[OralableDevice] ❌ Required characteristics not found")
            characteristicDiscoveryContinuation?.resume(throwing: DeviceError.characteristicNotFound("Required TGM characteristics not found (found \(foundCount))"))
            characteristicDiscoveryContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.warning("[OralableDevice] ⚠️ Descriptor discovery failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        let hasCCC = characteristic.descriptors?.contains(where: {
            $0.uuid == CBUUID(string: "2902")
        }) ?? false

        if hasCCC {
            NRFConnectBLELogger.shared.discoveredCCC(for: characteristic.uuid.uuidString)
        } else {
            NRFConnectBLELogger.shared.characteristicHasNoDescriptors(characteristic.uuid.uuidString)
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
            } else if characteristic.uuid == statusCharUUID {
                statusNotificationContinuation?.resume(throwing: error)
                statusNotificationContinuation = nil
            } else if characteristic.uuid == tgmBatteryCharUUID {
                batteryNotificationContinuation?.resume(throwing: error)
                batteryNotificationContinuation = nil
            } else if characteristic.uuid == commandCharUUID {
                temperatureNotificationContinuation?.resume(throwing: error)
                temperatureNotificationContinuation = nil
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
                temperatureNotificationContinuation?.resume()
                temperatureNotificationContinuation = nil

            case statusCharUUID:
                notificationReadiness.insert(.status)
                Logger.shared.info("[OralableDevice] 📡 Status notifications confirmed ready")
                statusNotificationContinuation?.resume()
                statusNotificationContinuation = nil

            case tgmBatteryCharUUID:
                notificationReadiness.insert(.battery)
                Logger.shared.info("[OralableDevice] 📡 Battery notifications confirmed ready")
                batteryNotificationContinuation?.resume()
                batteryNotificationContinuation = nil

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
            let disableError = DeviceError.connectionFailed(
                "Notifications disabled for \(characteristic.uuid.uuidString.prefix(12))"
            )
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.remove(.ppgData)
                notificationEnableContinuation?.resume(throwing: disableError)
                notificationEnableContinuation = nil
            case accelerometerCharUUID:
                notificationReadiness.remove(.accelerometer)
                accelerometerNotificationContinuation?.resume(throwing: disableError)
                accelerometerNotificationContinuation = nil
            case commandCharUUID:
                notificationReadiness.remove(.temperature)
                temperatureNotificationContinuation?.resume(throwing: disableError)
                temperatureNotificationContinuation = nil
            case statusCharUUID:
                notificationReadiness.remove(.status)
                statusNotificationContinuation?.resume(throwing: disableError)
                statusNotificationContinuation = nil
            case tgmBatteryCharUUID:
                notificationReadiness.remove(.battery)
                batteryNotificationContinuation?.resume(throwing: disableError)
                batteryNotificationContinuation = nil
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
            if characteristic.uuid == firmwareVersionCharUUID, let c = firmwareReadContinuation {
                firmwareReadContinuation = nil
                c.resume(throwing: error)
            } else if characteristic.uuid == deviceIdCharUUID, let c = deviceIdReadContinuation {
                deviceIdReadContinuation = nil
                c.resume(throwing: error)
            }
            if characteristic.uuid == firmwareConfigStateCharUUID, let c = firmwareConfigStateReadContinuation {
                firmwareConfigStateReadContinuation = nil
                c.resume(throwing: error)
            }
            return
        }

        guard let data = characteristic.value else {
            Logger.shared.warning("[OralableDevice] ⚠️ Received nil data from characteristic")
            if characteristic.uuid == firmwareVersionCharUUID, let c = firmwareReadContinuation {
                firmwareReadContinuation = nil
                c.resume(throwing: DeviceError.invalidData)
            } else if characteristic.uuid == deviceIdCharUUID, let c = deviceIdReadContinuation {
                deviceIdReadContinuation = nil
                c.resume(throwing: DeviceError.invalidData)
            }
            return
        }

        NRFConnectBLELogger.shared.updatedValue(of: characteristic.uuid.uuidString, data: data)
        linkActivityHandler?(peripheral.identifier)

        // Route data based on characteristic UUID
        switch characteristic.uuid {
        case deviceIdCharUUID:
            if let deviceId = OralableCore.BLEDataParser.parseDeviceId(data) {
                deviceIdValue = deviceId
                if let c = deviceIdReadContinuation {
                    deviceIdReadContinuation = nil
                    c.resume(returning: deviceId)
                }
            } else if let c = deviceIdReadContinuation {
                deviceIdReadContinuation = nil
                c.resume(throwing: DeviceError.invalidData)
            }

        case statusCharUUID:
            parseDeviceStatus(data)

        case firmwareVersionCharUUID:
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                if let c = firmwareReadContinuation {
                    firmwareReadContinuation = nil
                    c.resume(throwing: DeviceError.invalidData)
                }
                return
            }
            deviceInfo.firmwareVersion = raw
            if let c = firmwareReadContinuation {
                firmwareReadContinuation = nil
                c.resume(returning: raw)
            }

        case sensorDataCharUUID:
            // PPG data (244 bytes typically: 4 + 20x12)
            parseSensorData(data)

        case accelerometerCharUUID:
            // Accelerometer data (154 bytes typically: 4 + 25x6)
            parseAccelerometerData(data)

        case commandCharUUID:
            // Temperature data (6 bytes typically: 4 + 2)
            parseTemperature(data)

        case tgmBatteryCharUUID:
            // TGM Battery (4 bytes, millivolts)
            parseBatteryData(data)

        case firmwareLogCharUUID:
            let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .newlines) ?? "<non-utf8 \(data.count)b>"
            Logger.shared.info("[FW][\(peripheral.identifier.uuidString.prefix(8))] \(line)")
            NRFConnectBLELogger.shared.log(
                source: .connectedDevice,
                level: .application,
                line: "\"\(line)\" value received."
            )

        case firmwareConfigStateCharUUID:
            let bytes = [UInt8](data)
            Logger.shared.info("[FWCFG][\(peripheral.identifier.uuidString.prefix(8))] state bytes=\(bytes)")
            if let continuation = firmwareConfigStateReadContinuation {
                firmwareConfigStateReadContinuation = nil
                continuation.resume(returning: data)
            }

        default:
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on unknown characteristic: \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            Logger.shared.warning("[OralableDevice] ⚠️ RSSI read failed: \(error.localizedDescription)")
            return
        }

        let value = RSSI.intValue
        deviceInfo.signalStrength = value
        Logger.shared.debug("[OralableDevice] 📶 RSSI updated: \(value) dBm")
        linkMetricsHandler?(peripheral.identifier, value)
    }
}
