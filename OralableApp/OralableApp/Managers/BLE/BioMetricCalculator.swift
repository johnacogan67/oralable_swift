import Foundation
import Combine

/// Enhanced BioMetricCalculator that coordinates Green/Red/IR signals
/// and Accelerometer data to extract accurate vitals from muscle sites.
class BioMetricCalculator: ObservableObject {
    // Services & Utilities
    private let hrService = HeartRateService()
    private let spo2Calculator = SpO2Calculator()
    private let motionCompensator = MotionCompensator()
    
    // Published Outputs for UI integration
    @Published var heartRate: Int = 0
    @Published var spo2: Int = 0
    @Published var isWorn: Bool = false
    @Published var signalQuality: Double = 0.0 // 0.0 to 1.0 confidence score

    // MARK: - Internal buffers for SpO2 calculation (expects arrays)
    private var redBuffer: [Int32] = []
    private var irBuffer: [Int32] = []
    // Cap buffers to a reasonable size (e.g., ~10 seconds at 50-200 Hz)
    private let maxSpo2BufferCount: Int = 2000

    /// Main entry point for processing synchronized multi-channel sensor data.
    /// This is called by the SensorDataProcessor for every received BLE frame.
    ///
    /// - Parameters:
    ///   - red: Raw Red LED value (used for SpO2)
    ///   - ir: Raw Infrared LED value (used for clench detection and SpO2)
    ///   - green: Raw Green LED value (primary source for Heart Rate)
    ///   - accelerometer: Combined magnitude (vector sum) of X, Y, Z motion
    func processFrame(red: Double, ir: Double, green: Double, accelerometer: Double) {
        
        // 1. Motion Artifact Cancellation
        // We use the accelerometer magnitude as the 'noise reference' to clean the Green PPG signal.
        // This effectively subtracts mechanical clench noise from the heartbeat waveform.
        let cleanedGreen = motionCompensator.filter(signal: green, noiseReference: accelerometer)
        
        // 2. Heart Rate Extraction
        // We feed the cleaned green signal to the HeartRateService which handles
        // bandpass filtering, peak detection, and BPM calculation.
        let hrResult = hrService.process(samples: [cleanedGreen])
        
        // 3. Update Vitals on the Main Thread for UI binding
        DispatchQueue.main.async {
            // Update HR and Worn Status
            if hrResult.bpm > 0 {
                self.heartRate = hrResult.bpm
                self.signalQuality = hrResult.confidence
                self.isWorn = hrResult.isWorn
            } else {
                // If the signal is too noisy or the device is off, signal quality drops
                self.signalQuality = 0.0
            }
            
            // 4. SpO2 Calculation (Motion Gating + Buffering)
            // SpO2 logic is highly sensitive to the DC baseline of Red and IR.
            // Clenching shifts the DC baseline rapidly, so we "gate" the calculation:
            // Only update SpO2 when the accelerometer magnitude is stable (near 1.0g).
            let motionThreshold = 1.05

            // Always append latest samples to buffers; we will only compute when motion is low.
            // Convert Double to Int32 as expected by SpO2Calculator.
            let redSample = Int32(clamping: Int(red))
            let irSample = Int32(clamping: Int(ir))
            self.redBuffer.append(redSample)
            self.irBuffer.append(irSample)

            // Trim buffers to avoid unbounded growth
            if self.redBuffer.count > self.maxSpo2BufferCount {
                self.redBuffer.removeFirst(self.redBuffer.count - self.maxSpo2BufferCount)
            }
            if self.irBuffer.count > self.maxSpo2BufferCount {
                self.irBuffer.removeFirst(self.irBuffer.count - self.maxSpo2BufferCount)
            }

            // Only attempt calculation when motion is below threshold
            if accelerometer < motionThreshold {
                // Use the existing API that expects arrays
                if let result = self.spo2Calculator.calculateSpO2WithQuality(redSamples: self.redBuffer, irSamples: self.irBuffer) {
                    // Round to Int for UI
                    self.spo2 = Int(result.spo2.rounded())
                    // Optionally, blend signalQuality with SpO2 quality, or keep separate
                    // For now, we could keep HR signalQuality unchanged or combine if desired.
                }
            } else {
                // Optional: We keep the last known stable SpO2 during the clench
                // to prevent the UI from flickering to zero.
            }
        }
    }
    
    /// Resets the internal filters and state. Use this when the sensor is re-attached.
    func reset() {
        motionCompensator.reset()
        // Clear SpO2 buffers to force re-accumulation
        redBuffer.removeAll(keepingCapacity: false)
        irBuffer.removeAll(keepingCapacity: false)
        // Add other reset logic if services maintain state
    }
}

