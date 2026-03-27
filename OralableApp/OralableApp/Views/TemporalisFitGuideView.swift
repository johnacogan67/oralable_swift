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

    let onExit: () -> Void
    /// Called only after the 10-minute calibration saves baseline (not on Cancel).
    var onCalibrationSucceeded: (() -> Void)?

    init(onExit: @escaping () -> Void, onCalibrationSucceeded: (() -> Void)? = nil) {
        self.onExit = onExit
        self.onCalibrationSucceeded = onCalibrationSucceeded
    }

    @StateObject private var camera = FrontMirrorCaptureSession()
    @State private var cameraAuthorized = false
    @State private var cameraDenied = false

    @State private var placementState: TemporalisIRDCPlacementState = .noSignal
    @State private var estimatedVolts: Double = 0
    @State private var goodVoltageSamples: [Double] = []
    @State private var stableGoodSince: Date?
    @State private var showCalibrationWizard = false
    @State private var lockedBaselineVoltage: Double = 0

    private let stableHoldSeconds: TimeInterval = 2
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
                                        templeReticle(in: g.size)
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
                    if canAdvanceToCalibration {
                        Button {
                            lockedBaselineVoltage = averagedGoodVoltage
                            showCalibrationWizard = true
                        } label: {
                            Text("Signal locked — start 10-minute calibration")
                                .font(designSystem.typography.labelMedium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(designSystem.colors.primaryBlack)
                                .foregroundColor(designSystem.colors.primaryWhite)
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
                onSuccessfulCalibration: onCalibrationSucceeded,
                onFinished: {
                    showCalibrationWizard = false
                    camera.stop()
                    onExit()
                }
            )
            .environmentObject(designSystem)
            .environmentObject(sessionHistoryStore)
            .environmentObject(deviceManager)
            .environmentObject(sensorDataProcessor)
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
    }

    private var lightLeakBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .foregroundColor(designSystem.colors.warning)
            Text("Light leakage detected: tighten the headband to block ambient light.")
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
            return "Adjust placement — signal low"
        case .good:
            return "Placement OK — hold steady"
        case .lightLeak:
            return "Too bright — reduce stray light"
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
        let state = TemporalisIRDCVoltageEstimator.placementState(irRaw: irRaw)
        estimatedVolts = v
        placementState = state

        switch state {
        case .good:
            goodVoltageSamples.append(v)
            if goodVoltageSamples.count > maxGoodSamples {
                goodVoltageSamples.removeFirst(goodVoltageSamples.count - maxGoodSamples)
            }
            if goodVoltageSamples.count >= minGoodSamples {
                if stableGoodSince == nil {
                    stableGoodSince = Date()
                }
            } else {
                stableGoodSince = nil
            }
        default:
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
