//
//  AuthenticationManager.swift
//  OralableApp
//
//  Manages Apple ID authentication and user session state.
//
//  Responsibilities:
//  - Sign in with Apple integration
//  - User profile storage (Keychain)
//  - Session persistence across app launches
//  - First launch detection
//
//  Published Properties:
//  - isAuthenticated: Current auth state
//  - isFirstLaunch: First time user flag
//  - userID, userFullName, userEmail: Profile data
//
//  Storage:
//  - User credentials stored in Keychain
//  - Profile data persisted in UserDefaults
//

import Foundation
import AuthenticationServices
import Combine

@MainActor
final class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isFirstLaunch: Bool = false
    @Published var userID: String? = nil
    @Published var userFullName: String? = nil
    @Published var userGivenName: String? = nil
    @Published var userFamilyName: String? = nil
    @Published var userEmail: String? = nil
    @Published var authenticationError: String? = nil
    
    var displayName: String {
        if let fullName = userFullName, !fullName.isEmpty {
            return fullName
        }
        if let givenName = userGivenName {
            return givenName
        }
        return "User"
    }
    
    var userInitials: String {
        var initials = ""
        if let givenName = userGivenName, let first = givenName.first {
            initials.append(first)
        }
        if let familyName = userFamilyName, let first = familyName.first {
            initials.append(first)
        }
        return initials.isEmpty ? "U" : initials
    }
    
    var hasCompleteProfile: Bool {
        return userID != nil && userFullName != nil && !userFullName!.isEmpty
    }

    init() {
        isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }

        loadAuthenticationState()
    }

    // MARK: - Apple ID Sign-In

    func handleSignIn(with credential: ASAuthorizationAppleIDCredential) {
        userID = credential.user
        userGivenName = credential.fullName?.givenName
        userFamilyName = credential.fullName?.familyName
        userFullName = [userGivenName, userFamilyName].compactMap { $0 }.joined(separator: " ")
        userEmail = credential.email

        isAuthenticated = true
        authenticationError = nil
        persistAuthenticationState()

        Logger.shared.info("🔐 Signed in as \(userFullName ?? "User")")
    }

    func testAppleIDAuth() {
        userID = "test-user-id"
        userGivenName = "Test"
        userFamilyName = "User"
        userFullName = "Test User"
        isAuthenticated = true
    }

    func signOut() {
        userID = nil
        userFullName = nil
        userGivenName = nil
        userFamilyName = nil
        isAuthenticated = false
        persistAuthenticationState()
    }

    func continueAsGuest() {
        userID = "guest"
        userFullName = "Guest"
        userGivenName = "Guest"
        userFamilyName = nil
        isAuthenticated = true
    }

    // MARK: - Persistence

    private func persistAuthenticationState() {
        let defaults = UserDefaults.standard
        defaults.set(isAuthenticated, forKey: "isAuthenticated")
        defaults.set(userID, forKey: "userID")
        defaults.set(userFullName, forKey: "userFullName")
        defaults.set(userGivenName, forKey: "userGivenName")
        defaults.set(userFamilyName, forKey: "userFamilyName")
        defaults.set(userEmail, forKey: "userEmail")
    }

    private func loadAuthenticationState() {
        let defaults = UserDefaults.standard
        isAuthenticated = defaults.bool(forKey: "isAuthenticated")
        userID = defaults.string(forKey: "userID")
        userFullName = defaults.string(forKey: "userFullName")
        userGivenName = defaults.string(forKey: "userGivenName")
        userFamilyName = defaults.string(forKey: "userFamilyName")
        userEmail = defaults.string(forKey: "userEmail")
    }
    
    // MARK: - Debug Methods
    
    func debugAuthState() {
        print("=== Authentication State ===")
        print("Authenticated: \(isAuthenticated)")
        print("User ID: \(userID ?? "nil")")
        print("Full Name: \(userFullName ?? "nil")")
        print("Given Name: \(userGivenName ?? "nil")")
        print("Family Name: \(userFamilyName ?? "nil")")
        print("Email: \(userEmail ?? "nil")")
        print("Display Name: \(displayName)")
        print("Initials: \(userInitials)")
        print("Complete Profile: \(hasCompleteProfile)")
        print("===========================")
    }
    
    func refreshFromStorage() {
        loadAuthenticationState()
    }
    
    func resetAppleIDAuth() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "isAuthenticated")
        defaults.removeObject(forKey: "userID")
        defaults.removeObject(forKey: "userFullName")
        defaults.removeObject(forKey: "userGivenName")
        defaults.removeObject(forKey: "userFamilyName")
        defaults.removeObject(forKey: "userEmail")

        isAuthenticated = false
        userID = nil
        userFullName = nil
        userGivenName = nil
        userFamilyName = nil
        userEmail = nil
        authenticationError = nil

        Logger.shared.info("🔐 Authentication state reset")
    }

    // MARK: - Account Deletion (Apple App Store Requirement)

    /// Deletes all user data and signs out
    /// This is required by Apple for apps that support account creation
    func deleteAccount() async {
        Logger.shared.info("🗑️ Starting account deletion process")

        // Clear all UserDefaults
        clearAllUserDefaults()

        // Clear Keychain data
        clearKeychainData()

        // Reset authentication state
        isAuthenticated = false
        userID = nil
        userFullName = nil
        userGivenName = nil
        userFamilyName = nil
        userEmail = nil
        authenticationError = nil

        Logger.shared.info("🗑️ Account deletion completed - local data cleared")
    }

    private func clearAllUserDefaults() {
        let defaults = UserDefaults.standard

        // Authentication keys
        defaults.removeObject(forKey: "isAuthenticated")
        defaults.removeObject(forKey: "userID")
        defaults.removeObject(forKey: "userFullName")
        defaults.removeObject(forKey: "userGivenName")
        defaults.removeObject(forKey: "userFamilyName")
        defaults.removeObject(forKey: "userEmail")
        defaults.removeObject(forKey: "appleUserID")

        // App state keys
        defaults.removeObject(forKey: "hasLaunchedBefore")
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "sessionCount")
        defaults.removeObject(forKey: "totalSleepHours")

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

        Logger.shared.info("🗑️ UserDefaults cleared")
    }

    private func clearKeychainData() {
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

        Logger.shared.info("🗑️ Keychain data cleared")
    }
}
