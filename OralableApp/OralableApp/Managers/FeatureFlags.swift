//
//  FeatureFlags.swift
//  OralableApp
//
//  Created: December 4, 2025
//  Purpose: Feature flags for controlling app functionality
//  Pre-launch release hides advanced features for simpler App Store approval
//

import Foundation
import Combine

/// Feature flags for controlling app functionality
/// Pre-launch release hides advanced features for simpler App Store approval
class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let showEMGCard = "feature.dashboard.showEMG"
        static let showMovementCard = "feature.dashboard.showMovement"
        static let showTemperatureCard = "feature.dashboard.showTemperature"
        static let showHeartRateCard = "feature.dashboard.showHeartRate"
        static let showSpO2Card = "feature.dashboard.showSpO2"
        static let showBatteryCard = "feature.dashboard.showBattery"
        static let showShareWithProfessional = "feature.share.showProfessional"
        static let showShareWithResearcher = "feature.share.showResearcher"
        static let showSubscription = "feature.settings.showSubscription"
        static let showAdvancedMetrics = "feature.dashboard.showAdvancedMetrics"
        static let showDetectionSettings = "feature.settings.showDetectionSettings"
        static let showCloudKitShare = "feature.share.showCloudKitShare"
        static let demoModeEnabled = "feature.demo.enabled"
        static let showPilotStudy = "feature.pilot.showStudy"
    }

    // MARK: - Default Configuration
    // Default dashboard: PPG IR only (pre-launch minimal)
    private enum Defaults {
        // Dashboard Cards - ALL OFF by default for pre-launch (PPG IR always shown)
        static let showEMGCard = false         // Hidden by default
        static let showHeartRateCard = false   // Hidden by default
        static let showBatteryCard = false     // Hidden by default
        static let showMovementCard = false
        static let showTemperatureCard = false
        static let showSpO2Card = false

        // Share Features
        static let showShareWithProfessional = true
        static let showShareWithResearcher = false

        // Settings Features
        static let showSubscription = false  // Hidden by default for pre-launch
        static let showAdvancedMetrics = false
        static let showDetectionSettings = false
        static let showCloudKitShare = false

        // Demo Mode
        static let demoModeEnabled = false

        // Pilot Study
        static let showPilotStudy = false
    }

    // MARK: - Dashboard Features
    @Published var showEMGCard: Bool {
        didSet { defaults.set(showEMGCard, forKey: Keys.showEMGCard) }
    }

    @Published var showMovementCard: Bool {
        didSet { defaults.set(showMovementCard, forKey: Keys.showMovementCard) }
    }

    @Published var showTemperatureCard: Bool {
        didSet { defaults.set(showTemperatureCard, forKey: Keys.showTemperatureCard) }
    }

    @Published var showHeartRateCard: Bool {
        didSet { defaults.set(showHeartRateCard, forKey: Keys.showHeartRateCard) }
    }

    @Published var showSpO2Card: Bool {
        didSet { defaults.set(showSpO2Card, forKey: Keys.showSpO2Card) }
    }

    @Published var showBatteryCard: Bool {
        didSet { defaults.set(showBatteryCard, forKey: Keys.showBatteryCard) }
    }

    @Published var showAdvancedMetrics: Bool {
        didSet { defaults.set(showAdvancedMetrics, forKey: Keys.showAdvancedMetrics) }
    }

    // MARK: - Share Features
    @Published var showShareWithProfessional: Bool {
        didSet { defaults.set(showShareWithProfessional, forKey: Keys.showShareWithProfessional) }
    }

    @Published var showShareWithResearcher: Bool {
        didSet { defaults.set(showShareWithResearcher, forKey: Keys.showShareWithResearcher) }
    }

    // MARK: - Settings Features
    @Published var showSubscription: Bool {
        didSet { defaults.set(showSubscription, forKey: Keys.showSubscription) }
    }

    @Published var showDetectionSettings: Bool {
        didSet { defaults.set(showDetectionSettings, forKey: Keys.showDetectionSettings) }
    }

    @Published var showCloudKitShare: Bool {
        didSet { defaults.set(showCloudKitShare, forKey: Keys.showCloudKitShare) }
    }

    // MARK: - Demo Mode
    @Published var demoModeEnabled: Bool {
        didSet { defaults.set(demoModeEnabled, forKey: Keys.demoModeEnabled) }
    }

    // MARK: - Pilot Study
    @Published var showPilotStudy: Bool {
        didSet { defaults.set(showPilotStudy, forKey: Keys.showPilotStudy) }
    }

    // MARK: - Post-Launch Features (v1.1)
    // TODO: Enable these when implementations are complete

    /// Whether to show PDF export option (not yet implemented)
    @Published var showPDFExport: Bool = false

    // MARK: - Initialization
    init() {
        // Load saved values or use pre-launch defaults
        self.showEMGCard = defaults.object(forKey: Keys.showEMGCard) as? Bool ?? Defaults.showEMGCard
        self.showMovementCard = defaults.object(forKey: Keys.showMovementCard) as? Bool ?? Defaults.showMovementCard
        self.showTemperatureCard = defaults.object(forKey: Keys.showTemperatureCard) as? Bool ?? Defaults.showTemperatureCard
        self.showHeartRateCard = defaults.object(forKey: Keys.showHeartRateCard) as? Bool ?? Defaults.showHeartRateCard
        self.showSpO2Card = defaults.object(forKey: Keys.showSpO2Card) as? Bool ?? Defaults.showSpO2Card
        self.showBatteryCard = defaults.object(forKey: Keys.showBatteryCard) as? Bool ?? Defaults.showBatteryCard
        self.showAdvancedMetrics = defaults.object(forKey: Keys.showAdvancedMetrics) as? Bool ?? Defaults.showAdvancedMetrics
        self.showShareWithProfessional = defaults.object(forKey: Keys.showShareWithProfessional) as? Bool ?? Defaults.showShareWithProfessional
        self.showShareWithResearcher = defaults.object(forKey: Keys.showShareWithResearcher) as? Bool ?? Defaults.showShareWithResearcher
        self.showSubscription = defaults.object(forKey: Keys.showSubscription) as? Bool ?? Defaults.showSubscription
        self.showDetectionSettings = defaults.object(forKey: Keys.showDetectionSettings) as? Bool ?? Defaults.showDetectionSettings
        self.showCloudKitShare = defaults.object(forKey: Keys.showCloudKitShare) as? Bool ?? Defaults.showCloudKitShare
        self.demoModeEnabled = defaults.object(forKey: Keys.demoModeEnabled) as? Bool ?? Defaults.demoModeEnabled
        self.showPilotStudy = defaults.object(forKey: Keys.showPilotStudy) as? Bool ?? Defaults.showPilotStudy

        Logger.shared.info("[FeatureFlags] Initialized with pre-launch configuration")
    }

    // MARK: - Presets

    /// Pre-launch configuration (PPG IR only)
    func applyPreLaunchConfig() {
        // Dashboard Cards - PPG IR only (always shown)
        showEMGCard = false
        showHeartRateCard = false
        showBatteryCard = false
        showMovementCard = false
        showTemperatureCard = false
        showSpO2Card = false
        showAdvancedMetrics = false

        // Share Features
        showShareWithProfessional = true
        showShareWithResearcher = false
        showCloudKitShare = false

        // Settings Features
        showSubscription = false  // Hidden for pre-launch
        showDetectionSettings = false
        Logger.shared.info("[FeatureFlags] Applied pre-launch config (PPG IR only)")
    }

    /// Full feature configuration (all features enabled)
    func applyFullConfig() {
        showEMGCard = true
        showMovementCard = true
        showTemperatureCard = true
        showHeartRateCard = true
        showSpO2Card = true
        showBatteryCard = true
        showAdvancedMetrics = true
        showShareWithProfessional = true
        showShareWithResearcher = true
        showSubscription = true
        showDetectionSettings = true
        showCloudKitShare = true
        Logger.shared.info("[FeatureFlags] Applied full config")
    }

    /// Wellness release configuration (consumer features)
    func applyWellnessConfig() {
        showEMGCard = true
        showMovementCard = true
        showTemperatureCard = true
        showHeartRateCard = false
        showSpO2Card = false
        showBatteryCard = true
        showAdvancedMetrics = true
        showShareWithProfessional = true
        showShareWithResearcher = false
        showSubscription = true
        showDetectionSettings = true
        showCloudKitShare = true
        Logger.shared.info("[FeatureFlags] Applied wellness config")
    }

    /// App Store Minimal - PPG IR only, CSV export, no CloudKit
    func applyAppStoreMinimalConfig() {
        // Dashboard Cards - ALL OFF except PPG IR (which is always shown)
        showEMGCard = false
        showMovementCard = false
        showTemperatureCard = false
        showHeartRateCard = false
        showSpO2Card = false
        showBatteryCard = false
        showAdvancedMetrics = false

        // Share Features
        showShareWithProfessional = true
        showShareWithResearcher = false
        showCloudKitShare = false

        // Settings Features
        showSubscription = false  // Hidden for App Store submission
        showDetectionSettings = false
        Logger.shared.info("[FeatureFlags] Applied App Store Minimal config (PPG IR only, CSV export)")
    }

    /// Research release configuration
    func applyResearchConfig() {
        showEMGCard = true
        showMovementCard = true
        showTemperatureCard = true
        showHeartRateCard = true
        showSpO2Card = true
        showBatteryCard = true
        showAdvancedMetrics = true
        showShareWithProfessional = true
        showShareWithResearcher = true
        showSubscription = true
        showDetectionSettings = true
        showCloudKitShare = true
        Logger.shared.info("[FeatureFlags] Applied research config")
    }

    /// Reset to defaults
    func resetToDefaults() {
        applyPreLaunchConfig()
        demoModeEnabled = false
    }

    // MARK: - Debug Description
    var currentConfigDescription: String {
        """
        FeatureFlags Configuration:
        - EMG Card: \(showEMGCard)
        - Movement Card: \(showMovementCard)
        - Temperature Card: \(showTemperatureCard)
        - Heart Rate Card: \(showHeartRateCard)
        - SpO2 Card: \(showSpO2Card)
        - Battery Card: \(showBatteryCard)
        - Advanced Metrics: \(showAdvancedMetrics)
        - Share with Professional: \(showShareWithProfessional)
        - Share with Researcher: \(showShareWithResearcher)
        - Subscription: \(showSubscription)
        - Detection Settings: \(showDetectionSettings)
        - CloudKit Share: \(showCloudKitShare)
        - Demo Mode: \(demoModeEnabled)
        - Pilot Study: \(showPilotStudy)
        """
    }
}
