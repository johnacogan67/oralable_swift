import SwiftUI

// MARK: - Share with Professional Component
struct ShareWithProfessionalSection: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var sharedDataManager: SharedDataManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var shareCode: String = ""
    @State private var showShareCode = false
    @State private var showUpgradePrompt = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            // Header
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(designSystem.colors.primaryBlack)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Share with Professional")
                        .font(designSystem.typography.headline)

                    Text("Allow your healthcare professional to view your data")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                Spacer()
            }

            // Generate Share Code Button
            Button(action: {
                if subscriptionManager.currentTier == .basic && sharedDataManager.sharedProfessionals.count >= 1 {
                    showUpgradePrompt = true
                } else {
                    generateShareCode()
                }
            }) {
                HStack {
                    Image(systemName: "qrcode")
                    Text("Generate Share Code")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(designSystem.colors.primaryBlack)
                .foregroundColor(designSystem.colors.primaryWhite)
                .cornerRadius(designSystem.cornerRadius.large)
            }

            // Show generated code
            if showShareCode {
                VStack(spacing: 12) {
                    Text("Share Code:")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)

                    Text(shareCode)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(designSystem.colors.primaryBlack)
                        .tracking(8)

                    Text("Code expires in 48 hours")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)

                    Button("Copy Code") {
                        UIPasteboard.general.string = shareCode
                    }
                    .font(designSystem.typography.buttonSmall)
                }
                .padding()
                .background(designSystem.colors.backgroundSecondary)
                .cornerRadius(designSystem.cornerRadius.large)
            }

            // List of shared professionals
            if !sharedDataManager.sharedProfessionals.isEmpty {
                Divider()
                    .padding(.vertical, designSystem.spacing.sm)

                Text("Shared With:")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)

                ForEach(sharedDataManager.sharedProfessionals) { professional in
                    SharedProfessionalRow(professional: professional)
                }
            }

            // Tier limitation message
            if subscriptionManager.currentTier == .basic {
                HStack(spacing: designSystem.spacing.sm) {
                    Image(systemName: "info.circle")
                    Text("Basic tier: Share with 1 professional")
                        .font(designSystem.typography.caption)
                }
                .foregroundColor(designSystem.colors.textSecondary)
                .padding(.top, designSystem.spacing.sm)
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.md)
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradeToShareMoreView()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func generateShareCode() {
        Task {
            do {
                shareCode = try await sharedDataManager.createShareInvitation()
                showShareCode = true
            } catch {
                Logger.shared.error("[ShareWithProfessionalSection] Error generating share code: \(error)")
                errorMessage = "Failed to generate share code: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

struct SharedProfessionalRow: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var sharedDataManager: SharedDataManager
    let professional: SharedProfessional
    @State private var showRevokeConfirmation = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(professional.professionalName ?? "Professional")
                    .font(designSystem.typography.body)

                Text("Shared: \(professional.sharedDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            Spacer()

            Button("Revoke") {
                showRevokeConfirmation = true
            }
            .font(designSystem.typography.caption)
            .foregroundColor(designSystem.colors.error)
        }
        .padding()
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
        .alert("Revoke Access?", isPresented: $showRevokeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Revoke", role: .destructive) {
                revokeAccess()
            }
        } message: {
            Text("This professional will no longer be able to view your data.")
        }
    }

    private func revokeAccess() {
        Task {
            do {
                try await sharedDataManager.revokeAccessForProfessional(professionalID: professional.professionalID)
            } catch {
                Logger.shared.error("[SharedProfessionalRow] Error revoking access: \(error)")
            }
        }
    }
}

struct UpgradeToShareMoreView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var designSystem: DesignSystem

    var body: some View {
        NavigationStack {
            VStack(spacing: designSystem.spacing.lg) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(designSystem.colors.primaryBlack)

                Text("Share with More Providers")
                    .font(designSystem.typography.title)

                Text("Upgrade to Premium to share your data with unlimited healthcare providers.")
                    .font(designSystem.typography.body)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: designSystem.spacing.buttonPadding) {
                    ShareFeatureRow(icon: "checkmark.circle.fill", text: "Share with unlimited providers")
                    ShareFeatureRow(icon: "checkmark.circle.fill", text: "Advanced analytics")
                    ShareFeatureRow(icon: "checkmark.circle.fill", text: "Unlimited data export")
                    ShareFeatureRow(icon: "checkmark.circle.fill", text: "Priority support")
                }
                .padding()

                Button("Upgrade to Premium") {
                    dismiss()
                }
                .font(designSystem.typography.buttonLarge)
                .foregroundColor(designSystem.colors.primaryWhite)
                .frame(maxWidth: .infinity)
                .padding()
                .background(designSystem.colors.primaryBlack)
                .cornerRadius(designSystem.cornerRadius.large)
                .padding(.horizontal)

                Button("Maybe Later") {
                    dismiss()
                }
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ShareFeatureRow: View {
    @EnvironmentObject var designSystem: DesignSystem
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: designSystem.spacing.buttonPadding) {
            Image(systemName: icon)
                .foregroundColor(designSystem.colors.success)
            Text(text)
                .font(designSystem.typography.body)
        }
    }
}
