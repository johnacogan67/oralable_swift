import Foundation

/// An Adaptive LMS (Least Mean Squares) Filter for motion artifact cancellation.
/// This filter uses an external noise reference (accelerometer) to estimate 
/// and subtract noise from the primary signal (PPG).
class MotionCompensator {
    // Filter Configuration
    private let filterOrder: Int = 32     // Number of "taps" or history points
    private let stepSize: Double = 0.01   // Convergence rate (mu)
    
    // State Buffers
    private var weights: [Double]         // Filter coefficients
    private var noiseHistory: [Double]    // Buffer for noise reference (Acc)
    
    init() {
        self.weights = Array(repeating: 0.0, count: filterOrder)
        self.noiseHistory = Array(repeating: 0.0, count: filterOrder)
    }
    
    /**
     Filters the input signal using the noise reference.
     
     - Parameters:
        - signal: The noisy PPG value (e.g., Green or IR channel).
        - noiseReference: The current accelerometer magnitude.
     - Returns: The "cleaned" signal with estimated noise subtracted.
     */
    func filter(signal: Double, noiseReference: Double) -> Double {
        // 1. Update noise history (Shift and insert new sample)
        noiseHistory.removeLast()
        noiseHistory.insert(noiseReference, at: 0)
        
        // 2. Calculate the filter output (Estimated Noise)
        var estimatedNoise: Double = 0
        for i in 0..<filterOrder {
            estimatedNoise += weights[i] * noiseHistory[i]
        }
        
        // 3. Calculate Error (The cleaned signal)
        let cleanedSignal = signal - estimatedNoise
        
        // 4. Update Weights using LMS algorithm
        for i in 0..<filterOrder {
            weights[i] += stepSize * cleanedSignal * noiseHistory[i]
        }
        
        // 5. Final Guard: High-Motion Damping
        let noiseVariance = calculateVariance(noiseHistory)
        if noiseVariance > 2.0 {
            return cleanedSignal * 0.1 // Heavy attenuation during high-shock periods
        }
        
        return cleanedSignal
    }
    
    private func calculateVariance(_ buffer: [Double]) -> Double {
        let mean = buffer.reduce(0, +) / Double(buffer.count)
        let sumOfSquares = buffer.reduce(0) { $0 + pow($1 - mean, 2) }
        return sumOfSquares / Double(buffer.count)
    }
    
    func reset() {
        weights = Array(repeating: 0.0, count: filterOrder)
        noiseHistory = Array(repeating: 0.0, count: filterOrder)
    }
}