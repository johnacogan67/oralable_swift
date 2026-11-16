//
//  AppleHealthManager.swift
//  OralableApp
//
//  HealthKit bridge: heart rate + oxygen saturation write + authorization.
//  Does not write Oralable overnight states as Apple Sleep Stages.
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

struct AppleHealthHeartRateSample: Sendable, Equatable {
    let date: Date
    let bpm: Double
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
            return "Heart rate or oxygen saturation is not available in HealthKit."
        case .noSamples:
            return "No heart rate or SpO₂ samples to export."
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
    func exportSpO2ToAppleHealthStub(samples: [AppleHealthSpO2SampleStub]) async throws
    func exportVitalsToAppleHealth(
        heartRate: [AppleHealthHeartRateSample],
        spo2: [AppleHealthSpO2SampleStub]
    ) async throws
}

// MARK: - Manager

final class AppleHealthManager: ObservableObject, AppleHealthBridging {

    /// HealthKit is not a 50 Hz store — keep at most one sample per this interval.
    static let downsampleInterval: TimeInterval = 5

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
        guard let spo2 = HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
              let hr = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw AppleHealthError.typeUnavailable
        }
        let toShare: Set<HKSampleType> = [spo2, hr]
        let toRead: Set<HKObjectType> = [spo2, hr]
        try await healthStore.requestAuthorization(toShare: toShare, read: toRead)
        Logger.shared.info("[AppleHealthManager] HealthKit authorization requested for heart rate and oxygen saturation")
    }

    /// Saves one `HKQuantitySample` for SpO₂ using the session mean; HealthKit convention is 0…1 with `%` unit.
    func writeSpO2ToHealthKit(sessionAveragePercent: Double, sampleStart: Date, sampleEnd: Date) async throws {
        let sample = AppleHealthSpO2SampleStub(
            date: sampleStart,
            oxygenSaturationPercent: sessionAveragePercent
        )
        try await saveSpO2Samples([sample], endFallback: sampleEnd)
    }

    func syncHeartRateVariabilityStub(samples: [AppleHealthHRVSampleStub]) async throws {
        Logger.shared.debug("[AppleHealthManager] HRV sync not implemented — \(samples.count) samples (no-op)")
    }

    func syncSleepStagesStub(segments: [AppleHealthSleepStageSegmentStub]) async throws {
        Logger.shared.debug("[AppleHealthManager] Sleep stages not written — Oralable states are not Apple Sleep Stages")
    }

    func exportSpO2ToAppleHealthStub(samples: [AppleHealthSpO2SampleStub]) async throws {
        try await exportVitalsToAppleHealth(heartRate: [], spo2: samples)
    }

    func exportVitalsToAppleHealth(
        heartRate: [AppleHealthHeartRateSample],
        spo2: [AppleHealthSpO2SampleStub]
    ) async throws {
        guard !heartRate.isEmpty || !spo2.isEmpty else { throw AppleHealthError.noSamples }
        try await requestAuthorization()
        let hrDown = Self.downsample(heartRate.map { ($0.date, $0.bpm) }).map {
            AppleHealthHeartRateSample(date: $0.0, bpm: $0.1)
        }
        let oxDown = Self.downsample(spo2.map { ($0.date, $0.oxygenSaturationPercent) }).map {
            AppleHealthSpO2SampleStub(date: $0.0, oxygenSaturationPercent: $0.1)
        }
        if !hrDown.isEmpty {
            try await saveHeartRateSamples(hrDown)
        }
        if !oxDown.isEmpty {
            try await saveSpO2Samples(oxDown, endFallback: oxDown.last!.date.addingTimeInterval(1))
        }
        markSyncSuccess()
        Logger.shared.info("[AppleHealthManager] Wrote \(hrDown.count) HR and \(oxDown.count) SpO₂ samples to Health")
    }

    /// Keep at most one sample per `downsampleInterval` (last value in each bucket).
    static func downsample(_ samples: [(Date, Double)], interval: TimeInterval = downsampleInterval) -> [(Date, Double)] {
        let sorted = samples.sorted { $0.0 < $1.0 }
        guard !sorted.isEmpty else { return [] }
        var out: [(Date, Double)] = []
        var bucketStart = sorted[0].0
        var last = sorted[0]
        for sample in sorted.dropFirst() {
            if sample.0.timeIntervalSince(bucketStart) >= interval {
                out.append(last)
                bucketStart = sample.0
            }
            last = sample
        }
        out.append(last)
        return out
    }

    private func saveHeartRateSamples(_ samples: [AppleHealthHeartRateSample]) async throws {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw AppleHealthError.typeUnavailable
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let hk: [HKQuantitySample] = samples.compactMap { s in
            guard s.bpm >= 40, s.bpm <= 200 else { return nil }
            return HKQuantitySample(
                type: hrType,
                quantity: HKQuantity(unit: unit, doubleValue: s.bpm),
                start: s.date,
                end: s.date.addingTimeInterval(1),
                metadata: [HKMetadataKeyWasUserEntered: false]
            )
        }
        guard !hk.isEmpty else { return }
        try await save(hk)
    }

    private func saveSpO2Samples(_ samples: [AppleHealthSpO2SampleStub], endFallback: Date) async throws {
        guard let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            throw AppleHealthError.typeUnavailable
        }
        let hk: [HKQuantitySample] = samples.compactMap { s in
            let clamped = min(100, max(0, s.oxygenSaturationPercent))
            guard clamped > 0 else { return nil }
            let end = max(s.date.addingTimeInterval(1), endFallback)
            return HKQuantitySample(
                type: spo2Type,
                quantity: HKQuantity(unit: HKUnit.percent(), doubleValue: clamped / 100.0),
                start: s.date,
                end: end,
                metadata: [HKMetadataKeyWasUserEntered: false]
            )
        }
        guard !hk.isEmpty else { return }
        try await save(hk)
    }

    private func save(_ samples: [HKSample]) async throws {
        guard isHealthDataAvailable else {
            throw AppleHealthError.healthDataUnavailable
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
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
    }

    private func markSyncSuccess() {
        let now = Date()
        lastSuccessfulSpO2SyncAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSyncDefaultsKey)
    }
}
