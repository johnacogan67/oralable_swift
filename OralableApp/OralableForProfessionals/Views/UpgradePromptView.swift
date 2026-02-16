import SwiftUI
import StoreKit

struct UpgradePromptView: View {
    @EnvironmentObject var subscriptionManager: ProfessionalSubscriptionManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedTier: ProfessionalSubscriptionTier = .professional
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.black)
                        .padding(.top, 20)

                    Text("Upgrade Your Plan")
                        .font(.title.bold())

                    Text("Unlock more features and manage more participants")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Current Plan Badge
                if subscriptionManager.currentTier != .starter {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Text("Current: \(subscriptionManager.currentTier.displayName)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)
                }

                // Tier Cards
                VStack(spacing: 16) {
                    ForEach(ProfessionalSubscriptionTier.allCases.filter { $0 != .starter }, id: \.self) { tier in
                        TierCard(
                            tier: tier,
                            isSelected: selectedTier == tier,
                            isCurrent: subscriptionManager.currentTier == tier
                        ) {
                            selectedTier = tier
                        }
                    }
                }
                .padding(.horizontal)

                // Purchase Button
                if subscriptionManager.currentTier != selectedTier {
                    VStack(spacing: 16) {
                        Button(action: {
                            Task {
                                await purchaseSelectedTier()
                            }
                        }) {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.black)
                                    .cornerRadius(12)
                            } else {
                                Text("Subscribe to \(selectedTier.displayName)")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.black)
                                    .cornerRadius(12)
                            }
                        }
                        .disabled(isPurchasing)

                        Text("Billed monthly. Cancel anytime.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Features Comparison
                VStack(alignment: .leading, spacing: 16) {
                    Text("Compare Plans")
                        .font(.title3.bold())
                        .padding(.horizontal)

                    FeatureComparisonTable()
                }
                .padding(.top, 16)

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .navigationTitle("Upgrade")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onReceive(subscriptionManager.$purchaseInProgress) { inProgress in
            isPurchasing = inProgress
        }
        .onReceive(subscriptionManager.$errorMessage) { error in
            errorMessage = error
        }
    }

    // MARK: - Purchase Logic

    private func purchaseSelectedTier() async {
        // Find the monthly product for the selected tier
        let productID: String
        switch selectedTier {
        case .professional:
            productID = "com.jacdental.oralable.professional.professional.monthly"
        case .practice:
            productID = "com.jacdental.oralable.professional.practice.monthly"
        case .starter:
            return // Can't purchase free tier
        }

        guard let product = subscriptionManager.availableProducts.first(where: { $0.id == productID }) else {
            errorMessage = "Product not available"
            return
        }

        do {
            try await subscriptionManager.purchase(product)
            // On success, dismiss
            dismiss()
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Tier Card

struct TierCard: View {
    let tier: ProfessionalSubscriptionTier
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(tier.displayName)
                                .font(.title3.bold())

                            if isCurrent {
                                Text("Current")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .cornerRadius(4)
                            }
                        }

                        Text(tier.monthlyPrice)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSelected && !isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.black)
                    }
                }

                // Features
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tier.features.prefix(4), id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.green)

                            Text(feature)
                                .font(.subheadline)
                        }
                    }

                    if tier.features.count > 4 {
                        Text("+ \(tier.features.count - 4) more features")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: isSelected ? Color.black.opacity(0.2) : Color.black.opacity(0.05), radius: isSelected ? 8 : 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.black : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Feature Comparison Table

struct FeatureComparisonTable: View {
    let features = [
        ("Max Participants", ["5", "50", "Unlimited"]),
        ("Data Export", ["CSV", "CSV", "All Formats"]),
        ("Analytics", ["Basic", "Advanced", "Practice-wide"]),
        ("Support", ["Email", "Priority", "Dedicated"]),
        ("API Access", ["-", "✓", "✓"]),
        ("Multi-Professional", ["-", "-", "✓"])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                Text("Feature")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Text("Starter")
                    .font(.caption.weight(.semibold))
                    .frame(width: 80)
                    .padding()

                Text("Pro")
                    .font(.caption.weight(.semibold))
                    .frame(width: 80)
                    .padding()

                Text("Practice")
                    .font(.caption.weight(.semibold))
                    .frame(width: 80)
                    .padding()
            }
            .background(Color.gray.opacity(0.1))

            // Feature Rows
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 0) {
                    Text(feature.0)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    ForEach(feature.1, id: \.self) { value in
                        Text(value)
                            .font(.caption)
                            .frame(width: 80)
                            .padding()
                    }
                }
                .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        UpgradePromptView()
            .environmentObject(ProfessionalSubscriptionManager.shared)
    }
}
