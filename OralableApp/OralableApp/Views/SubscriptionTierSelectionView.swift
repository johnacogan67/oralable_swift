//
//  SubscriptionTierSelectionView.swift
//  OralableApp
//
//  Created: November 11, 2025
//  Subscription tier selection and purchase flow
//

import SwiftUI
import StoreKit

struct SubscriptionTierSelectionView: View {
    @StateObject private var subscriptionManager = SubscriptionManager()
    @EnvironmentObject var designSystem: DesignSystem
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: Product?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showRestoreSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: designSystem.spacing.xl) {
                    // Header
                    headerSection

                    // Current Plan Status
                    currentPlanSection

                    // Available Plans
                    if subscriptionManager.isLoading {
                        ProgressView("Loading plans...")
                            .padding()
                    } else {
                        plansSection
                    }

                    // Features Comparison
                    featuresSection

                    // Restore Purchases
                    restorePurchasesButton

                    // Terms
                    termsSection
                }
                .padding(designSystem.spacing.lg)
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Your purchases have been restored successfully!")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: designSystem.spacing.md) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Upgrade to Premium")
                .font(designSystem.typography.h2)
                .foregroundColor(designSystem.colors.textPrimary)

            Text("Unlock advanced features and unlimited data access")
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, designSystem.spacing.xl)
    }

    // MARK: - Current Plan Section

    private var currentPlanSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Current Plan")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
                .textCase(.uppercase)

            HStack {
                Text(subscriptionManager.currentTier.displayName)
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)

                if subscriptionManager.isPaidSubscriber {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(designSystem.colors.success)
                }

                Spacer()
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.md)
    }

    // MARK: - Plans Section

    private var plansSection: some View {
        VStack(spacing: designSystem.spacing.md) {
            if let monthlyProduct = subscriptionManager.monthlyProduct {
                SubscriptionPlanCard(
                    product: monthlyProduct,
                    isSelected: selectedProduct?.id == monthlyProduct.id,
                    isPurchasing: subscriptionManager.isLoading,
                    action: {
                        Task {
                            await purchaseProduct(monthlyProduct)
                        }
                    }
                )
            }

            if let yearlyProduct = subscriptionManager.yearlyProduct {
                SubscriptionPlanCard(
                    product: yearlyProduct,
                    isSelected: selectedProduct?.id == yearlyProduct.id,
                    isPurchasing: subscriptionManager.isLoading,
                    isRecommended: true,
                    action: {
                        Task {
                            await purchaseProduct(yearlyProduct)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
            Text("Premium Features")
                .font(designSystem.typography.h3)
                .foregroundColor(designSystem.colors.textPrimary)

            VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                ForEach(SubscriptionTier.premium.features, id: \.self) { feature in
                    SubscriptionFeatureRow(feature: feature)
                }
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.md)
    }

    // MARK: - Restore Purchases Button

    private var restorePurchasesButton: some View {
        Button {
            Task {
                await restorePurchases()
            }
        } label: {
            HStack {
                if subscriptionManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(designSystem.colors.primaryBlack)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text("Restore Purchases")
            }
            .font(designSystem.typography.buttonMedium)
            .foregroundColor(designSystem.colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(designSystem.spacing.md)
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: designSystem.cornerRadius.md)
                    .stroke(designSystem.colors.border, lineWidth: 1)
            )
        }
        .disabled(subscriptionManager.isLoading)
    }

    // MARK: - Terms Section

    private var termsSection: some View {
        VStack(spacing: designSystem.spacing.sm) {
            Text("Subscriptions auto-renew unless cancelled 24 hours before the end of the current period. Manage subscriptions in App Store settings.")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: designSystem.spacing.md) {
                Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                Text("•")
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
            }
            .font(designSystem.typography.caption)
            .foregroundColor(designSystem.colors.textSecondary)
        }
        .padding(.vertical, designSystem.spacing.lg)
    }

    // MARK: - Actions

    private func purchaseProduct(_ product: Product) async {
        selectedProduct = product

        do {
            try await subscriptionManager.purchase(product)
            dismiss()
        } catch let error as SubscriptionError {
            if case .purchaseCancelled = error {
                // User cancelled, don't show error
                selectedProduct = nil
                return
            }
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        selectedProduct = nil
    }

    private func restorePurchases() async {
        do {
            try await subscriptionManager.restorePurchases()
            showRestoreSuccess = true
        } catch {
            if let subscriptionError = error as? SubscriptionError {
                errorMessage = subscriptionError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
            showError = true
        }
    }
}

// MARK: - Subscription Plan Card

struct SubscriptionPlanCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    let product: Product
    let isSelected: Bool
    let isPurchasing: Bool
    var isRecommended: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                // Header with badge
                HStack {
                    Text(product.displayName)
                        .font(designSystem.typography.headline)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Spacer()

                    if isRecommended {
                        Text("Best Value")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.primaryWhite)
                            .padding(.horizontal, designSystem.spacing.sm)
                            .padding(.vertical, designSystem.spacing.xs)
                            .background(designSystem.colors.warning)
                            .cornerRadius(designSystem.cornerRadius.sm)
                    }
                }

                // Price
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product.displayPrice)
                        .font(designSystem.typography.h2)
                        .foregroundColor(designSystem.colors.textPrimary)

                    if let period = subscriptionPeriod(for: product) {
                        Text("/ \(period)")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }

                // Description
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                // Purchase Button
                HStack {
                    Spacer()

                    if isPurchasing && isSelected {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Subscribe")
                            .font(designSystem.typography.buttonMedium)
                    }

                    Spacer()
                }
                .foregroundColor(designSystem.colors.primaryWhite)
                .padding(.vertical, designSystem.spacing.sm)
                .background(
                    isRecommended ?
                        LinearGradient(
                            colors: [designSystem.colors.warning, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [designSystem.colors.primaryBlack, designSystem.colors.primaryBlack],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .cornerRadius(designSystem.cornerRadius.sm)
            }
            .padding(designSystem.spacing.md)
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: designSystem.cornerRadius.md)
                    .stroke(
                        isRecommended ? designSystem.colors.warning : designSystem.colors.border,
                        lineWidth: isRecommended ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    private func subscriptionPeriod(for product: Product) -> String? {
        guard let subscription = product.subscription else { return nil }

        switch subscription.subscriptionPeriod.unit {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return subscription.subscriptionPeriod.value == 1 ? "month" : "\(subscription.subscriptionPeriod.value) months"
        case .year:
            return subscription.subscriptionPeriod.value == 1 ? "year" : "\(subscription.subscriptionPeriod.value) years"
        @unknown default:
            return nil
        }
    }
}

// MARK: - Subscription Feature Row

struct SubscriptionFeatureRow: View {
    @EnvironmentObject var designSystem: DesignSystem
    let feature: String

    var body: some View {
        HStack(alignment: .top, spacing: designSystem.spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(designSystem.colors.success)
                .font(.system(size: designSystem.spacing.screenPadding))

            Text(feature)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textPrimary)

            Spacer()
        }
    }
}

// MARK: - Preview

struct SubscriptionTierSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionTierSelectionView()
            .environmentObject(DesignSystem())
    }
}
