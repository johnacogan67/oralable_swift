//
//  ProfileView.swift
//  OralableApp
//
//  User profile and account management screen.
//
//  Sections:
//  - Profile Info: Name, email, member since
//  - Preferences: Notifications, Health sync, Auto export
//  - Account: Subscription status, sign out
//
//  Features:
//  - Displays Apple ID account information
//  - Links to support and user guide
//  - Sign out functionality
//

import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var sharedDataManager: SharedDataManager
    @Environment(\.dismiss) var dismiss

    @State private var showingPrivacyPolicy = false
    @State private var showingTerms = false
    @State private var showingSignOut = false
    @State private var showingDeleteAccount = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: designSystem.spacing.xl) {
                    // Profile Header (name and email only)
                    profileHeader

                    // Account Actions (sign out and delete account)
                    accountSection

                    Spacer(minLength: 50)
                }
                .padding(designSystem.spacing.lg)
            }
            .background(designSystem.colors.backgroundPrimary)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                        }
                        .foregroundColor(designSystem.colors.primaryBlack)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(designSystem.colors.textPrimary)
                }
            }
        }
        // Sign Out Alert
        .alert("Sign Out", isPresented: $showingSignOut) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        // Delete Account - First Confirmation
        .alert("Delete Account", isPresented: $showingDeleteAccount) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } message: {
            Text("This will permanently delete your account and all associated data. This action cannot be undone.")
        }
        // Delete Account - Final Confirmation
        .alert("Are You Absolutely Sure?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete My Account", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("All your data including wellness recordings, shared professional connections, and account information will be permanently deleted.")
        }
        // Delete Error Alert
        .alert("Deletion Error", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
        // Loading overlay during deletion
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Deleting account...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(UIColor.systemGray5))
                    .cornerRadius(16)
                }
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true

        Task {
            do {
                // Delete CloudKit data first
                try await sharedDataManager.deleteAllUserData()

                // Delete local data and sign out
                await authManager.deleteAccount()

                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: designSystem.spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [designSystem.colors.backgroundSecondary, designSystem.colors.backgroundTertiary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 50))
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            
            // Name
            Text(authManager.userFullName ?? "Guest")
                .font(designSystem.typography.h2)
                .foregroundColor(designSystem.colors.textPrimary)
            
            // User ID
            Text(authManager.userID ?? "Not signed in")
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
        }
        .padding(.top, designSystem.spacing.lg)
    }
    
    // MARK: - User Info Section
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("USER INFORMATION")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
                .padding(.horizontal, designSystem.spacing.xs)
            
            VStack(spacing: 0) {
                ProfileInfoRow(
                    icon: "calendar",
                    label: "Member Since",
                    value: formattedMemberDate
                )
                
                Divider()
                    .background(designSystem.colors.divider)
                
                ProfileInfoRow(
                    icon: "cpu",
                    label: "Device",
                    value: "Oralable PPG"
                )
                
                Divider()
                    .background(designSystem.colors.divider)
                
                ProfileInfoRow(
                    icon: "moon.fill",
                    label: "Sessions Recorded",
                    value: "\(sessionCount)"
                )
                
                Divider()
                    .background(designSystem.colors.divider)
                
                ProfileInfoRow(
                    icon: "clock.fill",
                    label: "Total Sleep Time",
                    value: totalSleepTime
                )
            }
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.medium)
        }
    }
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("PREFERENCES")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
                .padding(.horizontal, designSystem.spacing.xs)
            
            VStack(spacing: 0) {
                NavigationLink(destination: EmptyView()) {
                    SettingRow(
                        icon: "bell",
                        label: "Notifications",
                        value: "On"
                    )
                }
                
                Divider()
                    .background(designSystem.colors.divider)
                
                NavigationLink(destination: EmptyView()) {
                    SettingRow(
                        icon: "heart.text.square",
                        label: "Health Data",
                        value: "Synced"
                    )
                }
                
                Divider()
                    .background(designSystem.colors.divider)
                
                NavigationLink(destination: EmptyView()) {
                    SettingRow(
                        icon: "arrow.up.doc",
                        label: "Auto Export",
                        value: "Off"
                    )
                }
            }
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.medium)
        }
    }
    
    // MARK: - Account Section
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("ACCOUNT")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
                .padding(.horizontal, designSystem.spacing.xs)

            VStack(spacing: 0) {
                if authManager.isAuthenticated {
                    // Sign Out Button
                    Button(action: {
                        showingSignOut = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                                .foregroundColor(designSystem.colors.textSecondary)
                            Text("Sign Out")
                                .foregroundColor(designSystem.colors.textPrimary)
                            Spacer()
                        }
                        .padding(designSystem.spacing.md)
                    }

                    Divider()
                        .background(designSystem.colors.divider)

                    // Delete Account Button
                    Button(action: {
                        showingDeleteAccount = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete Account")
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(designSystem.spacing.md)
                    }
                } else {
                    SignInWithAppleButton(
                        onRequest: { _ in },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    authManager.handleSignIn(with: credential)
                                }
                            case .failure(let error):
                                print("Sign in failed: \(error.localizedDescription)")
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .padding(designSystem.spacing.sm)
                }
            }
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.medium)
        }
    }
    
    // MARK: - App Info Section
    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("ABOUT")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
                .padding(.horizontal, designSystem.spacing.xs)
            
            VStack(spacing: 0) {
                ProfileInfoRow(
                    icon: "info.circle",
                    label: "Version",
                    value: appVersion
                )
                
                Divider()
                    .background(designSystem.colors.divider)
                
                ProfileInfoRow(
                    icon: "hammer",
                    label: "Build",
                    value: buildNumber
                )
                
                Divider()
                    .background(designSystem.colors.divider)
                
                Button(action: { showingPrivacyPolicy = true }) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(designSystem.colors.textSecondary)
                        Text("Privacy Policy")
                            .foregroundColor(designSystem.colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(designSystem.colors.textTertiary)
                    }
                    .padding(designSystem.spacing.md)
                }
                
                Divider()
                    .background(designSystem.colors.divider)
                
                Button(action: { showingTerms = true }) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(designSystem.colors.textSecondary)
                        Text("Terms of Service")
                            .foregroundColor(designSystem.colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(designSystem.colors.textTertiary)
                    }
                    .padding(designSystem.spacing.md)
                }
            }
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.medium)
        }
    }
    
    // MARK: - Support Section
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("SUPPORT")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
                .padding(.horizontal, designSystem.spacing.xs)
            
            VStack(spacing: 0) {
                Button(action: { sendSupportEmail() }) {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(designSystem.colors.textSecondary)
                        Text("Contact Support")
                            .foregroundColor(designSystem.colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(designSystem.colors.textTertiary)
                    }
                    .padding(designSystem.spacing.md)
                }
                
                Divider()
                    .background(designSystem.colors.divider)
                
                Button(action: { openUserGuide() }) {
                    HStack {
                        Image(systemName: "book")
                            .foregroundColor(designSystem.colors.textSecondary)
                        Text("User Guide")
                            .foregroundColor(designSystem.colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(designSystem.colors.textTertiary)
                    }
                    .padding(designSystem.spacing.md)
                }
            }
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.medium)
        }
    }
    
    // MARK: - Helper Properties
    private var formattedMemberDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: Date(timeIntervalSinceNow: -30*24*60*60)) // Mock: 30 days ago
    }
    
    private var sessionCount: Int {
        UserDefaults.standard.integer(forKey: "sessionCount")
    }
    
    private var totalSleepTime: String {
        let hours = UserDefaults.standard.integer(forKey: "totalSleepHours")
        if hours == 0 { return "0 hours" }
        return "\(hours) hours"
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2025.1.15"
    }
    
    // MARK: - Helper Methods
    private func sendSupportEmail() {
        if let url = URL(string: "mailto:support@oralable.com") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openUserGuide() {
        if let url = URL(string: "https://oralable.com/guide") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Supporting Views
struct ProfileInfoRow: View {
    @EnvironmentObject var designSystem: DesignSystem
    let icon: String?
    let label: String
    let value: String
    
    init(icon: String? = nil, label: String, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .frame(width: 20)
            }
            Text(label)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
            Spacer()
            Text(value)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textPrimary)
        }
        .padding(designSystem.spacing.md)
    }
}

struct SettingRow: View {
    @EnvironmentObject var designSystem: DesignSystem
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(designSystem.colors.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textPrimary)
            Spacer()
            Text(value)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(designSystem.colors.textTertiary)
        }
        .padding(designSystem.spacing.md)
    }
}

// MARK: - Preview
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(DesignSystem())
    }
}
