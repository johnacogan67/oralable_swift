//
//  DemoDataProvider.swift
//  OralableApp
//
//  Provides simulated sensor data for demo mode.
//
//  Purpose:
//  Allows app testing and demonstration without physical hardware.
//
//  Simulates:
//  - PPG IR values with realistic muscle activity patterns
//  - Accelerometer data with movement variation
//  - Temperature readings in skin contact range
//  - Heart rate and SpO2 calculations
//
//  States:
//  - isDiscovered: Demo device visible in scan results
//  - isConnected: Demo device "connected" and streaming
//
//  Data Source:
//  - Generated algorithmically (DemoDataGenerator)
//  - Or loaded from bundled CSV files
//
//  Access: Enable via Developer Settings (tap version 7x)
//

import Foundation
import Combine

class DemoDataProvider: ObservableObject {
    static let shared = DemoDataProvider()

    // MARK: - Published State (for device simulation)
    @Published var isConnected: Bool = false
    @Published var isDiscovered: Bool = false
    @Published var isPlaying: Bool = false

    // MARK: - Current Values (published for UI binding)
    @Published var currentPPGIR: Double = 0
    @Published var currentPPGRed: Double = 0
    @Published var currentPPGGreen: Double = 0

    // MARK: - Device Info
    let deviceName: String = "Oralable"
    let deviceID: String = "DEMO-ORALABLE-001"

    // Backward compatibility
    var demoDeviceName: String { deviceName }
    var demoDeviceID: String { deviceID }

    // MARK: - Private Properties
    private var csvRows: [[String]] = []
    private var currentIndex: Int = 0
    private var timer: Timer?

    // CSV column indices (Timestamp,Device_Type,EMG,PPG_IR,PPG_Red,PPG_Green)
    private let ppgIRIndex = 3
    private let ppgRedIndex = 4
    private let ppgGreenIndex = 5

    // Callback to inject data into real pipeline
    var onDataPoint: ((Double, Double, Double) -> Void)?

    // MARK: - Initialization
    private init() {
        loadCSV()
        setupDataInjection()
    }

    // MARK: - Load CSV
    private func loadCSV() {
        // Try the new CSV file first
        guard let url = Bundle.main.url(forResource: "oralable_data_001333.e_1765745675", withExtension: "csv") else {
            Logger.shared.error("[DemoDataProvider] CSV file not found in bundle - trying fallback name")
            // Try fallback name
            if let fallbackURL = Bundle.main.url(forResource: "oralable_demo_data", withExtension: "csv") {
                loadCSVFromURL(fallbackURL)
            } else {
                Logger.shared.error("[DemoDataProvider] No demo CSV file found - generating fallback data")
                generateFallbackData()
            }
            return
        }

        loadCSVFromURL(url)
    }

    private func loadCSVFromURL(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            // Skip header, parse data rows
            for i in 1..<lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                let columns = line.components(separatedBy: ",")
                guard columns.count >= 6 else { continue }
                csvRows.append(columns)
            }

