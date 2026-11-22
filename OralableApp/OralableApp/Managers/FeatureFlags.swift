//
//  FeatureFlags.swift
//  OralableApp
//
//  Runtime feature flag management for gradual feature rollout.
//
//  Dashboard Cards:
//  - showEMGCard: EMG activity card
//  - showMovementCard: Accelerometer/movement card
//  - showTemperatureCard: Temperature card
//  - showHeartRateCard: Heart rate card
//  - showSpO2Card: Blood oxygen card
//  - showBatteryCard: Battery level card
//
//  Features:
//  - showSubscription: Subscription UI
//  - showDetectionSettings: Event detection settings
//  - showCloudKitShare: Professional sharing
//  - demoModeEnabled: Virtual device mode
//
//  Persistence: UserDefaults
//  Access: Developer Settings (tap version 7x)
//
//  Created: December 4, 2025
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
        static let devicePlacementMode = "feature.device.placementMode"
        static let enableFirmwareLogNotify = "feature.ble.enableFirmwareLogNotify"
        static let vitalsPhaseEnabled = "feature.pilot.vitalsPhaseEnabled"
        static let debugRebootIntervalMinutes = "feature.pilot.debugRebootIntervalMinutes"
        static let showOvernightHypnogram = "feature.dashboard.showOvernightHypnogram"
        /// v2 key (v1 retired). Default OFF — enable in Developer Settings for research.
        static let showDualProtocolA = "feature.research.showDualProtocolA.v2"
        /// v2: Beacon default OFF (pair → dashboard). v1 defaulted ON and locked clinic loaners behind ~6 min cues.
        static let requireProtocolASetup = "feature.setup.requireProtocolASetup.v2"
    }

    // MARK: - Default Configuration
    // Default dashboard: PPG IR only (pre-launch minimal)
    private enum Defaults {
        // Dashboard Cards - ALL OFF by default for pre-launch (PPG IR always shown)
        static let showEMGCard = false         // Phase 0 / App Store off; research dual-BLE later (ANR_M40_CONCORDANCE)
        static let showHeartRateCard = false   // Hidden by default
        static let showBatteryCard = false     // Hidden by default
        static let showMovementCard = false
        static let showTemperatureCard = false
        static let showSpO2Card = false

        // Share Features
        static let showShareWithProfessional = false
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

        /// Manual placement until chrsts GPIO is repaired (0=auto).
        static let devicePlacementMode: UInt8 = 2

        /// `3A0FF00A` fw-log notify — off by default (can destabilize link on pilot builds).
        static let enableFirmwareLogNotify = false

        /// Phase 0 pilot: HR + SpO2 first; hide Protocol B / muscle calibration.
        static let vitalsPhaseEnabled = true

        /// In-app state hypnogram (FIG-CO-025 adaptation) — Share preview + morning card.
        static let showOvernightHypnogram = true

        /// Bench-only firmware warm reboot interval (minutes). 0 = off.
        static let debugRebootIntervalMinutes: UInt16 = 0

        /// Dual Protocol A (~6 min Mac-parity cues + ANR). OFF — Beacon / vitals stay Oralable-only.
        static let showDualProtocolA = false

        /// Protocol A Setup is optional research QC. Beacon clinic loaner: pair → temple → night.
        static let requireProtocolASetup = false
    }

    /// Explicit device placement for firmware status / `00B` 0x09 (manual override of auto dock).
    enum DevicePlacementMode: UInt8, CaseIterable, Identifiable {
        case auto = 0
        case onCharger = 1
        case offDockIdle = 2
        case worn = 3

        var id: UInt8 { rawValue }

        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .onCharger: return "On MAM case"
            case .offDockIdle: return "Off case (not worn)"
            case .worn: return "Worn on temple"
            }
        }

        var detail: String {
            switch self {
            case .auto:
                return "STAT blink means on the case and charging. Flash green means still below hold (~4.20 V). A brief green pulse about every 10 s means hold. The MAM LED is off while the phone is linked. Status never shows red."
            case .onCharger:
                return "MAM case only. No phone: flash green while below hold (~4.20 V). Brief green pulse ~every 10 s when in hold. Status never shows red. While linked, the MAM LED is off and sensors stay off."
            case .offDockIdle:
                return "On table or off case — status LED stays dark. While linked, the MAM LED is off."
            case .worn:
                return "On temple with pad or tape (no headband). Sensors run while the phone is linked. Red/IR is PPG, not a status light. Use Off case when the MAM is on a table."
            }
        }
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

    @Published var devicePlacementMode: DevicePlacementMode {
        didSet { defaults.set(devicePlacementMode.rawValue, forKey: Keys.devicePlacementMode) }
    }

    /// Enables `3A0FF00A` notify during connect (developer / bench only).
    @Published var enableFirmwareLogNotify: Bool {
        didSet { defaults.set(enableFirmwareLogNotify, forKey: Keys.enableFirmwareLogNotify) }
    }

    /// Phase 0 vitals pilot: HR/SpO2 focus, manual placement, no Protocol B.
    @Published var vitalsPhaseEnabled: Bool {
        didSet {
            defaults.set(vitalsPhaseEnabled, forKey: Keys.vitalsPhaseEnabled)
            if vitalsPhaseEnabled {
                applyVitalsPhaseConfig()
            }
        }
    }

    /// Optional bench firmware reboot (opcode 0x0A). 0 = disabled.
    @Published var debugRebootIntervalMinutes: UInt16 {
        didSet { defaults.set(debugRebootIntervalMinutes, forKey: Keys.debugRebootIntervalMinutes) }
    }

    /// In-app overnight state hypnogram (Share preview + Dashboard morning card).
    @Published var showOvernightHypnogram: Bool {
        didSet { defaults.set(showOvernightHypnogram, forKey: Keys.showOvernightHypnogram) }
    }

    /// Research Dual Protocol A (Oralable + ANR, ~6 min Mac-parity cues). Default OFF.
    @Published var showDualProtocolA: Bool {
        didSet { defaults.set(showDualProtocolA, forKey: Keys.showDualProtocolA) }
    }

    /// When true, pair alone does not unlock MainTab — single-MAM Protocol A Setup must complete.
    @Published var requireProtocolASetup: Bool {
        didSet { defaults.set(requireProtocolASetup, forKey: Keys.requireProtocolASetup) }
    }

    /// Set by Share → Prepare Protocol B session; promotes off-dock → worn on next connect.
    @Published var protocolBSessionPrepared: Bool = false

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
        let modeRaw = defaults.object(forKey: Keys.devicePlacementMode) as? UInt8 ?? Defaults.devicePlacementMode
        self.devicePlacementMode = DevicePlacementMode(rawValue: modeRaw) ?? .offDockIdle
        self.enableFirmwareLogNotify = defaults.object(forKey: Keys.enableFirmwareLogNotify) as? Bool ?? Defaults.enableFirmwareLogNotify
        self.vitalsPhaseEnabled = defaults.object(forKey: Keys.vitalsPhaseEnabled) as? Bool ?? Defaults.vitalsPhaseEnabled
        self.debugRebootIntervalMinutes = defaults.object(forKey: Keys.debugRebootIntervalMinutes) as? UInt16 ?? Defaults.debugRebootIntervalMinutes
        self.showOvernightHypnogram = defaults.object(forKey: Keys.showOvernightHypnogram) as? Bool ?? Defaults.showOvernightHypnogram
        self.showDualProtocolA = defaults.object(forKey: Keys.showDualProtocolA) as? Bool ?? Defaults.showDualProtocolA
        self.requireProtocolASetup = defaults.object(forKey: Keys.requireProtocolASetup) as? Bool ?? Defaults.requireProtocolASetup

        if vitalsPhaseEnabled {
            applyVitalsPhaseConfig()
        }

        Logger.shared.info("[FeatureFlags] Initialized with pre-launch configuration")
    }

    // MARK: - Presets

    /// Phase 0 vitals pilot — HR, SpO₂, battery, device status; no muscle / Protocol B.
    func applyVitalsPhaseConfig() {
        showEMGCard = false
        showMovementCard = false
        showTemperatureCard = false
        showHeartRateCard = true
        showSpO2Card = true
        showBatteryCard = true
        showAdvancedMetrics = false
        showPilotStudy = false
        showDetectionSettings = false
        showOvernightHypnogram = true
        showDualProtocolA = false
        Logger.shared.info("[FeatureFlags] Applied vitals phase config (HR + SpO2, Dual A off)")
    }

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
        showOvernightHypnogram = false
        showDualProtocolA = false

        // Share Features
        showShareWithProfessional = false
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
        showOvernightHypnogram = true
        showDualProtocolA = true
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
        showOvernightHypnogram = true
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
        showOvernightHypnogram = false
        showDualProtocolA = false

        // Share Features
        showShareWithProfessional = false
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
        showOvernightHypnogram = true
        showDualProtocolA = true
        Logger.shared.info("[FeatureFlags] Applied research config")
    }

    /// Reset to defaults
    func resetToDefaults() {
        applyPreLaunchConfig()
        demoModeEnabled = false
        devicePlacementMode = .offDockIdle
        showDualProtocolA = Defaults.showDualProtocolA
        requireProtocolASetup = Defaults.requireProtocolASetup
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
        - Overnight Hypnogram: \(showOvernightHypnogram)
        - Dual Protocol A: \(showDualProtocolA)
        - Require Protocol A Setup: \(requireProtocolASetup)
        """
    }
}
