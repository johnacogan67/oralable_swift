import Foundation
import Combine
import OralableCore

@MainActor
class PatientListViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var patients: [ProfessionalPatient] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var showingAddPatient: Bool = false
    @Published var selectedPatient: ProfessionalPatient?

    // Remove patient confirmation
    @Published var showingRemoveConfirmation: Bool = false
    @Published var patientToRemove: ProfessionalPatient?
    @Published var isRemoving: Bool = false

    // MARK: - Dependencies

    private let dataManager: ProfessionalDataManager
    private let subscriptionManager: ProfessionalSubscriptionManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var filteredPatients: [ProfessionalPatient] {
        if searchText.isEmpty {
            return patients
        }
        return patients.filter { patient in
            patient.displayName.localizedCaseInsensitiveContains(searchText) ||
            patient.patientID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var canAddMorePatients: Bool {
        return subscriptionManager.canAddMorePatients(currentCount: patients.count)
    }

    var patientsRemaining: String {
        let remaining = subscriptionManager.patientsRemaining(currentCount: patients.count)
        if remaining == .max {
            return "Unlimited"
        }
        return "\(remaining) remaining"
    }

    var currentTier: ProfessionalSubscriptionTier {
        return subscriptionManager.currentTier
    }

    // MARK: - Initialization

    init(dataManager: ProfessionalDataManager, subscriptionManager: ProfessionalSubscriptionManager) {
        self.dataManager = dataManager
        self.subscriptionManager = subscriptionManager

        // Subscribe to data manager updates
        dataManager.$patients
            .receive(on: DispatchQueue.main)
            .assign(to: &$patients)

        dataManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        dataManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
    }

    // MARK: - Actions

    func loadPatients() {
        dataManager.loadPatients()
    }

    func showAddPatient() {
        if canAddMorePatients {
            showingAddPatient = true
        } else {
            errorMessage = "You've reached your participant limit. Please upgrade your subscription."
        }
    }

    // MARK: - Remove Patient

    func confirmRemovePatient(_ patient: ProfessionalPatient) {
        patientToRemove = patient
        showingRemoveConfirmation = true
    }

    func removePatient() async {
        guard let patient = patientToRemove else { return }

        isRemoving = true
        errorMessage = nil

        do {
            try await dataManager.removePatient(patient)

            isRemoving = false
            patientToRemove = nil
            showingRemoveConfirmation = false

            Logger.shared.info("[PatientListViewModel] ✅ Patient removed successfully")

        } catch {
            isRemoving = false
            errorMessage = "Failed to remove participant: \(error.localizedDescription)"
            Logger.shared.error("[PatientListViewModel] ❌ Failed to remove patient: \(error)")
        }
    }

    func cancelRemove() {
        patientToRemove = nil
        showingRemoveConfirmation = false
    }

    func selectPatient(_ patient: ProfessionalPatient) {
        selectedPatient = patient
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshPatients() async {
        dataManager.loadPatients()
    }
}
