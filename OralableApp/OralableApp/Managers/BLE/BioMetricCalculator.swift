import Foundation
import Combine
import OralableCore

/// Legacy biometric calculator — **quarantined**.
///
/// Clinical HR/SpO2 must come from `UnifiedBiometricProcessor` (Mac → phone parity).
/// `SignalProcessingPipeline` previously emitted fake SpO2 (~98±noise) and must not
/// feed dashboard vitals or history.
@MainActor
class BioMetricCalculator: ObservableObject {
    @Published var heartRate: Int = 0
    @Published var spo2: Int = 0
    @Published var currentActivity: ActivityType = .relaxed

    /// No-op: kept for call-site compatibility with `SensorDataProcessor` only.
    func processFrame(ir: Double, red: Double, green: Double, accelerometer: AccelerometerData) {
        // Intentionally empty — see Mac → phone parity / ALGORITHM_ARCHITECTURE §0.
    }
}
