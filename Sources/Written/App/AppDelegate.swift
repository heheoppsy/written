import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowFactory = WindowFactory()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up any temp drafts from previous sessions
        EditorViewModel.cleanupOrphanedDrafts()

        // Register any previously cached Google Fonts
        _ = FontManager.shared

        let args = ProcessInfo.processInfo.arguments

        // Parse --show flag (used after move-to-Applications relaunch)
        var showOverlay: String?
        if let idx = args.firstIndex(of: "--show"), idx + 1 < args.count {
            showOverlay = args[idx + 1]
        }

        // First non-flag argument is a folder path (from CLI)
        let folderArg = args.count > 1 && !args[1].hasPrefix("-") ? args[1] : nil

        if let folderPath = folderArg {
            let url = URL(fileURLWithPath: folderPath).standardized
            windowFactory.ensureWindow(folderURL: url, launchOverlay: showOverlay, delegate: self)
        } else {
            windowFactory.ensureWindow(launchOverlay: showOverlay, delegate: self)
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
                let fileURL = URL(fileURLWithPath: fileParam)
                windowFactory.ensureWindow(fileURL: fileURL, folderURL: fileURL.deletingLastPathComponent(), launchOverlay: showOverlay, delegate: self)
            } else if let folderParam = items.first(where: { $0.name == "folder" })?.value {
                let folderURL = URL(fileURLWithPath: folderParam)
                windowFactory.ensureWindow(folderURL: folderURL, launchOverlay: showOverlay, delegate: self)
            } else if showOverlay != nil {
                windowFactory.ensureWindow(launchOverlay: showOverlay, delegate: self)
            }
        }
    }
}
