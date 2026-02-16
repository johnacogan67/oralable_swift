//
//  ErrorBannerView.swift
//  OralableApp
//

import SwiftUI

struct ErrorBannerView: View {
    let title: String
    let message: String
    let isRecoverable: Bool
    var retryAction: (() -> Void)?
    var dismissAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let dismiss = dismissAction {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(.caption, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }

            Text(message)
                .font(.system(.caption))
                .foregroundColor(.white.opacity(0.9))

            if isRecoverable, let retry = retryAction {
                Button(action: retry) {
                    Text("Retry")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
