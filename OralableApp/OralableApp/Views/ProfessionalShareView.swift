//
//  ProfessionalShareView.swift
//  OralableApp
//
//  Withings-style “Share with clinician” flow: secure link id, short manual code, JSON handshake.
//

import SwiftUI

struct ProfessionalShareView: View {
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var designSystem: DesignSystem

    @State private var linkUUID: UUID?
    @State private var displayCode: String = ""
    @State private var exportPayload: Data?
    @State private var exportError: String?
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
                headerCard

                Button {
                    generateLink()
                } label: {
                    Label("Generate Clinician Link Code", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(designSystem.colors.info)

                if !displayCode.isEmpty {
                    codeCard
                }

                if exportPayload != nil {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Export Secure Session Package", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let exportError {
                    Text(exportError)
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.warning)
                }

                Text(
                    "Your clinician enters this code in Oralable for Professionals. The package contains de-identified rollups and session summaries — not raw PPG."
                )
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
            }
            .padding(designSystem.spacing.md)
        }
        .background(designSystem.colors.backgroundSecondary)
        .navigationTitle("Share with clinician")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            Group {
                if let data = exportPayload {
                    ActivityView(item: ClinicianExportItem(data: data, code: displayCode))
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            HStack(spacing: designSystem.spacing.sm) {
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundColor(designSystem.colors.info)
                Text("Professional sharing")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)
            }
            Text(
                "Generate a one-time code and secure payload so your care team can review Temporalis load, hypoxic burden (SASHB), and vitals context in the professional app."
            )
            .font(designSystem.typography.body)
            .foregroundColor(designSystem.colors.textSecondary)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.spacing.sm, style: .continuous))
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("Clinician code")
                .font(designSystem.typography.labelLarge)
                .foregroundColor(designSystem.colors.textSecondary)
            Text(displayCode)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(6)
                .foregroundColor(designSystem.colors.textPrimary)
                .frame(maxWidth: .infinity)

            if let uuid = linkUUID {
                Text("Link id: \(uuid.uuidString)")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
                    .textSelection(.enabled)
            }

            Button {
                UIPasteboard.general.string = displayCode
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.spacing.sm, style: .continuous))
    }

    private func generateLink() {
        exportError = nil
        let uuid = UUID()
        linkUUID = uuid
        displayCode = ClinicianLinkCodeFormatter.sixCharacterCode(linkUUID: uuid)
        do {
            let data = try dependencies.sessionHistoryStore.encodeProfessionalHandshakeExportJSON(
                linkUUID: uuid,
                sensorHistory: dependencies.sensorDataProcessor.sensorDataHistory
            )
            exportPayload = data
        } catch {
            exportPayload = nil
            exportError = error.localizedDescription
        }
    }
}

// MARK: - UIKit share wrapper

private struct ClinicianExportItem {
    let data: Data
    let code: String
}

private struct ActivityView: UIViewControllerRepresentable {
    let item: ClinicianExportItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let name = "oralable_clinical_handshake_\(item.code).json"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? item.data.write(to: tmp, options: .atomic)
        return UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

