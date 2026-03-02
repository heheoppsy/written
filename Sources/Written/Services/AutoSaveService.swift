import Foundation

@MainActor
final class AutoSaveService {
    private var saveTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(500)
    private let shadowManager = ShadowFileManager.shared

    /// Debounced write to shadow file (called on every keystroke via ViewModel).
    func scheduleShadowSave(text: String, shadowURL: URL, meta: ShadowFileManager.ShadowMeta) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            shadowManager.writeShadow(text: text, shadowURL: shadowURL, meta: meta)
        }
    }

    /// Immediate write to shadow (called before file switch / close).
    func saveShadowImmediately(text: String, shadowURL: URL, meta: ShadowFileManager.ShadowMeta) {
        saveTask?.cancel()
        shadowManager.writeShadow(text: text, shadowURL: shadowURL, meta: meta)
    }

    /// Cancel any pending shadow write.
    func cancelPending() {
        saveTask?.cancel()
    }

    /// Write to the REAL file on disk. Only called by explicit save (Cmd+S).
    static func saveToRealFile(text: String, fileURL: URL) throws {
        try withTrailingNewline(text).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func withTrailingNewline(_ text: String) -> String {
        if text.isEmpty || text.hasSuffix("\n") { return text }
        return text + "\n"
    }

    deinit {
        saveTask?.cancel()
    }
}
