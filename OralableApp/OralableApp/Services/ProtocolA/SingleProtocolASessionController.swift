//
//  SingleProtocolASessionController.swift
//  OralableApp
//
//  Single-MAM Protocol A Setup: idle → couple seat QC → 360 s cues → export → done.
//  Mac parity: cursor_oralable/scripts/run_protocol_a_session.py + CouplingGate.
//

import Foundation
import Combine
import OralableCore

enum SingleProtocolAPhase: Equatable {
    case idle
    case connecting
    case seatQC(elapsed: TimeInterval, couple: CoupleState?)
    case seatQCFailed(String)
    case settling
    case running(elapsed: TimeInterval, cue: DualProtocolACue)
    case exporting
    case done(SingleProtocolAExportArtifacts)
    case cancelled
    case failed(String)
}

struct SingleProtocolACoupleStats: Equatable, Sendable {
    var passed: Bool
    var coupleRaw: Int? // nil = unknown, 0/1/2
    var allowCouple1: Bool
    var pulseLatched: Bool
    var hrBPM: Double?
    var snippet: String
}

@MainActor
final class SingleProtocolASessionController: ObservableObject {

    static let couplePreflightTimeoutS: TimeInterval = 60
    static let coupleDeskAbortGraceS: TimeInterval = 20

    @Published private(set) var phase: SingleProtocolAPhase = .idle
    @Published private(set) var latestIR: Double = 0
    @Published private(set) var coupleSnippet: String = "couple=unknown"
    @Published private(set) var oralableConnected: Bool = false
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var coupleStats: SingleProtocolACoupleStats?
    @Published private(set) var exportArtifacts: SingleProtocolAExportArtifacts?
    /// Mac `--allow-couple-1`: start clock on poor seat, not only couple=2.
    @Published var allowCouple1: Bool = false

    private weak var deviceManager: DeviceManager?
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var phaseStartedAt: Date?
    private var cueStartedAt: Date?
    private var sessionOralPoints: [EDFSessionGrid.Point] = []
    private var savedThrottle: Bool = true
    private var sessionStamp: String = ""

    private let gate = CouplingGate(requireAcc: true)
    private var lastAccX: Double?
    private var lastAccY: Double?
    private var lastAccZ: Double?
    private var lastRed: Double?
    private var deskSince: Date?
    private var clockStarted = false
    private var lastCoupleWarn: CoupleState?
    /// Bumped on each settle and on cancel / reset / link drop so a stale 2 s callback cannot start cues.
    private var settleGeneration: UInt = 0

    func attach(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        cancellables.removeAll()

        deviceManager.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.oralableConnected = devices.contains { $0.type == .oralable }
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
        if let status = deviceManager.primaryFirmwareDeviceStatus {
            gate.setOnDock(status.onDock)
        }
    }

    func start() {
        guard phase == .idle || isRetryableFailure else { return }
        phase = .connecting
        statusMessage = "Connect Oralable (MAM), seat on temple, then Start."
        guard oralableConnected else {
            phase = .failed("Oralable must be connected before Protocol A Setup.")
            return
        }
        armWornAndStream()
        beginSeatQC()
    }

    func retrySeatQC() {
        guard case .seatQCFailed = phase else { return }
        armWornAndStream()
        beginSeatQC()
    }

