import Foundation
import Combine

/// Extension to handle real-time HR integration in the Dashboard.
extension DashboardViewModel {
    
    // Call this inside your SensorDataProcessor subscription
    func updateHeartRate(with rawIRSamples: [Double]) {
        let hrService = HeartRateService() // Usually a persistent property
        let result = hrService.process(samples: rawIRSamples)
        
        DispatchQueue.main.async {
            self.currentHRResult = result
            
            // Only allow bruxism detection if the device is worn
            if result.isWorn {
                self.wornStatus = .active
                self.startBruxismProcessing()
            } else {
                self.wornStatus = .repositioning
                self.pauseBruxismProcessing()
            }
        }
    }
}