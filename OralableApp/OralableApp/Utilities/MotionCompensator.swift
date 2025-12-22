import Foundation

class MotionCompensator {
    private let historySize = 32
    private var weights: [Double]
    private var noiseHistory: [Double]
    private let learningRate: Double
    private let varianceThreshold: Double

    /// Initializes the MotionCompensator.
    /// - Parameters:
    ///   - learningRate: The LMS learning rate (mu). Defaults to 0.01.
    ///   - varianceThreshold: The variance threshold for the noise reference to trigger dampening. Defaults to 1.0.
    init(learningRate: Double = 0.01, varianceThreshold: Double = 1.0) {
        self.learningRate = learningRate
        self.varianceThreshold = varianceThreshold
        self.weights = Array(repeating: 0.0, count: historySize)
        self.noiseHistory = Array(repeating: 0.0, count: historySize)
    }

    /// Filters the signal by subtracting the adaptive noise estimate.
    /// - Parameters:
    ///   - signal: The primary signal containing desired data plus noise.
    ///   - noiseReference: The reference noise signal (e.g., from an accelerometer).
    /// - Returns: The filtered signal with noise reduced, or a dampened signal if motion is excessive.
    func filter(signal: Double, noiseReference: Double) -> Double {
        // Update history
        noiseHistory.removeLast()
        noiseHistory.insert(noiseReference, at: 0)

        // Variance check for excessive motion
        let mean = noiseHistory.reduce(0, +) / Double(historySize)
        let variance = noiseHistory.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(historySize)

        if variance > varianceThreshold {
            // Excessive motion detected; dampen the signal significantly
            return signal * 0.01
        }

        // LMS Adaptive Filter
        var noiseEstimate: Double = 0.0
        for i in 0..<historySize {
            noiseEstimate += weights[i] * noiseHistory[i]
        }

        let error = signal - noiseEstimate

        // Update weights
        for i in 0..<historySize {
            weights[i] += learningRate * error * noiseHistory[i]
        }

        return error
    }
    
    /// Resets the internal filter state (weights and noise history).
    /// Call this when the sensor is re-attached or when starting a new measurement session.
    func reset() {
        weights = Array(repeating: 0.0, count: historySize)
        noiseHistory = Array(repeating: 0.0, count: historySize)
    }
}
