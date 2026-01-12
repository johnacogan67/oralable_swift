//
//  AuthenticationView.swift
//  OralableApp
//
//  Authentication and account management view.
//
//  Features:
//  - Sign in with Apple integration
//  - Profile details display
//  - Sign out confirmation
//
//  Uses shared AuthenticationManager passed from parent
//  to maintain consistent auth state across the app.
//
//  Fixed: November 7, 2025 - Corrected component signatures
//

import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @Environment(\.dismiss) private var dismiss

    // Use the SHARED AuthenticationManager passed from parent
    @StateObject private var viewModel: AuthenticationViewModel

    @State private var showingProfileDetails = false
    @State private var showingSignOutConfirmation = false

    init(sharedAuthManager: AuthenticationManager) {
        // Use the SHARED authManager, not a new instance
        _viewModel = StateObject(wrappedValue: AuthenticationViewModel(
            authenticationManager: sharedAuthManager
        ))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: designSystem.spacing.xl) {
                    // Profile Header
                    profileHeaderSection
                    
                    // Authentication Status
                    authenticationStatusCard
                    
                    // Profile Information (if authenticated)
                    if viewModel.isAuthenticated {
                        profileInformationSection
                        profileActionsSection

                        // Continue to Dashboard Button
                        Button(action: {
                            Logger.shared.info("🔵 Continue to Dashboard button tapped")
                            Logger.shared.info("🔵 isAuthenticated: \(viewModel.isAuthenticated)")
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Continue to Dashboard")
                            }
                            .font(designSystem.typography.buttonLarge)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(designSystem.colors.primaryBlack)
                            .cornerRadius(designSystem.cornerRadius.md)
                        }
                    } else {
                        signInSection
                    }
                    
                    // Debug Section (only in DEBUG builds)
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(designSystem.spacing.md)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.isAuthenticated {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingProfileDetails = true }) {
                            Image(systemName: "person.crop.circle")
                                .foregroundColor(designSystem.colors.textPrimary)
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.checkAuthenticationState()
        }
        .alert("Sign Out", isPresented: $showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to sign in again to access your data.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.authenticationError ?? "An authentication error occurred")
        }
        .sheet(isPresented: $showingProfileDetails) {
            ProfileDetailView(viewModel: viewModel)
        }
    }
    
    // MARK: - Profile Header Section
    
    private var profileHeaderSection: some View {
        VStack(spacing: designSystem.spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(viewModel.isAuthenticated ? Color.green : designSystem.colors.backgroundTertiary)
                    .frame(width: 100, height: 100)
                
                if viewModel.isAuthenticated {
                    Text(viewModel.userInitials)
                        .font(designSystem.typography.largeTitle)
                        .foregroundColor(designSystem.colors.primaryWhite)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 50))
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }
            
            // Greeting
            Text(viewModel.greetingText)
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)
            
            // Display Name - FIXED: Removed if let for non-optional String
            Text(viewModel.displayName)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
        }
    }
    
    // MARK: - Authentication Status Card
    
    private var authenticationStatusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                HStack {
                    Circle()
                        .fill(viewModel.isAuthenticated ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    
                    Text(viewModel.isAuthenticated ? "Signed In" : "Not Signed In")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textPrimary)
                }
                
                Text(viewModel.profileStatusText)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            
            Spacer()
            
            if viewModel.isAuthenticated {
                // Profile Completion
                CircularProgressView(
                    progress: viewModel.profileCompletionPercentage / 100,
                    lineWidth: 4,
                    size: 40
                ) {
                    Text("\(Int(viewModel.profileCompletionPercentage))%")
                        .font(designSystem.typography.caption2)
                }
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.md)
    }
    
    // MARK: - Sign In Section
    
    private var signInSection: some View {
        VStack(spacing: designSystem.spacing.lg) {
            // Benefits List
            VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                Text("Sign in to:")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)
                
                // FIXED: Changed 'subtitle' to 'description'
                FeatureRow(
                    icon: "icloud",
                    title: "Sync your data",
                    description: "Access from any device"
                )
                
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track progress",
                    description: "View historical trends"
                )
                
                FeatureRow(
                    icon: "square.and.arrow.up",
                    title: "Export reports",
                    description: "Share with healthcare providers"
                )
            }
            .padding(designSystem.spacing.md)
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.md)
            
            // Sign In Button
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    viewModel.handleSignIn(result: result)
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .cornerRadius(designSystem.cornerRadius.md)
        }
    }
    
    // MARK: - Profile Information Section
    
    private var profileInformationSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            SectionHeaderView(title: "Profile Information", icon: "person.circle")
            
            VStack(spacing: designSystem.spacing.sm) {
                // FIXED: InfoRowView expects (icon:, title:, value:, iconColor:)
                if let email = viewModel.userEmail {
                    InfoRowView(
                        icon: "envelope.fill",
                        title: "Email",
                        value: email,
                        iconColor: .blue
                    )
                }
                
                if let fullName = viewModel.userFullName {
                    InfoRowView(
                        icon: "person.fill",
                        title: "Name",
                        value: fullName,
                        iconColor: .blue
                    )
                }
                
                if let userID = viewModel.userID {
                    InfoRowView(
                        icon: "number",
                        title: "User ID",
                        value: String(userID.prefix(8)) + "...",
                        iconColor: .blue
                    )
                }
                
                InfoRowView(
                    icon: "calendar",
                    title: "Member Since",
                    value: viewModel.memberSinceText,
                    iconColor: .blue
                )
            }
            .padding(designSystem.spacing.md)
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.md)
        }
    }
    
    // MARK: - Profile Actions Section
    
    private var profileActionsSection: some View {
        VStack(spacing: designSystem.spacing.sm) {
            // FIXED: ActionCardView expects (icon:, title:, description:, iconColor:, action:)
            // Refresh Profile
            ActionCardView(
                icon: "arrow.clockwise",
                title: "Refresh Profile",
                description: "Update profile information",
                iconColor: .blue,
                action: {
                    viewModel.refreshProfile()
                }
            )
            
            // Export Data
            ActionCardView(
                icon: "square.and.arrow.up",
                title: "Export Data",
                description: "Download all your data",
                iconColor: .green,
                action: {
                    // Navigate to export view
                }
            )
            
            // Privacy Settings
            ActionCardView(
                icon: "lock.shield",
                title: "Privacy Settings",
                description: "Manage data and permissions",
                iconColor: .orange,
                action: {
                    // Navigate to privacy settings
                }
            )
            
            // Sign Out
            ActionCardView(
                icon: "arrow.right.square",
                title: "Sign Out",
                description: "Sign out of your account",
                iconColor: .red,
                action: {
                    showingSignOutConfirmation = true
                }
            )
        }
    }
    
    // MARK: - Debug Section
    
    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            SectionHeaderView(title: "Debug Information", icon: "ant.circle")
            
            VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
                Button(action: { viewModel.debugAuthState() }) {
                    HStack {
                        Image(systemName: "ant.circle")
                        Text("Print Auth State")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(designSystem.spacing.sm)
                    .background(designSystem.colors.backgroundTertiary)
                    .cornerRadius(designSystem.cornerRadius.sm)
                }
                
                Button(action: { viewModel.resetAppleIDAuth() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Reset Apple ID Auth")
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(designSystem.spacing.sm)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(designSystem.cornerRadius.sm)
                }
                
                // Auth State Info
                Text("Auth State: \(viewModel.isAuthenticated ? "Authenticated" : "Not Authenticated")")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
                
                if let userID = viewModel.userID {
                    Text("User ID: \(userID)")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }
            .padding(designSystem.spacing.md)
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.md)
        }
    }
    #endif
}

