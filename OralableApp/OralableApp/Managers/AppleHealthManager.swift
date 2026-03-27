//
//  AppleHealthManager.swift
//  OralableApp
//
//  Architectural stub for a future HealthKit bridge (HRV, sleep stages). No HealthKit
//  import yet — avoids entitlements until the sync feature ships.
//

import Foundation

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

// MARK: - Bridge protocol

/// Contract for syncing derived metrics into Apple Health (implemented for real with HKHealthStore later).
protocol AppleHealthBridging: AnyObject {
    var isHealthDataAvailable: Bool { get }

    /// Future: HKHealthStore.requestAuthorization(toShare:read:)
    func requestAuthorizationIfNeeded() async throws

    /// Future: HKQuantityType heartRateVariabilitySDNN (or equivalent series)
    func syncHeartRateVariabilityStub(samples: [AppleHealthHRVSampleStub]) async throws

    /// Future: HKCategoryValueSleepAnalysis–backed writes
    func syncSleepStagesStub(segments: [AppleHealthSleepStageSegmentStub]) async throws
}

// MARK: - Stub manager

@MainActor
final class AppleHealthManager: ObservableObject, AppleHealthBridging {

    @Published private(set) var isHealthDataAvailable: Bool = false

    init() {
        // Future: HKHealthStore.isHealthDataAvailable()
        isHealthDataAvailable = false
    }

    func requestAuthorizationIfNeeded() async throws {
        Logger.shared.info("[AppleHealthManager] Stub — authorization not requested (HealthKit not linked)")
    }

    func syncHeartRateVariabilityStub(samples: [AppleHealthHRVSampleStub]) async throws {
        Logger.shared.debug("[AppleHealthManager] Stub HRV sync — \(samples.count) samples (no-op)")
    }

    func syncSleepStagesStub(segments: [AppleHealthSleepStageSegmentStub]) async throws {
        Logger.shared.debug("[AppleHealthManager] Stub sleep stages — \(segments.count) segments (no-op)")
    }
}
