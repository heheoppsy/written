import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowFactory = WindowFactory()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register any previously cached Google Fonts
        _ = FontManager.shared

        // Shadow directory must exist — crash recovery depends on it.
        // Retry in a loop until the user gives up or it succeeds.
        if !ShadowFileManager.shared.isReady {
            while true {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Cannot create recovery directory"
                alert.informativeText = "Written needs \(ShadowFileManager.shadowsDir.path) to protect your work from data loss. Check disk permissions or free space, then try again."
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Quit")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if ShadowFileManager.shared.ensureDirectory() { break }
                } else {
                    NSApp.terminate(nil)
                    return
                }
            }
        }

        let args = ProcessInfo.processInfo.arguments

        // Parse --show flag (used after move-to-Applications relaunch)
        var showOverlay: String?
        if let idx = args.firstIndex(of: "--show"), idx + 1 < args.count {
            showOverlay = args[idx + 1]
        }

        // First non-flag argument is a folder path (from CLI)
        let folderArg = args.count > 1 && !args[1].hasPrefix("-") ? args[1] : nil

        // Check for crash recovery before normal launch
        let shadows = EditorViewModel.checkForRecoverableShadows()
        if !shadows.isEmpty {
            if attemptCrashRecovery(shadows: shadows, showOverlay: showOverlay) != nil {
                // Recovery handled — window already created
                return
            }
            // User discarded — fall through to normal launch
        }

        if let folderPath = folderArg {
            let url = URL(fileURLWithPath: folderPath).standardized
            windowFactory.ensureWindow(folderURL: url, launchOverlay: showOverlay, delegate: self)
        } else {
            windowFactory.ensureWindow(launchOverlay: showOverlay, delegate: self)
        }
    }

    // MARK: - Crash Recovery

    private func attemptCrashRecovery(shadows: [(url: URL, meta: ShadowFileManager.ShadowMeta)], showOverlay: String?) -> Bool? {
        // Sort by most recent first
        let sorted = shadows.sorted { $0.meta.shadowWriteDate > $1.meta.shadowWriteDate }

        // Filter to readable shadows with actual content
        let readable = sorted.compactMap { shadow -> (url: URL, meta: ShadowFileManager.ShadowMeta, text: String)? in
            guard let data = ShadowFileManager.shared.readShadow(at: shadow.url) else { return nil }
            // Skip empty/whitespace-only shadows (orphaned from discarded untitled docs)
            let trimmed = data.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                ShadowFileManager.shared.deleteShadow(at: shadow.url)
                return nil
            }
            return (shadow.url, shadow.meta, data.text)
        }

        guard let newest = readable.first else {
            ShadowFileManager.shared.removeAllShadows()
            return nil
        }

        // Build file list and check for disk changes
        struct RecoveryInfo {
            let name: String
            let diskChanged: Bool
        }

        let infos: [RecoveryInfo] = readable.map { item in
            if let realPath = item.meta.realFilePath {
                let name = URL(fileURLWithPath: realPath).lastPathComponent
                var changed = false
                if let lastMod = item.meta.lastDiskModDate,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: realPath),
                   let diskMod = attrs[.modificationDate] as? Date,
                   diskMod > lastMod {
                    changed = true
                }
                return RecoveryInfo(name: name, diskChanged: changed)
            }
            return RecoveryInfo(name: "Untitled", diskChanged: false)
        }

        let anyDiskChanged = infos.contains { $0.diskChanged }

        let alert = NSAlert()
        alert.messageText = "Recover unsaved changes?"

        var info = ""
        if infos.count == 1 {
            info = "Found unsaved changes for \"\(infos[0].name)\"."
        } else {
            let list = infos.map { $0.name }.joined(separator: ", ")
            info = "Found unsaved changes for \(infos.count) files: \(list)."
        }
        if anyDiskChanged {
            info += " Some files on disk have also changed since your last save."
        }
        alert.informativeText = info

        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: infos.count > 1 ? "Discard All" : "Discard")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Recover the most recent shadow. Other shadows remain on disk —
            // they'll be recovered naturally when those files are opened, or
            // offered again on next launch if unused.
            if let realPath = newest.meta.realFilePath {
                let fileURL = URL(fileURLWithPath: realPath)
                let folderURL = fileURL.deletingLastPathComponent()
                windowFactory.ensureWindow(
                    fileURL: fileURL,
                    folderURL: folderURL,
                    recoveredText: newest.text,
                    launchOverlay: showOverlay,
                    delegate: self
                )
            } else {
                windowFactory.ensureWindow(
                    recoveredText: newest.text,
                    launchOverlay: showOverlay,
                    delegate: self
                )
            }
            return true
        } else {
            ShadowFileManager.shared.removeAllShadows()
            return nil
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowFactory.promptToSaveIfNeeded() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    // MARK: - URL Scheme

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "written" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if components.host == "open" {
            let items = components.queryItems ?? []
            let showOverlay = items.first(where: { $0.name == "show" })?.value

            if let fileParam = items.first(where: { $0.name == "file" })?.value {
                let fileURL = URL(fileURLWithPath: fileParam).standardized
                // Only open plaintext files via URL scheme
                guard fileURL.pathExtension.lowercased() == "txt" else { return }
                windowFactory.ensureWindow(fileURL: fileURL, folderURL: fileURL.deletingLastPathComponent(), launchOverlay: showOverlay, delegate: self)
            } else if let folderParam = items.first(where: { $0.name == "folder" })?.value {
                let folderURL = URL(fileURLWithPath: folderParam).standardized
                windowFactory.ensureWindow(folderURL: folderURL, launchOverlay: showOverlay, delegate: self)
            } else if showOverlay != nil {
                windowFactory.ensureWindow(launchOverlay: showOverlay, delegate: self)
            }
        }
    }
}