            Logger.shared.info("[DemoDataProvider] Loaded \(csvRows.count) rows from CSV")
        } catch {
            Logger.shared.error("[DemoDataProvider] Failed to load CSV: \(error)")
            generateFallbackData()
        }
    }

    // MARK: - Fallback Data Generation
    private func generateFallbackData() {
        Logger.shared.info("[DemoDataProvider] Generating fallback demo data (10000 samples)")
        csvRows.removeAll()

        // Generate 10000 samples of simple sine wave pattern
        for i in 0..<10000 {
            let t = Double(i) / 1200.0  // 1200Hz
            let ppgIR = 50000 + 10000 * sin(t * 2.0 * .pi) + Double.random(in: -500...500)
            let ppgRed = ppgIR * 0.7 + Double.random(in: -200...200)
            let ppgGreen = ppgIR * 0.5 + Double.random(in: -100...100)

            // Format: Timestamp,Device_Type,EMG,PPG_IR,PPG_Red,PPG_Green
            let row = [
                "2025-01-01T00:00:00Z",
                "Oralable",
                "0",
                String(Int(ppgIR)),
                String(Int(ppgRed)),
                String(Int(ppgGreen))
            ]
            csvRows.append(row)
        }
    }

    // MARK: - Setup Data Injection
    private func setupDataInjection() {
        // Wire the callback to inject data into SensorDataProcessor
        onDataPoint = { [weak self] ir, red, green in
            guard let self = self, self.isConnected else { return }

            // Inject into SensorDataProcessor (runs on MainActor)
            Task { @MainActor in
                SensorDataProcessor.shared.injectDemoReading(ir: ir, red: red, green: green)
            }
        }
    }

    // MARK: - Discovery Simulation

    /// Call this when user taps Scan in Devices view (if demo mode enabled)
    func simulateDiscovery() {
        guard FeatureFlags.shared.demoModeEnabled else { return }
        guard !isDiscovered else { return }

        // Simulate scan delay (0.5-1 second)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.isDiscovered = true
            Logger.shared.info("[DemoDataProvider] Demo device discovered")
        }
    }

    /// Reset discovery state (when scan stops or demo mode disabled)
    func resetDiscovery() {
        isDiscovered = false
    }

    // MARK: - Connection Simulation

    /// Call this when user taps Connect on demo device
    func simulateConnect() {
        guard FeatureFlags.shared.demoModeEnabled else { return }
        guard isDiscovered else {
            Logger.shared.warning("[DemoDataProvider] Cannot connect - device not discovered")
            return
        }

        Logger.shared.info("[DemoDataProvider] Connecting to demo device...")

        // Simulate connection delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            self.startPlayback()
            Logger.shared.info("[DemoDataProvider] Demo device connected")
        }
    }

    /// Disconnect demo device
    func disconnect() {
        stopPlayback()
        isConnected = false
        Logger.shared.info("[DemoDataProvider] Demo device disconnected")
    }

    // MARK: - Data Playback

    func startPlayback() {
        guard !isPlaying else { return }
        guard !csvRows.isEmpty else {
            Logger.shared.error("[DemoDataProvider] No CSV data to play")
            return
        }

        isPlaying = true
        currentIndex = 0

        // 1200Hz = 0.000833 second interval
        timer = Timer.scheduledTimer(withTimeInterval: 0.000833, repeats: true) { [weak self] _ in
            self?.emitNextDataPoint()
        }

        // Ensure timer fires during UI interactions
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        Logger.shared.info("[DemoDataProvider] Started data playback at 1200Hz with \(csvRows.count) samples")
    }

    func stopPlayback() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        currentIndex = 0
        Logger.shared.info("[DemoDataProvider] Stopped data playback")
    }

    private func emitNextDataPoint() {
        // Loop when reaching end
        if currentIndex >= csvRows.count {
            currentIndex = 0
            Logger.shared.debug("[DemoDataProvider] Looping demo data")
        }

        let row = csvRows[currentIndex]
        currentIndex += 1

        // Parse PPG values
        let ppgIR = Double(row[ppgIRIndex]) ?? 0
        let ppgRed = Double(row[ppgRedIndex]) ?? 0
        let ppgGreen = Double(row[ppgGreenIndex]) ?? 0

        // Update published values (for direct UI binding if needed)
        DispatchQueue.main.async { [weak self] in
            self?.currentPPGIR = ppgIR
            self?.currentPPGRed = ppgRed
            self?.currentPPGGreen = ppgGreen
        }

        // Call injection callback (to feed into real pipeline)
        onDataPoint?(ppgIR, ppgRed, ppgGreen)
    }

    // MARK: - Backward Compatibility Properties

    /// Accelerometer (static values since CSV doesn't have this)
    @Published var currentAccelX: Double = 0
    @Published var currentAccelY: Double = 0
    @Published var currentAccelZ: Double = 16384  // ~1g in Z axis (at rest)

    /// Temperature (static value)
    @Published var currentTemperature: Double = 36.5

    /// Heart rate (static value)
    @Published var currentHeartRate: Int = 70

    /// SpO2 (static value)
    @Published var currentSpO2: Double = 98.0

    /// Battery (static value)
    @Published var currentBattery: Int = 85

    /// Legacy PPG value
    var currentPPGValue: Double { currentPPGIR }

    // MARK: - Data Duration
    var totalDuration: TimeInterval {
        // 10000 samples at 1200Hz = ~8.3 seconds
        return Double(csvRows.count) / 1200.0
    }
}
