//
//  HistoricalMetricDetailView.swift
//  OralableApp
//
//  Apple Health–style metric detail: segmented Hour / Day / Week and Temporalis HOI chart.
//

import SwiftUI

struct HistoricalMetricDetailView: View {
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var appleHealthManager: AppleHealthManager

    @State private var scope: TemporalisHistoryScope = .day
    @State private var exportBanner: String?
    @State private var showExportAlert = false

    var body: some View {
        let hourlySorted = dependencies.sessionHistoryStore.segmentByHour.values.sorted { $0.hourIndex < $1.hourIndex }
        let model = TemporalisAnalysisChart.build(
            from: dependencies.sensorDataProcessor.sensorDataHistory,
            hourlyRescue: hourlySorted,
            scope: scope
        )

        ScrollView {
            VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
                Picker("Range", selection: $scope) {
                    ForEach(TemporalisHistoryScope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                TemporalisAnalysisChart(
                    lineSeries: model.line,
                    rescuePerHour: model.bars,
                    hypoxiaMarkers: model.markers,
                    detailCaption: model.detailCaption
                )
            }
            .padding(.horizontal, designSystem.spacing.md)
            .padding(.vertical, designSystem.spacing.sm)
        }
        .background(designSystem.colors.backgroundSecondary)
        .navigationTitle("Temporalis HOI")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Apple Health") {
                    Task { await runExport() }
                }
            }
        }
        .alert("Export to Apple Health", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportBanner ?? "")
        }
    }

    private func runExport() async {
        do {
            let oral = dependencies.sensorDataProcessor.sensorDataHistory.filter { $0.deviceType == .oralable }
            let samples = oral.compactMap { s -> AppleHealthSpO2SampleStub? in
                guard let p = s.spo2, p.percentage > 0, p.percentage <= 100 else { return nil }
                return AppleHealthSpO2SampleStub(date: s.timestamp, oxygenSaturationPercent: p.percentage)
            }
            try await appleHealthManager.exportSpO2ToAppleHealthStub(samples: samples)
            exportBanner = "Saved session-average SpO₂ (\(samples.count) samples) to Apple Health."
            showExportAlert = true
        } catch {
            exportBanner = error.localizedDescription
            showExportAlert = true
        }
    }
}
