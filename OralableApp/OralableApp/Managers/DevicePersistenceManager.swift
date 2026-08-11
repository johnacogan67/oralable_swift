//
//  DevicePersistenceManager.swift
//  OralableApp
//
//  Manages persistence of remembered devices for auto-reconnect functionality
//

import Foundation

class DevicePersistenceManager {
    static let shared = DevicePersistenceManager()
    private let rememberedDevicesKey = "rememberedOralableDevices"

    struct RememberedDevice: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let dateAdded: Date

        static func == (lhs: RememberedDevice, rhs: RememberedDevice) -> Bool {
            return lhs.id == rhs.id
        }
    }

    private init() {}

    func getRememberedDevices() -> [RememberedDevice] {
        guard let data = UserDefaults.standard.data(forKey: rememberedDevicesKey),
              let devices = try? JSONDecoder().decode([RememberedDevice].self, from: data) else {
            return []
        }
        return devices
    }

    func rememberDevice(id: String, name: String) {
        var devices = getRememberedDevices()
        let newDevice = RememberedDevice(id: id, name: name, dateAdded: Date())
        if !devices.contains(where: { $0.id == id }) {
            devices.append(newDevice)
            saveDevices(devices)
            Logger.shared.info("[DevicePersistenceManager] Remembered device: \(name)")
        }
    }

    func forgetDevice(id: String) {
        var devices = getRememberedDevices()
        if let device = devices.first(where: { $0.id == id }) {
            Logger.shared.info("[DevicePersistenceManager] Forgetting device: \(device.name)")
        }
        devices.removeAll { $0.id == id }
        saveDevices(devices)
    }

    func forgetAllDevices() {
        UserDefaults.standard.removeObject(forKey: rememberedDevicesKey)
        Logger.shared.info("[DevicePersistenceManager] Forgot all remembered devices")
    }

    func isDeviceRemembered(id: String) -> Bool {
        return getRememberedDevices().contains { $0.id == id }
    }

    /// Check if any Oralable device has been previously paired
    func hasOralableDevicePaired() -> Bool {
        return getRememberedDevices().contains { device in
            device.name.lowercased().contains("oralable")
        }
    }

    /// Check if any ANR device has been previously paired
    func hasANRDevicePaired() -> Bool {
        return getRememberedDevices().contains { device in
            device.name.lowercased().contains("anr") || device.name.lowercased().contains("m40")
        }
    }

    /// Get remembered device of a specific type
    func getRememberedDevice(ofType type: DeviceType) -> RememberedDevice? {
        return getRememberedDevices().first { device in
            switch type {
            case .oralable:
                return device.name.lowercased().contains("oralable")
            case .anr:
                return device.name.lowercased().contains("anr") || device.name.lowercased().contains("m40")
            case .demo:
                return device.name.lowercased().contains("demo")
            }
        }
    }

    private func saveDevices(_ devices: [RememberedDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: rememberedDevicesKey)
        }
    }
}
