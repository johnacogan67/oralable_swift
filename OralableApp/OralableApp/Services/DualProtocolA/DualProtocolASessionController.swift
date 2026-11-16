//
//  DualProtocolASessionController.swift
//  OralableApp
//
//  Dual Protocol A: idle → ANR EMG preflight → MAM couple seat QC → 360 s cues → export.
//  MAM seat QC matches Single Protocol A / Mac run_protocol_a_session.py CouplingGate.
//

import Foundation
import Combine
import OralableCore

enum DualProtocolAPhase: Equatable {
    case idle
    case connecting
    case preflight(stage: PreflightStage, elapsed: TimeInterval)
    case preflightFailed(DualProtocolAPreflightStats)
    case seatQC(elapsed: TimeInterval, couple: CoupleState?)
    case seatQCFailed(String)
    case settling
    case running(elapsed: TimeInterval, cue: DualProtocolACue)
    case exporting
    case done(DualProtocolAExportArtifacts)
    case cancelled
    case failed(String)

    enum PreflightStage: String, Equatable {
        case rest1 = "REST — jaw relaxed (10 s)"
        case clench = "HARD CLENCH — hold max (10 s)"
        case rest2 = "REST — release (10 s)"
    }
}

@MainActor
final class DualProtocolASessionController: ObservableObject {

    static let couplePreflightTimeoutS: TimeInterval = SingleProtocolASessionController.couplePreflightTimeoutS
    static let coupleDeskAbortGraceS: TimeInterval = SingleProtocolASessionController.coupleDeskAbortGraceS

    @Published private(set) var phase: DualProtocolAPhase = .idle
    @Published private(set) var latestEMG: Double = 0
    @Published private(set) var latestIR: Double = 0
    @Published private(set) var coupleSnippet: String = "couple=unknown"
    @Published private(set) var oralableConnected: Bool = false
    @Published private(set) var anrConnected: Bool = false
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var preflightStats: DualProtocolAPreflightStats?
    @Published private(set) var coupleStats: SingleProtocolACoupleStats?
    @Published private(set) var exportArtifacts: DualProtocolAExportArtifacts?
    @Published var emgGate: Double = DualProtocolACues.defaultEmgGate
    /// Mac `--allow-couple-1`: start cues on poor MAM seat, not only couple=2.
    @Published var allowCouple1: Bool = false

    private weak var deviceManager: DeviceManager?
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var phaseStartedAt: Date?
    private var cueStartedAt: Date?
    private var cueStartUnix: TimeInterval?
    private var sessionANRRows: [(Date, Double)] = []
    private var sessionOralPoints: [EDFSessionGrid.Point] = []
    private var sessionSkinTempsC: [Double] = []
    private var preflightRestSamples: [Double] = []
    private var preflightClenchSamples: [Double] = []
    private var savedThrottle: Bool = true
    private var sessionStamp: String = ""

    private let gate = CouplingGate(requireAcc: true)
    private var lastAccX: Double?
    private var lastAccY: Double?
    private var lastAccZ: Double?
    private var lastRed: Double?
    private var deskSince: Date?
    private var lastCoupleWarn: CoupleState?

    // MARK: - Wire

    func attach(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        cancellables.removeAll()

        deviceManager.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.oralableConnected = devices.contains { $0.type == .oralable }
                self.anrConnected = devices.contains { $0.type == .anr }
                self.failIfCaptureLinkDropped()
            }
            .store(in: &cancellables)

        deviceManager.$primaryFirmwareDeviceStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, let status else { return }
                self.gate.setOnDock(status.onDock)
            }
            .store(in: &cancellables)

        deviceManager.readingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                self?.ingest(reading: reading)
            }
            .store(in: &cancellables)

        deviceManager.readingsBatchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readings in
                for reading in readings {
                    self?.ingest(reading: reading)
                }
            }
            .store(in: &cancellables)

        oralableConnected = deviceManager.connectedDevices.contains { $0.type == .oralable }
        anrConnected = deviceManager.connectedDevices.contains { $0.type == .anr }
        if let status = deviceManager.primaryFirmwareDeviceStatus {
            gate.setOnDock(status.onDock)
        }
    }

    // MARK: - Public controls

    func start() {
        guard phase == .idle || isRetryableFailure else { return }
        phase = .connecting
        statusMessage = "Connect Oralable and ANR, then Start."
        guard oralableConnected, anrConnected else {
            phase = .failed("Both Oralable and ANR must be connected before Dual Protocol A.")
            return
        }
        armWornAndStream()
        beginPreflight()
    }

    func retryPreflight() {
        guard case .preflightFailed = phase else { return }
        armWornAndStream()
        beginPreflight()
    }

    func retrySeatQC() {
        guard case .seatQCFailed = phase else { return }
        armWornAndStream()
        beginSeatQC()
    }

    /// Research escape hatch after EMG fail — still run MAM couple seat QC.
    func forceStartDespitePreflight() {
        guard case .preflightFailed(let stats) = phase else { return }
        var forced = stats
        forced.passed = false
        preflightStats = forced
        beginSeatQC()
    }

    /// Desk escape hatch after couple fail — continue to cues.
    func forceStartDespiteSeatQC() {
        guard case .seatQCFailed = phase else { return }
        coupleStats = SingleProtocolACoupleStats(
            passed: false,
            coupleRaw: gate.state?.rawValue,
            allowCouple1: allowCouple1,
            pulseLatched: gate.isPulseLatched,
            hrBPM: gate.heartRateBPM,
            snippet: gate.statusSnippet()
        )
        beginSettleThenCues()
    }

    func cancel() {
        stopTimers()
        restoreLoggerThrottle()
        phase = .cancelled
        statusMessage = "Cancelled."
    }

    func resetToIdle() {
        stopTimers()
        restoreLoggerThrottle()
        phase = .idle
        statusMessage = ""
        preflightStats = nil
        coupleStats = nil
        exportArtifacts = nil
        sessionANRRows.removeAll()
        sessionOralPoints.removeAll()
        sessionSkinTempsC.removeAll()
        preflightRestSamples.removeAll()
        preflightClenchSamples.removeAll()
        cueStartUnix = nil
        cueStartedAt = nil
        latestEMG = 0
        latestIR = 0
        coupleSnippet = "couple=unknown"
        deskSince = nil
        lastCoupleWarn = nil
        gate.markUnknown()
    }

    // MARK: - Worn / stream (Mac + Single parity)

    private func armWornAndStream() {
        guard let dm = deviceManager else { return }
        FeatureFlags.shared.devicePlacementMode = .worn
        dm.applyFirmwarePlacementMode(.worn, force: true)
        if let oralable = dm.primaryBLEDevice as? OralableDevice {
            do {
                try oralable.setFirmwareStreamEnableMask(0x03)
            } catch {
                Logger.shared.warning("[DualProtocolA] stream mask write failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - ANR EMG preflight

    private func beginPreflight() {
        stopTimers()
        preflightRestSamples.removeAll()
        preflightClenchSamples.removeAll()
        sessionANRRows.removeAll()
        sessionOralPoints.removeAll()
        phaseStartedAt = Date()
        phase = .preflight(stage: .rest1, elapsed: 0)
        statusMessage = "ANR long-axis VERTICAL on anterior temporalis."
        startTickTimer()
    }

    private func advancePreflight(elapsed: TimeInterval) {
        let rest = DualProtocolACues.preflightRestSeconds
        let clench = DualProtocolACues.preflightClenchSeconds
        let total = rest + clench + rest

        if elapsed < rest {
            phase = .preflight(stage: .rest1, elapsed: elapsed)
        } else if elapsed < rest + clench {
            phase = .preflight(stage: .clench, elapsed: elapsed)
        } else if elapsed < total {
            phase = .preflight(stage: .rest2, elapsed: elapsed)
        } else {
            finishPreflight()
        }
    }

    private func finishPreflight() {
        stopTimers()
        let clenchMax = preflightClenchSamples.max() ?? 0
        let clenchMean = preflightClenchSamples.isEmpty
            ? 0
            : preflightClenchSamples.reduce(0, +) / Double(preflightClenchSamples.count)
        let restMax = preflightRestSamples.max() ?? 0
        let passed = clenchMax >= emgGate
        let stats = DualProtocolAPreflightStats(
            passed: passed,
            emgGate: emgGate,
            clenchMax: clenchMax,
            clenchMean: clenchMean,
            restMax: restMax
        )
        preflightStats = stats

        if passed {
            statusMessage = String(format: "EMG PASS — clench max %.0f ≥ %.0f. Next: MAM seat QC.", clenchMax, emgGate)
            beginSeatQC()
        } else {
            statusMessage = String(
                format: "EMG FAIL — clench max %.0f < %.0f. Re-seat ANR (vertical) and retry.",
                clenchMax,
                emgGate
            )
            phase = .preflightFailed(stats)
        }
    }

    // MARK: - MAM couple seat QC (Single Protocol A parity)

    private func beginSeatQC() {
        stopTimers()
        gate.markUnknown()
        deskSince = nil
        lastCoupleWarn = nil
        phaseStartedAt = Date()
        phase = .seatQC(elapsed: 0, couple: nil)
        let need = allowCouple1 ? "couple≥1" : "couple=2"
        statusMessage = "MAM seat QC (\(need); GATT worn≠couple) — temple, off case."
        startTickTimer()
    }

    private func maybeSeatReady() -> Bool {
        guard let st = gate.state else { return false }
        if st == .good { return true }
        if allowCouple1 && st == .poor { return true }
        return false
    }

    private func finishSeatQCSuccess() {
        stopTimers()
        let stats = SingleProtocolACoupleStats(
            passed: true,
            coupleRaw: gate.state?.rawValue,
            allowCouple1: allowCouple1,
            pulseLatched: gate.isPulseLatched,
            hrBPM: gate.heartRateBPM,
            snippet: gate.statusSnippet()
        )
        coupleStats = stats
        coupleSnippet = stats.snippet
        statusMessage = "Seat QC ready — \(stats.snippet)"
        beginSettleThenCues()
    }

    private func failSeatQC(_ reason: String) {
        stopTimers()
        coupleStats = SingleProtocolACoupleStats(
            passed: false,
            coupleRaw: gate.state?.rawValue,
            allowCouple1: allowCouple1,
            pulseLatched: gate.isPulseLatched,
            hrBPM: gate.heartRateBPM,
            snippet: gate.statusSnippet()
        )
        coupleSnippet = coupleStats?.snippet ?? "couple=unknown"
        statusMessage = reason
        phase = .seatQCFailed(reason)
    }

    // MARK: - Cues

    private func beginSettleThenCues() {
        phase = .settling
        statusMessage = "Settling 2 s before cues…"
        savedThrottle = NRFConnectBLELogger.shared.throttleHighRateNotifications
        NRFConnectBLELogger.shared.throttleHighRateNotifications = false
        NRFConnectBLELogger.shared.clear()
        sessionStamp = DualProtocolAExport.makeSessionTimestamp()
        sessionANRRows.removeAll()
        sessionSkinTempsC.removeAll()
        sessionOralPoints.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.beginCueRun()
        }
    }

    private func beginCueRun() {
        cueStartedAt = Date()
        cueStartUnix = Date().timeIntervalSince1970
        deskSince = nil
        let cue = DualProtocolACues.cue(at: 0)
        phase = .running(elapsed: 0, cue: cue)
        statusMessage = "Protocol A running — \(DualProtocolACues.formatMMSS(DualProtocolACues.sessionDurationSeconds))"
        startTickTimer()
    }

    private func advanceCues(elapsed: TimeInterval) {
        if elapsed >= DualProtocolACues.sessionDurationSeconds {
            finishCueRun()
            return
        }
        let cue = DualProtocolACues.cue(at: elapsed)
        phase = .running(elapsed: elapsed, cue: cue)
    }

    private func finishCueRun() {
        stopTimers()
        phase = .exporting
        statusMessage = "Writing Dual A export pack…"
        Task { await exportPack() }
    }

    // MARK: - Export

    private func exportPack() async {
        let oralID = deviceManager?.connectedDevices.first(where: { $0.type == .oralable })?.id.uuidString ?? "unknown"
        let anrID = deviceManager?.connectedDevices.first(where: { $0.type == .anr })?.id.uuidString ?? "unknown"
        let rows = sessionANRRows
        let oralPoints = sessionOralPoints
        let temps = sessionSkinTempsC
        let cueUnix = cueStartUnix
        let stats = preflightStats
        let couple = coupleStats
        let stamp = sessionStamp

        do {
            let artifacts = try DualProtocolAExport.writeSessionPack(
                anrRows: rows,
                oralablePoints: oralPoints,
                oralableID: oralID,
                anrID: anrID,
                cueStartUnix: cueUnix,
                preflight: stats,
                couple: couple,
                sessionTimestamp: stamp.isEmpty ? nil : stamp,
                skinTempSamplesC: temps
            )
            restoreLoggerThrottle()
            exportArtifacts = artifacts
            phase = .done(artifacts)
            statusMessage = "Session complete — Share TEMPORALIS + ANR + DUAL_PAIR + session.edf (EMG inside)."
            Logger.shared.info("[DualProtocolA] Export \(artifacts.sessionTimestamp) edf=\(artifacts.edfURL != nil)")
        } catch {
            restoreLoggerThrottle()
            phase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            Logger.shared.error("[DualProtocolA] Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Ingest

    private func ingest(reading: SensorReading) {
        let mono = ProcessInfo.processInfo.systemUptime

        switch reading.sensorType {
        case .ppgInfrared:
            latestIR = reading.value
            let red = lastRed.map { Int($0) }
            gate.feedPPGSamples(
                irSamples: [Int(reading.value)],
                monoS: mono,
                reds: red.map { [$0] }
            )
            coupleSnippet = gate.statusSnippet()
        case .ppgRed:
            lastRed = reading.value
        case .accelerometerX:
            lastAccX = reading.value
            feedAccIfReady(mono: mono)
        case .accelerometerY:
            lastAccY = reading.value
            feedAccIfReady(mono: mono)
        case .accelerometerZ:
            lastAccZ = reading.value
            feedAccIfReady(mono: mono)
        case .temperature:
            gate.feedTempC(reading.value)
            let c = reading.value
            if c.isFinite, c > 0 {
                sessionSkinTempsC.append(c)
            }
        default:
            break
        }

        // Oralable streams for EDF (settling + cue run)
        switch phase {
        case .settling, .running:
            switch reading.sensorType {
            case .ppgInfrared:
                sessionOralPoints.append(.init(time: reading.timestamp, ir: reading.value))
            case .ppgRed:
                sessionOralPoints.append(.init(time: reading.timestamp, red: reading.value))
            case .ppgGreen:
                sessionOralPoints.append(.init(time: reading.timestamp, green: reading.value))
            case .accelerometerX:
                sessionOralPoints.append(.init(time: reading.timestamp, accX: reading.value))
            case .accelerometerY:
                sessionOralPoints.append(.init(time: reading.timestamp, accY: reading.value))
            case .accelerometerZ:
                sessionOralPoints.append(.init(time: reading.timestamp, accZ: reading.value))
            case .spo2:
                sessionOralPoints.append(.init(time: reading.timestamp, spo2: reading.value))
            default:
                break
            }
        default:
            break
        }

        guard reading.sensorType == .emg else { return }
        latestEMG = reading.value

        switch phase {
        case .preflight(let stage, _):
            switch stage {
            case .rest1, .rest2:
                preflightRestSamples.append(reading.value)
            case .clench:
                preflightClenchSamples.append(reading.value)
            }
        case .settling, .running:
            sessionANRRows.append((reading.timestamp, reading.value))
        default:
            break
        }
    }

    private func feedAccIfReady(mono: Double) {
        guard let x = lastAccX, let y = lastAccY, let z = lastAccZ else { return }
        let mag = (x * x + y * y + z * z).squareRoot()
        gate.feedAccMagnitudes([mag], monoS: mono)
        coupleSnippet = gate.statusSnippet()
    }

    // MARK: - Tick

    private func startTickTimer() {
        stopTimers()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
    }

    private func stopTimers() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func onTick() {
        if failIfCaptureLinkDropped() { return }
        let mono = ProcessInfo.processInfo.systemUptime

        switch phase {
        case .preflight:
            guard let started = phaseStartedAt else { return }
            advancePreflight(elapsed: Date().timeIntervalSince(started))

        case .seatQC:
            gate.tick(monoS: mono)
            coupleSnippet = gate.statusSnippet()
            guard let started = phaseStartedAt else { return }
            let elapsed = Date().timeIntervalSince(started)
            phase = .seatQC(elapsed: elapsed, couple: gate.state)
            if maybeSeatReady() {
                finishSeatQCSuccess()
                return
            }
            if elapsed >= Self.couplePreflightTimeoutS {
                let need = allowCouple1 ? "couple≥1" : "couple=2"
                let st = CoupleLabel.label(gate.state)
                if gate.state == .desk || gate.state == nil {
                    failSeatQC(
                        "MAM seat QC failed: couple=\(st) (need \(need); desk/unknown — reseat on temple, off case)"
                    )
                } else {
                    failSeatQC(
                        "MAM seat QC timeout: couple=\(st) (need \(need); enable Allow couple=1 for poor seat)"
                    )
                }
            }

        case .running:
            gate.tick(monoS: mono)
            coupleSnippet = gate.statusSnippet()
            guard let started = cueStartedAt else { return }
            let elapsed = Date().timeIntervalSince(started)
            gate.setSessionElapsed(elapsed)
            if let st = gate.state, st == .poor, st != lastCoupleWarn {
                lastCoupleWarn = st
                statusMessage = "WARNING: couple=1 (MAM weak pulse/vitals) — reseat if needed"
            }
            if gate.state == nil {
                stopTimers()
                restoreLoggerThrottle()
                let msg = "couple=unknown (MAM PPG lost / cannot judge seat without BLE+PPG)"
                phase = .failed(msg)
                statusMessage = msg
                return
            }
            if gate.state == .desk {
                if deskSince == nil { deskSince = Date() }
                if let deskSince, Date().timeIntervalSince(deskSince) >= Self.coupleDeskAbortGraceS {
                    stopTimers()
                    restoreLoggerThrottle()
                    let msg = "couple=0 desk for \(Self.coupleDeskAbortGraceS)s — aborting Dual Protocol A"
                    phase = .failed(msg)
                    statusMessage = msg
                    return
                }
            } else {
                deskSince = nil
            }
            advanceCues(elapsed: elapsed)

        default:
            break
        }
    }

    /// FW 1.0.71+ stops Oralable PPG/ACC the instant BLE drops. Do not keep the cue clock.
    @discardableResult
    private func failIfCaptureLinkDropped() -> Bool {
        switch phase {
        case .preflight, .seatQC, .settling, .running:
            break
        default:
            return false
        }
        guard oralableConnected, anrConnected else {
            stopTimers()
            restoreLoggerThrottle()
            gate.markUnknown()
            phase = .failed(Self.linkDropMessage)
            statusMessage = Self.linkDropMessage
            return true
        }
        return false
    }

    static let linkDropMessage =
        "Oralable or ANR dropped. FW 1.0.71+ stops Oralable sensors when BLE drops — restart the session."

    private var isRetryableFailure: Bool {
        if case .failed = phase { return true }
        if case .cancelled = phase { return true }
        if case .preflightFailed = phase { return true }
        if case .seatQCFailed = phase { return true }
        return false
    }

    private func restoreLoggerThrottle() {
        NRFConnectBLELogger.shared.throttleHighRateNotifications = savedThrottle
    }
}
