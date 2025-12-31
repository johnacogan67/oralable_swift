//
//  MockDataProvider.swift
//  OralableApp
//
//  Created: Refactoring - Clean Architecture
//  Purpose: Separate mock data generation from production code
//

import Foundation
import Combine
import OralableCore

// MARK: - SensorDataProvider Protocol

/// Protocol for providing sensor data (real or mock)
protocol SensorDataProvider {
    /// Publisher that emits sensor readings
    var sensorReadingsPublisher: AnyPublisher<SensorReading, Never> { get }

    /// Publisher that emits connection state changes
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }

    /// Publisher that emits device name changes
    var deviceNamePublisher: AnyPublisher<String, Never> { get }

    /// Start providing data
    func startDataStream()

    /// Stop providing data
    func stopDataStream()

    /// Connect to a device (if applicable)
    func connect() async throws

    /// Disconnect from device (if applicable)
    func disconnect() async
}

// MARK: - Real BLE Data Provider

/// Production data provider using DeviceManager
@MainActor
class RealBLEDataProvider: SensorDataProvider {
    private let deviceManager: DeviceManager
    private var cancellables = Set<AnyCancellable>()

    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
    }

    var sensorReadingsPublisher: AnyPublisher<SensorReading, Never> {
        deviceManager.$allSensorReadings
            .flatMap { readings in
                Publishers.Sequence(sequence: readings)
            }
            .eraseToAnyPublisher()
    }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        deviceManager.$connectedDevices
            .map { !$0.isEmpty }
            .eraseToAnyPublisher()
    }

    var deviceNamePublisher: AnyPublisher<String, Never> {
        deviceManager.$primaryDevice
            .map { $0?.name ?? "No Device" }
            .eraseToAnyPublisher()
    }

    func startDataStream() {
        Task {
            await deviceManager.startScanning()
        }
    }

    func stopDataStream() {
        deviceManager.stopScanning()
    }

    func connect() async throws {
        guard let device = deviceManager.discoveredDevices.first else {
            throw DeviceError.invalidPeripheral("No discovered devices available")
        }
        try await deviceManager.connect(to: device)
    }

    func disconnect() async {
        if let device = deviceManager.primaryDevice {
            await deviceManager.disconnect(from: device)        }
    }
}

// MARK: - Mock Data Provider

/// Mock data provider for Demo mode and testing
@MainActor
class MockDataProvider: SensorDataProvider {
    // Publishers
    private let sensorReadingsSubject = PassthroughSubject<SensorReading, Never>()
    private let isConnectedSubject = CurrentValueSubject<Bool, Never>(false)
    private let deviceNameSubject = CurrentValueSubject<String, Never>("Oralable Demo")

    var sensorReadingsPublisher: AnyPublisher<SensorReading, Never> {
        sensorReadingsSubject.eraseToAnyPublisher()
    }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        isConnectedSubject.eraseToAnyPublisher()
    }

    var deviceNamePublisher: AnyPublisher<String, Never> {
        deviceNameSubject.eraseToAnyPublisher()
    }

    // Generation state
    private var generationTimer: Timer?
    private var sampleCount: Int = 0

    // Mock data parameters
    private let heartRateRange = 65...85
    private let spo2Range = 95...99
    private let temperatureBase = 36.5
    private let ppgAmplitude = 1000.0
    private let ppgOffset = 2000.0

    // MARK: - Lifecycle

    func startDataStream() {
        Logger.shared.info("[MockDataProvider] Starting mock data generation")
        isConnectedSubject.send(true)
        startGeneration()
    }

    func stopDataStream() {
        Logger.shared.info("[MockDataProvider] Stopping mock data generation")
        generationTimer?.invalidate()
        generationTimer = nil
        isConnectedSubject.send(false)
    }

    func connect() async throws {
        Logger.shared.info("[MockDataProvider] Mock connect")
        try await Task.sleep(nanoseconds: 500_000_000) // Simulate connection delay
        isConnectedSubject.send(true)
        startGeneration()
    }

    func disconnect() async {
        Logger.shared.info("[MockDataProvider] Mock disconnect")
        stopDataStream()
    }

    // MARK: - Mock Data Generation

    private func startGeneration() {
        generationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.generateSensorReadings()
        }
    }

    private func generateSensorReadings() {
        sampleCount += 1
        let timestamp = Date()
        let deviceId = "MOCK-DEVICE-001"

        // Generate PPG data (simulated heartbeat waveform)
        let ppgPhase = Double(sampleCount) * 0.1
        let ppgRed = ppgOffset + ppgAmplitude * sin(ppgPhase) + Double.random(in: -100...100)
        let ppgIR = ppgOffset + ppgAmplitude * sin(ppgPhase + 0.2) + Double.random(in: -100...100)
        let ppgGreen = ppgOffset + ppgAmplitude * sin(ppgPhase - 0.1) + Double.random(in: -100...100)

        emitReading(.ppgRed, value: ppgRed, timestamp: timestamp, deviceId: deviceId, quality: 0.95)
        emitReading(.ppgInfrared, value: ppgIR, timestamp: timestamp, deviceId: deviceId, quality: 0.95)
        emitReading(.ppgGreen, value: ppgGreen, timestamp: timestamp, deviceId: deviceId, quality: 0.95)

        // Generate accelerometer data (simulated movement)
        let accelPhase = Double(sampleCount) * 0.05
        let accelX = 0.05 * sin(accelPhase) + Double.random(in: -0.02...0.02)
        let accelY = 0.03 * cos(accelPhase * 1.5) + Double.random(in: -0.02...0.02)
        let accelZ = 1.0 + 0.02 * sin(accelPhase * 0.8) + Double.random(in: -0.01...0.01)

        emitReading(.accelerometerX, value: accelX, timestamp: timestamp, deviceId: deviceId)
        emitReading(.accelerometerY, value: accelY, timestamp: timestamp, deviceId: deviceId)
        emitReading(.accelerometerZ, value: accelZ, timestamp: timestamp, deviceId: deviceId)

        // Generate computed metrics every 20 samples (~1 second)
        if sampleCount % 20 == 0 {
            let heartRate = Double(heartRateRange.randomElement() ?? 72)
            let spo2 = Double(spo2Range.randomElement() ?? 98)
            let temperature = temperatureBase + Double.random(in: -0.3...0.3)
            let battery = Double.random(in: 75...100)

            emitReading(.heartRate, value: heartRate, timestamp: timestamp, deviceId: deviceId, quality: 0.9)
            emitReading(.spo2, value: spo2, timestamp: timestamp, deviceId: deviceId, quality: 0.88)
            emitReading(.temperature, value: temperature, timestamp: timestamp, deviceId: deviceId)
            emitReading(.battery, value: battery, timestamp: timestamp, deviceId: deviceId)
        }
    }

    private func emitReading(_ sensorType: SensorType, value: Double, timestamp: Date, deviceId: String, quality: Double? = nil) {
        let reading = SensorReading(
            id: UUID(),
            sensorType: sensorType,
            value: value,
            timestamp: timestamp,
            deviceId: deviceId,
            quality: quality
        )
        sensorReadingsSubject.send(reading)
    }

    // MARK: - Cleanup

    deinit {
        generationTimer?.invalidate()
    }
}
