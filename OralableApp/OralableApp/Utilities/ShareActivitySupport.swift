//
//  ShareActivitySupport.swift
//  OralableApp
//
//  UIActivityViewController helpers. Raw file URLs (Documents, Caches) can cause
//  ShareSheet / Collaboration to log -10814, 3328, and "CKShare/SWY" probing.
//  We copy to a unique path under the app tmp directory and share via NSItemProvider
//  with an explicit UTType, then remove copies when the sheet dismisses.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Prepare items

enum ShareActivityItems {

    /// Returns activity items and temp file URLs that must be deleted after the share sheet closes.
    static func preparingForShare(_ items: [Any]) -> (prepared: [Any], tempURLsToDelete: [URL]) {
        var tempURLsToDelete: [URL] = []
        let prepared: [Any] = items.map { item in
            guard let url = item as? URL, url.isFileURL else { return item }
            do {
                let shareURL = try makeSecureShareCopy(of: url)
                if shareURL != url {
                    tempURLsToDelete.append(shareURL)
                }
                return itemProvider(forFileURL: shareURL, contentType: utType(forFileURL: shareURL))
            } catch {
                // Fall back to original URL if copy fails (read-only volume, etc.)
                return itemProvider(forFileURL: url, contentType: utType(forFileURL: url))
            }
        }
        return (prepared, tempURLsToDelete)
    }

    /// Copy into tmp with a unique name so LaunchServices / file-provider does not treat the path as an iCloud/Caches document.
    private static func makeSecureShareCopy(of url: URL) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dest = base.appendingPathComponent("oralable_share_\(UUID().uuidString)_\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    private static func itemProvider(forFileURL url: URL, contentType: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        let typeId = contentType.identifier
        provider.registerFileRepresentation(
            forTypeIdentifier: typeId,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(url, true, nil)
            return nil
        }
        provider.suggestedName = url.lastPathComponent
        return provider
    }

    static func utType(forFileURL url: URL) -> UTType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv": return .commaSeparatedText
        case "pdf": return .pdf
        case "json": return .json
        case "txt", "log": return .plainText
        default:
            return UTType(filenameExtension: ext) ?? .data
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let (prepared, tempURLs) = ShareActivityItems.preparingForShare(items)
        context.coordinator.tempURLsToDelete = tempURLs

        let vc = UIActivityViewController(activityItems: prepared, applicationActivities: nil)
        vc.completionWithItemsHandler = { [weak coordinator = context.coordinator] _, _, _, _ in
            coordinator?.removeTempShareFiles()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    final class Coordinator {
        var tempURLsToDelete: [URL] = []

        func removeTempShareFiles() {
            for url in tempURLsToDelete {
                try? FileManager.default.removeItem(at: url)
            }
            tempURLsToDelete.removeAll()
        }
    }
}
