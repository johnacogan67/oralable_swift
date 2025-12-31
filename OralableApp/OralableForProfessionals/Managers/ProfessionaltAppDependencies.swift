import Foundation
import SwiftUI
import Combine
import OralableCore

/// Central dependency injection container for the professional app
/// Manages all core services and provides factory methods for ViewModels
@MainActor
class ProfessionalAppDependencies: ObservableObject {
    // MARK: - Singleton Prevention

    private static var initializationCount = 0
    private static let maxInitializations = 2  // Allow app + cached default only

    // MARK: - Core Services

    let subscriptionManager: ProfessionalSubscriptionManager
    let dataManager: ProfessionalDataManager
    let authenticationManager: ProfessionalAuthenticationManager

    // Note: DesignSystem will be shared from patient app
    // let designSystem: DesignSystem

    // MARK: - Initialization

    init() {
        // CRITICAL: Prevent runaway initialization that causes memory crashes
        ProfessionalAppDependencies.initializationCount += 1
        let count = ProfessionalAppDependencies.initializationCount

        Logger.shared.info("[ProfessionalAppDependencies] Initializing dependency container #\(count)")

        if count > ProfessionalAppDependencies.maxInitializations {
            Logger.shared.error("[ProfessionalAppDependencies] ⚠️ CRITICAL: Too many initializations (\(count))! This will cause memory crash. Aborting.")
            fatalError("[ProfessionalAppDependencies] Runaway initialization detected - preventing memory leak crash")
        }

        // Initialize managers (no more singletons - using dependency injection)
        self.authenticationManager = ProfessionalAuthenticationManager()
        self.subscriptionManager = ProfessionalSubscriptionManager.shared  // TODO: Remove singleton
        self.dataManager = ProfessionalDataManager.shared  // TODO: Remove singleton

        Logger.shared.info("[ProfessionalAppDependencies] ✅ Dependency container initialized successfully")
    }

    // MARK: - Factory Methods

    /// Creates a PatientListViewModel with injected dependencies
    func makePatientListViewModel() -> PatientListViewModel {
        return PatientListViewModel(
            dataManager: dataManager,
            subscriptionManager: subscriptionManager
        )
    }

    /// Creates an AddPatientViewModel with injected dependencies
    func makeAddPatientViewModel() -> AddPatientViewModel {
        return AddPatientViewModel(
            dataManager: dataManager,
            subscriptionManager: subscriptionManager
        )
    }

    /// Creates a ProfessionalSettingsViewModel with injected dependencies
    func makeSettingsViewModel() -> ProfessionalSettingsViewModel {
        return ProfessionalSettingsViewModel(
            subscriptionManager: subscriptionManager,
            authenticationManager: authenticationManager
        )
    }
}

// MARK: - Testing Support

#if DEBUG
extension ProfessionalAppDependencies {
    /// Creates a mock dependencies container for testing and previews
    static func mock() -> ProfessionalAppDependencies {
        return ProfessionalAppDependencies()
    }
}
#endif

// MARK: - Environment Key

/// Environment key for accessing dependencies throughout the app
struct ProfessionalAppDependenciesKey: EnvironmentKey {
    @MainActor static var defaultValue: ProfessionalAppDependencies {
        // Use a cached singleton to prevent repeated initialization
        // This prevents memory leaks from creating new instances on every access
        _cachedDefaultDependencies
    }

    // Cached instance to prevent repeated initialization
    @MainActor private static let _cachedDefaultDependencies = ProfessionalAppDependencies()
}

extension EnvironmentValues {
    var professionalDependencies: ProfessionalAppDependencies {
        get { self[ProfessionalAppDependenciesKey.self] }
        set { self[ProfessionalAppDependenciesKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Injects all professional app dependencies into the environment
    func withProfessionalDependencies(_ dependencies: ProfessionalAppDependencies) -> some View {
        self
            .environment(\.professionalDependencies, dependencies)
            .environmentObject(dependencies)
            .environmentObject(dependencies.subscriptionManager)
            .environmentObject(dependencies.dataManager)
            .environmentObject(dependencies.authenticationManager)
    }
}
