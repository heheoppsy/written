import AppKit

extension Theme {
    static let presets: [Theme] = [
        // MARK: - Solid Dark

        Theme(
            id: "midnight",
            name: "Midnight",
            backgroundColor: NSColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1),
            textColor: NSColor(red: 0.82, green: 0.83, blue: 0.88, alpha: 1),
            caretColor: NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1),
            selectionColor: NSColor(red: 0.22, green: 0.35, blue: 0.65, alpha: 0.65),
            sidebarBackgroundColor: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
            sidebarTextColor: NSColor(red: 0.68, green: 0.68, blue: 0.75, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: true
        ),

        Theme(
            id: "solarized-dark",
            name: "Solarized Dark",
            backgroundColor: NSColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1),
            textColor: NSColor(red: 0.58, green: 0.63, blue: 0.63, alpha: 1),
            caretColor: NSColor(red: 0.80, green: 0.29, blue: 0.09, alpha: 1),
            selectionColor: NSColor(red: 0.09, green: 0.33, blue: 0.42, alpha: 0.80),
            sidebarBackgroundColor: NSColor(red: 0.0, green: 0.12, blue: 0.15, alpha: 1),
            sidebarTextColor: NSColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: true
        ),

        Theme(
            id: "nord",
            name: "Nord",
            backgroundColor: NSColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1),
            textColor: NSColor(red: 0.85, green: 0.87, blue: 0.91, alpha: 1),
            caretColor: NSColor(red: 0.53, green: 0.75, blue: 0.82, alpha: 1),
            selectionColor: NSColor(red: 0.30, green: 0.36, blue: 0.48, alpha: 0.80),
            sidebarBackgroundColor: NSColor(red: 0.15, green: 0.17, blue: 0.22, alpha: 1),
            sidebarTextColor: NSColor(red: 0.62, green: 0.67, blue: 0.75, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: true
        ),

        Theme(
            id: "bubblegum",
            name: "Bubblegum",
            backgroundColor: NSColor(red: 0.22, green: 0.12, blue: 0.32, alpha: 1),
            textColor: NSColor(red: 0.92, green: 0.78, blue: 0.98, alpha: 1),
            caretColor: NSColor(red: 0.90, green: 0.42, blue: 0.92, alpha: 1),
            selectionColor: NSColor(red: 0.58, green: 0.30, blue: 0.72, alpha: 0.65),
            sidebarBackgroundColor: NSColor(red: 0.17, green: 0.08, blue: 0.26, alpha: 1),
            sidebarTextColor: NSColor(red: 0.78, green: 0.62, blue: 0.88, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: true
        ),

        // MARK: - Solid Light

        Theme(
            id: "paper",
            name: "Paper",
            backgroundColor: NSColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1),
            textColor: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1),
            caretColor: NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
            selectionColor: NSColor(red: 0.55, green: 0.68, blue: 0.95, alpha: 0.50),
            sidebarBackgroundColor: NSColor(red: 0.93, green: 0.93, blue: 0.92, alpha: 1),
            sidebarTextColor: NSColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: false
        ),

        Theme(
            id: "solarized-light",
            name: "Solarized Light",
            backgroundColor: NSColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1),
            textColor: NSColor(red: 0.35, green: 0.43, blue: 0.46, alpha: 1),
            caretColor: NSColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1),
            selectionColor: NSColor(red: 0.82, green: 0.76, blue: 0.58, alpha: 0.75),
            sidebarBackgroundColor: NSColor(red: 0.93, green: 0.91, blue: 0.84, alpha: 1),
            sidebarTextColor: NSColor(red: 0.35, green: 0.43, blue: 0.46, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: false
        ),

        Theme(
            id: "mint",
            name: "Mint",
            backgroundColor: NSColor(red: 0.91, green: 0.97, blue: 0.93, alpha: 1),
            textColor: NSColor(red: 0.12, green: 0.28, blue: 0.20, alpha: 1),
            caretColor: NSColor(red: 0.10, green: 0.58, blue: 0.38, alpha: 1),
            selectionColor: NSColor(red: 0.30, green: 0.72, blue: 0.50, alpha: 0.50),
            sidebarBackgroundColor: NSColor(red: 0.86, green: 0.94, blue: 0.89, alpha: 1),
            sidebarTextColor: NSColor(red: 0.18, green: 0.34, blue: 0.26, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: false
        ),

        Theme(
            id: "kitten",
            name: "Kitten",
            backgroundColor: NSColor(red: 1.0, green: 0.90, blue: 0.93, alpha: 1),
            textColor: NSColor(red: 0.55, green: 0.18, blue: 0.32, alpha: 1),
            caretColor: NSColor(red: 0.95, green: 0.30, blue: 0.50, alpha: 1),
            selectionColor: NSColor(red: 0.95, green: 0.48, blue: 0.62, alpha: 0.50),
            sidebarBackgroundColor: NSColor(red: 0.97, green: 0.85, blue: 0.89, alpha: 1),
            sidebarTextColor: NSColor(red: 0.55, green: 0.20, blue: 0.33, alpha: 1),
            isTranslucent: false,
            vibrancyMaterial: nil,
            isDark: false
        ),

        // MARK: - Transparent

        Theme(
            id: "void",
            name: "Void",
            backgroundColor: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
            textColor: NSColor(red: 0.85, green: 0.85, blue: 0.90, alpha: 1),
            caretColor: NSColor(red: 0.7, green: 0.7, blue: 0.9, alpha: 1),
            selectionColor: NSColor(red: 0.35, green: 0.35, blue: 0.60, alpha: 0.55),
            sidebarBackgroundColor: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
            sidebarTextColor: NSColor(red: 0.7, green: 0.7, blue: 0.8, alpha: 1),
            isTranslucent: true,
            vibrancyMaterial: .hudWindow,
            isDark: true
        ),

        Theme(
            id: "pale",
            name: "Pale",
            backgroundColor: NSColor(red: 0.16, green: 0.14, blue: 0.24, alpha: 1),
            textColor: NSColor(red: 0.78, green: 0.75, blue: 0.88, alpha: 1),
            caretColor: NSColor(red: 0.65, green: 0.55, blue: 0.90, alpha: 1),
            selectionColor: NSColor(red: 0.42, green: 0.36, blue: 0.65, alpha: 0.65),
            sidebarBackgroundColor: NSColor(red: 0.13, green: 0.11, blue: 0.20, alpha: 1),
            sidebarTextColor: NSColor(red: 0.65, green: 0.60, blue: 0.78, alpha: 1),
            isTranslucent: true,
            vibrancyMaterial: .hudWindow,
            isDark: true
        ),

        Theme(
            id: "forest",
            name: "Forest",
            backgroundColor: NSColor(red: 0.06, green: 0.10, blue: 0.07, alpha: 1),
            textColor: NSColor(red: 0.65, green: 0.82, blue: 0.60, alpha: 1),
            caretColor: NSColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1),
            selectionColor: NSColor(red: 0.18, green: 0.38, blue: 0.18, alpha: 0.65),
            sidebarBackgroundColor: NSColor(red: 0.04, green: 0.08, blue: 0.05, alpha: 1),
            sidebarTextColor: NSColor(red: 0.50, green: 0.70, blue: 0.50, alpha: 1),
            isTranslucent: true,
            vibrancyMaterial: .hudWindow,
            isDark: true
        ),

        Theme(
            id: "fog",
            name: "Fog",
            backgroundColor: NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1),
            textColor: NSColor(red: 0.28, green: 0.28, blue: 0.33, alpha: 1),
            caretColor: NSColor(red: 0.30, green: 0.30, blue: 0.40, alpha: 1),
            selectionColor: NSColor(red: 0.48, green: 0.58, blue: 0.85, alpha: 0.45),
            sidebarBackgroundColor: NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1),
            sidebarTextColor: NSColor(red: 0.30, green: 0.30, blue: 0.35, alpha: 1),
            isTranslucent: true,
            vibrancyMaterial: .hudWindow,
            isDark: false
        ),
    ]
}
