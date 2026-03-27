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

    private func flushIfNeeded() async {
        guard let dm = deviceManager, dm.automaticRecordingSession?.isSessionActive == true else { return }
        guard let proc = sensorDataProcessor else { return }
        await MainActor.run {
            proc.flushLiveHistoryToTempFileIfNonEmpty()
        }
        await dm.flushUnifiedSensorBufferToTempFile()
    }
}
