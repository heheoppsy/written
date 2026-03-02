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
    @Published var isDirty: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .documentDirtyChanged, object: isDirty)
        }
    }

    private let autoSave = AutoSaveService()
    private let shadowManager = ShadowFileManager.shared
    let fileWatcher = FileWatcher()

    // MARK: - Per-File Buffer State

    struct FileBufferState {
        var text: String
        var cursorPosition: Int
        var isDirty: Bool
        var shadowURL: URL
        var lastDiskModDate: Date?
        var untitledID: UUID?
    }

    private var bufferStates: [URL: FileBufferState] = [:]
    private var untitledState: FileBufferState?

    var cursorPosition: Int = 0
    var restoredCursorPosition: Int?

    /// Synchronous text flush closure, set by WritingTextView Coordinator.
    var flushEditorText: (() -> String)?

    // MARK: - Init

    init(document: WrittenDocument = WrittenDocument(), folderURL: URL? = nil) {
        self._document = document
        self.folderURL = folderURL
        setupFileWatcher()
    }

    init(fileURL: URL) throws {
        self._document = try WrittenDocument.load(from: fileURL)
        self.folderURL = fileURL.deletingLastPathComponent()

        let modDate = Self.modDate(for: fileURL)
        let shadowURL = shadowManager.shadowURL(for: fileURL)
        bufferStates[fileURL] = FileBufferState(
            text: _document.text,
            cursorPosition: 0,
            isDirty: false,
            shadowURL: shadowURL,
            lastDiskModDate: modDate
        )
        fileWatcher.watch(fileURL: fileURL, lastModDate: modDate)
        setupFileWatcher()
    }

    /// Init for crash recovery — pre-load recovered text as dirty.
    init(fileURL: URL, recoveredText: String, folderURL: URL? = nil) {
        self._document = WrittenDocument(text: recoveredText, fileURL: fileURL)
        self.folderURL = folderURL ?? fileURL.deletingLastPathComponent()
        self.isDirty = true

        let modDate = Self.modDate(for: fileURL)
        let shadowURL = shadowManager.shadowURL(for: fileURL)
        bufferStates[fileURL] = FileBufferState(
            text: recoveredText,
            cursorPosition: 0,
            isDirty: true,
            shadowURL: shadowURL,
            lastDiskModDate: modDate
        )
        fileWatcher.watch(fileURL: fileURL, lastModDate: modDate)
        setupFileWatcher()
    }

    /// Init for untitled crash recovery.
    init(recoveredText: String) {
        self._document = WrittenDocument(text: recoveredText)
        self.isDirty = true

        let id = UUID()
        untitledState = FileBufferState(
            text: recoveredText,
            cursorPosition: 0,
            isDirty: true,
            shadowURL: shadowManager.shadowURLForUntitled(id: id),
            untitledID: id
        )
        setupFileWatcher()
    }

    var windowTitle: String {
        _document.fileURL?.lastPathComponent ?? "Untitled.txt"
    }

    // MARK: - Text Changes (Typing)

    /// Update text + shadow-save WITHOUT notifying SwiftUI.
    func textDidChangeSilently(_ newText: String) {
        guard newText != _document.text else { return }
        _document.text = newText
        if !isDirty { isDirty = true }
        scheduleShadowSave(text: newText)
    }

    /// Update text + shadow-save AND notify SwiftUI.
    func textDidChange(_ newText: String) {
        guard newText != _document.text else { return }
        objectWillChange.send()
        _document.text = newText
        if !isDirty { isDirty = true }
        scheduleShadowSave(text: newText)
    }

    private func scheduleShadowSave(text: String) {
        let (shadowURL, meta) = currentShadowInfo()
        autoSave.scheduleShadowSave(text: text, shadowURL: shadowURL, meta: meta)
    }

    private func currentShadowInfo() -> (URL, ShadowFileManager.ShadowMeta) {
        if let fileURL = _document.fileURL {
            let shadowURL = shadowManager.shadowURL(for: fileURL)
            let meta = ShadowFileManager.ShadowMeta(
                realFilePath: fileURL.path,
                lastDiskModDate: bufferStates[fileURL]?.lastDiskModDate,
                shadowWriteDate: Date()
            )
            return (shadowURL, meta)
        } else {
            let id = ensureUntitledState().untitledID!
            let shadowURL = shadowManager.shadowURLForUntitled(id: id)
            let meta = ShadowFileManager.ShadowMeta(
                realFilePath: nil,
                lastDiskModDate: nil,
                shadowWriteDate: Date()
            )
            return (shadowURL, meta)
        }
    }

    private func ensureUntitledState() -> FileBufferState {
        if let state = untitledState { return state }
        let id = UUID()
        let state = FileBufferState(
            text: "",
            cursorPosition: 0,
            isDirty: false,
            shadowURL: shadowManager.shadowURLForUntitled(id: id),
            untitledID: id
        )
        untitledState = state
        return state
    }

    // MARK: - Explicit Save (Cmd+S)

    func saveToRealFile() throws {
        guard let fileURL = _document.fileURL else { return }
        try AutoSaveService.saveToRealFile(text: _document.text, fileURL: fileURL)

        // — Write succeeded — safe to clean up shadows and state —

        let modDate = Self.modDate(for: fileURL) ?? Date()
        bufferStates[fileURL]?.lastDiskModDate = modDate
        bufferStates[fileURL]?.isDirty = false

        let shadowURL = shadowManager.shadowURL(for: fileURL)
        shadowManager.deleteShadow(at: shadowURL)

        // Clean up the old untitled shadow if this was a save-as
        if let untitledShadow = pendingUntitledShadowURL {
            shadowManager.deleteShadow(at: untitledShadow)
            pendingUntitledShadowURL = nil
        }

        autoSave.cancelPending()
        isDirty = false
        fileWatcher.watch(fileURL: fileURL, lastModDate: modDate)
    }

    // MARK: - File Switching

    /// Synchronous flush + stash before switching files. Fixes the race condition.
    func flushAndStashCurrentBuffer(currentText: String) {
        _document.text = currentText

        // Write shadow immediately
        if isDirty {
            let (shadowURL, meta) = currentShadowInfo()
            autoSave.saveShadowImmediately(text: currentText, shadowURL: shadowURL, meta: meta)
        } else {
            autoSave.cancelPending()
        }

        // Stash state
        if let fileURL = _document.fileURL {
            bufferStates[fileURL] = FileBufferState(
                text: currentText,
                cursorPosition: cursorPosition,
                isDirty: isDirty,
                shadowURL: shadowManager.shadowURL(for: fileURL),
                lastDiskModDate: bufferStates[fileURL]?.lastDiskModDate
            )
        } else {
            untitledState?.text = currentText
            untitledState?.cursorPosition = cursorPosition
            untitledState?.isDirty = isDirty
        }
    }

    /// Load a file, restoring stashed buffer state if available.
    func loadFile(_ url: URL) throws {
        // Validate stash: if the file on disk changed (deleted/recreated/externally edited
        // while we weren't watching), the stash is stale — discard it.
        if let stashed = bufferStates[url] {
            let currentModDate = Self.modDate(for: url)
            if stashed.lastDiskModDate != currentModDate {
                shadowManager.deleteShadow(at: stashed.shadowURL)
                bufferStates.removeValue(forKey: url)
            }
        }

        if let stashed = bufferStates[url] {
            _document = WrittenDocument(text: stashed.text, fileURL: url)
            isDirty = stashed.isDirty
            restoredCursorPosition = stashed.cursorPosition
            fileWatcher.watch(fileURL: url, lastModDate: stashed.lastDiskModDate)
        } else {
            _document = try WrittenDocument.load(from: url)
            isDirty = false

            let modDate = Self.modDate(for: url)
            bufferStates[url] = FileBufferState(
                text: _document.text,
                cursorPosition: 0,
                isDirty: false,
                shadowURL: shadowManager.shadowURL(for: url),
                lastDiskModDate: modDate
            )
            fileWatcher.watch(fileURL: url, lastModDate: modDate)
        }
        objectWillChange.send()
    }

    // MARK: - Discard

    func discardChanges() {
        if let fileURL = _document.fileURL {
            let shadowURL = shadowManager.shadowURL(for: fileURL)
            shadowManager.deleteShadow(at: shadowURL)
            bufferStates.removeValue(forKey: fileURL)
        }
        autoSave.cancelPending()
        isDirty = false
    }

    /// Migrate buffer state and shadow from old URL to new URL (after rename).
    func migrateBuffer(from oldURL: URL, to newURL: URL) {
        // Move buffer state to new key
        if var state = bufferStates.removeValue(forKey: oldURL) {
            let newShadowURL = shadowManager.shadowURL(for: newURL)
            // Delete old shadow
            shadowManager.deleteShadow(at: state.shadowURL)
            state.shadowURL = newShadowURL
            bufferStates[newURL] = state

            // Write new shadow if dirty
            if state.isDirty {
                let meta = ShadowFileManager.ShadowMeta(
                    realFilePath: newURL.path,
                    lastDiskModDate: state.lastDiskModDate,
                    shadowWriteDate: Date()
                )
                shadowManager.writeShadow(text: state.text, shadowURL: newShadowURL, meta: meta)
            }
        }

        // Update file watcher
        if _document.fileURL == newURL {
            let modDate = Self.modDate(for: newURL)
            fileWatcher.watch(fileURL: newURL, lastModDate: modDate)
        }
    }

    /// Clean up buffer state and shadow for a specific file (e.g. after sidebar delete).
    func discardBuffer(for url: URL) {
        let shadowURL = shadowManager.shadowURL(for: url)
        shadowManager.deleteShadow(at: shadowURL)
        bufferStates.removeValue(forKey: url)
        // If discarding the current document's buffer, clear dirty state
        if _document.fileURL == url {
            autoSave.cancelPending()
            isDirty = false
        }
    }

    func discardUntitled() {
        if let state = untitledState {
            shadowManager.deleteShadow(at: state.shadowURL)
        }
        untitledState = nil
        autoSave.cancelPending()
        isDirty = false
    }

    // MARK: - Assign File (Save-As for untitled)

    /// Track the untitled shadow so we can clean it up after a successful save.
    private var pendingUntitledShadowURL: URL?

    func assignFile(url: URL) {
        // Don't delete the untitled shadow yet — save might fail.
        // Stash its URL so saveToRealFile() can clean it up on success.
        pendingUntitledShadowURL = untitledState?.shadowURL
        untitledState = nil
        objectWillChange.send()
        _document.fileURL = url
    }

    // MARK: - Dirty Query

    var hasAnyDirtyBuffers: Bool {
        if isDirty { return true }
        if bufferStates.values.contains(where: { $0.isDirty }) { return true }
        if untitledState?.isDirty == true { return true }
        return false
    }

    var dirtyFileURLs: [URL] {
        bufferStates.filter { $0.value.isDirty }.map { $0.key }
    }

    /// Summary of changes for each dirty buffer (for quit confirmation UI).
    struct DirtyFileSummary: Identifiable {
        let id = UUID()
        let name: String
        let wordCount: Int
        let wordDelta: Int   // positive = words added, negative = words removed
        let isUntitled: Bool
    }

    func dirtyFileSummaries() -> [DirtyFileSummary] {
        var summaries: [DirtyFileSummary] = []

        // Current document
        if isDirty {
            if let fileURL = _document.fileURL {
                let diskText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                let bufferWords = Self.wordCount(diskText)
                let currentWords = Self.wordCount(_document.text)
                summaries.append(DirtyFileSummary(
                    name: fileURL.lastPathComponent,
                    wordCount: currentWords,
                    wordDelta: currentWords - bufferWords,
                    isUntitled: false
                ))
            } else {
                let words = Self.wordCount(_document.text)
                summaries.append(DirtyFileSummary(
                    name: "Untitled.txt",
                    wordCount: words,
                    wordDelta: words,
                    isUntitled: true
                ))
            }
        }

        // Stashed dirty buffers (not the current doc)
        for (url, state) in bufferStates where state.isDirty && url != _document.fileURL {
            let diskText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let diskWords = Self.wordCount(diskText)
            let bufferWords = Self.wordCount(state.text)
            summaries.append(DirtyFileSummary(
                name: url.lastPathComponent,
                wordCount: bufferWords,
                wordDelta: bufferWords - diskWords,
                isUntitled: false
            ))
        }

        return summaries
    }

    private static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// Save all dirty stashed buffers to their real files.
    func saveAllDirtyBuffers() throws {
        // Save current buffer if dirty
        if _document.fileURL != nil, isDirty {
            try saveToRealFile()
        }

        // Save stashed dirty buffers
        for (url, state) in bufferStates where state.isDirty {
            guard url != _document.fileURL else { continue } // Already saved above
            try AutoSaveService.saveToRealFile(text: state.text, fileURL: url)
            shadowManager.deleteShadow(at: state.shadowURL)
            bufferStates[url]?.isDirty = false
            bufferStates[url]?.lastDiskModDate = Self.modDate(for: url)
        }
    }

    func discardAllBuffers() {
        shadowManager.removeAllShadows()
        bufferStates = [:]
        untitledState = nil
        autoSave.cancelPending()
        isDirty = false
    }

    // MARK: - External File Change

    /// Reload the current document from disk (user chose "Reload").
    func reloadFromDisk() throws {
        guard let fileURL = _document.fileURL else { return }
        _document = try WrittenDocument.load(from: fileURL)

        let modDate = Self.modDate(for: fileURL)
        bufferStates[fileURL] = FileBufferState(
            text: _document.text,
            cursorPosition: cursorPosition,
            isDirty: false,
            shadowURL: shadowManager.shadowURL(for: fileURL),
            lastDiskModDate: modDate
        )

        let shadowURL = shadowManager.shadowURL(for: fileURL)
        shadowManager.deleteShadow(at: shadowURL)
        autoSave.cancelPending()

        isDirty = false
        fileWatcher.watch(fileURL: fileURL, lastModDate: modDate)
        objectWillChange.send()
    }

    /// Keep current version, update mod date tracking (user chose "Keep mine").
    func keepCurrentVersion() {
        guard let fileURL = _document.fileURL else { return }
        let modDate = Self.modDate(for: fileURL)
        bufferStates[fileURL]?.lastDiskModDate = modDate
        fileWatcher.watch(fileURL: fileURL, lastModDate: modDate)
    }

    // MARK: - Crash Recovery

    static func checkForRecoverableShadows() -> [(url: URL, meta: ShadowFileManager.ShadowMeta)] {
        ShadowFileManager.shared.allShadows()
    }

    /// Pre-load remaining shadow files into buffer states so they're restored on file switch.
    /// Called after the primary recovery document is loaded.
    func loadRemainingRecoveryShadows() {
        let shadows = ShadowFileManager.shared.allShadows()
        for (shadowURL, meta) in shadows {
            guard let realPath = meta.realFilePath else { continue }
            let fileURL = URL(fileURLWithPath: realPath)

            // Skip the already-loaded primary document
            guard fileURL != _document.fileURL else { continue }
            // Skip if we already have a buffer state for this file
            guard bufferStates[fileURL] == nil else { continue }

            guard let data = ShadowFileManager.shared.readShadow(at: shadowURL) else { continue }
            let trimmed = data.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let modDate = Self.modDate(for: fileURL)
            bufferStates[fileURL] = FileBufferState(
                text: data.text,
                cursorPosition: 0,
                isDirty: true,
                shadowURL: shadowURL,
                lastDiskModDate: modDate
            )
        }
    }

    // MARK: - FileWatcher Setup

    private func setupFileWatcher() {
        fileWatcher.onExternalChange = { [weak self] fileURL, diskText, diskModDate in
            guard let self else { return }
            guard self._document.fileURL == fileURL else { return }

            if !self.isDirty {
                // Clean buffer: silently reload
                self._document = WrittenDocument(text: diskText, fileURL: fileURL)
                self.bufferStates[fileURL]?.lastDiskModDate = diskModDate
                self.bufferStates[fileURL]?.text = diskText
                self.fileWatcher.watch(fileURL: fileURL, lastModDate: diskModDate)
                self.objectWillChange.send()
            } else {
                // Dirty buffer: notify UI
                NotificationCenter.default.post(
                    name: .externalFileChange,
                    object: nil,
                    userInfo: ["fileURL": fileURL, "diskText": diskText, "diskModDate": diskModDate]
                )
            }
        }
        fileWatcher.startObserving()
    }

    // MARK: - Helpers

    private static func modDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
