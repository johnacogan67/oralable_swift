//
//  DeveloperSettingsView.swift
//  OralableApp
//
//  Created: December 4, 2025
//  Purpose: Hidden developer settings for enabling feature flags
//  Access: Tap "About" row 7 times in Settings
//  Updated: December 13, 2025 - Simplified for pre-launch
//

import SwiftUI

struct DeveloperSettingsView: View {
    @ObservedObject private var featureFlags = FeatureFlags.shared

    var body: some View {
        Form {
            // Dashboard Features Section
            Section("Dashboard Features") {
                Toggle("EMG Card", isOn: $featureFlags.showEMGCard)
                Toggle("Movement Card", isOn: $featureFlags.showMovementCard)
                Toggle("Temperature Card", isOn: $featureFlags.showTemperatureCard)
                Toggle("Heart Rate Card", isOn: $featureFlags.showHeartRateCard)
                Toggle("SpO2 Card", isOn: $featureFlags.showSpO2Card)
                Toggle("Battery Card", isOn: $featureFlags.showBatteryCard)
            }

            // Share Features Section
            Section("Share Features") {
                Toggle("CloudKit Sharing", isOn: $featureFlags.showCloudKitShare)
            }

            // Subscription Section
            Section("Subscription") {
                Toggle("Subscription UI", isOn: $featureFlags.showSubscription)
            }

            // Other Features Section
            Section("Other Features") {
                Toggle("Detection Settings", isOn: $featureFlags.showDetectionSettings)
            }

            // Reset Section
            Section {
                Button("Reset to Defaults") {
                    featureFlags.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Developer Settings")
    }
}

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }
}
