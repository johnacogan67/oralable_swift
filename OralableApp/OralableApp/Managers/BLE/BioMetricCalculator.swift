import Foundation
import Combine
import OralableCore

/// An ObservableObject that serves as the view model for biometric data.
///
/// It orchestrates the processing of raw sensor data by delegating to a background actor
/// and publishes the results on the main thread for UI consumption.
@MainActor
class BioMetricCalculator: ObservableObject {
    @Published var heartRate: Int = 0
    @Published var spo2: Int = 0
    @Published var currentActivity: ActivityType = .relaxed

    private let pipeline = SignalProcessingPipeline()

    /// Processes a single frame of sensor data by offloading computation to a background actor.
    func processFrame(ir: Double, red: Double, green: Double, accelerometer: AccelerometerData) {
        Task {
            // Perform the heavy processing on the actor's isolated context (a background thread).
            let result = await pipeline.process(ir: ir, red: red, green: green, accelerometer: accelerometer)

            // Because this class is marked with @MainActor, property updates after an 'await'
            // are guaranteed to execute on the main thread.
            (heartRate, spo2, currentActivity) = (result.heartRate, result.spo2, result.activity)
        }
    }
}
