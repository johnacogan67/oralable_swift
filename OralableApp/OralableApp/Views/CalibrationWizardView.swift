//
//  CalibrationWizardView.swift
//  OralableApp
//
//  Ten-minute settling / baseline validation gate before overnight sleep study.
//

import SwiftUI
import OralableCore
import UIKit

struct CalibrationActiveElapsedClock {
    private(set) var activeElapsed: TimeInterval = 0
    private var lastActiveTickAt: Date?

    mutating func reset(startingAt start: Date) {
        activeElapsed = 0
        lastActiveTickAt = start
    }

    mutating func elapsedSeconds(now: Date, isActive: Bool) -> Int {
        guard isActive else {
            lastActiveTickAt = nil
            return Int(activeElapsed)
        }

        if let lastActiveTickAt {
            activeElapsed += max(0, now.timeIntervalSince(lastActiveTickAt))
        }
        lastActiveTickAt = now
        return Int(activeElapsed)
    }
}

struct CalibrationWizardView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor
    @Environment(\.scenePhase) private var scenePhase

    let lockedBaselineVoltage: Double
    /// When true, calibration CSV rows include `is_manual_override=1` (research fit-gate bypass).
    let isManualPlacementOverride: Bool
    let totalSeconds: Int
    let onSuccessfulCalibration: (() -> Void)?
    let onFinished: () -> Void

    init(
        lockedBaselineVoltage: Double,
        isManualPlacementOverride: Bool = false,
        totalSeconds: Int = 90,
        onSuccessfulCalibration: (() -> Void)? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.lockedBaselineVoltage = lockedBaselineVoltage
        self.isManualPlacementOverride = isManualPlacementOverride
        self.totalSeconds = max(15, totalSeconds)
        self.onSuccessfulCalibration = onSuccessfulCalibration
        self.onFinished = onFinished
    }

    @State private var elapsed: Int = 0
    @State private var didComplete = false
    @State private var hasStarted = false
    @State private var timerActive = false
    @State private var lastPhaseIndex: Int = -1
    @State private var activeElapsedClock = CalibrationActiveElapsedClock()

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, Double(elapsed) / Double(totalSeconds))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: designSystem.spacing.xl) {
                Text("Calibration")
                    .font(designSystem.typography.h3)
                    .foregroundColor(designSystem.colors.textPrimary)

                Text("Follow the timed protocol to lock your baseline.")
                    .font(designSystem.typography.bodySmall)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if hasStarted {
                    ZStack {
                        Circle()
                            .stroke(designSystem.colors.gray200, lineWidth: 10)
                            .frame(width: 180, height: 180)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(designSystem.colors.success, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 180, height: 180)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: designSystem.spacing.xs) {
                            Text(formattedRemaining)
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(designSystem.colors.textPrimary)
                            Text("remaining")
                                .font(designSystem.typography.caption)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                    }
                    .padding(.vertical, designSystem.spacing.lg)

                    phaseHint
                } else {
                    protocolCard
                    Button("Start \(calibrationDurationDescription) calibration") {
                        startCalibration()
                    }
                    .font(designSystem.typography.labelMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(designSystem.colors.primaryBlack)
                    .foregroundColor(designSystem.colors.primaryWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()
            }
            .padding(designSystem.spacing.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        timerActive = false
                        if hasStarted {
                            _ = sensorDataProcessor.endCalibrationOralableCapture()
                        }
                        onFinished()
                    }
                }
            }
            .onAppear {
                elapsed = 0
                didComplete = false
                hasStarted = false
                timerActive = false
                lastPhaseIndex = -1
            }
            .onDisappear {
                timerActive = false
                if hasStarted, !didComplete {
                    _ = sensorDataProcessor.endCalibrationOralableCapture()
                }
            }
            .task(id: timerActive) {
                guard timerActive else { return }
                guard hasStarted, !didComplete else { return }

                while !Task.isCancelled, timerActive, hasStarted, !didComplete {
                    let newElapsed = min(
                        totalSeconds,
                        activeElapsedClock.elapsedSeconds(now: Date(), isActive: scenePhase == .active)
                    )
                    if newElapsed != elapsed {
                        elapsed = newElapsed
                        emitPhaseHapticIfNeeded()
                    }
                    if elapsed >= totalSeconds {
                        completeCalibration()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
    }

    private var formattedRemaining: String {
        let left = max(0, totalSeconds - elapsed)
        let m = left / 60
        let s = left % 60
        return String(format: "%d:%02d", m, s)
    }

    private var phaseHint: some View {
        let text: String
        if elapsed < settleEndSeconds {
            text = "0-\(settleEndSeconds)s: Settle fit, keep still, breathe normally."
        } else if elapsed < quietEndSeconds {
            text = "\(settleEndSeconds)-\(quietEndSeconds)s: Quiet baseline — jaw relaxed, no clenching or talking."
        } else if elapsed < holdEndSeconds {
            text = "\(quietEndSeconds)-\(holdEndSeconds)s: Hold posture and strap tension."
        } else if elapsed < totalSeconds {
            text = "\(holdEndSeconds)-\(totalSeconds)s: Final lock — stay fully still."
        } else {
            text = "Complete."
        }
        return Text(text)
            .font(designSystem.typography.labelMedium)
            .foregroundColor(designSystem.colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Calibration protocol (\(calibrationDurationDescription))")
                .font(designSystem.typography.labelMedium)
                .foregroundColor(designSystem.colors.textPrimary)
            protocolRow("0-\(settleEndSeconds)s", "Settle fit and posture.")
            protocolRow("\(settleEndSeconds)-\(quietEndSeconds)s", "Quiet baseline: jaw relaxed, no clench.")
            protocolRow("\(quietEndSeconds)-\(holdEndSeconds)s", "Hold steady: do not touch headset.")
            protocolRow("\(holdEndSeconds)-\(totalSeconds)s", "Final lock: remain fully still.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func protocolRow(_ window: String, _ instruction: String) -> some View {
        HStack(alignment: .top, spacing: designSystem.spacing.sm) {
            Text(window)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textPrimary)
                .frame(width: 78, alignment: .leading)
            Text(instruction)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
        }
    }

    private var settleEndSeconds: Int { max(5, totalSeconds / 6) }
    private var quietEndSeconds: Int { max(settleEndSeconds + 1, totalSeconds / 2) }
    private var holdEndSeconds: Int { max(quietEndSeconds + 1, (totalSeconds * 5) / 6) }

    private var calibrationDurationDescription: String {
        if totalSeconds % 60 == 0 {
            let mins = totalSeconds / 60
            return mins == 1 ? "1 minute" : "\(mins) minutes"
        }
        return "\(totalSeconds) seconds"
    }

    private func startCalibration() {
        elapsed = 0
        didComplete = false
        hasStarted = true
        timerActive = true
        lastPhaseIndex = -1
        activeElapsedClock.reset(startingAt: Date())
        sensorDataProcessor.beginCalibrationOralableCapture()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func completeCalibration() {
        guard !didComplete else { return }
        didComplete = true
        timerActive = false
        guard let pid = deviceManager.primaryDevice?.peripheralIdentifier else {
            Logger.shared.warning("[CalibrationWizard] No primary device at completion; calibration not saved.")
            onFinished()
            return
        }
        let id = UUID()
        let samples = sensorDataProcessor.endCalibrationOralableCapture().filter { $0.deviceType == .oralable }
        var csvName: String?
        if !samples.isEmpty {
            let name = "temporalis_cal_\(id.uuidString).csv"
            do {
                let url = try SessionHistoryStore.researchCalibrationURL(fileName: name)
                try ResearchRawDataExport.writeOralableRaw50HzCSV(
                    samples: samples,
                    to: url,
                    isManualOverride: isManualPlacementOverride
                )
                csvName = name
                Logger.shared.info("[CalibrationWizard] Raw calibration CSV: \(samples.count) Oralable samples → \(name)")
            } catch {
                Logger.shared.warning("[CalibrationWizard] Could not save calibration CSV: \(error.localizedDescription)")
            }
        }
        sessionHistoryStore.recordTemporalisSleepCalibration(
            calibrationId: id,
            baselineVoltage: lockedBaselineVoltage,
            peripheralId: pid,
            rawCalibrationCSVFileName: csvName
        )
        Logger.shared.info("[CalibrationWizard] Completed calibration \(id) baseline=\(lockedBaselineVoltage)V peripheral=\(pid)")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSuccessfulCalibration?()
        onFinished()
    }

    private func emitPhaseHapticIfNeeded() {
        let phaseIndex: Int
        if elapsed < settleEndSeconds {
            phaseIndex = 0
        } else if elapsed < quietEndSeconds {
            phaseIndex = 1
        } else if elapsed < holdEndSeconds {
            phaseIndex = 2
        } else {
            phaseIndex = 3
        }
        guard phaseIndex != lastPhaseIndex else { return }
        lastPhaseIndex = phaseIndex
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
