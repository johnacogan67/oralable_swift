//
//  SingleProtocolASetupView.swift
//  OralableApp
//
//  Setup Mode: single-MAM Protocol A (Mac couple seat QC + Mac cues) before General Mode.
//

import SwiftUI
import OralableCore

struct SingleProtocolASetupView: View {
    @ObservedObject var firstLaunchManager: FirstLaunchManager
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var recordingSessionManager: RecordingSessionManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore

    @StateObject private var controller = SingleProtocolASessionController()
    @State private var showShareSheet = false
    @State private var shareURLs: [URL] = []
    @State private var didIngestSession = false

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
            .navigationTitle("Protocol A Setup")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                controller.attach(deviceManager: deviceManager)
            }
            .onChange(of: controller.phase) { _, newPhase in
                if case .done(let artifacts) = newPhase {
                    ingestIntoGeneralMode(artifacts)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareURLs)
            }
        }
    }

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Setup — single MAM")
                .font(designSystem.typography.bodySmall)
                .fontWeight(.semibold)
            Text("Seat Oralable on anterior temporalis (temple). PPG toward skin. This is a ~6 minute training protocol — wellness only, not a medical diagnosis.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text("Keep BLE linked the whole session. FW 1.0.71+ stops sensors if the link drops.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text("Seat QC uses Mac `couple` (not GATT worn). CCC order matches nRF Connect: battery → status → PPG → ACC → temp.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text("At 1:00 — five firm sync taps on the MAM housing.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            if let pct = deviceManager.primaryBatteryPercent() {
                Text("Battery \(pct)%")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            Toggle("Allow couple=1 (poor seat)", isOn: $controller.allowCouple1)
                .font(designSystem.typography.caption)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
    }

    private var connectionCard: some View {
        HStack(spacing: designSystem.spacing.sm) {
            Circle()
                .fill(controller.oralableConnected ? designSystem.colors.success : designSystem.colors.gray400)
                .frame(width: 10, height: 10)
            Text(controller.oralableConnected ? "MAM connected" : "MAM not connected")
                .font(designSystem.typography.labelMedium)
            Spacer()
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
    }

    private var liveSensorsCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
            Text("Live IR / couple")
                .font(designSystem.typography.bodySmall)
                .fontWeight(.semibold)
            Text(controller.latestIR > 0 ? String(format: "%.0f", controller.latestIR) : "—")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text(controller.coupleSnippet)
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.button)
    }

    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text(phaseTitle)
                .font(designSystem.typography.headline)
            Text(controller.statusMessage)
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
            if case .running(_, let cue) = controller.phase {
                Text(cue.text)
                    .font(designSystem.typography.labelMedium)
                    .padding(.top, 4)
                if case .running(let elapsed, _) = controller.phase {
                    Text("\(DualProtocolACues.formatMMSS(elapsed)) / \(DualProtocolACues.formatMMSS(DualProtocolACues.sessionDurationSeconds))")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }
            if case .seatQC(let elapsed, let couple) = controller.phase {
                Text("Waiting for \(controller.allowCouple1 ? "couple≥1" : "couple=2")")
                    .font(designSystem.typography.labelMedium)
                Text("\(CoupleLabel.label(couple)) · \(DualProtocolACues.formatMMSS(elapsed)) / \(DualProtocolACues.formatMMSS(SingleProtocolASessionController.couplePreflightTimeoutS))")
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
        case .seatQC: return "Seat QC (couple)"
        case .seatQCFailed: return "Seat QC failed"
        case .settling: return "Settling"
        case .running: return "Protocol A"
        case .exporting: return "Exporting"
        case .done: return "Complete"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: designSystem.spacing.sm) {
            switch controller.phase {
            case .idle, .cancelled, .failed:
                Button {
                    didIngestSession = false
                    controller.resetToIdle()
                    controller.start()
                } label: {
                    Text("Start Protocol A")
                        .font(designSystem.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(designSystem.colors.primaryBlack)
                        .foregroundColor(designSystem.colors.primaryWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            case .seatQCFailed:
                Button {
                    controller.retrySeatQC()
                } label: {
                    Text("Retry seat QC")
                        .font(designSystem.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(designSystem.colors.primaryBlack)
                        .foregroundColor(designSystem.colors.primaryWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button("Continue anyway (desk)") {
                    controller.forceStartDespiteSeatQC()
                }
                .font(designSystem.typography.caption)
            case .done(let artifacts):
                Button {
                    ingestIntoGeneralMode(artifacts)
                    firstLaunchManager.markProtocolASetupCompleted()
                } label: {
                    Text("Go to dashboard")
                        .font(designSystem.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(designSystem.colors.primaryBlack)
                        .foregroundColor(designSystem.colors.primaryWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button("Share export") {
                    shareURLs = artifacts.shareURLs
                    showShareSheet = true
                }
                .font(designSystem.typography.caption)
            case .seatQC, .settling, .running, .exporting, .connecting:
                Button("Cancel") {
                    controller.cancel()
                }
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.error)
            }
        }
    }

    /// Register Protocol A Setup as a completed IR session + Share bookmark.
    private func ingestIntoGeneralMode(_ artifacts: SingleProtocolAExportArtifacts) {
        guard !didIngestSession else { return }
        didIngestSession = true

        let device = deviceManager.connectedDevices.first(where: { $0.type == .oralable })
        let sessionId = UUID()
        var session = RecordingSession(
            id: sessionId,
            startTime: artifacts.sessionStart,
            status: .completed,
            deviceID: device?.id.uuidString,
            deviceName: device?.name ?? "Oralable",
            deviceType: .oralable
        )
        session.endTime = artifacts.sessionEnd
        session.notes = "Protocol A Setup"
        session.tags = [RecordingSession.protocolASetupTag]
        session.dataFilePath = artifacts.edfURL
        session.sensorDataCount = artifacts.sampleCount
        session.ppgDataCount = artifacts.sampleCount

        let registered = recordingSessionManager.registerCompletedSession(session)
        sessionHistoryStore.recordProtocolASetupExport(
            recordingSessionId: sessionId,
            sessionTimestamp: artifacts.sessionTimestamp,
            sampleCount: artifacts.sampleCount,
            deviceID: session.deviceID,
            deviceName: session.deviceName,
            completedAt: artifacts.sessionEnd
        )
        Logger.shared.info(
            "[SingleProtocolA] Ingested into General Mode session=\(sessionId) registered=\(registered) samples=\(artifacts.sampleCount)"
        )
    }
}
