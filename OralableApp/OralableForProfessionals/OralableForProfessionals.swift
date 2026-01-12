//
//  OralableForProfessionals.swift
//  OralableForProfessionals
//
//  Main entry point for the Oralable professional iOS app.
//
//  Purpose:
//  Clinical tool for healthcare professionals to view and analyze
//  patient oral muscle activity data shared from consumer app.
//
//  Features:
//  - Patient list management
//  - Data import from consumer app (via CloudKit or CSV)
//  - Multi-session analysis
//  - Professional dashboard with advanced metrics
//
//  Architecture:
//  - SwiftUI with MVVM pattern
//  - ProfessionalAppDependencies for DI
//  - Subscription-gated features
//
//  Version: 1.0.0
//  Target: iOS 16.0+
//

import SwiftUI
import AuthenticationServices

@main
struct OralableForProfessionals: App {
    @StateObject private var dependencies: ProfessionalAppDependencies
    @StateObject private var designSystem = DesignSystem()

    init() {
        let deps = ProfessionalAppDependencies()
        _dependencies = StateObject(wrappedValue: deps)
    }

    var body: some Scene {
        WindowGroup {
            ProfessionalRootView()
                .withProfessionalDependencies(dependencies)
                .environmentObject(designSystem)
        }
    }
}

struct ProfessionalRootView: View {
    @EnvironmentObject var authenticationManager: ProfessionalAuthenticationManager

    var body: some View {
        Group {
            if authenticationManager.isAuthenticated {
                ProfessionalMainTabView()
            } else {
                ProfessionalOnboardingView()
            }
        }
    }
}

struct ProfessionalMainTabView: View {
    @EnvironmentObject var dependencies: ProfessionalAppDependencies

    var body: some View {
        TabView {
            PatientListView()
                .tabItem {
                    Label("Participants", systemImage: "person.2.fill")
                }
                .tag(0)

            ProfessionalSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .accentColor(.black)
    }
}

struct ProfessionalOnboardingView: View {
    @EnvironmentObject var authenticationManager: ProfessionalAuthenticationManager
    @EnvironmentObject var designSystem: DesignSystem

    private let onboardingPages = [
        ProfessionalOnboardingPage(
            icon: "person.2.fill",
            title: "Manage Your Participants",
            description: "Access and monitor oral wellness data from your participants in one secure location",
            color: .black
        ),
        ProfessionalOnboardingPage(
            icon: "chart.bar.fill",
            title: "Track Progress",
            description: "View detailed muscle activity analytics and trends to provide better wellness recommendations",
            color: .black
        ),
        ProfessionalOnboardingPage(
            icon: "lock.shield.fill",
            title: "Secure & Private",
            description: "HIPAA-compliant data sharing with end-to-end encryption",
            color: .black
        )
    ]

    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "stethoscope")
                .font(.system(size: 80))
                .foregroundColor(.black)
                .padding(.top, 60)
                .padding(.bottom, 40)

            Text("Oralable for Professionals")
                .font(designSystem.typography.h2)
                .padding(.bottom, 40)

            TabView(selection: $currentPage) {
                ForEach(0..<onboardingPages.count, id: \.self) { index in
                    ProfessionalOnboardingPageView(page: onboardingPages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 400)

            Spacer()

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: authenticationManager.handleSignIn
            )
            .frame(height: 50)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .signInWithAppleButtonStyle(.black)

            if let errorMessage = authenticationManager.authenticationError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            VStack(spacing: 8) {
                Text("For healthcare professionals only")
                    .font(designSystem.typography.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Link("Privacy Policy", destination: URL(string: "https://oralable.com/professional/privacy")!)
                    Text("•")
                    Link("Terms of Service", destination: URL(string: "https://oralable.com/professional/terms")!)
                }
                .font(designSystem.typography.caption)
                .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct ProfessionalOnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct ProfessionalOnboardingPageView: View {
    let page: ProfessionalOnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundColor(page.color)

            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.system(size: 17))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
