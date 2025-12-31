//
//  DebugMenuView.swift
//  OralableApp
//
//  Created by John A Cogan on 23/11/2025.
//


import SwiftUI

struct DebugMenuView: View {
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter
    @EnvironmentObject var sensorDataStore: SensorDataStore

    var body: some View {
        Form {
            Section(header: Text("BLE")) {
                Toggle("Simulate BLE Connection", isOn: $deviceManagerAdapter.isConnected)
                Toggle("Simulate Recording", isOn: $deviceManagerAdapter.isRecording)
            }

            Section(header: Text("Sensor Data")) {
                Button("Inject Mock Sensor Data") {
                    let mockDataBatch = SensorData.mockBatch()
                    // Store each mock data point as dictionary
                    for mockData in mockDataBatch {
                        let dict = mockData.toDictionary()
                        sensorDataStore.storeSensorData(dict)
                    }
                }

                Button("Clear Sensor History") {
                    sensorDataStore.clearHistory()
                }
            }
        }
        .navigationTitle("Debug Menu")
    }
}
