//
//  SettingsViewModel.swift
//  OralableApp
//
//  ViewModel for settings screen configuration.
//
//  Manages:
//  - Notification preferences (connection, battery alerts)
//  - Data retention settings
//  - Display preferences (units, time format)
//  - Privacy settings (analytics, local storage)
//  - Chart refresh rate
//
//  Persistence:
//  - Settings stored in UserDefaults
//  - Loaded on init, saved on change
//
//  Created: November 7, 2025
//

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    
    // MARK: - Published Properties (Observable by View)

    @Published var notificationsEnabled: Bool = true
    @Published var dataRetentionDays: Int = 30
    @Published var autoConnectEnabled: Bool = true
    @Published var showDebugInfo: Bool = false
    
    // Notification settings
    @Published var connectionAlerts: Bool = true
    @Published var batteryAlerts: Bool = true
    @Published var lowBatteryThreshold: Int = 20
    
    // Display settings
    @Published var useMetricUnits: Bool = true
    @Published var show24HourTime: Bool = true
    @Published var chartRefreshRate: ChartRefreshRate = .realTime
    
    // Privacy settings
    @Published var shareAnalytics: Bool = false
    @Published var localStorageOnly: Bool = true
    
    // UI State
    @Published var showResetConfirmation: Bool = false
    @Published var showClearDataConfirmation: Bool = false
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private weak var sensorDataProcessor: SensorDataProcessor?
    private var cancellables = Set<AnyCancellable>()
    
    // UserDefaults Keys
    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let dataRetentionDays = "dataRetentionDays"
        static let autoConnectEnabled = "autoConnectEnabled"
        static let showDebugInfo = "showDebugInfo"
        static let connectionAlerts = "connectionAlerts"
        static let batteryAlerts = "batteryAlerts"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let useMetricUnits = "useMetricUnits"
        static let show24HourTime = "show24HourTime"
        static let chartRefreshRate = "chartRefreshRate"
        static let shareAnalytics = "shareAnalytics"
        static let localStorageOnly = "localStorageOnly"
    }
    
    // MARK: - Computed Properties
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var versionText: String {
        "Version \(appVersion) (\(buildNumber))"
    }
    
    // MARK: - Initialization

    /// Initialize with injected dependencies
    init(sensorDataProcessor: SensorDataProcessor?) {
        self.sensorDataProcessor = sensorDataProcessor
        loadSettings()
        setupBindings()
    }

    // MARK: - Setup
    
    private func setupBindings() {
        // Save settings when they change
        $notificationsEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.saveSetting(Keys.notificationsEnabled, value: value)
            }
            .store(in: &cancellables)
        
        $dataRetentionDays
            .dropFirst()
            .sink { [weak self] value in
                self?.saveSetting(Keys.dataRetentionDays, value: value)
            }
            .store(in: &cancellables)
        
        $autoConnectEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.saveSetting(Keys.autoConnectEnabled, value: value)
            }
            .store(in: &cancellables)
        
        $showDebugInfo
            .dropFirst()
            .sink { [weak self] value in
                self?.saveSetting(Keys.showDebugInfo, value: value)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Settings Management
    
    func loadSettings() {
        notificationsEnabled = userDefaults.bool(forKey: Keys.notificationsEnabled, defaultValue: true)
        dataRetentionDays = userDefaults.integer(forKey: Keys.dataRetentionDays, defaultValue: 30)
        autoConnectEnabled = userDefaults.bool(forKey: Keys.autoConnectEnabled, defaultValue: true)
        showDebugInfo = userDefaults.bool(forKey: Keys.showDebugInfo, defaultValue: false)
        connectionAlerts = userDefaults.bool(forKey: Keys.connectionAlerts, defaultValue: true)
        batteryAlerts = userDefaults.bool(forKey: Keys.batteryAlerts, defaultValue: true)
        lowBatteryThreshold = userDefaults.integer(forKey: Keys.lowBatteryThreshold, defaultValue: 20)
        useMetricUnits = userDefaults.bool(forKey: Keys.useMetricUnits, defaultValue: true)
        show24HourTime = userDefaults.bool(forKey: Keys.show24HourTime, defaultValue: true)
        shareAnalytics = userDefaults.bool(forKey: Keys.shareAnalytics, defaultValue: false)
        localStorageOnly = userDefaults.bool(forKey: Keys.localStorageOnly, defaultValue: true)
        
        if let rateString = userDefaults.string(forKey: Keys.chartRefreshRate),
           let rate = ChartRefreshRate(rawValue: rateString) {
            chartRefreshRate = rate
        }
    }
    
    func saveSetting(_ key: String, value: Any) {
        userDefaults.set(value, forKey: key)
    }
    
    func resetToDefaults() {
        notificationsEnabled = true
        dataRetentionDays = 30
        autoConnectEnabled = true
        showDebugInfo = false
        connectionAlerts = true
        batteryAlerts = true
        lowBatteryThreshold = 20
        useMetricUnits = true
        show24HourTime = true
        shareAnalytics = false
        localStorageOnly = true
        chartRefreshRate = .realTime
        
        // Remove all saved settings
        let allKeys = [
            Keys.notificationsEnabled, Keys.dataRetentionDays,
            Keys.autoConnectEnabled, Keys.showDebugInfo, Keys.connectionAlerts,
            Keys.batteryAlerts, Keys.lowBatteryThreshold, Keys.useMetricUnits,
            Keys.show24HourTime, Keys.chartRefreshRate, Keys.shareAnalytics,
            Keys.localStorageOnly
        ]
        allKeys.forEach { userDefaults.removeObject(forKey: $0) }
    }
    
    func validateSettings() -> Bool {
        guard dataRetentionDays > 0 && dataRetentionDays <= 365 else { return false }
        guard lowBatteryThreshold > 0 && lowBatteryThreshold <= 100 else { return false }
        return true
    }
    
    // MARK: - Data Management
    
    func clearAllData() {
        sensorDataProcessor?.clearHistory()
    }
    
    func exportSettings() -> [String: Any] {
        return [
            Keys.notificationsEnabled: notificationsEnabled,
            Keys.dataRetentionDays: dataRetentionDays,
            Keys.autoConnectEnabled: autoConnectEnabled,
            Keys.showDebugInfo: showDebugInfo,
            Keys.connectionAlerts: connectionAlerts,
            Keys.batteryAlerts: batteryAlerts,
            Keys.lowBatteryThreshold: lowBatteryThreshold,
            Keys.useMetricUnits: useMetricUnits,
            Keys.show24HourTime: show24HourTime,
            Keys.shareAnalytics: shareAnalytics,
            Keys.localStorageOnly: localStorageOnly,
            Keys.chartRefreshRate: chartRefreshRate.rawValue
        ]
    }
    
    func importSettings(from dictionary: [String: Any]) {
        if let value = dictionary[Keys.notificationsEnabled] as? Bool {
            notificationsEnabled = value
        }
        if let value = dictionary[Keys.dataRetentionDays] as? Int {
            dataRetentionDays = value
        }
        if let value = dictionary[Keys.autoConnectEnabled] as? Bool {
            autoConnectEnabled = value
        }
        if let value = dictionary[Keys.showDebugInfo] as? Bool {
            showDebugInfo = value
        }
        if let value = dictionary[Keys.connectionAlerts] as? Bool {
            connectionAlerts = value
        }
        if let value = dictionary[Keys.batteryAlerts] as? Bool {
            batteryAlerts = value
        }
        if let value = dictionary[Keys.lowBatteryThreshold] as? Int {
            lowBatteryThreshold = value
        }
        if let value = dictionary[Keys.useMetricUnits] as? Bool {
            useMetricUnits = value
        }
        if let value = dictionary[Keys.show24HourTime] as? Bool {
            show24HourTime = value
        }
        if let value = dictionary[Keys.chartRefreshRate] as? String,
           let rate = ChartRefreshRate(rawValue: value) {
            chartRefreshRate = rate
        }
        if let value = dictionary[Keys.shareAnalytics] as? Bool {
            shareAnalytics = value
        }
        if let value = dictionary[Keys.localStorageOnly] as? Bool {
            localStorageOnly = value
        }
    }
}

// MARK: - Supporting Types

enum ChartRefreshRate: String, CaseIterable {
    case realTime = "Real-time"
    case everySecond = "Every Second"
    case everyFiveSeconds = "Every 5 Seconds"
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
    
    func integer(forKey key: String, defaultValue: Int) -> Int {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return integer(forKey: key)
    }
}

// MARK: - Mock for Previews

extension SettingsViewModel {
    static func mock() -> SettingsViewModel {
        // FIX: SensorDataProcessor requires a BioMetricCalculator
        let calculator = BioMetricCalculator()
        let processor = SensorDataProcessor(calculator: calculator)
        return SettingsViewModel(sensorDataProcessor: processor)
    }
}
