import SwiftUI
import AppKit

/// Captures the settings values that affect text view rendering, so we can skip
/// expensive reapplication when only the text changed.
@MainActor
fileprivate struct SettingsSnapshot: Equatable {
    let themeID: String
    let fontName: String
    let fontSize: Double
    let lineSpacing: Double
    let layoutMode: LayoutMode
    let columnWidthPercent: Double
    let centeredText: Bool
    let typewriterScrolling: Bool
    let spellCheck: Bool
    let currentLineHighlight: Bool

    init(_ s: AppSettings) {
        themeID = s.currentThemeID
        fontName = s.currentFontName
        fontSize = s.currentFontSize
        lineSpacing = s.lineSpacing
        layoutMode = s.layoutMode
        columnWidthPercent = s.columnWidthPercent
        centeredText = s.centeredText
        typewriterScrolling = s.typewriterScrolling
        spellCheck = s.spellCheckEnabled
        currentLineHighlight = s.currentLineHighlight
    }
}

@MainActor
final class VimModeState: ObservableObject {
    @Published var mode: VimMode = .insert
    @Published var enabled: Bool = false
    @Published var countBuffer: String = ""
}

struct WritingTextView: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var settings: AppSettings
    var overlayActive: Bool = false
    var wordCounter: DebouncedWordCounter?
    var vimState: VimModeState

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = WritingNSTextView()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        scrollView.wantsLayer = true
        scrollView.layer?.opacity = 0  // Start hidden; settleLayout fades in after positioning
        context.coordinator.textView = textView

        textView.configureForWriting()
        textView.string = viewModel.document.text

        textView.applyTheme(settings.currentTheme)
        textView.updateHighlightColor(from: settings.currentTheme)
        textView.currentLineHighlight = settings.currentLineHighlight
        textView.applyFont(settings.editorFont)
        textView.applyLineSpacing(CGFloat(settings.lineSpacing))
        textView.applyTextAlignment(settings.centeredText)
        textView.typewriterScrolling = settings.typewriterScrolling
        textView.applyColumnLayout(
            font: settings.editorFont,
            mode: settings.layoutMode,
            columnWidthPercent: settings.columnWidthPercent
        )

        context.coordinator.viewModel = viewModel
        context.coordinator.wordCounter = wordCounter
        wordCounter?.getText = { [weak textView] in textView?.string }
        wordCounter?.start()
        textView.onTextChange = { [weak coordinator = context.coordinator] newText in
            guard let coordinator else { return }
            coordinator.editGeneration += 1
            coordinator.textSyncTask?.cancel()
            coordinator.textSyncTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                coordinator.syncedGeneration = coordinator.editGeneration
                coordinator.viewModel?.textDidChangeSilently(newText)
            }
        }
        textView.onSelectionChange = { [weak coordinator = context.coordinator] position in
            coordinator?.viewModel?.cursorPosition = position
        }
        textView.onVimModeChange = { [weak vimState] mode in
            vimState?.mode = mode
        }
        textView.onVimCountChange = { [weak vimState] count in
            vimState?.countBuffer = count
        }
        textView.vimEnabled = settings.vimModeEnabled
        textView.vimEngine?.jjEscapeEnabled = settings.vimJJEscape
        vimState.enabled = settings.vimModeEnabled
        vimState.mode = .insert

        // Flush pending text sync immediately (e.g. before save/quit)
        context.coordinator.flushObserver = NotificationCenter.default.addObserver(
            forName: .flushEditorText,
            object: nil,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                coordinator?.flushTextSync()
            }
        }

        // Track initial width for frame observer's width-change detection
        textView.lastKnownWidth = scrollView.contentSize.width

        // Settle layout first, then place cursor (avoids premature ensureCursorVisible)
        textView.scheduleSettleLayout()
        let endPos = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: endPos, length: 0))

        // Listen for focus requests
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .focusEditor,
            object: nil,
            queue: .main
        ) { [weak textView] _ in
            DispatchQueue.main.async {
                textView?.window?.makeFirstResponder(textView)
            }
        }

        // Listen for unfocus requests (sidebar/overlay needs keyboard)
        context.coordinator.unfocusObserver = NotificationCenter.default.addObserver(
            forName: .unfocusEditor,
            object: nil,
            queue: .main
        ) { [weak textView] _ in
            DispatchQueue.main.async {
                guard let textView, let window = textView.window else { return }
                if window.firstResponder === textView {
                    window.makeFirstResponder(nil)
                }
            }
        }

        // Re-layout columns when the scroll view resizes
        scrollView.postsFrameChangedNotifications = true
        let coordinator = context.coordinator
        coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak textView] _ in
            Task { @MainActor in
                guard let textView,
                      let sv = textView.enclosingScrollView else { return }
                // Only settle on width changes (window resize). Height-only
                // changes (find bar open/close) don't affect column layout.
                let newWidth = sv.contentSize.width
                guard abs(newWidth - textView.lastKnownWidth) > 1 else { return }
                textView.lastKnownWidth = newWidth
                textView.scheduleSettleLayout()
            }
        }
        coordinator.lastSettings = settings
        coordinator.settingsSnapshot = SettingsSnapshot(settings)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let coord = context.coordinator

        // Guard all property sets — only apply when value actually changed
        if textView.overlayActive != overlayActive {
            let wasOverlay = textView.overlayActive
            textView.overlayActive = overlayActive
            // Suppress frame observer during blur animation when overlay
            // closes — it triggers invalidateLayout which scrolls to top.
            if wasOverlay && !overlayActive {
                textView.isSettlingLayout = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak textView] in
                    textView?.isSettlingLayout = false
                }
            }
        }
        if textView.typewriterScrolling != settings.typewriterScrolling {
            textView.typewriterScrolling = settings.typewriterScrolling
        }
        if textView.typewriterFollowCursor != settings.typewriterFollowCursor {
            textView.typewriterFollowCursor = settings.typewriterFollowCursor
        }
        if textView.isContinuousSpellCheckingEnabled != settings.spellCheckEnabled {
            textView.isContinuousSpellCheckingEnabled = settings.spellCheckEnabled
        }
        if textView.isGrammarCheckingEnabled != settings.spellCheckEnabled {
            textView.isGrammarCheckingEnabled = settings.spellCheckEnabled
        }
        if textView.vimEnabled != settings.vimModeEnabled {
            textView.vimEnabled = settings.vimModeEnabled
            vimState.enabled = settings.vimModeEnabled
        }
        textView.vimEngine?.jjEscapeEnabled = settings.vimJJEscape
        if textView.currentLineHighlight != settings.currentLineHighlight {
            textView.currentLineHighlight = settings.currentLineHighlight
        }

        // Only reapply expensive attribute/layout operations when settings actually changed
        let newSnapshot = SettingsSnapshot(settings)
        if coord.settingsSnapshot != newSnapshot {
            coord.lastSettings = settings
            coord.settingsSnapshot = newSnapshot
            textView.applyTheme(settings.currentTheme)
            textView.applyFont(settings.editorFont)
            textView.applyLineSpacing(CGFloat(settings.lineSpacing))
            textView.applyColumnLayout(
                font: settings.editorFont,
                mode: settings.layoutMode,
                columnWidthPercent: settings.columnWidthPercent
            )
            textView.applyTextAlignment(settings.centeredText)

            textView.updateHighlightColor(from: settings.currentTheme)

            textView.nudgeLayout()
        }

        // Only replace text when it was changed externally (e.g. file load).
        // If editGeneration > syncedGeneration, the user has typed since the last
        // sync — the text view has the truth, skip replacement.
        if textView.string != viewModel.document.text,
           coord.editGeneration == coord.syncedGeneration {
            coord.textSyncTask?.cancel()
            textView.string = viewModel.document.text
            textView.applyTheme(settings.currentTheme)
            textView.applyFont(settings.editorFont)
            textView.applyLineSpacing(CGFloat(settings.lineSpacing))
            textView.applyTextAlignment(settings.centeredText)
            textView.applyColumnLayout(
                font: settings.editorFont,
                mode: settings.layoutMode,
                columnWidthPercent: settings.columnWidthPercent
            )

            // Settle layout first (sets isSettlingLayout = true), then place
            // cursor — this prevents setSelectedRanges from firing a premature
            // ensureCursorVisible before layout has settled.
            textView.scheduleSettleLayout()
            let docLen = (textView.string as NSString).length
            let pos: Int
            if let restored = viewModel.restoredCursorPosition {
                pos = min(restored, docLen)
                viewModel.restoredCursorPosition = nil
            } else {
                pos = docLen
            }
            textView.setSelectedRange(NSRange(location: pos, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, @unchecked Sendable {
        var textView: WritingNSTextView?
        weak var viewModel: EditorViewModel?
        weak var wordCounter: DebouncedWordCounter?
        var focusObserver: Any?
        var unfocusObserver: Any?
        var flushObserver: Any?
        var frameObserver: Any?
        weak var lastSettings: AppSettings?
        fileprivate var settingsSnapshot: SettingsSnapshot?
        var textSyncTask: Task<Void, Never>?
        var editGeneration: UInt = 0
        var syncedGeneration: UInt = 0

        /// Immediately sync the current text view content to the view model.
        @MainActor func flushTextSync() {
            textSyncTask?.cancel()
            textSyncTask = nil
            guard let textView, let viewModel else { return }
            syncedGeneration = editGeneration
            viewModel.textDidChange(textView.string)
        }

        deinit {
            textSyncTask?.cancel()
            for observer in [focusObserver, unfocusObserver, flushObserver, frameObserver] {
                if let observer { NotificationCenter.default.removeObserver(observer) }
            }
        }
    }
}
