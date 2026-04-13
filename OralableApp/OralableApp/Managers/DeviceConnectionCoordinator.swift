//
//  DeviceConnectionCoordinator.swift
//  OralableApp
//
//  Extracted from DeviceManager.swift - handles BLE device connection lifecycle.
//
//  Responsibilities:
//  - Handling device connected/disconnected callbacks
//  - Service and characteristic discovery flow
//  - Connection and disconnection actions
//  - Demo device connection handling
//  - Reconnection cancellation
//  - Async timeout helper for BLE operations
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

// MARK: - Device Connection Management

extension DeviceManager {

    // MARK: - Connection Handlers

    // Day 1 & Day 2: Updated to use async discovery flow
    func handleDeviceConnected(peripheral: CBPeripheral) {
        Logger.shared.info("[DeviceManager] Device connected: \(peripheral.name ?? "Unknown")")

        isConnecting = false

        // Update connection readiness to .connected
        updateDeviceReadiness(peripheral.identifier, to: .connected)

        // Update device info
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            discoveredDevices[index].connectionState = .connected

            // Add to connected devices if not already there
            if !connectedDevices.contains(where: { $0.id == discoveredDevices[index].id }) {
                connectedDevices.append(discoveredDevices[index])
            }

            // Set as primary if none set
            if primaryDevice == nil {
                primaryDevice = discoveredDevices[index]
            }

            // Remember this device for auto-reconnect
            persistenceManager.rememberDevice(
                id: peripheral.identifier.uuidString,
                name: discoveredDevices[index].name
            )
        }

        // Start RSSI polling for connected peripherals
        let connectedPeripherals = connectedDevices.compactMap { deviceInfo -> CBPeripheral? in
            guard let peripheralId = deviceInfo.peripheralIdentifier else { return nil }
            return devices[peripheralId]?.peripheral
        }
        backgroundWorker.startRSSIPolling(for: connectedPeripherals)

