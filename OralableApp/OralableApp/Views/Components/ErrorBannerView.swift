//
//  ErrorBannerView.swift
//  OralableApp
//

import SwiftUI

struct ErrorBannerView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let title: String
    let message: String
    let isRecoverable: Bool
    var retryAction: (() -> Void)?
    var dismissAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(designSystem.colors.primaryWhite)
                Text(title)
                    .font(designSystem.typography.captionBold)
                    .foregroundColor(designSystem.colors.primaryWhite)
                Spacer()
                if let dismiss = dismissAction {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(designSystem.typography.labelSmall)
                            .foregroundColor(designSystem.colors.primaryWhite.opacity(0.8))
                    }
                }
            }

            Text(message)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.primaryWhite.opacity(0.9))

            if isRecoverable, let retry = retryAction {
                Button(action: retry) {
                    Text("Retry")
                        .font(designSystem.typography.captionBold)
                        .foregroundColor(designSystem.colors.error)
                        .padding(.horizontal, designSystem.spacing.md)
                        .padding(.vertical, designSystem.spacing.xs + 2)
                        .background(designSystem.colors.primaryWhite)
                        .cornerRadius(designSystem.cornerRadius.medium)
                }
            }
        }
        .padding(designSystem.spacing.buttonPadding)
        .background(designSystem.colors.error.opacity(0.9))
        .cornerRadius(designSystem.cornerRadius.large)
        .padding(.horizontal, designSystem.spacing.md)
    }
}
