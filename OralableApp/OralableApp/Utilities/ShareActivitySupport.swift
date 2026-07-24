//
//  ShareActivitySupport.swift
//  OralableApp
//
//  UIActivityViewController helpers. Raw file URLs (Documents, Caches) can cause
//  ShareSheet / Collaboration to log -10814, 3328, and "CKShare/SWY" probing.
//  We copy to a unique path under the app tmp directory and share via UIActivityItemSource
//  with an explicit UTType, then remove copies after a delay so Save to Files / WhatsApp
//  can finish async imports.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Prepare items

enum ShareActivityItems {

    /// Seconds to keep temp share copies after the sheet closes (async targets need time to read the file).
    static let tempFileRetentionSeconds: TimeInterval = 300

    /// Returns activity items and temp file URLs that must be deleted after sharing completes.
    static func preparingForShare(_ items: [Any]) -> (prepared: [Any], tempURLsToDelete: [URL]) {
        var tempURLsToDelete: [URL] = []
        let prepared: [Any] = items.map { item in
            guard let url = item as? URL, url.isFileURL else { return item }
            let contentType = utType(forFileURL: url)
            // CSV: share in-memory data — avoids LaunchServices -10814 / CKShare probing on tmp file URLs.
            if contentType == .commaSeparatedText, let data = try? Data(contentsOf: url) {
                return ShareableCSVDataItem(filename: url.lastPathComponent, data: data)
            }
            do {
                let shareURL = try makeSecureShareCopy(of: url)
                if shareURL != url {
                    tempURLsToDelete.append(shareURL)
                }
                return ShareableFileItem(fileURL: shareURL)
            } catch {
                return ShareableFileItem(fileURL: url)
            }
        }
        return (prepared, tempURLsToDelete)
    }

    /// Copy into tmp with a unique name so LaunchServices / file-provider does not treat the path as an iCloud/Caches document.
    static func makeSecureShareCopy(of url: URL) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dest = base.appendingPathComponent("oralable_share_\(UUID().uuidString)_\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
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

// MARK: - Activity item sources

/// In-memory CSV — avoids file-URL LaunchServices errors (-10814, CKShare/SWY).
final class ShareableCSVDataItem: NSObject, UIActivityItemSource {
    private let filename: String
    private let data: Data

    init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        filename
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        data
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.commaSeparatedText.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        filename
    }
}

/// File URL wrapper with explicit UTType — for PDF/JSON exports.
final class ShareableFileItem: NSObject, UIActivityItemSource {
    private let fileURL: URL
    private let contentType: UTType

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.contentType = ShareActivityItems.utType(forFileURL: fileURL)
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        contentType.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        fileURL.lastPathComponent
    }
}

// MARK: - Root presenter (avoids SwiftUI sheet-on-sheet failures)

enum SharePresentationSupport {

    /// Topmost view controller — present pickers here, not inside a SwiftUI `.sheet`.
    @MainActor
    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// Native Files folder picker — do not wrap in SwiftUI `.sheet` (breaks on device).
    @MainActor
    static func presentSaveToFiles(urls: [URL]) {
        guard let presenter = topViewController() else {
            Logger.shared.error("[SharePresentation] Save to Files: no view controller")
            return
        }

        let exportURLs = urls

        let picker = UIDocumentPickerViewController(forExporting: exportURLs, asCopy: true)
        picker.shouldShowFileExtensions = true
        picker.modalPresentationStyle = .formSheet

        if let popover = picker.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(picker, animated: true)
        Logger.shared.info("[SharePresentation] Save to Files presented for \(exportURLs.map(\.lastPathComponent).joined(separator: ", "))")
    }

    private static var shareCleanupWorkItem: DispatchWorkItem?
    private static var shareTempURLs: [URL] = []

    @MainActor
    static func presentShareSheet(items: [Any]) {
        guard let presenter = topViewController() else {
            Logger.shared.error("[SharePresentation] Share sheet: no view controller")
            return
        }

        let (prepared, tempURLs) = ShareActivityItems.preparingForShare(items)
        shareTempURLs = tempURLs

        let vc = UIActivityViewController(activityItems: prepared, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, error in
            if let error {
                Logger.shared.warning("[SharePresentation] Share completed=\(completed) error: \(error.localizedDescription)")
            }
            scheduleShareTempCleanup()
        }

        if let popover = vc.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(vc, animated: true)
    }

    private static func scheduleShareTempCleanup() {
        shareCleanupWorkItem?.cancel()
        let work = DispatchWorkItem {
            for url in shareTempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            shareTempURLs.removeAll()
        }
        shareCleanupWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ShareActivityItems.tempFileRetentionSeconds,
            execute: work
        )
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
        vc.completionWithItemsHandler = { [weak coordinator = context.coordinator] _, completed, _, error in
            if let error {
                Logger.shared.warning("[ShareSheet] Activity completed=\(completed) error: \(error.localizedDescription)")
            }
            coordinator?.scheduleTempShareFileCleanup()
        }

        if let popover = vc.popoverPresentationController {
            popover.permittedArrowDirections = []
            popover.sourceView = UIView(frame: CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0))
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    final class Coordinator {
        var tempURLsToDelete: [URL] = []
        private var cleanupWorkItem: DispatchWorkItem?

        func scheduleTempShareFileCleanup() {
            cleanupWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.removeTempShareFiles()
            }
            cleanupWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + ShareActivityItems.tempFileRetentionSeconds,
                execute: work
            )
        }

        func removeTempShareFiles() {
            for url in tempURLsToDelete {
                try? FileManager.default.removeItem(at: url)
            }
            tempURLsToDelete.removeAll()
        }
    }
}
