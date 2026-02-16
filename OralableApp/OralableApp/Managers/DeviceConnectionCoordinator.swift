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

        // Notify background worker of successful connection (clears reconnection state)
        backgroundWorker.handleConnectionSuccess(for: peripheral.identifier)

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

        // Start Day 2 async discovery flow
        Task {
            await discoverServicesAndCharacteristics(peripheral: peripheral)
        }
    }

    // Day 2: Async service and characteristic discovery with notification enabling
    func discoverServicesAndCharacteristics(peripheral: CBPeripheral) async {
        guard let device = devices[peripheral.identifier] else {
            Logger.shared.error("[DeviceManager] ❌ Device not found in devices dictionary")
            return
        }

        // Guard against race condition: peripheral may disconnect before this task runs
        guard peripheral.state == .connected else {
            Logger.shared.warning("[DeviceManager] Peripheral disconnected before discovery could start")
            updateDeviceReadiness(peripheral.identifier, to: .disconnected)
            return
        }

        do {
            // Step 1: Discover services (10-second timeout)
            updateDeviceReadiness(peripheral.identifier, to: .discoveringServices)
            try await withTimeout(seconds: 10) {
                try await device.discoverServices()
            }

            guard peripheral.state == .connected else {
                Logger.shared.warning("[DeviceManager] Peripheral disconnected during service discovery")
                updateDeviceReadiness(peripheral.identifier, to: .disconnected)
                return
            }
            updateDeviceReadiness(peripheral.identifier, to: .servicesDiscovered)

            // Step 2: Discover characteristics (10-second timeout)
            updateDeviceReadiness(peripheral.identifier, to: .discoveringCharacteristics)
            try await withTimeout(seconds: 10) {
                try await device.discoverCharacteristics()
            }

            guard peripheral.state == .connected else {
                Logger.shared.warning("[DeviceManager] Peripheral disconnected during characteristic discovery")
                updateDeviceReadiness(peripheral.identifier, to: .disconnected)
                return
            }
            updateDeviceReadiness(peripheral.identifier, to: .characteristicsDiscovered)

            // Step 3: Enable notifications on main characteristic (10-second timeout)
            updateDeviceReadiness(peripheral.identifier, to: .enablingNotifications)
            try await withTimeout(seconds: 10) {
                try await device.enableNotifications()
            }

            guard peripheral.state == .connected else {
                Logger.shared.warning("[DeviceManager] Peripheral disconnected during notification setup")
                updateDeviceReadiness(peripheral.identifier, to: .disconnected)
                return
            }

            // Step 4: Enable accelerometer notifications (with timeout)
            if let oralableDevice = device as? OralableDevice {
                do {
                    try await withTimeout(seconds: 10) {
                        await oralableDevice.enableAccelerometerNotifications()
                    }
                } catch {
                    Logger.shared.warning("[DeviceManager] ⚠️ Accelerometer notification timeout (non-critical): \(error.localizedDescription)")
                }

                // Step 4b: Enable temperature notifications on 3A0FF003 (with timeout)
                do {
                    try await withTimeout(seconds: 10) {
                        await oralableDevice.enableTemperatureNotifications()
                    }
                } catch {
                    Logger.shared.warning("[DeviceManager] ⚠️ Temperature notification timeout (non-critical): \(error.localizedDescription)")
                }

                // Step 5: Configure PPG LEDs to turn them on
                do {
                    try await oralableDevice.configurePPGLEDs()
                } catch {
                    Logger.shared.warning("[DeviceManager] ⚠️ LED configuration failed (non-critical): \(error.localizedDescription)")
                }
            }

            // Device is now ready!
            updateDeviceReadiness(peripheral.identifier, to: .ready)
            Logger.shared.info("[DeviceManager] ✅ Device fully ready - all notifications enabled, LEDs configured")

            // Start automatic recording session
            automaticRecordingSession?.onDeviceConnected()

        } catch {
            Logger.shared.error("[DeviceManager] ❌ Discovery failed: \(error.localizedDescription)")
            updateDeviceReadiness(peripheral.identifier, to: .failed(error.localizedDescription))
        }
    }

    func handleDeviceDisconnected(peripheral: CBPeripheral, error: Error?) {
        let wasUnexpectedDisconnection = error != nil

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

        // Update device states
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            discoveredDevices[index].connectionState = .disconnected
        }

        connectedDevices.removeAll { $0.peripheralIdentifier == peripheral.identifier }

        if primaryDevice?.peripheralIdentifier == peripheral.identifier {
            primaryDevice = connectedDevices.first
        }

        // Delegate reconnection to background worker
        backgroundWorker.handleDisconnection(
            for: peripheral.identifier,
            peripheral: peripheral,
            wasUnexpected: wasUnexpectedDisconnection
        )
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
        try? await device.stopDataCollection()
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
