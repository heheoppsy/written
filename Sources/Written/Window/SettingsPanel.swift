import AppKit
import SwiftUI

@MainActor
final class SettingsPanel {
    private var panel: NSPanel?
    private var resizeObserver: Any?
    private var parentWindow: NSWindow?
    private var selectedTab: SettingsTab = .general

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo parentWindow: NSWindow, settings: AppSettings) {
        if let panel = panel, panel.isVisible {
            close()
        } else {
            show(relativeTo: parentWindow, settings: settings)
        }
    }

    func show(relativeTo parentWindow: NSWindow, settings: AppSettings) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let onDismiss: () -> Void = { [weak self] in
            self?.close()
        }

        self.parentWindow = parentWindow

        // Panel fills parent window height minus fixed margins
        let parentFrame = parentWindow.frame
        let margin: CGFloat = 48
        let panelHeight = parentFrame.height - margin * 2
        let panelWidth: CGFloat = 420

        let tabBinding = Binding<SettingsTab>(
            get: { [weak self] in self?.selectedTab ?? .general },
            set: { [weak self] in self?.selectedTab = $0 }
        )
        let content = SettingsPanelContent(
            settings: settings,
            selectedTab: tabBinding,
            availableHeight: panelHeight,
            onDismiss: onDismiss
        )
        let hostingView = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.level = NSWindow.Level.floating
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView
        panel.alphaValue = 0

        let x = parentFrame.midX - panelWidth / 2
        let y = parentFrame.origin.y + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        // Track parent window resize/move to keep panel centered and scaled
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPanel()
            }
        }
    }

    func close() {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        guard let panel = panel else { return }
        let parentRef = panel.parent

        // Fade out then remove
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                parentRef?.removeChildWindow(panel)
                panel.orderOut(nil)
                self?.panel = nil
                self?.parentWindow = nil
            }
        })

        NotificationCenter.default.post(name: .settingsClosed, object: nil)
    }

    private func repositionPanel() {
        guard let panel = panel, let parentWindow = parentWindow else { return }
        let parentFrame = parentWindow.frame
        let margin: CGFloat = 48
        let panelWidth: CGFloat = 420
        let panelHeight = parentFrame.height - margin * 2

        let x = parentFrame.midX - panelWidth / 2
        let y = parentFrame.origin.y + margin

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        // Update the SwiftUI content's available height
        if let hostingView = panel.contentView as? NSHostingView<SettingsPanelContent> {
            var content = hostingView.rootView
            content.availableHeight = panelHeight
            hostingView.rootView = content
        }
    }
}
