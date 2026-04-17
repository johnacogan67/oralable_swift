//
//  DeviceScanningCoordinator.swift
//  OralableApp
//
//  Extracted from DeviceManager.swift - handles BLE device scanning and discovery.
//
//  Responsibilities:
//  - Starting and stopping BLE scans
//  - Handling discovered device callbacks
//  - Device type detection (Oralable, ANR, Demo)
//  - Demo device discovery in demo mode
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

// MARK: - Device Scanning & Discovery

extension DeviceManager {

    // MARK: - Advertised service UUID helpers

    /// TGM primary service UUID (matches `OralableDevice.tgmServiceUUID`).
    private static let oralableTgmServiceUUIDString = "3A0FF000-98C4-46B2-94AF-1AEE0FD4C48E"

    private static func advertisedServiceUUIDStrings(from advertisementData: [String: Any]) -> Set<String> {
        var out: Set<String> = []

        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            out.formUnion(uuids.map { $0.uuidString.uppercased() })
        }

        // Some stacks put additional UUIDs here when the main list overflows.
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            out.formUnion(overflow.map { $0.uuidString.uppercased() })
        }

        // Service-data keys are UUIDs too; include them as weak hints (still bounded).
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            out.formUnion(serviceData.keys.map { $0.uuidString.uppercased() })
        }

        return out
    }

    // MARK: - Device Discovery Handlers

    func handleDeviceDiscovered(peripheral: CBPeripheral, name: String, rssi: Int, advertisementData: [String: Any] = [:]) {
        discoveryCount += 1

        #if DEBUG
        if discoveryCount == 1 || discoveryCount % 25 == 0 {
            Logger.shared.debug("[DeviceManager] Discovered device #\(discoveryCount): \(name) | RSSI: \(rssi) dBm")
        }
        #endif

        // Check if already in discoveredDevices list (UI)
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            // Just update RSSI for existing entry
            discoveredDevices[index].signalStrength = rssi
            Logger.shared.debug("[DeviceManager] ⏭️ Device already in list - updating RSSI only")
            return
        }

        // Detect device type - STRICT FILTERING
        guard let deviceType = detectDeviceType(from: name, peripheral: peripheral, advertisementData: advertisementData) else {
            let rejectionKey = "\(peripheral.identifier.uuidString)|\(name.lowercased())"
            if rejectedDiscoveryLogSeenThisScan.insert(rejectionKey).inserted {
                #if DEBUG
                let adKeys = advertisementData.keys.map { String(describing: $0) }.sorted()
                let serviceUUIDs = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
                    .map { $0.uuidString.uppercased() }
                    .sorted()
                let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "n/a"
                let hasMfrData = advertisementData[CBAdvertisementDataManufacturerDataKey] != nil
                let serviceDataKeys = ((advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]) ?? [:])
                    .keys
                    .map { $0.uuidString.uppercased() }
                    .sorted()
                Logger.shared.debug(
                    "[DeviceManager] Rejected discovery details | name=\(name) | localName=\(localName) | rssi=\(rssi) | services=\(serviceUUIDs) | serviceDataKeys=\(serviceDataKeys) | hasManufacturerData=\(hasMfrData) | adKeys=\(adKeys)"
                )
                #endif
                Logger.shared.debug("[DeviceManager] ❌ Unknown device type '\(name)' - rejected")
            }
            return
        }

        Logger.shared.info("[DeviceManager] ✅ Device discovered: \(name) (\(deviceType))")

        // Create device info for UI
        let deviceInfo = DeviceInfo(
            type: deviceType,
            name: name,
            peripheralIdentifier: peripheral.identifier,
            connectionState: .disconnected,
            signalStrength: rssi
        )

        // Always add to discovered list for UI display
        discoveredDevices.append(deviceInfo)
        Logger.shared.info("[DeviceManager] 📝 Device added to UI list. Total discovered: \(discoveredDevices.count)")

        // Initialize readiness state
        deviceReadiness[peripheral.identifier] = .disconnected

        // Only create new device instance if we don't already have one
        // (device instances persist across scans to maintain state)
        if devices[peripheral.identifier] == nil {
            let device: BLEDeviceProtocol

            switch deviceType {
            case .oralable:
                device = OralableDevice(peripheral: peripheral)
            case .anr:
                device = ANRMuscleSenseDevice(peripheral: peripheral, name: name)
            case .demo:
                #if DEBUG
                device = MockBLEDevice(type: .demo)
                #else
                device = OralableDevice(peripheral: peripheral)
                #endif
            }

            // Store device - KEY POINT: Using peripheral.identifier as the key
            devices[peripheral.identifier] = device
            Logger.shared.debug("[DeviceManager] 💾 New device instance created and stored")

            // Subscribe to device sensor readings
            subscribeToDevice(device)
        } else {
            Logger.shared.debug("[DeviceManager] 📦 Reusing existing device instance")
        }

        #if DEBUG
        Logger.shared.debug("[DeviceManager] 📊 Total devices in system:")
        Logger.shared.debug("[DeviceManager]    - discoveredDevices: \(discoveredDevices.count)")
        Logger.shared.debug("[DeviceManager]    - devices dictionary: \(devices.count)")
        #endif
    }

    // MARK: - Device Type Detection
    // UPDATED: December 8, 2025 - Stricter filtering to only accept Oralable and ANR devices

    func detectDeviceType(from name: String, peripheral: CBPeripheral, advertisementData: [String: Any]) -> DeviceType? {
        let lowercaseName = name.lowercased()
        let serviceStrings = Self.advertisedServiceUUIDStrings(from: advertisementData)

        // Check for Oralable device - STRICT matching
        if lowercaseName.contains("oralable") {
            Logger.shared.info("[DeviceManager] ✅ Detected Oralable device: \(name)")
            return .oralable
        }

        // Check for ANR M40 device - STRICT matching
        if lowercaseName.contains("anr") || lowercaseName.contains("m40") {
            Logger.shared.info("[DeviceManager] ✅ Detected ANR device: \(name)")
            return .anr
        }

        // Fallback for firmware that advertises a generic name (often "Unknown"):
        // `FE9F` is NOT unique to Oralable (many Nordic-based peripherals use it),
        // so we only accept Oralable if the TGM service UUID is present in the advertisement.
        if serviceStrings.contains(Self.oralableTgmServiceUUIDString) {
            Logger.shared.info("[DeviceManager] ✅ Detected Oralable by TGM service UUID: \(name)")
            return .oralable
        }
        if serviceStrings.contains("FEAF") {
            Logger.shared.info("[DeviceManager] ✅ Detected ANR by service UUID FEAF: \(name)")
            return .anr
        }

        // Reject all other devices
        return nil
    }

    // MARK: - Scanning Control

    /// Start scanning for devices
    func startScanning() async {
        Logger.shared.info("[DeviceManager] 🔍 startScanning() called")
        Logger.shared.info("[DeviceManager] Current state - discoveredDevices: \(discoveredDevices.count), devices: \(devices.count)")

        // Day 4 Fix: Don't scan if we already have a ready device (but allow demo device discovery)
        if deviceReadiness.values.contains(.ready) && !FeatureFlags.shared.demoModeEnabled {
            Logger.shared.info("[DeviceManager] 🛑 Already have ready device - skipping scan")
            return
        }

        // Don't restart if already scanning
        if isScanning {
            Logger.shared.info("[DeviceManager] 🛑 Already scanning - skipping")
            return
        }

        Logger.shared.info("[DeviceManager] Starting device scan")

        scanStartTime = Date()
        discoveryCount = 0
        rejectedDiscoveryLogSeenThisScan.removeAll()
        discoveredDevices.removeAll()
        deviceReadiness.removeAll()
        isScanning = true

        Logger.shared.info("[DeviceManager] ✅ Scan started - discoveredDevices cleared, isScanning = true")

        bleService?.startScanning(services: nil)

        // If demo mode enabled, also "discover" the demo device
        if FeatureFlags.shared.demoModeEnabled {
            Logger.shared.info("[DeviceManager] 🎭 Demo mode enabled - triggering demo device discovery")

            // Add demo device to discoveredDevices after short delay (simulates discovery)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }

                // Create a demo device entry using the fixed UUID
                let demoUUID = UUID(uuidString: "DEADBEEF-DEMO-0001-0000-000000000001") ?? UUID()

                let demoDevice = DeviceInfo(
                    type: .demo,
                    name: DemoDataProvider.shared.deviceName,
                    peripheralIdentifier: demoUUID,
                    connectionState: .disconnected,
                    signalStrength: -50
                )

                // Add to discovered devices list (same list the UI displays)
                if !self.discoveredDevices.contains(where: { $0.type == .demo }) {
                    self.discoveredDevices.append(demoDevice)
                    DemoDataProvider.shared.isDiscovered = true
                    Logger.shared.info("[DeviceManager] 🎭 Demo device added to discoveredDevices (count: \(self.discoveredDevices.count))")
                }
            }
        }
    }

    /// Stop scanning for devices
    func stopScanning() {
        Logger.shared.info("[DeviceManager] 🛑 stopScanning() called")
        Logger.shared.info("[DeviceManager] Discovered devices at stop time: \(discoveredDevices.count)")

        #if DEBUG
        if let scanStart = scanStartTime {
            let elapsed = Date().timeIntervalSince(scanStart)
            Logger.shared.debug("[DeviceManager] Scan stopped | Duration: \(String(format: "%.1f", elapsed))s | Devices found: \(discoveredDevices.count)")
        }
        #endif

        isScanning = false
        bleService?.stopScanning()
        scanStartTime = nil

        // Note: Don't reset demo discovery state here - we want to keep the demo device
        // visible after scanning stops so user can still connect to it

        Logger.shared.info("[DeviceManager] ✅ Scan stopped - isScanning = false")
    }
}
