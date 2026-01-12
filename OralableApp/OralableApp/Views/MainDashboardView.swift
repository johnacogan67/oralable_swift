//
//  MainDashboardView.swift
//  OralableApp
//
//  Legacy/debug dashboard view (not the primary dashboard).
//
//  Purpose:
//  Simple debug view showing basic stats and navigation to DebugMenuView.
//  The primary dashboard is DashboardView.swift.
//
//  Created by John A Cogan on 23/11/2025.
//


import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject var historicalDataManager: HistoricalDataManager
    @EnvironmentObject var recordingSessionManager: RecordingSessionManager
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Oralable Dashboard")
                    .font(.largeTitle)
                    .bold()

                Text("Sessions recorded: \(recordingSessionManager.sessions.count)")
                Text("BLE Connected: \(deviceManagerAdapter.isConnected ? "Yes" : "No")")

                NavigationLink("Go to Debug Menu") {
                    DebugMenuView()
                }
            }
            .padding()
        }
    }
}