    /// Desk escape hatch — continue cues even if couple gate failed (Mac desk / --allow-couple-1 spirit).
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
        invalidatePendingCueStart()
        stopTimers()
        restoreLoggerThrottle()
        clockStarted = false
        phase = .cancelled
        statusMessage = "Cancelled."
    }

    func resetToIdle() {
        invalidatePendingCueStart()
        stopTimers()
        restoreLoggerThrottle()
        phase = .idle
        statusMessage = ""
        coupleStats = nil
        exportArtifacts = nil
        sessionOralPoints.removeAll()
        cueStartedAt = nil
        latestIR = 0
        coupleSnippet = "couple=unknown"
        clockStarted = false
        deskSince = nil
        lastCoupleWarn = nil
        gate.markUnknown()
    }

    // MARK: - Seat QC (Mac couple)

    private func armWornAndStream() {
        guard let dm = deviceManager else { return }
        FeatureFlags.shared.devicePlacementMode = .worn
        dm.applyFirmwarePlacementMode(.worn, force: true)
        if let oralable = dm.primaryBLEDevice as? OralableDevice {
            do {
                try oralable.setFirmwareStreamEnableMask(0x03) // PPG|ACC
            } catch {
                Logger.shared.warning("[SingleProtocolA] stream mask write failed: \(error.localizedDescription)")
            }
        }
    }

    private func beginSeatQC() {
        stopTimers()
        gate.markUnknown()
        sessionOralPoints.removeAll()
        deskSince = nil
        lastCoupleWarn = nil
        clockStarted = false
        phaseStartedAt = Date()
        phase = .seatQC(elapsed: 0, couple: nil)
        let need = allowCouple1 ? "couple≥1" : "couple=2"
        statusMessage = "Seat QC (\(need); GATT worn≠couple) — temple, off case, keep BLE up."
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
        statusMessage = "Seat QC ready — \(stats.snippet) (GATT worn may still be forced 1)."
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

    func beginSettleThenCues() {
        invalidatePendingCueStart()
        let generation = settleGeneration
        phase = .settling
        statusMessage = "Settling 2 s before cues…"
        savedThrottle = NRFConnectBLELogger.shared.throttleHighRateNotifications
        NRFConnectBLELogger.shared.throttleHighRateNotifications = false
        NRFConnectBLELogger.shared.clear()
        sessionStamp = DualProtocolAExport.makeSessionTimestamp()
        sessionOralPoints.removeAll()

        let delay = ProtocolASettleGate.delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.beginCueRun(scheduledGeneration: generation)
        }
    }

    private func invalidatePendingCueStart() {
        settleGeneration &+= 1
    }

    private func beginCueRun(scheduledGeneration: UInt) {
        let settling: Bool
        if case .settling = phase {
            settling = true
        } else {
            settling = false
        }
        guard ProtocolASettleGate.shouldStartCues(
            isSettling: settling,
            scheduledGeneration: scheduledGeneration,
            currentGeneration: settleGeneration
        ) else { return }
        cueStartedAt = Date()
        clockStarted = true
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
        clockStarted = false
        phase = .exporting
        statusMessage = "Writing Protocol A Setup export…"
        Task { await exportPack() }
    }

    private func exportPack() async {
        let oralID = deviceManager?.connectedDevices.first(where: { $0.type == .oralable })?.id.uuidString ?? "unknown"
        let oralPoints = sessionOralPoints
        let stats = coupleStats
        let stamp = sessionStamp

        do {
            let artifacts = try SingleProtocolAExport.writeSessionPack(
                oralablePoints: oralPoints,
                oralableID: oralID,
                couple: stats,
                sessionTimestamp: stamp.isEmpty ? nil : stamp,
                sessionStart: cueStartedAt,
                sessionEnd: Date()
            )
            restoreLoggerThrottle()
            exportArtifacts = artifacts
            phase = .done(artifacts)
            statusMessage = "Protocol A Setup complete."
            Logger.shared.info("[SingleProtocolA] Export \(artifacts.sessionTimestamp)")
        } catch {
            restoreLoggerThrottle()
            phase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            Logger.shared.error("[SingleProtocolA] Export failed: \(error.localizedDescription)")
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
        default:
            break
        }

        coupleSnippet = gate.statusSnippet()

        switch phase {
        case .seatQC:
            break
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
    }

    private func feedAccIfReady(mono: Double) {
        guard let x = lastAccX, let y = lastAccY, let z = lastAccZ else { return }
        let mag = (x * x + y * y + z * z).squareRoot()
        gate.feedAccMagnitudes([mag], monoS: mono)
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
        gate.tick(monoS: mono)
        coupleSnippet = gate.statusSnippet()

        switch phase {
        case .seatQC:
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
                        "Seat QC failed: couple=\(st) (need \(need); desk/unknown — reseat on temple, off case)"
                    )
                } else {
                    failSeatQC(
                        "Seat QC timeout: couple=\(st) (need \(need); enable Allow couple=1 to start on poor seat)"
                    )
                }
            }

        case .running:
            guard let started = cueStartedAt else { return }
            let elapsed = Date().timeIntervalSince(started)
            gate.setSessionElapsed(elapsed)
            if let st = gate.state, st == .poor, st != lastCoupleWarn {
                lastCoupleWarn = st
                statusMessage = "WARNING: couple=1 (on skin, weak pulse/vitals) — reseat if needed"
            }
            // Mid-session: unknown (PPG stall) or sustained desk → abort (Mac watchdog)
            if gate.state == nil {
                stopTimers()
                restoreLoggerThrottle()
                clockStarted = false
                let msg = "couple=unknown (PPG lost / cannot judge seat without BLE+PPG)"
                phase = .failed(msg)
                statusMessage = msg
                return
            }
            if gate.state == .desk {
                if deskSince == nil { deskSince = Date() }
                if let deskSince, Date().timeIntervalSince(deskSince) >= Self.coupleDeskAbortGraceS {
                    stopTimers()
                    restoreLoggerThrottle()
                    clockStarted = false
                    let msg = "couple=0 desk for \(Self.coupleDeskAbortGraceS)s — aborting Protocol A"
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

    @discardableResult
    private func failIfCaptureLinkDropped() -> Bool {
        switch phase {
        case .seatQC, .settling, .running:
            break
        default:
            return false
        }
        guard oralableConnected else {
            invalidatePendingCueStart()
            stopTimers()
            restoreLoggerThrottle()
            clockStarted = false
            gate.markUnknown()
            phase = .failed(Self.linkDropMessage)
            statusMessage = Self.linkDropMessage
            return true
        }
        return false
    }

    static let linkDropMessage =
        "Oralable dropped. FW 1.0.71+ stops sensors when BLE drops — restart Protocol A Setup."

    private var isRetryableFailure: Bool {
        if case .failed = phase { return true }
        if case .cancelled = phase { return true }
        if case .seatQCFailed = phase { return true }
        return false
    }

    private func restoreLoggerThrottle() {
        NRFConnectBLELogger.shared.throttleHighRateNotifications = savedThrottle
    }
}
