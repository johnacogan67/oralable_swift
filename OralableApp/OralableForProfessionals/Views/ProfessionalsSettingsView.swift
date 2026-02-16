//
//  ProfessionalSettingsView.swift
//  OralableForProfessionals
//
//  Apple style settings - matches OralableApp
//  Updated with FeatureFlags and Developer Settings access
//

import SwiftUI

struct ProfessionalSettingsView: View {
    @EnvironmentObject var authenticationManager: ProfessionalAuthenticationManager
    @EnvironmentObject var subscriptionManager: ProfessionalSubscriptionManager
    @EnvironmentObject var dataManager: ProfessionalDataManager
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject private var featureFlags = FeatureFlags.shared

    @State private var showingSignOutConfirmation = false
    @State private var versionTapCount = 0
    @State private var showDeveloperSettings = false

    // Account deletion states
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                // Demo Mode Section - ALWAYS VISIBLE
                Section {
                    Toggle("Demo Mode", isOn: $featureFlags.demoModeEnabled)

                    if featureFlags.demoModeEnabled {
                        Text("Shows a sample participant with 3 recorded sessions. No imported data required.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Enable to explore the app with sample participant data.")
                }

                Section {
                    accountRow
                } header: {
                    Text("Account")
                }

                // Subscription section (feature flagged)
                if featureFlags.showSubscription {
                    Section {
                        subscriptionRow

                        if subscriptionManager.currentTier != .practice {
                            NavigationLink(destination: UpgradePromptView()) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Upgrade Plan")
                                }
                            }
                        }
                    } header: {
                        Text("Subscription")
                    }
                }

                Section {
                    Link(destination: URL(string: "https://oralable.com/help")!) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                            Text("Help & Support")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://oralable.com/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.blue)
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://oralable.com/terms")!) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                            Text("Terms of Service")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Support")
                }

                Section {
                    // Version row with hidden developer access (7 taps)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 7 {
                            showDeveloperSettings = true
                            versionTapCount = 0
                        }
                        // Reset tap count after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            versionTapCount = 0
                        }
                    }
                } header: {
                    Text("App")
                }

                // Sign Out Section
                Section {
                    Button(action: {
                        showingSignOutConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }

                // Delete Account Section (Apple Requirement)
                Section {
                    Button(action: {
                        showDeleteAccountAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete Account")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("This will permanently delete your account and all associated data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            // Sign Out Confirmation
            .confirmationDialog(
                "Sign Out",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    authenticationManager.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            // Delete Account - First Confirmation
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } message: {
                Text("This will permanently delete your account, all participant connections, and data. This action cannot be undone.")
            }
            // Delete Account - Final Confirmation
            .alert("Are You Absolutely Sure?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete My Account", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("All your data including participant connections and account information will be permanently deleted. You will need to create a new account to use the app again.")
            }
            // Delete Error Alert
            .alert("Deletion Error", isPresented: .constant(deleteError != nil)) {
                Button("OK") { deleteError = nil }
            } message: {
                if let error = deleteError {
                    Text(error)
                }
            }
            .sheet(isPresented: $showDeveloperSettings) {
                NavigationStack {
                    DeveloperSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showDeveloperSettings = false
                                }
                            }
                        }
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
    }

    // MARK: - Account Deletion

    private func deleteAccount() {
        isDeleting = true

        Task {
            do {
                // Delete CloudKit data first
                try await dataManager.deleteAllUserData()

                // Delete local data and sign out
                await authenticationManager.deleteAccount()

                // Reset feature flags
                FeatureFlags.shared.resetToDefaults()

                await MainActor.run {
                    isDeleting = false
                    // Auth state change will trigger return to welcome screen
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }

    private var accountRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(authenticationManager.userFullName ?? "Professional")
                    .font(.headline)

                Text(authenticationManager.userEmail ?? "Signed in with Apple")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var subscriptionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Plan")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(subscriptionManager.currentTier.displayName)
                    .font(.headline)
            }

            Spacer()

            Text("\(dataManager.patients.count)/\(subscriptionManager.currentTier.maxPatients)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
