//
//  TemporalisFitGuideView.swift
//  OralableApp
//
//  Face ID / Vision Pro–inspired mirror fit: front camera preview, temple reticle,
//  and IR-DC-derived placement gate before the 10-minute calibration wizard.
//

import AVFoundation
import SwiftUI

struct TemporalisFitGuideView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor
    @EnvironmentObject var firstLaunchManager: FirstLaunchManager

    let onExit: () -> Void
    /// Called only after the 10-minute calibration saves baseline (not on Cancel).
    var onCalibrationSucceeded: (() -> Void)?
    /// Called when the user starts the 10-minute IR-DC calibration wizard (setup step 3).
    var onBeginCalibration: (() -> Void)?

    init(
        onExit: @escaping () -> Void,
        onCalibrationSucceeded: (() -> Void)? = nil,
        onBeginCalibration: (() -> Void)? = nil
    ) {
        self.onExit = onExit
        self.onCalibrationSucceeded = onCalibrationSucceeded
        self.onBeginCalibration = onBeginCalibration
    }

    @StateObject private var camera = FrontMirrorCaptureSession()
    @State private var cameraAuthorized = false
    @State private var cameraDenied = false

    @State private var placementState: TemporalisIRDCPlacementState = .noSignal
    @State private var estimatedVolts: Double = 0
    @State private var goodVoltageSamples: [Double] = []
    @State private var stableGoodSince: Date?
    /// After `minGoodSamples` in-band, use relaxed light-leak ceiling instead of 2.8 V (clench hysteresis).
    @State private var allowRelaxedLightLeakThreshold = false
    /// Require this long over threshold before showing red leak UI (sensor settle time).
    @State private var lightLeakPendingSince: Date?
    @State private var lastNonLeakDisplayState: TemporalisIRDCPlacementState = .noSignal
    @State private var showCalibrationWizard = false
    @State private var showSetupSuccess = false
    /// Set when `CalibrationWizardView` saves calibration; cleared when presenting `SetupSuccessView`.
    @State private var calibrationEndedSuccessfully = false
    @State private var lockedBaselineVoltage: Double = 0
    @State private var isResearchOverrideActive = false
    @State private var showResearchOverridePrompt = false
    @State private var manualOverrideForCurrentCalibration = false

    private let stableHoldSeconds: TimeInterval = 3
    private let lightLeakConfirmDelay: TimeInterval = 0.75
    private let minGoodSamples = 8
    private let maxGoodSamples = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { _ in
                    ZStack {
                        if cameraAuthorized {
                            FrontMirrorCameraPreview(session: camera.session)
                                .clipShape(RoundedRectangle(cornerRadius: designSystem.cornerRadius.card))
                                .overlay {
                                    GeometryReader { g in
                                        ZStack {
                                            templeReticle(in: g.size)
                                            Color.clear
                                                .contentShape(Rectangle())
                                                .onLongPressGesture(minimumDuration: 2) {
                                                    showResearchOverridePrompt = true
                                                }
                                        }
                                    }
                                }
                        } else {
                            cameraPermissionPlaceholder
                        }
                    }
                    .padding(.horizontal, designSystem.spacing.md)
                }
                .frame(height: 420)

                VStack(spacing: designSystem.spacing.md) {
                    instructionPanel
                    placementRow
                    if placementState == .lightLeak {
                        lightLeakBanner
                    }
                    if shouldShowPlacementBypass && !canAdvanceToCalibration && !isResearchOverrideActive {
                        placementBypassPanel
                    }
                    if canStartCalibration {
                        Button {
                            startCalibrationWizard()
                        } label: {
                            Text(startCalibrationButtonTitle)
                                .font(designSystem.typography.labelMedium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isResearchOverrideActive && !canAdvanceToCalibration ? designSystem.colors.warning : designSystem.colors.primaryBlack)
                                .foregroundColor(isResearchOverrideActive && !canAdvanceToCalibration ? designSystem.colors.primaryBlack : designSystem.colors.primaryWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.horizontal, designSystem.spacing.md)
                    }
                }
                .padding(.bottom, designSystem.spacing.lg)

                Spacer(minLength: 0)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Temporalis fit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        camera.stop()
                        onExit()
                    }
                }
            }
            .alert("Research override", isPresented: $showResearchOverridePrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Yes") {
                    isResearchOverrideActive = true
                }
            } message: {
                Text("Enter Research Override? This will bypass voltage safety gates.")
            }
        }
        .onAppear {
            requestCameraIfNeeded()
            camera.start()
            syncPlacement(from: deviceManagerAdapter.ppgIRValue)
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(deviceManagerAdapter.$ppgIRValue) { ir in
            syncPlacement(from: ir)
        }
        .fullScreenCover(isPresented: $showCalibrationWizard) {
            CalibrationWizardView(
                lockedBaselineVoltage: lockedBaselineVoltage,
                isManualPlacementOverride: manualOverrideForCurrentCalibration,
                onSuccessfulCalibration: {
                    calibrationEndedSuccessfully = true
                },
                onFinished: {
                    showCalibrationWizard = false
                    camera.stop()
                    if calibrationEndedSuccessfully {
                        calibrationEndedSuccessfully = false
                        showSetupSuccess = true
                    } else {
                        onExit()
                    }
                }
            )
            .environmentObject(designSystem)
            .environmentObject(sessionHistoryStore)
            .environmentObject(deviceManager)
            .environmentObject(sensorDataProcessor)
        }
        .fullScreenCover(isPresented: $showSetupSuccess) {
            SetupSuccessView {
                showSetupSuccess = false
                onCalibrationSucceeded?()
                onExit()
            }
            .environmentObject(designSystem)
        }
    }

    private var cameraPermissionPlaceholder: some View {
        VStack(spacing: designSystem.spacing.md) {
            Image(systemName: cameraDenied ? "camera.fill.badge.xmark" : "camera.fill")
                .font(.system(size: 44))
                .foregroundColor(designSystem.colors.textSecondary)
            Text(cameraDenied ? "Camera access is required for the mirror fit guide." : "Requesting camera…")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, designSystem.spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func templeReticle(in size: CGSize) -> some View {
        let diameter = min(size.width, size.height) * 0.24
        let centerX = size.width * 0.72
        let centerY = size.height * 0.38
        return ZStack {
            Circle()
                .stroke(reticleColor.opacity(0.95), lineWidth: 3)
                .frame(width: diameter, height: diameter)
                .position(x: centerX, y: centerY)
            Circle()
                .stroke(reticleColor.opacity(0.35), lineWidth: 1)
                .frame(width: diameter + 18, height: diameter + 18)
                .position(x: centerX, y: centerY)
        }
        .allowsHitTesting(false)
    }

    private var reticleColor: Color {
        switch placementState {
        case .good: return designSystem.colors.success
        case .lightLeak: return designSystem.colors.error
        case .tooLow, .noSignal: return designSystem.colors.textSecondary
        }
    }

    private var instructionPanel: some View {
        VStack(spacing: 8) {
            Text("Place sensor over the temple bulge and clench your teeth.")
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, designSystem.spacing.lg)
            Text("Ensure the headband is tight. The sensor must remain flush with the temple bulge even during a strong clench.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, designSystem.spacing.lg)
            Text("Use the mirror to align the headband. Relax, then gently clench to confirm coupling.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, designSystem.spacing.lg)
        }
        .padding(.vertical, designSystem.spacing.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var placementRow: some View {
        HStack(spacing: designSystem.spacing.md) {
            Circle()
                .fill(placementIndicatorColor)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(placementTitle)
                    .font(designSystem.typography.labelMedium)
                    .foregroundColor(designSystem.colors.textPrimary)
                Text(String(format: "IR-DC estimate: %.2f V (target 1.5–2.5 V)", estimatedVolts))
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            Spacer()
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.card)
        .padding(.horizontal, designSystem.spacing.md)
        .onLongPressGesture(minimumDuration: 2) {
            showResearchOverridePrompt = true
        }
    }

    private var lightLeakBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .foregroundColor(designSystem.colors.warning)
            Text("Placement gate (audit only): IR-DC reads high versus our nominal dark-coupling band—often firmware ambient / coupling scaling, not necessarily a real leak. You can still proceed with the bypass below; raw ambient IR counts are logged in CSV (ambient_ir_raw).")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textPrimary)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.warning.opacity(0.15))
        .cornerRadius(designSystem.cornerRadius.button)
        .padding(.horizontal, designSystem.spacing.md)
    }

    private var placementTitle: String {
        switch placementState {
        case .noSignal:
            return "Waiting for REV10 IR signal…"
        case .tooLow:
            if estimatedVolts > TemporalisIRDCVoltageEstimator.placementGoodUpperVolts {
                return "Placement error — IR-DC above target band"
            }
            return "Adjust placement — signal low"
        case .good:
            return "Placement OK — hold steady"
        case .lightLeak:
            return "Placement error — high IR / ambient"
        }
    }

    private var placementIndicatorColor: Color {
        switch placementState {
        case .good: return designSystem.colors.success
        case .lightLeak: return designSystem.colors.error
        case .tooLow, .noSignal: return designSystem.colors.gray400
        }
    }

    private var canAdvanceToCalibration: Bool {
        guard rev10PrimaryConnected else { return false }
        guard let start = stableGoodSince else { return false }
        return Date().timeIntervalSince(start) >= stableHoldSeconds && goodVoltageSamples.count >= minGoodSamples
    }

    private var canStartCalibration: Bool {
        if canAdvanceToCalibration { return true }
        if isResearchOverrideActive, deviceManagerAdapter.isConnected { return true }
        return false
    }

    private var startCalibrationButtonTitle: String {
        if isResearchOverrideActive && !canAdvanceToCalibration {
            return "Start 10-minute calibration (research override)"
        }
        return "Signal locked — start 10-minute calibration"
    }

    /// Elevated IR (above good window) or confirmed leak UI — user may bypass to 10-minute lock for research captures.
    private var shouldShowPlacementBypass: Bool {
        guard rev10PrimaryConnected else { return false }
        if placementState == .lightLeak { return true }
        if placementState == .tooLow, estimatedVolts > TemporalisIRDCVoltageEstimator.placementGoodUpperVolts { return true }
        return false
    }

    private var placementBypassPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bypass placement warning")
                .font(designSystem.typography.labelMedium)
                .foregroundColor(designSystem.colors.textPrimary)
            Text("Use only if you are confident the sensor is light-tight. Baseline will use the current IR-DC estimate.")
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
            Button {
                startCalibrationWizard()
            } label: {
                Text("Proceed to 10-minute calibration anyway")
                    .font(designSystem.typography.labelMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(designSystem.colors.warning)
                    .foregroundColor(designSystem.colors.primaryBlack)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.warning.opacity(0.12))
        .cornerRadius(designSystem.cornerRadius.card)
        .padding(.horizontal, designSystem.spacing.md)
    }

    private func startCalibrationWizard() {
        manualOverrideForCurrentCalibration = isResearchOverrideActive
        if isResearchOverrideActive {
            firstLaunchManager.markOralablePaired()
        }
        lockedBaselineVoltage = goodVoltageSamples.isEmpty ? estimatedVolts : averagedGoodVoltage
        onBeginCalibration?()
        showCalibrationWizard = true
    }

    private var averagedGoodVoltage: Double {
        let s = goodVoltageSamples
        guard !s.isEmpty else { return estimatedVolts }
        return s.reduce(0, +) / Double(s.count)
    }

    private var rev10PrimaryConnected: Bool {
        guard deviceManagerAdapter.isConnected,
              (deviceManager.primaryBLEDevice as? OralableDevice) != nil else { return false }
        guard let pid = deviceManager.primaryDevice?.peripheralIdentifier else { return false }
        return deviceManager.connectedDevices.contains {
            $0.peripheralIdentifier == pid && $0.connectionState == .connected
        }
    }

    private func syncPlacement(from irRaw: Double) {
        let v = TemporalisIRDCVoltageEstimator.estimateVolts(fromIRRaw: irRaw)
        estimatedVolts = v

        let leakThreshold = allowRelaxedLightLeakThreshold
            ? TemporalisIRDCVoltageEstimator.lightLeakThresholdRelaxed
            : TemporalisIRDCVoltageEstimator.lightLeakThresholdStrict
        let rawState = TemporalisIRDCVoltageEstimator.placementState(irRaw: irRaw, lightLeakThreshold: leakThreshold)

        let committedState: TemporalisIRDCPlacementState
        if rawState == .lightLeak {
            if lightLeakPendingSince == nil {
                lightLeakPendingSince = Date()
            }
            if Date().timeIntervalSince(lightLeakPendingSince!) >= lightLeakConfirmDelay {
                committedState = .lightLeak
            } else {
                committedState = lastNonLeakDisplayState
            }
        } else {
            lightLeakPendingSince = nil
            committedState = rawState
            lastNonLeakDisplayState = rawState
        }

        placementState = committedState

        if rawState == .good {
            goodVoltageSamples.append(v)
            if goodVoltageSamples.count > maxGoodSamples {
                goodVoltageSamples.removeFirst(goodVoltageSamples.count - maxGoodSamples)
            }
            if goodVoltageSamples.count >= minGoodSamples {
                if stableGoodSince == nil {
                    stableGoodSince = Date()
                    allowRelaxedLightLeakThreshold = true
                }
            } else {
                stableGoodSince = nil
            }
        } else if rawState == .lightLeak, committedState == .lightLeak {
            goodVoltageSamples = []
            stableGoodSince = nil
        } else if rawState != .lightLeak {
            goodVoltageSamples = []
            stableGoodSince = nil
        }
    }

    private func requestCameraIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    cameraAuthorized = ok
                    cameraDenied = !ok
                }
            }
        default:
            cameraDenied = true
        }
    }
}
