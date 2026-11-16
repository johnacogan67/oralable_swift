//
//  DualProtocolASessionView.swift
//  OralableApp
//
//  Research Dual Protocol A: ANR EMG gate → MAM couple seat QC → Mac cues → Share export.
//

import SwiftUI
import OralableCore

struct DualProtocolASessionView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var controller = DualProtocolASessionController()
    @State private var showShareSheet = false
    @State private var shareURLs: [URL] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                    placementCard
                    connectionCard
                    liveSensorsCard
                    phaseCard
                    controls
                }
                .padding(designSystem.spacing.md)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Dual Protocol A")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        controller.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear {
                controller.attach(deviceManager: deviceManager)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareURLs)
            }
        }
    }

    // MARK: - Sections

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Placement")
                .font(designSystem.typography.bodySmall)
                .fontWeight(.semibold)
            Text("ANR long-axis VERTICAL on anterior temporalis. MAM PPG coil against skin beside ANR.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text("Flow: ANR EMG preflight → MAM couple seat QC (same as Protocol A Setup) → 6 min cues.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text("Keep both BLE links up the whole session. FW 1.0.71+ stops MAM sensors if the link drops.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text("At 1:00 — five firm sync taps on the MAM housing.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Toggle("Allow couple=1 (poor MAM seat)", isOn: $controller.allowCouple1)
                .font(designSystem.typography.caption)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
    }

    private var connectionCard: some View {
        HStack(spacing: designSystem.spacing.lg) {
            connectionLED(
                title: "MAM",
                connected: controller.oralableConnected || dashboardViewModel.oralableConnected
            )
            connectionLED(
                title: "ANR",
                connected: controller.anrConnected || dashboardViewModel.anrConnected
            )
            Spacer()
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
    }

    private func connectionLED(title: String, connected: Bool) -> some View {
        HStack(spacing: designSystem.spacing.sm) {
            Circle()
                .fill(connected ? designSystem.colors.success : designSystem.colors.gray400)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(designSystem.typography.bodySmall)
                    .fontWeight(.medium)
                Text(connected ? "Connected" : "Not connected")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
        }
        .accessibilityLabel("\(title), \(connected ? "Connected" : "Not connected")")
    }

    private var liveSensorsCard: some View {
        HStack(alignment: .top, spacing: designSystem.spacing.md) {
            VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
                Text("Live ANR EMG")
                    .font(designSystem.typography.bodySmall)
                    .fontWeight(.semibold)
                Text(String(format: "%.0f", controller.latestEMG))
                    .font(designSystem.typography.h2)
                    .foregroundColor(designSystem.colors.textPrimary)
                Text("Raw 0–1023 · gate ≥ \(Int(controller.emgGate))")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
                Text("MAM IR / couple")
                    .font(designSystem.typography.bodySmall)
                    .fontWeight(.semibold)
                Text(controller.latestIR > 0 ? String(format: "%.0f", controller.latestIR) : "—")
                    .font(designSystem.typography.h2)
                    .foregroundColor(designSystem.colors.textPrimary)
                Text(controller.coupleSnippet)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live ANR EMG \(Int(controller.latestEMG)), MAM \(controller.coupleSnippet)")
    }

    @ViewBuilder
    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text(phaseTitle)
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)

            Text(phaseHeadline)
                .font(designSystem.typography.h3)
                .fontWeight(.semibold)
                .foregroundColor(designSystem.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let countdown = phaseCountdown {
                Text(countdown)
                    .font(designSystem.typography.body)
                    .monospacedDigit()
                    .foregroundColor(designSystem.colors.textPrimary)
            }

            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            if let stats = controller.preflightStats {
                Text(
                    String(
                        format: "EMG clench max %.0f · mean %.0f · rest max %.0f",
                        stats.clenchMax,
                        stats.clenchMean,
                        stats.restMax
                    )
                )
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
            }
            if let couple = controller.coupleStats {
                Text(couple.snippet)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
    }

    private var phaseTitle: String {
        switch controller.phase {
        case .idle: return "Ready"
        case .connecting: return "Connecting"
        case .preflight: return "EMG preflight"
        case .preflightFailed: return "EMG preflight failed"
        case .seatQC: return "MAM seat QC (couple)"
        case .seatQCFailed: return "MAM seat QC failed"
        case .settling: return "Settle"
        case .running: return "Protocol A"
        case .exporting: return "Export"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        case .failed: return "Error"
        }
    }

    private var phaseHeadline: String {
        switch controller.phase {
        case .idle:
            return "Connect both devices, then Start."
        case .connecting:
            return "Checking Oralable + ANR…"
        case .preflight(let stage, _):
            return stage.rawValue
        case .preflightFailed:
            return "Re-seat ANR vertical and retry, or Force start (then MAM seat QC)."
        case .seatQC:
            return "Waiting for \(controller.allowCouple1 ? "couple≥1" : "couple=2")"
        case .seatQCFailed:
            return "Re-seat MAM on temple and retry, or Continue anyway."
        case .settling:
            return "Hold still — cues start in 2 s."
        case .running(_, let cue):
            return cue.text
        case .exporting:
            return "Writing TEMPORALIS + ANR + DUAL_PAIR + session.edf…"
        case .done:
            return "Share four files (includes session.edf with ANR EMG)."
        case .cancelled:
            return "Session cancelled."
        case .failed(let message):
            return message
        }
    }

    private var phaseCountdown: String? {
        switch controller.phase {
        case .preflight(_, let elapsed):
            let total = DualProtocolACues.preflightRestSeconds * 2 + DualProtocolACues.preflightClenchSeconds
            return "\(DualProtocolACues.formatMMSS(elapsed)) / \(DualProtocolACues.formatMMSS(total))"
        case .seatQC(let elapsed, let couple):
            return "\(CoupleLabel.label(couple)) · \(DualProtocolACues.formatMMSS(elapsed)) / \(DualProtocolACues.formatMMSS(DualProtocolASessionController.couplePreflightTimeoutS))"
        case .running(let elapsed, _):
            return "\(DualProtocolACues.formatMMSS(elapsed)) / \(DualProtocolACues.formatMMSS(DualProtocolACues.sessionDurationSeconds))"
        default:
            return nil
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: designSystem.spacing.sm) {
            switch controller.phase {
            case .idle, .cancelled, .failed:
                Button("Start") { controller.start() }
                    .buttonStyle(PrimaryDualAButtonStyle(designSystem: designSystem))
                    .disabled(!(controller.oralableConnected || dashboardViewModel.oralableConnected)
                              || !(controller.anrConnected || dashboardViewModel.anrConnected))

            case .preflight, .seatQC, .settling, .running, .connecting, .exporting:
                Button("Cancel") { controller.cancel() }
                    .buttonStyle(SecondaryDualAButtonStyle(designSystem: designSystem))

            case .preflightFailed:
                Button("Retry EMG preflight") { controller.retryPreflight() }
                    .buttonStyle(PrimaryDualAButtonStyle(designSystem: designSystem))
                Button("Force start → MAM seat QC") { controller.forceStartDespitePreflight() }
                    .buttonStyle(SecondaryDualAButtonStyle(designSystem: designSystem))
                Button("Cancel") { controller.cancel() }
                    .buttonStyle(SecondaryDualAButtonStyle(designSystem: designSystem))

            case .seatQCFailed:
                Button("Retry MAM seat QC") { controller.retrySeatQC() }
                    .buttonStyle(PrimaryDualAButtonStyle(designSystem: designSystem))
                Button("Continue anyway (desk)") { controller.forceStartDespiteSeatQC() }
                    .buttonStyle(SecondaryDualAButtonStyle(designSystem: designSystem))
                Button("Cancel") { controller.cancel() }
                    .buttonStyle(SecondaryDualAButtonStyle(designSystem: designSystem))

            case .done(let artifacts):
                Button("Share export pack") {
                    shareURLs = artifacts.shareURLs
                    showShareSheet = true
                }
                .buttonStyle(PrimaryDualAButtonStyle(designSystem: designSystem))
                Button("Done") {
                    controller.resetToIdle()
                    dismiss()
                }
                .buttonStyle(SecondaryDualAButtonStyle(designSystem: designSystem))
            }
        }
    }
}

// MARK: - Button styles

private struct PrimaryDualAButtonStyle: ButtonStyle {
    let designSystem: DesignSystem

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(designSystem.typography.bodySmall)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, designSystem.spacing.sm)
            .foregroundColor(designSystem.colors.primaryWhite)
            .background(designSystem.colors.primaryBlack.opacity(configuration.isPressed ? 0.7 : 1))
            .cornerRadius(designSystem.cornerRadius.button)
    }
}

private struct SecondaryDualAButtonStyle: ButtonStyle {
    let designSystem: DesignSystem

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(designSystem.typography.bodySmall)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, designSystem.spacing.sm)
            .foregroundColor(designSystem.colors.textPrimary)
            .background(designSystem.colors.backgroundPrimary.opacity(configuration.isPressed ? 0.7 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: designSystem.cornerRadius.button)
                    .stroke(designSystem.colors.border, lineWidth: 1)
            )
            .cornerRadius(designSystem.cornerRadius.button)
    }
}
