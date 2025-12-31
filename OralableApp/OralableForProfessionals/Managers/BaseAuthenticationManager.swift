//
//  BaseAuthenticationManager.swift
//  OralableApp
//
//  Created: November 19, 2025
//  Purpose: Base class containing shared authentication logic for Apple Sign In
//

import Foundation
import AuthenticationServices
import SwiftUI
import Combine
import OralableCore

/// Base authentication manager with common Apple Sign In functionality
/// Subclasses should override `keychainKeys` to use app-specific storage keys
@MainActor
class BaseAuthenticationManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var userID: String?
    @Published var userEmail: String?
    @Published var userFullName: String?
    @Published var authenticationError: String?

    // MARK: - Keychain Configuration

    /// Override this in subclasses to provide app-specific keychain keys
    /// Returns tuple of (userIDKey, emailKey, fullNameKey)
    var keychainKeys: (userID: String, email: String, fullName: String) {
        // Default keys for patient app (can be overridden)
        return (
            "com.oralable.mam.userID",
            "com.oralable.mam.userEmail",
            "com.oralable.mam.userFullName"
        )
    }

    // MARK: - Profile UI Properties

    /// Get user initials for avatar display
    var userInitials: String {
        guard let fullName = userFullName, !fullName.isEmpty else {
            return "U" // Default to "U" for User
        }

        let components = fullName.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }

        if initials.count >= 2 {
            return "\(initials[0])\(initials[1])"
        } else if let first = initials.first {
            return first
        } else {
            return "U"
        }
    }

    /// Get display name with fallback
    var displayName: String {
        if let fullName = userFullName, !fullName.isEmpty {
            return fullName
        } else if let email = userEmail {
            // Extract name part from email if full name not available
            let emailPrefix = String(email.prefix(while: { $0 != "@" }))
            return emailPrefix.replacingOccurrences(of: ".", with: " ").capitalized
        } else {
            return "User"
        }
    }

    /// Check if we have complete profile information
    var hasCompleteProfile: Bool {
        return userID != nil && (userFullName != nil || userEmail != nil)
    }

    // MARK: - Initialization

    override init() {
        super.init()
        checkAuthenticationState()
    }

    // MARK: - Authentication State Management

    /// Check if user is already authenticated by loading from storage
    func checkAuthenticationState() {
        let auth = retrieveUserAuthentication()
        if let userID = auth.userID {
            self.userID = userID
            self.userEmail = auth.email
            self.userFullName = auth.fullName
            self.isAuthenticated = true
        }
    }

    // MARK: - Apple Sign In Handling

    /// Handle Apple Sign In authorization result
    /// - Parameter result: The authorization result from Apple
    func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                processAppleIDCredential(appleIDCredential)
            }

        case .failure(let error):
            Task { @MainActor in
                Logger.shared.error("Apple ID Sign In failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.authenticationError = error.localizedDescription
                self.isAuthenticated = false
            }
        }
    }

    /// Process Apple ID credential and save authentication data
    /// - Parameter credential: The Apple ID credential from successful sign in
    private func processAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let userID = credential.user
        let email = credential.email
        let fullName = credential.fullName

        Task { @MainActor in
            Logger.shared.info("Apple ID Sign In - User ID: \(userID)")
            Logger.shared.debug("Email: \(email?.description ?? "nil"), Full Name: \(fullName?.description ?? "nil")")
        }

        // Prepare values to save
        var emailToSave: String?
        var fullNameToSave: String?

        // Handle email (only provided on first sign-in)
        if let email = email, !email.isEmpty {
            emailToSave = email
            Task { @MainActor in
                Logger.shared.info("Email received: \(email)")
            }
        } else {
            // Load existing email from storage for subsequent sign-ins
            emailToSave = retrieveFromKeychain(key: keychainKeys.email)
            Task { @MainActor in
                Logger.shared.debug("Email not provided, loading from storage")
            }
        }

        // Handle full name (only provided on first sign-in)
        if let fullName = fullName,
           let givenName = fullName.givenName,
           !givenName.isEmpty {

            let displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            fullNameToSave = displayName
            Task { @MainActor in
                Logger.shared.info("Full name received: \(displayName)")
            }
        } else {
            // Load existing full name from storage for subsequent sign-ins
            fullNameToSave = retrieveFromKeychain(key: keychainKeys.fullName)
            Task { @MainActor in
                Logger.shared.debug("Full name not provided, loading from storage")
            }
        }

        // Save to storage
        saveUserAuthentication(userID: userID, email: emailToSave, fullName: fullNameToSave)

        // Update published properties
        DispatchQueue.main.async {
            self.userID = userID
            self.userEmail = emailToSave
            self.userFullName = fullNameToSave
            self.isAuthenticated = true
            self.authenticationError = nil

            Task { @MainActor in
                Logger.shared.info("Authentication successful - Email: \(self.userEmail ?? "nil"), Name: \(self.userFullName ?? "nil")")
            }
        }
    }

    // MARK: - Sign Out

    /// Sign out the current user and clear all stored data
    func signOut() {
        deleteAllAuthenticationData()

        DispatchQueue.main.async {
            self.userID = nil
            self.userEmail = nil
            self.userFullName = nil
            self.isAuthenticated = false
        }
    }

    // MARK: - Storage Methods (can be overridden for different storage backends)

    /// Save user authentication data to storage
    /// - Parameters:
    ///   - userID: The user's unique identifier
    ///   - email: The user's email (optional)
    ///   - fullName: The user's full name (optional)
    func saveUserAuthentication(userID: String, email: String?, fullName: String?) {
        saveToKeychain(value: userID, key: keychainKeys.userID)

        if let email = email {
            saveToKeychain(value: email, key: keychainKeys.email)
        }

        if let fullName = fullName {
            saveToKeychain(value: fullName, key: keychainKeys.fullName)
        }

        Logger.shared.info("User authentication data saved securely")
    }

    /// Retrieve user authentication data from storage
    /// - Returns: Tuple containing userID, email, and fullName (all optional)
    func retrieveUserAuthentication() -> (userID: String?, email: String?, fullName: String?) {
        let userID = retrieveFromKeychain(key: keychainKeys.userID)
        let email = retrieveFromKeychain(key: keychainKeys.email)
        let fullName = retrieveFromKeychain(key: keychainKeys.fullName)

        return (userID, email, fullName)
    }

    /// Delete all authentication data from storage
    func deleteAllAuthenticationData() {
        deleteFromKeychain(key: keychainKeys.userID)
        deleteFromKeychain(key: keychainKeys.email)
        deleteFromKeychain(key: keychainKeys.fullName)
        Logger.shared.info("All authentication data deleted")
    }

    // MARK: - Keychain Helpers

    /// Save a string value to Keychain
    /// - Parameters:
    ///   - value: The string to save
    ///   - key: The keychain key
    /// - Returns: True if successful
    @discardableResult
    private func saveToKeychain(value: String, key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            Logger.shared.error("Failed to convert string to data for key: \(key)")
            return false
        }

        // Delete existing item first
        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            return true
        } else {
            Logger.shared.error("Failed to save to keychain for key: \(key), status: \(status)")
            return false
        }
    }

    /// Retrieve a string value from Keychain
    /// - Parameter key: The keychain key
    /// - Returns: The stored string, or nil if not found
    private func retrieveFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete a value from Keychain
    /// - Parameter key: The keychain key
    /// - Returns: True if successful or item doesn't exist
    @discardableResult
    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Debug and Reset Methods

    /// Debug method to print current authentication state
    func debugAuthState() {
        Task { @MainActor in
            Logger.shared.debug("Authentication State - isAuthenticated: \(self.isAuthenticated), userID: \(self.userID ?? "nil")")
            Logger.shared.debug("User Info - Email: \(self.userEmail ?? "nil"), Name: \(self.userFullName ?? "nil")")
            Logger.shared.debug("Display - Initials: \(self.userInitials), DisplayName: \(self.displayName), Complete: \(self.hasCompleteProfile)")

            let auth = retrieveUserAuthentication()
            Logger.shared.debug("Storage - userID: \(auth.userID ?? "nil"), email: \(auth.email ?? "nil"), name: \(auth.fullName ?? "nil")")
        }
    }

    /// Reset Apple ID authentication (for testing - forces fresh sign-in)
    func resetAppleIDAuth() {
        Task { @MainActor in
            Logger.shared.info("Resetting Apple ID authentication")
        }
        signOut()
        // Note: To get fresh Apple ID data, user needs to:
        // 1. Go to Settings > Apple ID > Sign-In & Security > Apps Using Apple ID
        // 2. Find your app and tap "Stop Using Apple ID"
        // 3. Then sign in again to get fresh data
    }

    /// Force refresh from storage (useful after app updates)
    func refreshFromStorage() {
        Task { @MainActor in
            Logger.shared.info("Refreshing authentication state from storage")
        }

        DispatchQueue.main.async {
            let auth = self.retrieveUserAuthentication()
            self.userID = auth.userID
            self.userEmail = auth.email
            self.userFullName = auth.fullName
            self.isAuthenticated = self.userID != nil

            Task { @MainActor in
                Logger.shared.info("Refreshed authentication state successfully")
            }
            self.debugAuthState()
        }
    }
}
