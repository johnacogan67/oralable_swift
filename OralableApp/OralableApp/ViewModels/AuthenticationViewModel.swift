//
//  AuthenticationViewModel.swift
//  OralableApp
//
//  ViewModel for authentication state and user profile data.
//
//  Responsibilities:
//  - Syncs with AuthenticationManager state
//  - Exposes user profile (name, email, ID)
//  - Handles sign in/out actions
//  - Formats display name and member since date
//
//  Published Properties:
//  - isAuthenticated: Current auth state
//  - userFullName, userEmail, userID: Profile data
//  - showError, authenticationError: Error state
//
//  Delegates actual auth operations to AuthenticationManager.
//

import Foundation
import AuthenticationServices

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userFullName: String? = nil
    @Published var userGivenName: String? = nil
    @Published var userFamilyName: String? = nil
    @Published var userEmail: String? = nil
    @Published var userID: String? = nil
    @Published var showError: Bool = false
    @Published var authenticationError: String? = nil

    private let authenticationManager: AuthenticationManager
    private var memberSinceDate: Date = Date()

    init(authenticationManager: AuthenticationManager) {
        self.authenticationManager = authenticationManager
        syncState()
    }

    // MARK: - Computed Properties
    
    var displayName: String {
        if let fullName = userFullName, !fullName.isEmpty {
            return fullName
        } else if let givenName = userGivenName {
            return givenName
        } else if isAuthenticated {
            return "User"
        } else {
            return "Guest"
        }
    }
    
    var greetingText: String {
        if isAuthenticated {
            return "Welcome back!"
        } else {
            return "Welcome to Oralable"
        }
    }
    
    var userInitials: String {
        if let givenName = userGivenName?.first, let familyName = userFamilyName?.first {
            return "\(givenName)\(familyName)".uppercased()
        } else if let fullName = userFullName, !fullName.isEmpty {
            let components = fullName.split(separator: " ")
            if components.count >= 2 {
                return "\(components[0].first ?? "U")\(components[1].first ?? "U")".uppercased()
            } else {
                return String(fullName.prefix(2)).uppercased()
            }
        }
        return "U"
    }
    
    var profileStatusText: String {
        if isAuthenticated {
            return "Your profile is synced"
        } else {
            return "Sign in to sync your data"
        }
    }
    
    var profileCompletionPercentage: Double {
        guard isAuthenticated else { return 0 }
        
        var completed = 0
        let total = 5
        
        if userFullName != nil { completed += 1 }
        if userEmail != nil { completed += 1 }
        if userID != nil { completed += 1 }
        if userGivenName != nil { completed += 1 }
        if userFamilyName != nil { completed += 1 }
        
        return (Double(completed) / Double(total)) * 100
    }
    
    var memberSinceText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: memberSinceDate)
    }
    
    var lastUpdatedText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
    
    var subscriptionStatus: String {
        // TODO: Integrate with actual subscription system
        return "Active"
    }
    
    var subscriptionPlan: String {
        // TODO: Integrate with actual subscription system
        return "Free"
    }
    
    var hasSubscription: Bool {
        // TODO: Integrate with actual subscription system
        return false
    }
    
    var subscriptionExpiryText: String {
        // TODO: Integrate with actual subscription system
        return "N/A"
    }

    // MARK: - State Management
    
    func syncState() {
        isAuthenticated = authenticationManager.isAuthenticated
        userFullName = authenticationManager.userFullName
        userGivenName = authenticationManager.userGivenName
        userFamilyName = authenticationManager.userFamilyName
        userEmail = authenticationManager.userEmail
        userID = authenticationManager.userID
    }
    
    func checkAuthenticationState() {
        syncState()
    }

    // MARK: - Authentication Actions

    func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                handleAppleIDCredential(appleIDCredential)
            }
        case .failure(let error):
            authenticationError = error.localizedDescription
            showError = true
        }
    }
    
    func handleAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) {
        authenticationManager.handleSignIn(with: credential)
        syncState()
    }

    func signOut() {
        authenticationManager.signOut()
        syncState()
    }

    func continueAsGuest() {
        authenticationManager.continueAsGuest()
        syncState()
    }
    
    func refreshProfile() {
        syncState()
    }
    
    func dismissError() {
        showError = false
        authenticationError = nil
    }

    // MARK: - Debug Methods
    
    #if DEBUG
    func debugAuthState() {
        print("=== Authentication Debug State ===")
        print("Authenticated: \(isAuthenticated)")
        print("User ID: \(userID ?? "nil")")
        print("Full Name: \(userFullName ?? "nil")")
        print("Given Name: \(userGivenName ?? "nil")")
        print("Family Name: \(userFamilyName ?? "nil")")
        print("Email: \(userEmail ?? "nil")")
        print("Profile Completion: \(profileCompletionPercentage)%")
        print("================================")
    }
    
    func testAppleIDAuth() {
        authenticationManager.testAppleIDAuth()
        syncState()
    }
    
    func resetAppleIDAuth() {
        authenticationManager.signOut()
        syncState()
        print("Apple ID authentication has been reset")
    }
    #endif
}
