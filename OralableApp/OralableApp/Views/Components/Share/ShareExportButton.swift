import SwiftUI

// MARK: - Export Button Component
struct ShareExportButton: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var csvExportManager: CSVExportManager
    @Binding var showShareSheet: Bool
    @Binding var showDocumentExporter: Bool
    @Binding var exportURL: URL?
    @Binding var exportDocument: CSVDocument?
    @ObservedObject var sensorDataProcessor: SensorDataProcessor
    @State private var isExporting = false

    private var hasData: Bool {
        !Logger.shared.service.recentLogs.isEmpty || !sensorDataProcessor.sensorDataHistory.isEmpty
    }

    var body: some View {
        Button(action: exportData) {
            HStack(spacing: designSystem.spacing.sm) {
                if isExporting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: DesignSystem.Sizing.Icon.md))
                }

                Text(isExporting ? "Exporting..." : "Export Data as CSV")
                    .font(designSystem.typography.buttonMedium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, designSystem.spacing.md)
            .background(
                hasData ?
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
            )
            .cornerRadius(designSystem.cornerRadius.lg)
            .designShadow(hasData ? DesignSystem.Shadow.md : DesignSystem.Shadow.sm)
        }
        .disabled(!hasData || isExporting)
        .animation(DesignSystem.Animation.fast, value: isExporting)
    }

    private func exportData() {
        isExporting = true

        DispatchQueue.global(qos: .userInitiated).async {
            csvExportManager.cleanupOldExports()

            let exportResult = csvExportManager.exportData(
                sensorData: sensorDataProcessor.sensorDataHistory,
                logs: Logger.shared.service.recentLogs.map { $0.message }
            )

            DispatchQueue.main.async {
                isExporting = false
                if let url = exportResult {
                    exportURL = url

                    if let csvContent = try? String(contentsOf: url, encoding: .utf8) {
                        exportDocument = CSVDocument(csvContent: csvContent)
                        showDocumentExporter = true
                    } else {
                        showShareSheet = true
                    }
                } else {
                    Logger.shared.warning("Export failed - no URL returned")
                }
            }
        }
    }
}
