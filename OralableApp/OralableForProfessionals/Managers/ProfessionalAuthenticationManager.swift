//
//  ProfessionalAuthenticationManager.swift
//  OralableForProfessionals
//
//  Manages authentication for professional app using Sign in with Apple
//  Inherits common Apple Sign In functionality from BaseAuthenticationManager
//

import Foundation
import AuthenticationServices
import SwiftUI
import OralableCore

/// Professional app authentication manager
/// Inherits common Apple Sign In functionality from BaseAuthenticationManager
@MainActor
class ProfessionalAuthenticationManager: BaseAuthenticationManager {

    // MARK: - Professional-Specific Properties

    /// Convenience accessors for professional-specific naming
    var professionalID: String? { userID }
    var professionalName: String? { userFullName }
    var professionalEmail: String? { userEmail }

    // MARK: - Keychain Configuration Override

    /// Override to use professional-specific keychain keys
    override var keychainKeys: (userID: String, email: String, fullName: String) {
        return (
            "com.oralable.professional.userID",
            "com.oralable.professional.userEmail",
            "com.oralable.professional.userFullName"
        )
    }

    // MARK: - Initialization

    override init() {
        super.init()

        // Migrate any existing UserDefaults data to Keychain
        migrateFromUserDefaults()

        Logger.shared.info("[ProfessionalAuth] Professional authentication manager initialized")
    }

    // MARK: - Migration from UserDefaults

    /// Migrate authentication data from UserDefaults to secure Keychain storage
    private func migrateFromUserDefaults() {
        let userIDKey = "professionalAppleID"
        let nameKey = "professionalName"
        let emailKey = "professionalEmail"

        // Check if there's data in UserDefaults that needs migration
        if let oldUserID = UserDefaults.standard.string(forKey: userIDKey) {
            Logger.shared.info("[ProfessionalAuth] Migrating authentication data from UserDefaults to Keychain")

            let oldName = UserDefaults.standard.string(forKey: nameKey)
            let oldEmail = UserDefaults.standard.string(forKey: emailKey)

            // Save to keychain
            saveUserAuthentication(userID: oldUserID, email: oldEmail, fullName: oldName)

            // Update published properties
            self.userID = oldUserID
            self.userEmail = oldEmail
            self.userFullName = oldName
            self.isAuthenticated = true

            // Clear UserDefaults
            UserDefaults.standard.removeObject(forKey: userIDKey)
            UserDefaults.standard.removeObject(forKey: nameKey)
            UserDefaults.standard.removeObject(forKey: emailKey)

            Logger.shared.info("[ProfessionalAuth] Migration complete - data now securely stored in Keychain")
        }
    }

    // MARK: - Credential State Check

    /// Check if the Apple ID credential is still valid
    func checkCredentialState() async {
        guard let professionalID = professionalID else { return }

        let provider = ASAuthorizationAppleIDProvider()

        do {
            let state = try await provider.credentialState(forUserID: professionalID)

            await MainActor.run {
                switch state {
                case .authorized:
                    self.isAuthenticated = true
                    Logger.shared.info("[ProfessionalAuth] Credential state: authorized")

                case .revoked, .notFound:
                    Logger.shared.warning("[ProfessionalAuth] Credential state: revoked/not found - signing out")
                    self.signOut()

                case .transferred:
                    Logger.shared.warning("[ProfessionalAuth] Credential transferred")

                @unknown default:
                    Logger.shared.warning("[ProfessionalAuth] Unknown credential state")
                }
            }
        } catch {
            Logger.shared.error("[ProfessionalAuth] Failed to check credential state: \(error)")
        }
    }

    // MARK: - Account Deletion (Apple App Store Requirement)

    /// Deletes all user data and signs out
    /// This is required by Apple for apps that support account creation
    func deleteAccount() async {
        Logger.shared.info("[ProfessionalAuth] 🗑️ Starting account deletion process")

        // Clear all UserDefaults
        clearAllUserDefaults()

        // Clear Keychain data (includes professional-specific keys)
        clearAllKeychainData()

        // Delete all authentication data from parent class
        deleteAllAuthenticationData()

        // Reset authentication state
        isAuthenticated = false
        userID = nil
        userEmail = nil
        userFullName = nil
        authenticationError = nil

        Logger.shared.info("[ProfessionalAuth] 🗑️ Account deletion completed - local data cleared")
    }

    private func clearAllUserDefaults() {
        let defaults = UserDefaults.standard

        // Legacy authentication keys
        defaults.removeObject(forKey: "professionalAppleID")
        defaults.removeObject(forKey: "professionalName")
        defaults.removeObject(forKey: "professionalEmail")

        // App state keys
        defaults.removeObject(forKey: "hasLaunchedBefore")
        defaults.removeObject(forKey: "hasCompletedOnboarding")

        // Feature flags (reset to defaults)
        defaults.removeObject(forKey: "feature.dashboard.showMovement")
        defaults.removeObject(forKey: "feature.dashboard.showTemperature")
        defaults.removeObject(forKey: "feature.dashboard.showHeartRate")
        defaults.removeObject(forKey: "feature.dashboard.showAdvancedAnalytics")
        defaults.removeObject(forKey: "feature.settings.showSubscription")
        defaults.removeObject(forKey: "feature.showMultiParticipant")
        defaults.removeObject(forKey: "feature.showDataExport")
        defaults.removeObject(forKey: "feature.showANRComparison")

        // Sync to disk
        defaults.synchronize()

        Logger.shared.info("[ProfessionalAuth] 🗑️ UserDefaults cleared")
    }

    private func clearAllKeychainData() {
        // Clear all keychain items for this app
        let secItemClasses = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]

        for secItemClass in secItemClasses {
            let query: [String: Any] = [kSecClass as String: secItemClass]
            SecItemDelete(query as CFDictionary)
        }

        Logger.shared.info("[ProfessionalAuth] 🗑️ Keychain data cleared")
    }
}
