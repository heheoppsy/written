import AppKit
import CoreText

enum FontCategory: String, CaseIterable, Sendable {
    case serif = "Serif"
    case sans = "Sans"
    case mono = "Mono"
    case system = "System"
}

struct CuratedFont: Identifiable, Sendable {
    let id: String // PostScript name for Regular weight
    let displayName: String
    let category: FontCategory

    var isSystem: Bool { category == .system }
}

@MainActor
final class FontManager: ObservableObject {
    static let shared = FontManager()

    @Published var availableFonts: Set<String> = [] // PostScript names that are ready to use

    init() {
        registerBundledFonts()
    }

    // MARK: - Font Catalog

    static let catalog: [CuratedFont] = [
        // System
        CuratedFont(id: "SF-Mono", displayName: "SF Mono", category: .system),
        CuratedFont(id: "SF-Pro", displayName: "SF Pro", category: .system),

        // Serif
        CuratedFont(id: "Lora-Regular", displayName: "Lora", category: .serif),
        CuratedFont(id: "Merriweather-Regular", displayName: "Merriweather", category: .serif),
        CuratedFont(id: "PlayfairDisplay-Regular", displayName: "Playfair Display", category: .serif),
        CuratedFont(id: "SourceSerif4-Regular", displayName: "Source Serif 4", category: .serif),
        CuratedFont(id: "CrimsonText-Regular", displayName: "Crimson Text", category: .serif),
        CuratedFont(id: "EBGaramond-Regular", displayName: "EB Garamond", category: .serif),
        CuratedFont(id: "CormorantGaramond-Regular", displayName: "Cormorant Garamond", category: .serif),
        CuratedFont(id: "Literata-Regular", displayName: "Literata", category: .serif),
        CuratedFont(id: "Spectral-Regular", displayName: "Spectral", category: .serif),
        CuratedFont(id: "LibreBaskerville-Regular", displayName: "Libre Baskerville", category: .serif),

        // Sans
        CuratedFont(id: "Inter-Regular", displayName: "Inter", category: .sans),
        CuratedFont(id: "SourceSans3-Regular", displayName: "Source Sans 3", category: .sans),
        CuratedFont(id: "WorkSans-Regular", displayName: "Work Sans", category: .sans),
        CuratedFont(id: "Nunito-Regular", displayName: "Nunito", category: .sans),
        CuratedFont(id: "Karla-Regular", displayName: "Karla", category: .sans),
        CuratedFont(id: "Lato-Regular", displayName: "Lato", category: .sans),

        // Mono
        CuratedFont(id: "JetBrainsMono-Regular", displayName: "JetBrains Mono", category: .mono),
        CuratedFont(id: "SourceCodePro-Regular", displayName: "Source Code Pro", category: .mono),
        CuratedFont(id: "FiraCode-Regular", displayName: "Fira Code", category: .mono),
        CuratedFont(id: "IBMPlexMono-Regular", displayName: "IBM Plex Mono", category: .mono),
        CuratedFont(id: "SpaceMono-Regular", displayName: "Space Mono", category: .mono),
        CuratedFont(id: "Inconsolata-Regular", displayName: "Inconsolata", category: .mono),
    ]

    // MARK: - Registration

    /// Registers all .ttf files from the app bundle's Resources/Fonts directory.
    private func registerBundledFonts() {
        guard let fontsURL = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: fontsURL, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "ttf" {
            registerFont(at: file)
        }
    }

    private func registerFont(at url: URL) {
        var errorRef: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)

        // Always extract PostScript names (font may already be registered)
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
            for desc in descriptors {
                if let psName = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String {
                    availableFonts.insert(psName)
                }
            }
        }
    }

    // MARK: - Font Availability

    /// Ensures a font is ready to use. With bundled fonts, this always succeeds for non-system fonts.
    func ensureFont(_ curatedFont: CuratedFont, completion: @escaping (Bool) -> Void) {
        if curatedFont.isSystem {
            completion(true)
            return
        }
        completion(availableFonts.contains(curatedFont.id))
    }

    func fontForSettings(_ settings: AppSettings) -> NSFont {
        let size = CGFloat(settings.currentFontSize)
        let name = settings.currentFontName

        if name.isEmpty || name == "SF-Mono" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        if name == "SF-Pro" {
            return NSFont.systemFont(ofSize: size, weight: .regular)
        }

        if let font = NSFont(name: name, size: size) {
            return font
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