        // Start Day 2 async discovery flow (single-flight per peripheral)
        startDiscoveryFlowIfNeeded(for: peripheral)
    }

    // Day 2: Async service and characteristic discovery with notification enabling
    func discoverServicesAndCharacteristics(peripheral: CBPeripheral) async {
        guard let device = devices[peripheral.identifier] else {
            Logger.shared.error("[DeviceManager] ❌ Device not found in devices dictionary")
            return
        }

        let traceId = String(peripheral.identifier.uuidString.prefix(8))
        let flowStartedAt = Date()
        Logger.shared.info("[DeviceManager][BLETrace \(traceId)] ▶️ Discovery flow started for \(peripheral.name ?? "Unknown")")

        // Guard against race condition: peripheral may disconnect before this task runs
        guard peripheral.state == .connected else {
            Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] Peripheral disconnected before discovery could start")
            updateDeviceReadiness(peripheral.identifier, to: .disconnected)
            return
        }

        // Clear any prior pending continuations before starting a new flow (reconnect churn safety).
        if let oralableDevice = device as? OralableDevice {
            oralableDevice.cancelPendingContinuations()
        }

        do {
            // Step 1: Discover services (10-second timeout)
            let step1Start = Date()
            Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 1/5 discoverServices() start")
            updateDeviceReadiness(peripheral.identifier, to: .discoveringServices)
            try await withTimeout(seconds: 10) {
                try await device.discoverServices()
            }
            Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 1/5 discoverServices() done in \(Int(Date().timeIntervalSince(step1Start) * 1000))ms")

            guard peripheral.state == .connected else {
                Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] Peripheral disconnected during service discovery")
                updateDeviceReadiness(peripheral.identifier, to: .disconnected)
                return
            }
            updateDeviceReadiness(peripheral.identifier, to: .servicesDiscovered)

            // Step 2: Discover characteristics (10-second timeout)
            let step2Start = Date()
            Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 2/5 discoverCharacteristics() start")
            updateDeviceReadiness(peripheral.identifier, to: .discoveringCharacteristics)
            try await withTimeout(seconds: 10) {
                try await device.discoverCharacteristics()
            }
            Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 2/5 discoverCharacteristics() done in \(Int(Date().timeIntervalSince(step2Start) * 1000))ms")

            guard peripheral.state == .connected else {
                Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] Peripheral disconnected during characteristic discovery")
                updateDeviceReadiness(peripheral.identifier, to: .disconnected)
                return
            }
            updateDeviceReadiness(peripheral.identifier, to: .characteristicsDiscovered)

            // Firmware safety gate (REV10): read version before enabling notifications / streaming.
            if let oralableDevice = device as? OralableDevice {
                let firmwareReadStart = Date()
                Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 3/5 readFirmwareVersion() start")
                let version = try await withTimeout(seconds: 5) {
                    try await oralableDevice.readFirmwareVersion()
                }
                Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 3/5 readFirmwareVersion() done in \(Int(Date().timeIntervalSince(firmwareReadStart) * 1000))ms -> \(version)")
                applyDiscoveredFirmwareVersion(peripheralId: peripheral.identifier, version: version)
                if FirmwareGate.isOralableVersionOutdated(version) {
                    lastError = .firmwareUpdateRequired(
                        requiredMinimum: FirmwareGate.minimumOralableSemanticVersion,
                        reported: version
                    )
                    oralableFirmwareBlockedPeripheralIds.insert(peripheral.identifier)
                    isConnecting = false
                    updateDeviceReadiness(peripheral.identifier, to: .failed("Firmware update required"))
                    bleService?.disconnect(from: peripheral)
                    return
                }
                oralableFirmwareBlockedPeripheralIds.remove(peripheral.identifier)
            }

            // Step 3: Enable notifications on main characteristic (10-second timeout)
            let step4Start = Date()
            Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 4/5 enableNotifications() start")
            updateDeviceReadiness(peripheral.identifier, to: .enablingNotifications)
            try await withTimeout(seconds: 10) {
                try await device.enableNotifications()
            }
            Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 4/5 enableNotifications() done in \(Int(Date().timeIntervalSince(step4Start) * 1000))ms")

            guard peripheral.state == .connected else {
                Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] Peripheral disconnected during notification setup")
                updateDeviceReadiness(peripheral.identifier, to: .disconnected)
                return
            }

            // Step 4: Enable accelerometer notifications (with timeout)
            if let oralableDevice = device as? OralableDevice {
                do {
                    let accelNotifyStart = Date()
                    Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 5/5 enableAccelerometerNotifications() start")
                    try await withTimeout(seconds: 10) {
                        await oralableDevice.enableAccelerometerNotifications()
                    }
                    Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 5/5 enableAccelerometerNotifications() done in \(Int(Date().timeIntervalSince(accelNotifyStart) * 1000))ms")
                } catch {
                    Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] ⚠️ Accelerometer notification timeout (non-critical): \(error.localizedDescription)")
                }

                // Step 4b: Enable temperature notifications on 3A0FF003 (with timeout)
                do {
                    let tempNotifyStart = Date()
                    Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 5b enableTemperatureNotifications() start")
                    try await withTimeout(seconds: 10) {
                        await oralableDevice.enableTemperatureNotifications()
                    }
                    Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 5b enableTemperatureNotifications() done in \(Int(Date().timeIntervalSince(tempNotifyStart) * 1000))ms")
                } catch {
                    Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] ⚠️ Temperature notification timeout (non-critical): \(error.localizedDescription)")
                }

                // Step 5: Configure PPG LEDs to turn them on
                do {
                    let ledConfigStart = Date()
                    Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 5c configurePPGLEDs() start")
                    try await oralableDevice.configurePPGLEDs()
                    Logger.shared.debug("[DeviceManager][BLETrace \(traceId)] Step 5c configurePPGLEDs() done in \(Int(Date().timeIntervalSince(ledConfigStart) * 1000))ms")
                } catch {
                    Logger.shared.warning("[DeviceManager][BLETrace \(traceId)] ⚠️ LED configuration failed (non-critical): \(error.localizedDescription)")
                }
            }

            // Device is now ready!
            updateDeviceReadiness(peripheral.identifier, to: .ready)
            Logger.shared.info("[DeviceManager][BLETrace \(traceId)] ✅ Device fully ready in \(Int(Date().timeIntervalSince(flowStartedAt) * 1000))ms")

            // Start automatic recording session
            automaticRecordingSession?.onDeviceConnected()

        } catch {
            Logger.shared.error("[DeviceManager][BLETrace \(traceId)] ❌ Discovery failed after \(Int(Date().timeIntervalSince(flowStartedAt) * 1000))ms: \(error.localizedDescription)")
            updateDeviceReadiness(peripheral.identifier, to: .failed(error.localizedDescription))
        }
    }

    private func startDiscoveryFlowIfNeeded(for peripheral: CBPeripheral) {
        let id = peripheral.identifier

        // If a discovery task is already running, do not start another.
        if let existing = discoveryFlowTasks[id], !existing.isCancelled {
            Logger.shared.warning("[DeviceManager][BLETrace \(String(id.uuidString.prefix(8)))] ⚠️ Discovery already in progress - skipping duplicate start")
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.discoverServicesAndCharacteristics(peripheral: peripheral)
            await MainActor.run {
                self.discoveryFlowTasks[id] = nil
            }
        }
        discoveryFlowTasks[id] = task
    }

    func handleDeviceDisconnected(peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            Logger.shared.warning("[DeviceManager] Device disconnected with error: \(error.localizedDescription)")
            lastError = .connectionLost
        } else {
            Logger.shared.info("[DeviceManager] Device disconnected: \(peripheral.name ?? "Unknown")")
        }

        isConnecting = false

        // Stop automatic recording session (saves events and triggers sync)
        automaticRecordingSession?.onDeviceDisconnected()

        // Update readiness state
        updateDeviceReadiness(peripheral.identifier, to: .disconnected)

        // Cancel any in-flight discovery flow task and clear pending continuations.
        discoveryFlowTasks[peripheral.identifier]?.cancel()
        discoveryFlowTasks[peripheral.identifier] = nil
        if let device = devices[peripheral.identifier] as? OralableDevice {
            device.cancelPendingContinuations()
        }

        // Update device states
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            discoveredDevices[index].connectionState = .disconnected
        }

        connectedDevices.removeAll { $0.peripheralIdentifier == peripheral.identifier }

        if primaryDevice?.peripheralIdentifier == peripheral.identifier {
            primaryDevice = connectedDevices.first
        }

        // Reconnection handling is centralized in BLEBackgroundWorker's BLE event subscription.
        // Avoid invoking worker handlers here to prevent duplicate reconnection scheduling.
    }

    /// Cancel all ongoing reconnection attempts
    func cancelAllReconnections() {
        backgroundWorker.cancelAllReconnections()
        Logger.shared.debug("[DeviceManager] Cancelled all reconnection attempts via background worker")
    }

    // MARK: - Connection Actions

    // CORRECTED METHOD - Using peripheralIdentifier as dictionary key
    func connect(to deviceInfo: DeviceInfo) async throws {
        Logger.shared.info("[DeviceManager] Connecting to device: \(deviceInfo.name)")

        // Check if this is the demo device
        if deviceInfo.type == .demo {
            Logger.shared.info("[DeviceManager] 🎭 Connecting to demo device")
            isConnecting = true

            // Update device state to connecting
            if let index = discoveredDevices.firstIndex(where: { $0.type == .demo }) {
                discoveredDevices[index].connectionState = .connecting
            }

            // Start playback (connection happens after delay in simulateConnect)
            DemoDataProvider.shared.simulateConnect()

            // Wait for connection to complete
            try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds

            // Move demo device from discovered to connected
            if let index = discoveredDevices.firstIndex(where: { $0.type == .demo }) {
                var connectedDemo = discoveredDevices[index]
                connectedDemo.connectionState = .connected
                connectedDemo.connectionReadiness = .ready

                // Add to connected devices
                if !connectedDevices.contains(where: { $0.type == .demo }) {
                    connectedDevices.append(connectedDemo)
                }

                // Remove from discovered
                discoveredDevices.remove(at: index)
            }

            isConnecting = false
            Logger.shared.info("[DeviceManager] 🎭 Demo device connected and moved to connectedDevices")
            return
        }

        // CRITICAL FIX: Use peripheralIdentifier, not deviceInfo.id
        guard let peripheralId = deviceInfo.peripheralIdentifier else {
            throw DeviceError.invalidPeripheral("Device has no peripheral identifier")
        }

        guard let device = devices[peripheralId] else {
            Logger.shared.error("[DeviceManager] Device not found in registry")
            throw DeviceError.invalidPeripheral("Device not found in registry")
        }

        guard let peripheral = device.peripheral else {
            throw DeviceError.invalidPeripheral("Device has no peripheral")
        }

        isConnecting = true

        // Update state
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
            discoveredDevices[index].connectionState = .connecting
        }

        updateDeviceReadiness(peripheralId, to: .connecting)

        // Cancel any existing reconnection attempts on manual connect
        backgroundWorker.cancelReconnection(for: peripheralId)
        if isScanning {
            Logger.shared.info("[DeviceManager] 🛑 Stopping scan before connect to reduce discovery pressure")
            stopScanning()
        }

        // Connect via BLE manager
        bleService?.connect(to: peripheral)
    }

    func disconnect(from deviceInfo: DeviceInfo) async {
        Logger.shared.info("[DeviceManager] Disconnecting from device: \(deviceInfo.name)")

        // Check if this is the demo device
        if deviceInfo.type == .demo {
            Logger.shared.info("[DeviceManager] 🎭 Disconnecting from demo device")
            DemoDataProvider.shared.disconnect()

            // Remove from connected devices
            connectedDevices.removeAll { $0.type == .demo }
            Logger.shared.info("[DeviceManager] 🎭 Demo device removed from connectedDevices")
            return
        }

        guard let peripheralId = deviceInfo.peripheralIdentifier,
              let device = devices[peripheralId],
              let peripheral = device.peripheral else {
            Logger.shared.error("[DeviceManager] Device or peripheral not found")
            return
        }

        // Cancel any pending reconnection attempts for this device via background worker
        backgroundWorker.cancelReconnection(for: peripheralId)

        // Cancel pending continuations to prevent hangs
        if let oralableDevice = device as? OralableDevice {
            oralableDevice.cancelPendingContinuations()
        }

        bleService?.disconnect(from: peripheral)

        // Stop data collection
        await device.stopDataCollection()
    }

    func disconnectAll() {
        Logger.shared.info("[DeviceManager] Disconnecting all devices")

        for deviceInfo in connectedDevices {
            Task {
                await disconnect(from: deviceInfo)
            }
        }

        // Also disconnect demo device if connected
        if DemoDataProvider.shared.isConnected {
            Logger.shared.info("[DeviceManager] 🎭 Also disconnecting demo device")
            DemoDataProvider.shared.disconnect()
            DemoDataProvider.shared.resetDiscovery()
            connectedDevices.removeAll { $0.type == .demo }
            discoveredDevices.removeAll { $0.type == .demo }
        }

        // Cancel all reconnection attempts
        cancelAllReconnections()
    }

    /// Disconnect demo device and reset its state (called when demo mode is disabled)
    func disconnectDemoDevice() {
        if DemoDataProvider.shared.isConnected {
            Logger.shared.info("[DeviceManager] 🎭 Disconnecting demo device (demo mode disabled)")
            DemoDataProvider.shared.disconnect()
        }
        DemoDataProvider.shared.resetDiscovery()

        // Remove demo device from both lists
        connectedDevices.removeAll { $0.type == .demo }
        discoveredDevices.removeAll { $0.type == .demo }
    }

    // MARK: - Timeout Helper

    // Day 2: Timeout helper for async operations (safe unwrap fix)
    func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation
            group.addTask {
                try await operation()
            }

            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw DeviceError.timeout
            }

            // Return the first one to complete (safe unwrap)
            guard let result = try await group.next() else {
                throw DeviceError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
