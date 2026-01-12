//
//  PatientDashboardView.swift
//  OralableForProfessionals
//
//  Dashboard view for individual patient data analysis.
//
//  Features:
//  - Session list with date and duration
//  - Summary statistics across sessions
//  - Chart previews for key metrics
//  - Navigation to detailed analysis
//
//  Metrics Displayed:
//  - PPG activity patterns
//  - Movement analysis
//  - Temperature trends
//  - Event frequency
//

import SwiftUI
import Charts

struct PatientDashboardView: View {
    let patient: ProfessionalPatient
    @StateObject private var viewModel: PatientDashboardViewModel
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject private var featureFlags = FeatureFlags.shared

    init(patient: ProfessionalPatient) {
        self.patient = patient
        _viewModel = StateObject(wrappedValue: PatientDashboardViewModel(patient: patient))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Participant info header
                patientHeader

                if viewModel.isLoading {
                    ProgressView("Loading wellness data...")
                        .padding()
                } else if !viewModel.hasSensorData {
                    noDataView
                } else {
                    // View Historical Data - Single entry point with tabbed metrics
                    NavigationLink(destination: PatientHistoricalView(patient: patient)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("View Historical Data", systemImage: "chart.xyaxis.line")
                                    .font(.headline)
                                Text("EMG, IR, Movement, Temperature")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Quick stats cards
                    HStack(spacing: 12) {
                        // Muscle Activity
                        HealthMetricCard(
                            icon: "waveform.path.ecg",
                            title: "Activity",
                            value: viewModel.muscleActivity > 0 ? String(format: "%.0f", viewModel.muscleActivity) : "N/A",
                            unit: "",
                            color: .purple,
                            sparklineData: viewModel.muscleActivityHistory,
                            showChevron: false
                        )

                        // Movement
                        if featureFlags.showMovementCard {
                            HealthMetricCard(
                                icon: "figure.walk",
                                title: "Movement",
                                value: viewModel.isMoving ? "Active" : "Still",
                                unit: "",
                                color: .blue,
                                sparklineData: Array(viewModel.accelerometerHistory.suffix(20)),
                                showChevron: false
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        // Heart Rate
                        if featureFlags.showHeartRateCard {
                            HealthMetricCard(
                                icon: "heart.fill",
                                title: "Heart Rate",
                                value: viewModel.heartRate > 0 ? "\(viewModel.heartRate)" : "N/A",
                                unit: viewModel.heartRate > 0 ? "BPM" : "",
                                color: .red,
                                sparklineData: Array(viewModel.heartRateHistory.suffix(20)),
                                showChevron: false
                            )
                        }

                        // Temperature
                        if featureFlags.showTemperatureCard {
                            HealthMetricCard(
                                icon: "thermometer",
                                title: "Temp",
                                value: viewModel.temperature > 0 ? String(format: "%.1f", viewModel.temperature) : "N/A",
                                unit: viewModel.temperature > 0 ? "°C" : "",
                                color: .orange,
                                sparklineData: [],
                                showChevron: false
                            )
                        }
                    }

                    // Last updated
                    if let lastUpdated = viewModel.lastUpdated {
                        Text("Last updated: \(lastUpdated, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(patient.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task { await viewModel.loadLatestData() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await viewModel.loadLatestData()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Subviews

    private var patientHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(patient.displayName)
                    .font(.headline)

                Text("Added \(patient.accessGrantedDate, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if viewModel.hasSensorData {
                    Text("\(viewModel.sensorDataCount) data points")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Wellness Data")
                .font(.headline)

            Text("This participant hasn't shared any wellness data yet. Data is uploaded when they complete recording sessions.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}