// MARK: - Profile Detail View

struct ProfileDetailView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @Environment(\.dismiss) private var dismiss
    
    let viewModel: AuthenticationViewModel
    
    var body: some View {
        NavigationView {
            List {
                Section("Account Information") {
                    // FIXED: InfoRowView with correct parameters
                    if let email = viewModel.userEmail {
                        InfoRowView(
                            icon: "envelope.fill",
                            title: "Email",
                            value: email,
                            iconColor: .blue
                        )
                    }
                    
                    if let fullName = viewModel.userFullName {
                        InfoRowView(
                            icon: "person.fill",
                            title: "Full Name",
                            value: fullName,
                            iconColor: .blue
                        )
                    }
                    
                    if let userID = viewModel.userID {
                        InfoRowView(
                            icon: "number",
                            title: "User ID",
                            value: userID,
                            iconColor: .blue
                        )
                    }
                }
                
                Section("Profile Stats") {
                    InfoRowView(
                        icon: "chart.pie.fill",
                        title: "Completion",
                        value: "\(Int(viewModel.profileCompletionPercentage))%",
                        iconColor: .green
                    )
                    InfoRowView(
                        icon: "calendar",
                        title: "Member Since",
                        value: viewModel.memberSinceText,
                        iconColor: .orange
                    )
                    InfoRowView(
                        icon: "clock.fill",
                        title: "Last Updated",
                        value: viewModel.lastUpdatedText,
                        iconColor: .purple
                    )
                }
                
                Section("Subscription") {
                    InfoRowView(
                        icon: "creditcard.fill",
                        title: "Status",
                        value: viewModel.subscriptionStatus,
                        iconColor: .green
                    )
                    InfoRowView(
                        icon: "star.fill",
                        title: "Plan",
                        value: viewModel.subscriptionPlan,
                        iconColor: .yellow
                    )
                    if viewModel.hasSubscription {
                        InfoRowView(
                            icon: "calendar.badge.clock",
                            title: "Expires",
                            value: viewModel.subscriptionExpiryText,
                            iconColor: .red
                        )
                    }
                }
                
                Section("Data & Privacy") {
                    Button(action: {
                        // Request data export
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Request Data Export")
                        }
                    }
                    
                    Button(action: {
                        // Delete account
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Account")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Profile Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Circular Progress View

struct CircularProgressView<Content: View>: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            
            content()
        }
    }
}

// MARK: - Preview

struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView(sharedAuthManager: AuthenticationManager())
            .environmentObject(DesignSystem())
    }
}
