//
//  AppleHealthManager.swift
//  OralableApp
//
//  HealthKit bridge: oxygen saturation write + authorization.
//

import Foundation
import HealthKit

// MARK: - Forward-looking models (not HK types)

struct AppleHealthHRVSampleStub: Sendable, Equatable {
    let date: Date
    let sdnnMilliseconds: Double
}

struct AppleHealthSleepStageSegmentStub: Sendable, Equatable {
    let start: Date
    let end: Date
    let stage: AppleHealthSleepStageKindStub
}

enum AppleHealthSleepStageKindStub: String, Sendable, Codable {
    case awake
    case rem
    case core
    case deep
    case unspecified
}

/// Local Oralable SpO₂ sample (`percentage` 0…100). Maps to HealthKit oxygen saturation when wired.
struct AppleHealthSpO2SampleStub: Sendable, Equatable {
    let date: Date
    /// Pulse oximeter reading in percent (0–100), same as UI / `SensorData.spo2.percentage`.
    let oxygenSaturationPercent: Double
}

/// Describes how samples map to `HKQuantityTypeIdentifier.oxygenSaturation`.
enum AppleHealthOxygenSaturationMapping {
    static let quantityTypeIdentifier = "HKQuantityTypeIdentifierOxygenSaturation"
}

enum AppleHealthError: LocalizedError {
    case healthDataUnavailable
    case typeUnavailable
    case noSamples

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .typeUnavailable:
            return "Oxygen saturation is not available in HealthKit."
        case .noSamples:
            return "No SpO₂ samples to export."
        }
    }
}

// MARK: - Bridge protocol

protocol AppleHealthBridging: AnyObject {
    var isHealthDataAvailable: Bool { get }
    var lastSuccessfulSpO2SyncAt: Date? { get }

    func requestAuthorizationIfNeeded() async throws
    func requestAuthorization() async throws
    func writeSpO2ToHealthKit(sessionAveragePercent: Double, sampleStart: Date, sampleEnd: Date) async throws

    func syncHeartRateVariabilityStub(samples: [AppleHealthHRVSampleStub]) async throws
    func syncSleepStagesStub(segments: [AppleHealthSleepStageSegmentStub]) async throws
    /// Writes one oxygen-saturation sample using the **session mean** over `samples` (time range from start…end).
    func exportSpO2ToAppleHealthStub(samples: [AppleHealthSpO2SampleStub]) async throws
}

// MARK: - Manager

final class AppleHealthManager: ObservableObject, AppleHealthBridging {

    private let healthStore = HKHealthStore()
    private let lastSyncDefaultsKey = "oralable.healthkit.lastSpO2Sync"

    @Published private(set) var isHealthDataAvailable: Bool = false
    @Published private(set) var lastSuccessfulSpO2SyncAt: Date?

    init() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        let saved = UserDefaults.standard.double(forKey: lastSyncDefaultsKey)
        if saved > 0 {
            lastSuccessfulSpO2SyncAt = Date(timeIntervalSince1970: saved)
        }
    }

    func requestAuthorizationIfNeeded() async throws {
        try await requestAuthorization()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw AppleHealthError.healthDataUnavailable
        }
        guard let spo2 = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            throw AppleHealthError.typeUnavailable
        }
        let toShare: Set<HKSampleType> = [spo2]
        let toRead: Set<HKObjectType> = [spo2]
        try await healthStore.requestAuthorization(toShare: toShare, read: toRead)
        Logger.shared.info("[AppleHealthManager] HealthKit authorization requested for oxygen saturation")
    }

    /// Saves one `HKQuantitySample` for SpO₂ using the session mean; HealthKit convention is 0…1 with `%` unit.
    func writeSpO2ToHealthKit(sessionAveragePercent: Double, sampleStart: Date, sampleEnd: Date) async throws {
        guard isHealthDataAvailable else {
            throw AppleHealthError.healthDataUnavailable
        }
        guard let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            throw AppleHealthError.typeUnavailable
        }
        let clamped = min(100, max(0, sessionAveragePercent))
        guard clamped > 0 else { return }
        let fraction = clamped / 100.0
        let quantity = HKQuantity(unit: HKUnit.percent(), doubleValue: fraction)
        let end = sampleEnd > sampleStart ? sampleEnd : sampleStart.addingTimeInterval(1)
        let sample = HKQuantitySample(
            type: spo2Type,
            quantity: quantity,
            start: sampleStart,
            end: end,
            metadata: [HKMetadataKeyWasUserEntered: false]
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard success else {
                    cont.resume(throwing: AppleHealthError.typeUnavailable)
                    return
                }
                cont.resume(returning: ())
            }
        }
        let now = Date()
        lastSuccessfulSpO2SyncAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSyncDefaultsKey)
        Logger.shared.info("[AppleHealthManager] Wrote SpO₂ session average \(String(format: "%.1f", clamped))% to Health")
    }

    func syncHeartRateVariabilityStub(samples: [AppleHealthHRVSampleStub]) async throws {
        Logger.shared.debug("[AppleHealthManager] HRV sync not implemented — \(samples.count) samples (no-op)")
    }

    func syncSleepStagesStub(segments: [AppleHealthSleepStageSegmentStub]) async throws {
        Logger.shared.debug("[AppleHealthManager] Sleep stages sync not implemented — \(segments.count) segments (no-op)")
    }

    func exportSpO2ToAppleHealthStub(samples: [AppleHealthSpO2SampleStub]) async throws {
        guard !samples.isEmpty else { throw AppleHealthError.noSamples }
        try await requestAuthorization()
        let sum = samples.reduce(0.0) { $0 + $1.oxygenSaturationPercent }
        let mean = sum / Double(samples.count)
        let sortedDates = samples.map(\.date).sorted()
        let start = sortedDates.first!
        let end = sortedDates.last!
        try await writeSpO2ToHealthKit(sessionAveragePercent: mean, sampleStart: start, sampleEnd: end)
    }
}
