//
//  DeviceDetailView.swift
//  OralableApp
//
//  Device detail sheet showing device info and actions.
//
//  Displays:
//  - Device name and type
//  - Connection status
//  - Signal strength (RSSI)
//  - UUID identifier
//
//  Actions:
//  - Disconnect: Disconnects active connection
//  - Forget Device: Removes from remembered devices
//

import SwiftUI

struct DeviceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let device: DeviceRowItem
    let onForget: () -> Void
    let onDisconnect: () -> Void

    @State private var showingForgetAlert = false

    var body: some View {
        NavigationView {
            List {
                // Device Name Section
                Section {
                    HStack {
                        Text("Name")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(device.name)
                            .foregroundColor(.primary)
                    }
                }

                // Connection Status Section
                Section {
                    HStack {
                        Text("Status")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(device.isConnected ? "Connected" : "Not Connected")
                            .foregroundColor(device.isConnected ? .blue : .secondary)
                    }
                }

                // Actions Section
                Section {
                    Button(action: {
                        showingForgetAlert = true
                    }) {
                        Text("Forget This Device")
                            .foregroundColor(.blue)
                    }
                }

                if device.isConnected {
                    Section {
                        Button(action: {
                            onDisconnect()
                        }) {
                            Text("Disconnect")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                        }
                    }
                }
            }
            .alert("Forget Device", isPresented: $showingForgetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Forget", role: .destructive) {
                    onForget()
                }
            } message: {
                Text("Your device will no longer automatically connect to \(device.name).")
            }
        }
    }
}

// MARK: - Preview
struct DeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceDetailView(
            device: DeviceRowItem(id: "test-uuid", name: "Oralable Device", isConnected: true),
            onForget: {},
            onDisconnect: {}
        )
    }
}
