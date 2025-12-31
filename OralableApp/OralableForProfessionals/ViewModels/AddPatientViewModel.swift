import Foundation
import Combine
import OralableCore

@MainActor
class AddPatientViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var shareCode: String = ""
    @Published var isAdding: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var shouldDismiss: Bool = false

    // MARK: - Dependencies

    private let dataManager: ProfessionalDataManager
    private let subscriptionManager: ProfessionalSubscriptionManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var isShareCodeValid: Bool {
        return shareCode.count == 6 && Int(shareCode) != nil
    }

    var canAddPatient: Bool {
        return !isAdding && isShareCodeValid
    }

    // MARK: - Initialization

    init(dataManager: ProfessionalDataManager, subscriptionManager: ProfessionalSubscriptionManager) {
        self.dataManager = dataManager
        self.subscriptionManager = subscriptionManager

        // Subscribe to data manager updates
        dataManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAdding)

        dataManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)

        dataManager.$successMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] success in
                if success != nil {
                    self?.successMessage = success
                    // Auto-dismiss after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.shouldDismiss = true
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func addPatient() {
        Logger.shared.info("[AddPatientViewModel] addPatient called, shareCode: \(shareCode)")
        Logger.shared.info("[AddPatientViewModel] canAddPatient: \(canAddPatient)")
        guard canAddPatient else {
            Logger.shared.warning("[AddPatientViewModel] canAddPatient is false, returning")
            return
        }

        // Check subscription limits
        let currentPatientCount = dataManager.patients.count
        Logger.shared.info("[AddPatientViewModel] Current patient count: \(currentPatientCount)")
        if !subscriptionManager.canAddMorePatients(currentCount: currentPatientCount) {
            Logger.shared.warning("[AddPatientViewModel] Patient limit reached")
            errorMessage = "You've reached your participant limit. Please upgrade to add more participants."
            return
        }

        Logger.shared.info("[AddPatientViewModel] Starting CloudKit query for share code: \(shareCode)")
        Task {
            do {
                try await dataManager.addPatientWithShareCode(shareCode)
                Logger.shared.info("[AddPatientViewModel] Successfully added patient")
                shareCode = ""
            } catch {
                Logger.shared.error("[AddPatientViewModel] Error adding patient: \(error)")
                // Error is handled by subscription to dataManager.$errorMessage
            }
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    func formatShareCode(_ input: String) -> String {
        // Only allow digits, max 6 characters
        let filtered = input.filter { $0.isNumber }
        return String(filtered.prefix(6))
    }
}
