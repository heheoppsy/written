import SwiftUI
import Combine

enum LayoutMode: String, Sendable {
    case column
    case fullWidth
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var defaultsObserver: Any?

    init() {
        // Ensure any @AppStorage change triggers objectWillChange for cross-window updates
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    @AppStorage("currentThemeID") var currentThemeID: String = "void"
    @AppStorage("currentFontName") var currentFontName: String = "Lora-Regular"
    @AppStorage("currentFontSize") var currentFontSize: Double = 18
    @AppStorage("layoutMode") private var layoutModeRaw: String = "column"
    @AppStorage("lineSpacing") var lineSpacing: Double = 4
    @AppStorage("lastSerifFont") var lastSerifFont: String = "Lora-Regular"
    @AppStorage("lastSansFont") var lastSansFont: String = "Inter-Regular"
    @AppStorage("lastMonoFont") var lastMonoFont: String = ""
    @AppStorage("backgroundOpacityPct") var backgroundOpacityPct: Double = 20

    var backgroundOpacity: Double {
        backgroundOpacityPct / 100.0
    }
    @AppStorage("typewriterScrolling") var typewriterScrolling: Bool = false
    @AppStorage("typewriterFollowCursor") var typewriterFollowCursor: Bool = true
    @AppStorage("spellCheckEnabled") var spellCheckEnabled: Bool = false
    @AppStorage("columnWidthPercent") var columnWidthPercent: Double = 65
    @AppStorage("centeredText") var centeredText: Bool = false
    @AppStorage("hideFileExtensions") var hideFileExtensions: Bool = true
    @AppStorage("showWordCount") var showWordCount: Bool = true
    @AppStorage("vimModeEnabled") var vimModeEnabled: Bool = false
    @AppStorage("vimJJEscape") var vimJJEscape: Bool = true
    @AppStorage("currentLineHighlight") var currentLineHighlight: Bool = false
    @AppStorage("showSidebarButton") var showSidebarButton: Bool = true
    @AppStorage("hasSeenTutorial") var hasSeenTutorial: Bool = false

    var currentFontCategory: FontCategory {
        guard let font = FontManager.catalog.first(where: { $0.id == currentFontName }) else {
            return .mono // SF Mono default
        }
        return font.category
    }

    func lastUsedFont(for category: FontCategory) -> String {
        switch category {
        case .serif: return lastSerifFont
        case .sans: return lastSansFont
        case .mono: return lastMonoFont.isEmpty ? "SF-Mono" : lastMonoFont
        case .system: return "SF-Mono"
        }
    }

    func setLastUsedFont(_ fontID: String, for category: FontCategory) {
        switch category {
        case .serif: lastSerifFont = fontID
        case .sans: lastSansFont = fontID
        case .mono: lastMonoFont = fontID
        case .system: break
        }
    }

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: layoutModeRaw) ?? .column }
        set {
            objectWillChange.send()
            layoutModeRaw = newValue.rawValue
        }
    }

    var currentTheme: Theme {
        Theme.presets.first { $0.id == currentThemeID } ?? Theme.presets[0]
    }

    /// Fixed-size font for the settings preview (doesn't change with font size slider).
    var previewFont: NSFont {
        let size: CGFloat = 16
        if currentFontName.isEmpty || currentFontName == "SF-Mono" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        if currentFontName == "SF-Pro" {
            return NSFont.systemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: currentFontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var editorFont: NSFont {
        let size = CGFloat(currentFontSize)

        if currentFontName.isEmpty || currentFontName == "SF-Mono" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        if currentFontName == "SF-Pro" {
            return NSFont.systemFont(ofSize: size, weight: .regular)
        }

        return NSFont(name: currentFontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
