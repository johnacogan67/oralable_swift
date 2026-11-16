//
//  OnboardingView.swift
//  OralableApp
//
//  Welcome and onboarding flow for new users.
//
//  Pages:
//  - Welcome: App introduction with tagline "Word of mouth"
//  - Features: Key capabilities overview
//  - Sign In: Apple ID authentication
//
//  Features:
//  - Page indicator dots
//  - Swipe navigation between pages
//  - Sign in with Apple button
//  - Skip option to explore without account
//
//  Updated: December 13, 2025 - New tagline and broader description
//

import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var authenticationManager: AuthenticationManager
    @State private var currentPage = 0

    private let onboardingPages = [
        OnboardingPage(
            icon: nil,
            tagline: "Word of mouth",
            title: "One night on the temple",
            description: "Charge on the Oralable case. Pad or tape on the temple for one night. Heart rate and blood oxygen. Wellness — not a diagnosis.",
            color: .black
        ),
        OnboardingPage(
            icon: "heart.fill",
            tagline: nil,
            title: "Integrate with Apple Health",
            description: "When you allow it, Oralable can save heart rate and blood oxygen samples to Apple Health.",
            color: .black
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            tagline: nil,
            title: "See last night",
            description: "Morning view: wear hours, heart rate, blood oxygen, and a state map of the night.",
            color: .black
        ),
        OnboardingPage(
            icon: "square.and.arrow.up",
            tagline: nil,
            title: "Share the night report",
            description: "Export a PDF and full-night CSV for the clinic. This build does not share with a dentist app.",
            color: .black
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            Image("OralableLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: designSystem.cornerRadius.xl))
                .padding(.top, designSystem.spacing.xxl + designSystem.spacing.buttonPadding)
                .padding(.bottom, designSystem.spacing.xl + designSystem.spacing.sm)

            // Paging content
            TabView(selection: $currentPage) {
                ForEach(0..<onboardingPages.count, id: \.self) { index in
                    OnboardingPageView(page: onboardingPages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 400)

            Spacer()

            // Sign In with Apple Button - Direct, no intermediate screen
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    handleSignInResult(result)
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .frame(maxWidth: 375)
            .cornerRadius(designSystem.cornerRadius.large)
            .padding(.horizontal, designSystem.spacing.lg)
            .padding(.bottom, designSystem.spacing.screenPadding)

            // Footer
            VStack(spacing: designSystem.spacing.sm) {
                Text("Requires Oralable device")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)

                HStack(spacing: designSystem.spacing.buttonPadding) {
                    Link("Privacy Policy", destination: URL(string: "https://oralable.com/privacy")!)
                    Text("•")
                    Link("Terms of Service", destination: URL(string: "https://oralable.com/terms")!)
                }
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
            }
            .padding(.bottom, designSystem.spacing.xl + designSystem.spacing.sm)
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                authenticationManager.handleSignIn(with: appleIDCredential)
                Logger.shared.info("🔐 Apple Sign In successful - transitioning to main app")
            }
        case .failure(let error):
            Logger.shared.error("🔐 Apple Sign In failed: \(error.localizedDescription)")
        }
    }
}

struct OnboardingPage {
    let icon: String?  // Optional - nil when using tagline
    let tagline: String?  // Optional - shown instead of icon on first page
    let title: String
    let description: String
    let color: Color
}

struct OnboardingPageView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: designSystem.spacing.lg) {
            // Show tagline OR icon (tagline takes precedence)
            if let tagline = page.tagline {
                Text(tagline)
                    .font(designSystem.typography.h3)
                    .fontWeight(.medium)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .italic()
                    .frame(height: 80)  // Match icon height for consistency
            } else if let icon = page.icon {
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundColor(page.color)
            }

            Text(page.title)
                .font(designSystem.typography.largeTitle)
                .foregroundColor(designSystem.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, designSystem.spacing.xl + designSystem.spacing.sm)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(DesignSystem())
        .environmentObject(AuthenticationManager())
}
