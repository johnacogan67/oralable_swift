//
//  PrimaryDeviceSlotPolicy.swift
//  OralableApp
//
//  The primary slot drives placement, battery, firmware status, and the
//  Temporalis sleep-calibration gate. Only an Oralable may inherit it.
//

import Foundation

enum PrimaryDeviceSlotPolicy {
    /// Primary after `disconnectedPeripheralId` drops.
    /// Another connected Oralable may inherit the slot. ANR must not.
    static func primaryAfterDisconnect(
        disconnectedPeripheralId: UUID,
        connectedDevices: [DeviceInfo],
        currentPrimary: DeviceInfo?
    ) -> DeviceInfo? {
        guard currentPrimary?.peripheralIdentifier == disconnectedPeripheralId else {
            return currentPrimary
        }
        return connectedDevices.first {
            $0.peripheralIdentifier != disconnectedPeripheralId && $0.type == .oralable
        }
    }

    /// Primary after `candidate` connects.
    /// An Oralable takes the slot when it is empty or held by a non-Oralable.
    /// A non-Oralable becomes primary only when the slot is empty.
    static func primaryAfterConnect(
        candidate: DeviceInfo,
        currentPrimary: DeviceInfo?
    ) -> DeviceInfo? {
        if candidate.type == .oralable {
            if currentPrimary == nil || currentPrimary?.type != .oralable {
                return candidate
            }
            return currentPrimary
        }
        return currentPrimary ?? candidate
    }

    /// Erase a stored REV10 calibration only when a different Oralable is now primary.
    static func shouldClearSleepCalibration(
        storedPeripheralId: UUID,
        primary: DeviceInfo?
    ) -> Bool {
        guard let primary, primary.type == .oralable, let pid = primary.peripheralIdentifier else {
            return false
        }
        return pid != storedPeripheralId
    }
}
