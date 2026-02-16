import SwiftUI
import AuthenticationServices

struct AppleIDDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthenticationManager()
    @State private var credentialStateText: String = "Unknown"
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Current State") {
                    DebugRow(title: "Authenticated", value: authManager.isAuthenticated ? "Yes" : "No")
                    DebugRow(title: "User ID", value: authManager.userID ?? "nil")
                    DebugRow(title: "Full Name", value: authManager.userFullName ?? "nil")
                    DebugRow(title: "Email", value: authManager.userEmail ?? "nil")
                    DebugRow(title: "Display Name", value: authManager.displayName)
                    DebugRow(title: "Initials", value: authManager.userInitials)
                    DebugRow(title: "Complete Profile", value: authManager.hasCompleteProfile ? "Yes" : "No")
                }

                Section("Credential State") {
                    HStack {
                        Text("AppleID Credential")
                        Spacer()
                        Text(credentialStateText)
                            .foregroundColor(.secondary)
                    }
                    Button {
                        checkCredentialState()
                    } label: {
                        Label("Check Credential State", systemImage: "person.badge.key")
                    }
                }

                Section("Actions") {
                    Button {
                        authManager.debugAuthState()
                        alert("Auth state printed to console.")
                    } label: {
                        Label("Debug Auth State (Console)", systemImage: "terminal")
                    }

                    Button {
                        authManager.refreshFromStorage()
                        alert("Refreshed from UserDefaults.")
                    } label: {
                        Label("Refresh From Storage", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        authManager.resetAppleIDAuth()
                        alert("Authentication reset. You may need to remove the app from Apple ID > Apps Using Apple ID.")
                    } label: {
                        Label("Reset Apple ID Auth", systemImage: "trash")
                    }
                }

                if let error = authManager.authenticationError {
                    Section("Last Error") {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Apple ID Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                updateCredentialStateLabel(.notFound)
            }
            .alert("Info", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { showingAlert = false }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func checkCredentialState() {
        guard let userID = authManager.userID else {
            updateCredentialStateLabel(.notFound)
            alert("No stored userID. Sign in first.")
            return
        }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
            DispatchQueue.main.async {
                updateCredentialStateLabel(state)
            }
        }
    }

    private func updateCredentialStateLabel(_ state: ASAuthorizationAppleIDProvider.CredentialState) {
        switch state {
        case .authorized: credentialStateText = "Authorized"
        case .revoked: credentialStateText = "Revoked"
        case .notFound: credentialStateText = "Not Found"
        case .transferred: credentialStateText = "Transferred"
        @unknown default: credentialStateText = "Unknown"
        }
    }

    private func alert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

private struct DebugRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
