//
//  MemoryFlushStatus.swift
//  OralableApp
//
//  UI signal: hourly flush wrote CSV under Application Support.
//

import Foundation

@MainActor
final class MemoryFlushStatus: ObservableObject {
    static let shared = MemoryFlushStatus()

    @Published private(set) var lastApplicationSupportFlushAt: Date?

    private init() {}

    func recordFlushSuccess() {
        lastApplicationSupportFlushAt = Date()
    }
}
