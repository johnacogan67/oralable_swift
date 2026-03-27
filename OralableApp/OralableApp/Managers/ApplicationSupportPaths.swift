//
//  ApplicationSupportPaths.swift
//  OralableApp
//
//  Stable on-disk locations under Application Support (trial / long recordings).
//

import Foundation

enum ApplicationSupportPaths {
    /// Hourly memory-flush CSV spillover (paired with AutoFlushService).
    static var memoryFlushDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Oralable/MemoryFlush", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
