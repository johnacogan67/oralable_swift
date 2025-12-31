//
//  PatientDetailView.swift
//  OralableForProfessionals
//
//  Patient detail - now shows full dashboard with historical navigation
//

import SwiftUI
import OralableCore

struct PatientDetailView: View {
    let patient: ProfessionalPatient
    @Environment(\.dismiss) var dismiss
    @State private var showingRemoveAlert = false
    @State private var isRemoving = false

    var body: some View {
        NavigationView {
            PatientDashboardView(patient: patient)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showingRemoveAlert = true
                            } label: {
                                Label("Remove Participant", systemImage: "person.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .alert("Remove Participant", isPresented: $showingRemoveAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Remove", role: .destructive) {
                        Task {
                            await removePatient()
                        }
                    }
                } message: {
                    Text("Are you sure you want to remove \(patient.displayName)?\n\nYou will no longer have access to their data. The participant can share a new code if they want to reconnect.")
                }
                .overlay {
                    if isRemoving {
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
        }
    }

    private func removePatient() async {
        isRemoving = true
        do {
            try await ProfessionalDataManager.shared.removePatient(patient)
            await MainActor.run {
                dismiss()
            }
        } catch {
            isRemoving = false
            Logger.shared.error("[PatientDetailView] Failed to remove patient: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    PatientDetailView(patient: ProfessionalPatient(
        id: "1",
        patientID: "patient123",
        patientName: "John Doe",
        shareCode: "123456",
        accessGrantedDate: Date(),
        lastDataUpdate: Date(),
        recordID: "record1"
    ))
    .environmentObject(DesignSystem())
}
