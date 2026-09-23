//
//  AutomaticRecordingCapturePolicy.swift
//  OralableApp
//
//  Automatic overnight recording is tied to Oralable clinical capture readiness,
// not to every peripheral in a multi-device (Oralable + ANR) session.
//

import Foundation
import OralableCore

enum AutomaticRecordingCapturePolicy {

    /// True when at least one Oralable peripheral is fully ready.
    static func hasReadyOralable(
        connectedDevices: [DeviceInfo],
        readiness: [UUID: ConnectionReadiness]
    ) -> Bool {
        for info in connectedDevices where info.type == .oralable {
            guard let id = info.peripheralIdentifier else { continue }
            if case .ready = readiness[id] ?? .disconnected {
                return true
            }
        }
        return false
    }

    /// ANR (and other non-Oralable) readiness must not start/resume automatic recording.
    static func shouldStartOrResume(for deviceType: DeviceType) -> Bool {
        deviceType == .oralable
    }
}
