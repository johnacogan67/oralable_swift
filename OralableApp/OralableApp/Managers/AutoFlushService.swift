//
//  AutoFlushService.swift
//  OralableApp
//
//  Spills in-memory sensor rings to temporary CSV during long automatic recordings.
//

import Combine
import Foundation

@MainActor
final class AutoFlushService {
    static let shared = AutoFlushService()

    private var tick: AnyCancellable?
    private weak var deviceManager: DeviceManager?
    private weak var sensorDataProcessor: SensorDataProcessor?

    private init() {}

    func start(deviceManager: DeviceManager, sensorDataProcessor: SensorDataProcessor) {
        self.deviceManager = deviceManager
        self.sensorDataProcessor = sensorDataProcessor
        tick?.cancel()
        tick = Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.flushIfNeeded() }
            }
    }

    /// Spill processor + unified rings to Application Support CSVs.
    /// - Parameter force: When true, flush even if the automatic session is no longer active
    ///   (required from `onSessionStopped` after pause expiry clears `isSessionActive`).
    func flushNow(force: Bool = false) async {
        guard let dm = deviceManager, let proc = sensorDataProcessor else { return }
        if !force {
            guard dm.automaticRecordingSession?.isSessionActive == true else { return }
        }
        proc.flushLiveHistoryToTempFileIfNonEmpty()
        await dm.flushUnifiedSensorBufferToTempFile()
    }

    private func flushIfNeeded() async {
        await flushNow(force: false)
    }
}
