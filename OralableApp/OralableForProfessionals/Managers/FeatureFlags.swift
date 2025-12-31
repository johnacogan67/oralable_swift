//
//  FeatureFlags.swift
//  OralableForProfessionals
//
//  Created: December 5, 2025
//  Purpose: Feature flags for controlling app functionality
//  Pre-launch release hides advanced features for simpler App Store approval
//

import Foundation
import Combine
import OralableCore

// MARK: - Notification Names
extension Notification.Name {
    static let demoModeChanged = Notification.Name("demoModeChanged")
}

/// Feature flags for controlling OralableForProfessionals functionality
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
        static let showAdvancedAnalytics = "feature.dashboard.showAdvancedAnalytics"
        static let showSubscription = "feature.settings.showSubscription"
        static let showMultiParticipant = "feature.showMultiParticipant"
        static let showDataExport = "feature.showDataExport"
        static let showANRComparison = "feature.showANRComparison"
        static let showCloudKitShare = "feature.share.showCloudKitShare"
        static let demoModeEnabled = "feature.demo.enabled"
    }

    // MARK: - Pre-Launch Defaults (all advanced features OFF)
    private enum Defaults {
        static let showEMGCard = false
        static let showMovementCard = false
        static let showTemperatureCard = false
        static let showHeartRateCard = false
        static let showAdvancedAnalytics = false
        static let showSubscription = false  // Hidden by default for pre-launch
        static let showMultiParticipant = true  // Basic participant list always on
        static let showDataExport = true        // Basic export always on
        static let showANRComparison = false
        static let showCloudKitShare = false
        static let demoModeEnabled = false
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

    @Published var showAdvancedAnalytics: Bool {
        didSet { defaults.set(showAdvancedAnalytics, forKey: Keys.showAdvancedAnalytics) }
    }

    // MARK: - Settings Features
    @Published var showSubscription: Bool {
        didSet { defaults.set(showSubscription, forKey: Keys.showSubscription) }
    }

    // MARK: - Research Features
    @Published var showMultiParticipant: Bool {
        didSet { defaults.set(showMultiParticipant, forKey: Keys.showMultiParticipant) }
    }

    @Published var showDataExport: Bool {
        didSet { defaults.set(showDataExport, forKey: Keys.showDataExport) }
    }

    @Published var showANRComparison: Bool {
        didSet { defaults.set(showANRComparison, forKey: Keys.showANRComparison) }
    }

    @Published var showCloudKitShare: Bool {
        didSet { defaults.set(showCloudKitShare, forKey: Keys.showCloudKitShare) }
    }

    // MARK: - Demo Mode
    @Published var demoModeEnabled: Bool {
        didSet {
            defaults.set(demoModeEnabled, forKey: Keys.demoModeEnabled)
            // DemoDataManager is loaded/cleared in response to this flag change
            // The manager observes this flag or is called from views
            NotificationCenter.default.post(
                name: .demoModeChanged,
                object: nil,
                userInfo: ["enabled": demoModeEnabled]
            )
        }
    }

    // MARK: - Initialization
    init() {
        self.showEMGCard = defaults.object(forKey: Keys.showEMGCard) as? Bool ?? Defaults.showEMGCard
        self.showMovementCard = defaults.object(forKey: Keys.showMovementCard) as? Bool ?? Defaults.showMovementCard
        self.showTemperatureCard = defaults.object(forKey: Keys.showTemperatureCard) as? Bool ?? Defaults.showTemperatureCard
        self.showHeartRateCard = defaults.object(forKey: Keys.showHeartRateCard) as? Bool ?? Defaults.showHeartRateCard
        self.showAdvancedAnalytics = defaults.object(forKey: Keys.showAdvancedAnalytics) as? Bool ?? Defaults.showAdvancedAnalytics
        self.showSubscription = defaults.object(forKey: Keys.showSubscription) as? Bool ?? Defaults.showSubscription
        self.showMultiParticipant = defaults.object(forKey: Keys.showMultiParticipant) as? Bool ?? Defaults.showMultiParticipant
        self.showDataExport = defaults.object(forKey: Keys.showDataExport) as? Bool ?? Defaults.showDataExport
        self.showANRComparison = defaults.object(forKey: Keys.showANRComparison) as? Bool ?? Defaults.showANRComparison
        self.showCloudKitShare = defaults.object(forKey: Keys.showCloudKitShare) as? Bool ?? Defaults.showCloudKitShare
        self.demoModeEnabled = defaults.object(forKey: Keys.demoModeEnabled) as? Bool ?? Defaults.demoModeEnabled

        Logger.shared.info("[FeatureFlags] Initialized with pre-launch configuration")
    }

    // MARK: - Presets

    /// Pre-launch configuration (minimal features for App Store approval)
    func applyPreLaunchConfig() {
        showEMGCard = false
        showMovementCard = false
        showTemperatureCard = false
        showHeartRateCard = false
        showAdvancedAnalytics = false
        showSubscription = false  // Hidden for pre-launch
        showMultiParticipant = true
        showDataExport = true
        showANRComparison = false
        showCloudKitShare = false
        Logger.shared.info("[FeatureFlags] Applied pre-launch config")
    }

    /// Wellness release configuration (consumer features)
    func applyWellnessConfig() {
        showEMGCard = true
        showMovementCard = true
        showTemperatureCard = true
        showHeartRateCard = false
        showAdvancedAnalytics = true
        showSubscription = true
        showMultiParticipant = true
        showDataExport = true
        showANRComparison = false
        showCloudKitShare = true
        Logger.shared.info("[FeatureFlags] Applied wellness config")
    }

    /// Research release configuration
    func applyResearchConfig() {
        showEMGCard = true
        showMovementCard = true
        showTemperatureCard = true
        showHeartRateCard = true
        showAdvancedAnalytics = true
        showSubscription = true
        showMultiParticipant = true
        showDataExport = true
        showANRComparison = true
        showCloudKitShare = true
        Logger.shared.info("[FeatureFlags] Applied research config")
    }

    /// Full feature configuration
    func applyFullConfig() {
        showEMGCard = true
        showMovementCard = true
        showTemperatureCard = true
        showHeartRateCard = true
        showAdvancedAnalytics = true
        showSubscription = true
        showMultiParticipant = true
        showDataExport = true
        showANRComparison = true
        showCloudKitShare = true
        Logger.shared.info("[FeatureFlags] Applied full config")
    }

    /// App Store Minimal - PPG IR only, CSV export, no CloudKit
    func applyAppStoreMinimalConfig() {
        showEMGCard = false
        showMovementCard = false
        showTemperatureCard = false
        showHeartRateCard = false
        showAdvancedAnalytics = false
        showSubscription = false  // Hidden for App Store submission
        showMultiParticipant = true
        showDataExport = true
        showANRComparison = false
        showCloudKitShare = false
        Logger.shared.info("[FeatureFlags] Applied App Store Minimal config (PPG IR only, CSV export)")
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
        - Advanced Analytics: \(showAdvancedAnalytics)
        - Subscription: \(showSubscription)
        - Multi-Participant: \(showMultiParticipant)
        - Data Export: \(showDataExport)
        - ANR Comparison: \(showANRComparison)
        - CloudKit Share: \(showCloudKitShare)
        - Demo Mode: \(demoModeEnabled)
        """
    }
}
