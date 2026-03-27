import Foundation
import Combine

@MainActor
class AppStateManager: ObservableObject {
    // MARK: - Dependency Injection (Phase 4: Singleton Removed)
    // Note: Use AppDependencies.shared.appStateManager instead

    // Patient app is always in subscription mode
    @Published var selectedMode: HistoricalAppMode? = .subscription

    // Never needs mode selection
    var needsModeSelection: Bool {
        return false
    }

    /// TFI / Temporalis / gated SpO2 — only when primary **connected** unit supports the
    /// Temporalis clinical dashboard (REV10 via `OralableClinicalDeviceAdapter`), not ANR-only.
    @Published private(set) var showsOralableClinicalMetrics: Bool = false

    init() {}

    func refreshOralableClinicalMetrics(primaryBLE: BLEDeviceProtocol?) {
        showsOralableClinicalMetrics = OralableClinicalMetricsGate.shouldShowTemporalisClinicalDashboard(
            primaryBLE: primaryBLE
        )
    }

    // Mode management not needed for patient app, but keep for compatibility
    func setMode(_ mode: HistoricalAppMode) {
        selectedMode = mode
    }

    func clearMode() {
        // Do nothing - patient app doesn't change modes
    }
}
