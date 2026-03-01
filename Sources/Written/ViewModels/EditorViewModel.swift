import SwiftUI
import Combine

@MainActor
final class EditorViewModel: ObservableObject {
    /// The document. Direct assignment triggers SwiftUI re-render.
    /// Use `textDidChangeSilently()` during typing to avoid re-render.
    var document: WrittenDocument {
        get { _document }
        set {
            objectWillChange.send()
            _document = newValue
        }
    }
    private var _document: WrittenDocument

    @Published var folderURL: URL?

    private let autoSave = AutoSaveService()
    private var tempFileURL: URL?

    // MARK: - Cursor Position Memory

    private var cursorPositions: [URL: Int] = [:]
    var cursorPosition: Int = 0
    var restoredCursorPosition: Int?

    func saveCursorPosition() {
        guard let url = _document.fileURL else { return }
        cursorPositions[url] = cursorPosition
    }

    func restoreCursorPosition(for url: URL) {
        restoredCursorPosition = cursorPositions[url]
    }

    init(document: WrittenDocument = WrittenDocument(), folderURL: URL? = nil) {
        self._document = document
        self.folderURL = folderURL
    }

    init(fileURL: URL) throws {
        self._document = try WrittenDocument.load(from: fileURL)
        self.folderURL = fileURL.deletingLastPathComponent()
    }

    var windowTitle: String {
        _document.fileURL?.lastPathComponent ?? "Untitled.txt"
    }

    /// Update text + auto-save WITHOUT notifying SwiftUI.
    /// Used during active typing for performance.
    func textDidChangeSilently(_ newText: String) {
        _document.text = newText
        scheduleAutoSave(text: newText)
    }

    /// Update text + auto-save AND notify SwiftUI.
    /// Used for flush (save/quit/file switch).
    func textDidChange(_ newText: String) {
        objectWillChange.send()
        _document.text = newText
        scheduleAutoSave(text: newText)
    }

    private func scheduleAutoSave(text: String) {
        if let fileURL = _document.fileURL {
            autoSave.textDidChange(text: text, fileURL: fileURL)
        } else {
            let tempURL = ensureTempFile()
            autoSave.textDidChange(text: text, fileURL: tempURL)
        }
    }

    func saveImmediately() {
        guard let fileURL = _document.fileURL else { return }
        autoSave.saveImmediately(text: _document.text, fileURL: fileURL)
    }

    func assignFile(url: URL) {
        let oldTempURL = tempFileURL
        objectWillChange.send()
        _document.fileURL = url
        if let tempURL = oldTempURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempFileURL = nil
        }
    }

    func cleanupTempFile() {
        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempFileURL = nil
        }
    }

    // MARK: - Temp File Management

    private static let draftsDir: URL = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Written/Drafts", isDirectory: true)
        }
        return appSupport.appendingPathComponent("Written/Drafts", isDirectory: true)
    }()

    private func ensureTempFile() -> URL {
        if let existing = tempFileURL { return existing }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.draftsDir, withIntermediateDirectories: true)
        let tempURL = Self.draftsDir.appendingPathComponent(UUID().uuidString + ".txt")
        tempFileURL = tempURL
        return tempURL
    }

    static func cleanupOrphanedDrafts() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: draftsDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
}
