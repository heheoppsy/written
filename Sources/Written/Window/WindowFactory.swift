import AppKit
import SwiftUI

@MainActor
final class WindowFactory: NSObject, NSWindowDelegate {
    private let settings = AppSettings.shared
    private var mainWindow: NSWindow?
    private var viewModel: EditorViewModel?
    private var titleObserver: Any?
    private var quitObserver: Any?
    private var themeObserver: Any?
    private var dirtyObserver: Any?
    private var quitSaveObserver: Any?
    private var quitDiscardObserver: Any?
    /// Set after the user has resolved unsaved work, so re-entrant terminate calls don't double-prompt.
    private var safeToQuit = false

    func ensureWindow(fileURL: URL? = nil, folderURL: URL? = nil, recoveredText: String? = nil, launchOverlay: String? = nil, delegate: AppDelegate) {
        if let existing = mainWindow, existing.isVisible {
            if let fileURL = fileURL {
                NotificationCenter.default.post(name: .openFileInWindow, object: fileURL)
            } else if let folderURL = folderURL {
                NotificationCenter.default.post(name: .folderSelected, object: folderURL)
            }
            if let launchOverlay {
                NotificationCenter.default.post(name: .showOverlay, object: launchOverlay)
            }
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let viewModel: EditorViewModel

        if let recoveredText = recoveredText {
            if let fileURL = fileURL {
                // Crash recovery for named file
                viewModel = EditorViewModel(fileURL: fileURL, recoveredText: recoveredText, folderURL: folderURL)
                // Pre-load other recovered shadows so they restore on file switch
                viewModel.loadRemainingRecoveryShadows()
            } else {
                // Crash recovery for untitled
                viewModel = EditorViewModel(recoveredText: recoveredText)
            }
        } else if let fileURL = fileURL {
            do {
                viewModel = try EditorViewModel(fileURL: fileURL)
            } catch {
                print("Failed to open file: \(error)")
                viewModel = EditorViewModel()
            }
        } else {
            viewModel = EditorViewModel(folderURL: folderURL)
        }

        let startInEditor = fileURL != nil || recoveredText != nil
        let showSidebar = folderURL != nil && fileURL == nil && recoveredText == nil

        let contentView = MainContentView(
            viewModel: viewModel,
            settings: settings,
            showSidebar: showSidebar,
            startInEditor: startInEditor || showSidebar,
            initialOverlay: launchOverlay,
            onOpenFolder: {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    NotificationCenter.default.post(name: .folderSelected, object: url)
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Written"
        window.titlebarAppearsTransparent = true
        // Keep the title visible in the titlebar area — Tahoe renders this with glass
        window.titleVisibility = .visible

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.setFrameSize(NSSize(width: 900, height: 700))
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 520, height: 560)
        window.minSize = NSSize(width: 520, height: 560)
        window.setFrameAutosaveName("WrittenMainWindow")
        if !window.setFrameUsingName("WrittenMainWindow") {
            window.center()
        }

        // Allow transparency — the SwiftUI view handles the background.
        // The hosting view's layer must also be non-opaque so the
        // NSVisualEffectView can composite the desktop through.
        window.isOpaque = false
        window.backgroundColor = .clear
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = .clear
        window.isMovableByWindowBackground = true

        window.collectionBehavior.insert(.fullScreenPrimary)

        self.viewModel = viewModel
        window.delegate = self
        mainWindow = window
        window.makeKeyAndOrderFront(nil)

        // Listen for quit requests (Cmd+Q routed through SwiftUI commands)
        quitObserver = NotificationCenter.default.addObserver(
            forName: .quitApp,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.promptToSaveIfNeeded() {
                    self.safeToQuit = true
                    NSApp.terminate(nil)
                }
            }
        }

        // Listen for quit confirmation results from the custom modal
        quitSaveObserver = NotificationCenter.default.addObserver(
            forName: .quitConfirmSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.completeQuit(saveAll: true) }
        }

        quitDiscardObserver = NotificationCenter.default.addObserver(
            forName: .quitConfirmDiscard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.completeQuit(saveAll: false) }
        }

        // Listen for title updates from MainContentView
        titleObserver = NotificationCenter.default.addObserver(
            forName: .updateWindowTitle,
            object: nil,
            queue: .main
        ) { [weak window] notification in
            let title = notification.object as? String
            Task { @MainActor in
                if let title { window?.title = title }
            }
        }

        // Track dirty state in the window close button dot
        dirtyObserver = NotificationCenter.default.addObserver(
            forName: .documentDirtyChanged,
            object: nil,
            queue: .main
        ) { [weak window] notification in
            let dirty = notification.object as? Bool ?? false
            MainActor.assumeIsolated {
                window?.isDocumentEdited = dirty
            }
        }
        // Apply initial dirty state (the notification may have fired before the observer was registered)
        window.isDocumentEdited = viewModel.isDirty

        // Match title bar appearance to theme (dark/light)
        updateWindowAppearance(window)
        themeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.updateWindowAppearance(window)
            }
        }

    }

    private func updateWindowAppearance(_ window: NSWindow) {
        let isDark = settings.currentTheme.isDark
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    // MARK: - Save Prompt

    /// Returns true if safe to proceed (no unsaved work, or user saved/discarded).
    /// Returns false if user cancelled (or if showing the custom quit modal).
    func promptToSaveIfNeeded() -> Bool {
        if safeToQuit { return true }

        guard let vm = viewModel else { return true }

        // Synchronous flush from the text view
        let currentText = vm.flushEditorText?() ?? vm.document.text
        vm.textDidChange(currentText)

        // No dirty buffers — safe to quit
        guard vm.hasAnyDirtyBuffers else { return true }

        // Show our custom quit confirmation modal — cancel the quit for now
        NotificationCenter.default.post(name: .showQuitConfirmation, object: nil)
        return false
    }

    /// Called by MainContentView after the user resolves the quit modal.
    func completeQuit(saveAll: Bool) {
        guard let vm = viewModel else { return }

        if saveAll {
            // If current doc is untitled, need save panel
            if vm.document.fileURL == nil && !vm.document.text.isEmpty {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.plainText]
                panel.nameFieldStringValue = "Untitled.txt"
                let saveResponse = panel.runModal()
                guard saveResponse == .OK, let url = panel.url else { return }
                vm.assignFile(url: url)
                RecentItemsService.shared.add(url: url)
            }
            do {
                try vm.saveAllDirtyBuffers()
            } catch {
                // Save failed — don't quit. Shadows are still intact as safety net.
                print("Save failed during quit: \(error)")
                return
            }
        } else {
            vm.discardAllBuffers()
        }

        safeToQuit = true
        NSApp.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, 520),
            height: max(frameSize.height, 560)
        )
    }

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            promptToSaveIfNeeded()
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            for observer in [titleObserver, quitObserver, themeObserver, dirtyObserver, quitSaveObserver, quitDiscardObserver] {
                if let observer { NotificationCenter.default.removeObserver(observer) }
            }
            titleObserver = nil
            quitObserver = nil
            themeObserver = nil
            dirtyObserver = nil
            quitSaveObserver = nil
            quitDiscardObserver = nil
            mainWindow = nil
            viewModel = nil
        }
    }
}
