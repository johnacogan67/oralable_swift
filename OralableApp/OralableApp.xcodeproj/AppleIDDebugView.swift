import SwiftUI
import AuthenticationServices

// MARK: - Apple ID Debug View
struct AppleIDDebugView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showResetAlert = false
    @State private var debugOutput = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current Authentication State
                    AuthStateCard()
                    
                    // Debug Actions
                    DebugActionsCard(
                        showResetAlert: $showResetAlert,
                        debugOutput: $debugOutput
                    )
                    
                    // Apple ID Information
                    AppleIDInfoCard()
                    
                    // Troubleshooting Guide
                    TroubleshootingCard()
                    
                    if !debugOutput.isEmpty {
                        // Debug Output
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Debug Output")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(debugOutput)
                                .font(.system(size: 12, family: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Apple ID Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Reset Apple ID", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                authManager.resetAppleIDAuth()
                updateDebugOutput()
            }
        } message: {
            Text("This will sign you out. To get fresh Apple ID data, you'll need to go to Settings > Apple ID > Sign-In & Security > Apps Using Apple ID, find this app, and tap 'Stop Using Apple ID', then sign in again.")
        }
        .onAppear {
            updateDebugOutput()
        }
    }
    
    private func updateDebugOutput() {
        // Capture debug output
        var output = ""
        
        // Redirect print statements to capture debug info
        let originalPrint = print
        
        // Create a custom print function that captures output
        func customPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
            let message = items.map { "\($0)" }.joined(separator: separator)
            output += message + terminator
            originalPrint(items, separator: separator, terminator: terminator)
        }
        
        // Run debug with custom print
        authManager.debugAuthState()
        
        DispatchQueue.main.async {
            self.debugOutput = output.isEmpty ? "No debug output captured. Check console logs." : output
        }
    }
}

// MARK: - Auth State Card
struct AuthStateCard: View {
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authentication State")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                StateRow(label: "Authenticated", value: authManager.isAuthenticated ? "✅ Yes" : "❌ No", 
                        color: authManager.isAuthenticated ? .green : .red)
                
                StateRow(label: "User ID", value: authManager.userID?.prefix(8).appending("...") ?? "None", 
                        color: authManager.userID != nil ? .green : .gray)
                
                StateRow(label: "Full Name", value: authManager.userFullName ?? "None", 
                        color: authManager.userFullName != nil ? .green : .orange)
                
                StateRow(label: "Email", value: authManager.userEmail ?? "None", 
                        color: authManager.userEmail != nil ? .green : .orange)
                
                StateRow(label: "Display Name", value: authManager.displayName, 
                        color: .blue)
                
                StateRow(label: "Initials", value: authManager.userInitials, 
                        color: .blue)
                
                StateRow(label: "Complete Profile", value: authManager.hasCompleteProfile ? "✅ Yes" : "⚠️ No", 
                        color: authManager.hasCompleteProfile ? .green : .orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StateRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Debug Actions Card
struct DebugActionsCard: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @Binding var showResetAlert: Bool
    @Binding var debugOutput: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                Button(action: {
                    authManager.debugAuthState()
                    // Update debug output capture would go here
                }) {
                    ActionButtonContent(icon: "info.circle", text: "Print Debug Info", color: .blue)
                }
                
                Button(action: {
                    authManager.refreshFromStorage()
                }) {
                    ActionButtonContent(icon: "arrow.clockwise", text: "Refresh from Storage", color: .green)
                }
                
                Button(action: {
                    showResetAlert = true
                }) {
                    ActionButtonContent(icon: "trash", text: "Reset Apple ID Auth", color: .red)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActionButtonContent: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Apple ID Info Card
struct AppleIDInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple ID Behavior")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoPoint(
                    icon: "1.circle.fill", 
                    text: "First Sign-In: Provides name and email",
                    color: .green
                )
                
                InfoPoint(
                    icon: "2.circle.fill", 
                    text: "Subsequent Sign-Ins: Only provides User ID",
                    color: .orange
                )
                
                InfoPoint(
                    icon: "photo.circle", 
                    text: "Profile Pictures: Never provided by Apple",
                    color: .red
                )
                
                InfoPoint(
                    icon: "lock.circle.fill", 
                    text: "Privacy: Data is cached locally after first sign-in",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct InfoPoint: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Troubleshooting Card
struct TroubleshootingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Troubleshooting")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                TroubleshootingStep(
                    number: "1",
                    title: "Name/Email Missing?",
                    description: "Go to Settings > Apple ID > Sign-In & Security > Apps Using Apple ID"
                )
                
                TroubleshootingStep(
                    number: "2",
                    title: "Reset App Authorization",
                    description: "Find this app and tap 'Stop Using Apple ID'"
                )
                
                TroubleshootingStep(
                    number: "3",
                    title: "Sign In Again",
                    description: "Sign in again to provide fresh name and email data"
                )
                
                TroubleshootingStep(
                    number: "4",
                    title: "Profile Pictures",
                    description: "Apple never provides profile pictures. The app uses initials instead."
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct TroubleshootingStep: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    AppleIDDebugView()
}