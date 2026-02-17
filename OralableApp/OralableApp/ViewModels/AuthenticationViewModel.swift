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
import Combine

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

    // Subscription state synced from SubscriptionManager
    @Published private(set) var currentSubscriptionTier: SubscriptionTier = .basic
    @Published private(set) var isPaidSubscriber: Bool = false
    @Published private(set) var subscriptionExpiryDate: Date? = nil

    private let authenticationManager: AuthenticationManager
    private let subscriptionManager: SubscriptionManager
    private var memberSinceDate: Date = Date()
    private var cancellables = Set<AnyCancellable>()

    init(authenticationManager: AuthenticationManager,
         subscriptionManager: SubscriptionManager) {
        self.authenticationManager = authenticationManager
        self.subscriptionManager = subscriptionManager
        syncState()
        observeSubscriptionChanges()
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
        if isPaidSubscriber {
            if subscriptionManager.hasExpired {
                return "Expired"
            } else if subscriptionManager.isExpiringSoon {
                return "Expiring Soon"
            }
            return "Active"
        }
        return "Active" // Basic/Free tier is always "Active"
    }

    var subscriptionPlan: String {
        return currentSubscriptionTier.displayName
    }

    var hasSubscription: Bool {
        return isPaidSubscriber
    }

    var subscriptionExpiryText: String {
        guard let expiryDate = subscriptionExpiryDate else {
            return isPaidSubscriber ? "Unknown" : "N/A"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: expiryDate)
    }

    // MARK: - State Management

    func syncState() {
        isAuthenticated = authenticationManager.isAuthenticated
        userFullName = authenticationManager.userFullName
        userGivenName = authenticationManager.userGivenName
        userFamilyName = authenticationManager.userFamilyName
        userEmail = authenticationManager.userEmail
        userID = authenticationManager.userID
        syncSubscriptionState()
    }

    private func syncSubscriptionState() {
        currentSubscriptionTier = subscriptionManager.currentTier
        isPaidSubscriber = subscriptionManager.isPaidSubscriber
        subscriptionExpiryDate = subscriptionManager.subscriptionExpiryDate
    }

    func checkAuthenticationState() {
        syncState()
    }

    func refreshSubscription() {
        Task {
            await subscriptionManager.updateSubscriptionStatus()
            syncSubscriptionState()
        }
    }

    // MARK: - Subscription Observation

    private func observeSubscriptionChanges() {
        subscriptionManager.currentTierPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tier in
                self?.currentSubscriptionTier = tier
            }
            .store(in: &cancellables)

        subscriptionManager.isPaidSubscriberPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPaid in
                self?.isPaidSubscriber = isPaid
            }
            .store(in: &cancellables)

        subscriptionManager.$subscriptionExpiryDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expiryDate in
                self?.subscriptionExpiryDate = expiryDate
            }
            .store(in: &cancellables)
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
        print("--- Subscription ---")
        print("Tier: \(currentSubscriptionTier.displayName)")
        print("Paid Subscriber: \(isPaidSubscriber)")
        print("Status: \(subscriptionStatus)")
        print("Expiry: \(subscriptionExpiryText)")
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
