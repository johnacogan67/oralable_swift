//
//  PatientListView.swift
//  OralableForProfessionals
//
//  Main screen displaying list of patients with shared data.
//
//  Features:
//  - List of patients who have shared data
//  - Search and filter functionality
//  - Add patient button
//  - Patient detail navigation
//
//  Data Source:
//  - CloudKit shared data (when enabled)
//  - Local CSV imports
//  - Demo patients (for testing)
//

import SwiftUI

struct PatientListView: View {
    @EnvironmentObject var dependencies: ProfessionalAppDependencies
    @StateObject private var viewModel: PatientListViewModel
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @ObservedObject private var demoDataManager = DemoDataManager.shared

    init() {
        _viewModel = StateObject(wrappedValue: PatientListViewModel(
            dataManager: ProfessionalDataManager.shared,
            subscriptionManager: ProfessionalSubscriptionManager.shared
        ))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.currentTier == .starter {
                        upgradeBanner
                    }

                    if viewModel.isLoading && viewModel.patients.isEmpty {
                        LoadingView(message: "Loading participants...")
                    } else if viewModel.filteredPatients.isEmpty {
                        EmptyStateView(
                            icon: "person.2.slash",
                            title: "No Participants Yet",
                            message: "Add your first participant by entering their share code",
                            buttonTitle: "Add Participant",
                            buttonAction: { viewModel.showAddPatient() }
                        )
                    } else {
                        patientList
                    }
                }
            }
            .navigationTitle("My Participants")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.showAddPatient() }) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search participants")
            .sheet(isPresented: $viewModel.showingAddPatient) {
                AddPatientView()
            }
            .sheet(item: $viewModel.selectedPatient) { patient in
                NavigationView {
                    PatientHistoricalView(patient: patient)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    viewModel.selectedPatient = nil
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Menu {
                                    Button(role: .destructive) {
                                        viewModel.selectedPatient = nil
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            viewModel.confirmRemovePatient(patient)
                                        }
                                    } label: {
                                        Label("Remove Participant", systemImage: "person.badge.minus")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.clearError() }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .alert("Remove Participant", isPresented: $viewModel.showingRemoveConfirmation) {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelRemove()
                }
                Button("Remove", role: .destructive) {
                    Task {
                        await viewModel.removePatient()
                    }
                }
            } message: {
                if let patient = viewModel.patientToRemove {
                    Text("Are you sure you want to remove \(patient.displayName)?\n\nYou will no longer have access to their data. The participant can share a new code if they want to reconnect.")
                }
            }
            .overlay {
                if viewModel.isRemoving {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Removing participant...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                    }
                }
            }
            .onAppear {
                viewModel.loadPatients()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var patientList: some View {
        List {
            // Demo Participant Section (when demo mode enabled)
            if featureFlags.demoModeEnabled, let demoParticipant = demoDataManager.demoParticipant {
                Section {
                    DemoParticipantRowCard(participant: demoParticipant)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Demo Participant")
                        .foregroundColor(.orange)
                }
            }

            // Regular participants
            ForEach(viewModel.filteredPatients) { patient in
                PatientRowCard(patient: patient)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onTapGesture {
                        viewModel.selectPatient(patient)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.confirmRemovePatient(patient)
                        } label: {
                            Label("Remove", systemImage: "person.badge.minus")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.confirmRemovePatient(patient)
                        } label: {
                            Label("Remove Participant", systemImage: "person.badge.minus")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refreshPatients()
        }
    }

    private var upgradeBanner: some View {
        Group {
            if viewModel.patients.count >= viewModel.currentTier.maxPatients - 1 {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approaching Limit")
                            .font(.subheadline.weight(.semibold))

                        Text("\(viewModel.patients.count)/\(viewModel.currentTier.maxPatients) participants")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    NavigationLink(destination: UpgradePromptView()) {
                        Text("Upgrade")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
        }
    }
}

struct PatientRowCard: View {
    let patient: ProfessionalPatient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)

                    Text("Participant")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Connection type indicator
                HStack(spacing: 4) {
                    Image(systemName: patient.connectionIcon)
                        .font(.system(size: 10))
                        .foregroundColor(patient.isLocalImport ? .orange : .green)
                    Text(patient.connectionType)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(patient.isLocalImport ? .orange : .green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(patient.isLocalImport ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            Text(patient.displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Added \(formattedDate(patient.accessGrantedDate))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                if let lastUpdate = patient.lastDataUpdate {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("Updated \(relativeDate(lastUpdate))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                // Show data point count for CSV imports
                if patient.isLocalImport, let count = patient.dataPointCount {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(count) points")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Demo Participant Row Card

struct DemoParticipantRowCard: View {
    let participant: DemoDataManager.DemoParticipant
    @State private var showingDemoDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)

                    Text("Demo Participant")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Demo badge
                Text("DEMO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.1))
                    )

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            Text(participant.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(participant.sessions.count) sessions")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(totalDurationMinutes) min total")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            showingDemoDetail = true
        }
        .sheet(isPresented: $showingDemoDetail) {
            DemoParticipantDetailView(participant: participant)
        }
    }

    private var totalDurationMinutes: Int {
        Int(participant.sessions.map { $0.duration }.reduce(0, +) / 60)
    }
}
