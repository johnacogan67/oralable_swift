import Foundation

/// Service to handle raw IR/Red data before it reaches the calculators.
/// Essential for muscle-site PPG where the DC component is very high.
class PPGNormalizationService: ObservableObject {
    // MARK: - Shared singleton (for views that expect EnvironmentObject or shared access)
    static let shared = PPGNormalizationService()

    // MARK: - Configuration / Modes
    enum Method {
        case raw                 // pass-through
        case dynamicRange        // simple min-max or z-score like scaling
        case adaptiveBaseline    // baseline corrected using moving average
        case heartRateSimulation // placeholder method (maps to dynamicRange)
        case persistent          // persistent baseline tracking across samples
    }

    // MARK: - Internal state for baseline tracking
    private var movingAverageIR: Double = 0
    private var movingAverageRed: Double = 0
    private var movingAverageGreen: Double = 0
    private var initializedIR = false
    private var initializedRed = false
    private var initializedGreen = false

    private var movingAverage: Double = 0
    private let alpha: Double = 0.01 // Very slow tracking for DC component

    /// Normalizes the signal by removing the quasi-static DC component.
    /// This isolates the "AC" pulsatile signal.
    func normalize(_ rawValue: Double) -> Double {
        if movingAverage == 0 {
            movingAverage = rawValue
            return 0
        }

        // Update the DC baseline estimate
        movingAverage = (alpha * rawValue) + ((1.0 - alpha) * movingAverage)

        // Subtract baseline to get AC signal
        let acSignal = rawValue - movingAverage

        return acSignal
    }

    /// Checks if the sensor is likely "off-skin" or "saturated"
    func validateSignal(ir: Double) -> Bool {
        // Adjust these constants based on your ADC's range (e.g., 0-65535 for 16-bit)
        let isSaturated = ir > 65000
        let isTooLow = ir < 1000
        return !isSaturated && !isTooLow
    }

    // MARK: - Multi-channel normalization used by historical/debug views
    /// Normalize multi-channel PPG tuples.
    /// - Parameters:
    ///   - samples: Array of (timestamp, ir, red, green) tuples
    ///   - method: Normalization method to apply
    ///   - sensorData: Optional raw SensorData array for context (motion, temp etc.)
    /// - Returns: Array of normalized tuples matching the input shape
    func normalizePPGData(
        _ samples: [(timestamp: Date, ir: Double, red: Double, green: Double)],
        method: Method,
        sensorData: [SensorData]? = nil
    ) -> [(timestamp: Date, ir: Double, red: Double, green: Double)] {

        guard !samples.isEmpty else { return samples }

        switch method {
        case .raw:
            return samples

        case .dynamicRange:
            // Simple per-channel min-max scaling to 0...1 (robust enough for charts)
            let irValues = samples.map { $0.ir }
            let redValues = samples.map { $0.red }
            let greenValues = samples.map { $0.green }

            let irMin = irValues.min() ?? 0
            let irMax = irValues.max() ?? 1
            let redMin = redValues.min() ?? 0
            let redMax = redValues.max() ?? 1
            let greenMin = greenValues.min() ?? 0
            let greenMax = greenValues.max() ?? 1

            return samples.map { s in
                let irNorm = irMax > irMin ? (s.ir - irMin) / (irMax - irMin) : 0
                let redNorm = redMax > redMin ? (s.red - redMin) / (redMax - redMin) : 0
                let greenNorm = greenMax > greenMin ? (s.green - greenMin) / (greenMax - greenMin) : 0
                return (timestamp: s.timestamp, ir: irNorm, red: redNorm, green: greenNorm)
            }

        case .adaptiveBaseline:
            // Baseline correct per call (resets baseline for the batch)
            var irBaseline = samples.first?.ir ?? 0
            var redBaseline = samples.first?.red ?? 0
            var greenBaseline = samples.first?.green ?? 0

            // Use a slow-moving average within the batch
            let alphaLocal = 0.02
            return samples.map { s in
                irBaseline = alphaLocal * s.ir + (1 - alphaLocal) * irBaseline
                redBaseline = alphaLocal * s.red + (1 - alphaLocal) * redBaseline
                greenBaseline = alphaLocal * s.green + (1 - alphaLocal) * greenBaseline
                return (timestamp: s.timestamp, ir: s.ir - irBaseline, red: s.red - redBaseline, green: s.green - greenBaseline)
            }

        case .heartRateSimulation:
            // For now, treat as dynamicRange (placeholder)
            return normalizePPGData(samples, method: .dynamicRange, sensorData: sensorData)

        case .persistent:
            // Persistent baseline per channel across calls (uses instance state)
            let alphaPersistent = 0.01

            return samples.map { s in
                // IR
                if !initializedIR {
                    movingAverageIR = s.ir
                    initializedIR = true
                } else {
                    movingAverageIR = alphaPersistent * s.ir + (1 - alphaPersistent) * movingAverageIR
                }
                let irAC = s.ir - movingAverageIR

                // Red
                if !initializedRed {
                    movingAverageRed = s.red
                    initializedRed = true
                } else {
                    movingAverageRed = alphaPersistent * s.red + (1 - alphaPersistent) * movingAverageRed
                }
                let redAC = s.red - movingAverageRed

                // Green
                if !initializedGreen {
                    movingAverageGreen = s.green
                    initializedGreen = true
                } else {
                    movingAverageGreen = alphaPersistent * s.green + (1 - alphaPersistent) * movingAverageGreen
                }
                let greenAC = s.green - movingAverageGreen

                return (timestamp: s.timestamp, ir: irAC, red: redAC, green: greenAC)
            }
        }
    }

    // Optional: reset persistent baselines (useful when changing context)
    func resetPersistentBaselines() {
        movingAverageIR = 0
        movingAverageRed = 0
        movingAverageGreen = 0
        initializedIR = false
        initializedRed = false
        initializedGreen = false
    }
}
