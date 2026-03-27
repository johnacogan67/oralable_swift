//
//  CalibrationWizardView.swift
//  OralableApp
//
//  Ten-minute settling / baseline validation gate before overnight sleep study.
//

import SwiftUI
import OralableCore

struct CalibrationWizardView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor

    let lockedBaselineVoltage: Double
    let onSuccessfulCalibration: (() -> Void)?
    let onFinished: () -> Void

    init(
        lockedBaselineVoltage: Double,
        onSuccessfulCalibration: (() -> Void)? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.lockedBaselineVoltage = lockedBaselineVoltage
        self.onSuccessfulCalibration = onSuccessfulCalibration
        self.onFinished = onFinished
    }

    private let totalSeconds: Int = 600

    @State private var elapsed: Int = 0
    @State private var didComplete = false
    @State private var timerActive = false

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

                Text("Stay seated with the headband in the confirmed fit. Relax your jaw—avoid clenching for the full 10 minutes so we can lock an IR-DC baseline.")
                    .font(designSystem.typography.bodySmall)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

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

                Spacer()
            }
            .padding(designSystem.spacing.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        timerActive = false
                        _ = sensorDataProcessor.endCalibrationOralableCapture()
                        onFinished()
                    }
                }
            }
            .onAppear {
                elapsed = 0
                didComplete = false
                timerActive = true
                sensorDataProcessor.beginCalibrationOralableCapture()
            }
            .onDisappear {
                timerActive = false
                if !didComplete {
                    _ = sensorDataProcessor.endCalibrationOralableCapture()
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                guard timerActive, !didComplete else { return }
                if elapsed < totalSeconds {
                    elapsed += 1
                }
                if elapsed >= totalSeconds {
                    completeCalibration()
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
        if elapsed < 120 {
            text = "Phase 1: Keep still and breathe normally."
        } else if elapsed < 360 {
            text = "Phase 2: Hold placement—minor drift is OK."
        } else if elapsed < totalSeconds {
            text = "Phase 3: Final baseline capture."
        } else {
            text = "Complete."
        }
        return Text(text)
            .font(designSystem.typography.labelMedium)
            .foregroundColor(designSystem.colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
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
                try ResearchRawDataExport.writeOralableRaw50HzCSV(samples: samples, to: url)
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
        onSuccessfulCalibration?()
        onFinished()
    }
}
