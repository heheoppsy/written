import AppKit

struct Theme: Identifiable, Sendable {
    let id: String
    let name: String
    let backgroundColor: NSColor
    let textColor: NSColor
    let caretColor: NSColor
    let selectionColor: NSColor
    let sidebarBackgroundColor: NSColor
    let sidebarTextColor: NSColor
    let isTranslucent: Bool
    let vibrancyMaterial: NSVisualEffectView.Material?
    let isDark: Bool
}
