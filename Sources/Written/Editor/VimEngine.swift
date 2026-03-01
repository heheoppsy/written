import AppKit

enum VimMode: Equatable {
    case normal
    case insert
    case replace
    case operatorPending(Character)
    case visual
    case visualLine

    var label: String {
        switch self {
        case .normal: "NORMAL"
        case .insert: "INSERT"
        case .replace: "REPLACE"
        case .operatorPending: "PENDING"
        case .visual: "VISUAL"
        case .visualLine: "V-LINE"
        }
    }
}

@MainActor
final class VimEngine {
    var mode: VimMode = .insert {
        didSet {
            if mode != oldValue {
                onModeChange?(mode)
            }
        }
    }

    var onModeChange: ((VimMode) -> Void)?
    var onCountChange: ((String) -> Void)?
    weak var textView: WritingNSTextView?
    var jjEscapeEnabled: Bool = true

    private var countBuffer = "" {
        didSet { onCountChange?(countBuffer) }
    }
    private var lastYankedContent: String?
    private var isLinewiseYank = false

    // jj escape buffer
    private var jBuffered = false
    private var jTimer: DispatchWorkItem?

    // Visual mode
    private var visualAnchor: Int = 0
    private var visualGPending = false
    private var visualLineCursorPos: Int = 0

    private func consumeCount() -> Int {
        let n = Int(countBuffer) ?? 1
        countBuffer = ""
        return n
    }

    // MARK: - Key Handling

    /// Returns true if the key was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch mode {
        case .insert:
            return handleInsertMode(event)
        case .normal:
            return handleNormalMode(event)
        case .replace:
            return handleReplaceMode(event)
        case .operatorPending(let op):
            return handleOperatorPending(op, event: event)
        case .visual:
            return handleVisualMode(event)
        case .visualLine:
            return handleVisualMode(event)
        }
    }

    // MARK: - Insert Mode

    private func handleInsertMode(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            cancelJBuffer(insert: false)
            enterNormalMode()
            return true
        }

        guard let chars = event.charactersIgnoringModifiers, let char = chars.first else { return false }

        if jjEscapeEnabled && char == "j" {
            if jBuffered {
                // Second j — enter normal mode, delete the buffered j that was inserted
                cancelJBuffer(insert: false)
                textView?.deleteBackward(nil)
                enterNormalMode()
                return true
            } else {
                // First j — buffer it, start timer
                jBuffered = true
                // Insert the j immediately so typing feels responsive
                textView?.insertText("j", replacementRange: NSRange(location: NSNotFound, length: 0))
                let item = DispatchWorkItem { [weak self] in
                    self?.flushJBuffer()
                }
                jTimer = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: item)
                return true
            }
        }

        if jjEscapeEnabled && jBuffered {
            // Non-j key pressed while j is buffered — j already inserted, just clear buffer
            cancelJBuffer(insert: false)
        }

        return false
    }

    private func cancelJBuffer(insert: Bool) {
        jTimer?.cancel()
        jTimer = nil
        jBuffered = false
    }

    private func flushJBuffer() {
        // Timer expired — j was already inserted, just clear the buffer
        jBuffered = false
        jTimer = nil
    }

    private func enterNormalMode() {
        mode = .normal
        // In vim, Escape moves cursor back one position
        textView?.moveLeft(nil)
        updateBlockCursor()
    }

    // MARK: - Normal Mode

    private func handleNormalMode(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers, let char = chars.first else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ctrl+R = redo
        if mods.contains(.control) && char == "r" {
            textView?.undoManager?.redo()
            updateBlockCursor()
            return true
        }

        // Ignore keys with Command/Option modifiers (let system handle Cmd+S, etc.)
        if mods.contains(.command) || mods.contains(.option) {
            return false
        }

        // Count accumulation (digits, but 0 alone means beginning-of-line)
        if char.isNumber && (char != "0" || !countBuffer.isEmpty) {
            countBuffer.append(char)
            return true
        }

        let n = consumeCount()

        switch char {
        // Movement — collapse block cursor selection before moving so
        // NSTextView actually moves rather than just collapsing the selection.
        case "h": collapseSelection(); times(n) { moveLeftBounded() }; updateBlockCursor()
        case "j": collapseSelection(); times(n) { textView?.moveDown(nil) }; updateBlockCursor()
        case "k": collapseSelection(); times(n) { textView?.moveUp(nil) }; updateBlockCursor()
        case "l": collapseSelection(); times(n) { moveRightBounded() }; updateBlockCursor()
        case "w": collapseSelection(); times(n) { moveWordForwardBounded() }; updateBlockCursor()
        case "b": collapseSelection(); times(n) { moveWordBackwardBounded() }; updateBlockCursor()
        case "0": collapseSelection(); textView?.moveToBeginningOfLine(nil); updateBlockCursor()
        case "$": collapseSelection(); textView?.moveToEndOfLine(nil); nudgeBackIfNeeded(); updateBlockCursor()
        case "^": collapseSelection(); moveToFirstNonWhitespace(); updateBlockCursor()

        // Document movement
        case "g":
            countBuffer = n > 1 ? String(n) : ""
            mode = .operatorPending("g")
            return true
        case "G":
            collapseSelection()
            textView?.moveToEndOfDocument(nil)
            nudgeBackIfNeeded()
            updateBlockCursor()

        // Enter insert mode — collapse block cursor before positioning
        case "i":
            collapseSelection()
            mode = .insert
        case "I":
            collapseSelection()
            moveToFirstNonWhitespace()
            mode = .insert
        case "a":
            collapseSelection()
            // Don't cross newline — if on \n, just enter insert mode in place
            if let tv = textView {
                let text = tv.string as NSString
                let loc = tv.selectedRange().location
                if loc < text.length && text.character(at: loc) != 0x0A {
                    tv.moveRight(nil)
                }
            }
            mode = .insert
        case "A":
            collapseSelection()
            textView?.moveToEndOfLine(nil)
            mode = .insert
        case "o":
            collapseSelection()
            textView?.moveToEndOfParagraph(nil)
            textView?.insertNewline(nil)
            mode = .insert
        case "O":
            collapseSelection()
            textView?.moveToBeginningOfParagraph(nil)
            textView?.insertNewline(nil)
            textView?.moveUp(nil)
            mode = .insert

        // Operators (wait for motion or double-tap)
        case "d":
            countBuffer = n > 1 ? String(n) : ""
            mode = .operatorPending("d")
            return true
        case "y":
            countBuffer = n > 1 ? String(n) : ""
            mode = .operatorPending("y")
            return true

        // Visual mode
        case "v":
            collapseSelection()
            visualAnchor = textView?.selectedRange().location ?? 0
            mode = .visual
            updateVisualSelection()
        case "V":
            collapseSelection()
            visualAnchor = textView?.selectedRange().location ?? 0
            visualLineCursorPos = visualAnchor
            mode = .visualLine
            updateVisualLineSelection()

        // Find
        case "?":
            collapseSelection()
            mode = .insert
            let item = NSMenuItem()
            item.tag = 1 // showFindPanel
            textView?.performFindPanelAction(item)

        // Single-key actions
        case "x": collapseSelection(); times(n) { textView?.deleteForward(nil) }; updateBlockCursor()
        case "r": mode = .replace
        case "u": textView?.undoManager?.undo(); updateBlockCursor()
        case "p": pasteAfter(); updateBlockCursor()
        case "P": pasteBefore(); updateBlockCursor()

        default:
            return true  // Consume all keys in normal mode
        }

        return true
    }

    // MARK: - Operator Pending Mode (d, y, g)

    private func handleOperatorPending(_ op: Character, event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers, let char = chars.first else {
            mode = .normal
            return false
        }

        // Escape cancels
        if event.keyCode == 53 {
            countBuffer = ""
            mode = .normal
            return true
        }

        // Count accumulation (e.g. d3w, y5l)
        if char.isNumber && (char != "0" || !countBuffer.isEmpty) {
            countBuffer.append(char)
            return true
        }

        let n = consumeCount()

        switch op {
        case "d":
            switch char {
            case "d": deleteLine(count: n)
            case "w": times(n) { deleteMotion { _ in self.moveWordForwardBounded(forOperator: true) } }
            case "b": times(n) { deleteMotion { _ in self.moveWordBackwardBounded() } }
            case "l": deleteMotion { [self] _ in times(n) { moveRightBounded() } }
            case "h": deleteMotion { [self] _ in times(n) { moveLeftBounded() } }
            case "$": deleteMotion { $0?.moveToEndOfLine(nil) }
            case "0": deleteMotion { $0?.moveToBeginningOfLine(nil) }; isLinewiseYank = false
            default: break
            }

        case "y":
            switch char {
            case "y": yankLine(count: n)
            case "w": yankMotion(count: n) { _ in self.moveWordForwardBounded(forOperator: true) }
            case "l": yankMotion { [self] _ in times(n) { moveRightBounded() } }
            case "h": yankMotion { [self] _ in times(n) { moveLeftBounded() } }
            default: break
            }

        case "g":
            if char == "g" {
                collapseSelection()
                textView?.moveToBeginningOfDocument(nil)
                updateBlockCursor()
            }

        default:
            break
        }

        mode = .normal
        updateBlockCursor()
        return true
    }

    // MARK: - Replace Mode

    private func handleReplaceMode(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            mode = .normal
            updateBlockCursor()
            return true
        }

        guard let chars = event.characters, let char = chars.first,
              let tv = textView else {
            mode = .normal
            return true
        }

        let range = tv.selectedRange()
        let len = (tv.string as NSString).length
        if range.location < len {
            tv.insertText(String(char), replacementRange: NSRange(location: range.location, length: 1))
            tv.moveLeft(nil) // Stay on the replaced character
        }

        mode = .normal
        updateBlockCursor()
        return true
    }

    // MARK: - Visual Mode

    private func handleVisualMode(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers, let char = chars.first else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape exits visual mode
        if event.keyCode == 53 {
            countBuffer = ""
            exitVisualMode()
            return true
        }

        // Let system handle Cmd/Option
        if mods.contains(.command) || mods.contains(.option) {
            return false
        }

        // gg handling
        if visualGPending {
            visualGPending = false
            if char == "g" {
                moveCursorInVisual { tv in tv.moveToBeginningOfDocument(nil) }
            }
            return true
        }

        // Count accumulation (0 alone = beginning-of-line)
        if char.isNumber && (char != "0" || !countBuffer.isEmpty) {
            countBuffer.append(char)
            return true
        }

        let n = consumeCount()

        switch char {
        // Movements
        case "h": times(n) { moveCursorInVisual { [self] _ in moveLeftBounded() } }
        case "j":
            if mode == .visualLine {
                times(n) { advanceVisualLineCursor(forward: true) }
            } else {
                times(n) { moveCursorInVisual { tv in tv.moveDown(nil) } }
            }
        case "k":
            if mode == .visualLine {
                times(n) { advanceVisualLineCursor(forward: false) }
            } else {
                times(n) { moveCursorInVisual { tv in tv.moveUp(nil) } }
            }
        case "l": times(n) { moveCursorInVisual { [self] _ in moveRightBounded(pastLastChar: false) } }
        case "w": times(n) { moveCursorInVisual { [self] _ in moveWordForwardBounded() } }
        case "b": times(n) { moveCursorInVisual { [self] _ in moveWordBackwardBounded() } }
        case "0": moveCursorInVisual { tv in tv.moveToBeginningOfLine(nil) }
        case "$": moveCursorInVisual { tv in tv.moveToEndOfLine(nil) }
        case "^": moveCursorInVisual { [self] _ in moveToFirstNonWhitespace() }
        case "G": moveCursorInVisual { tv in tv.moveToEndOfDocument(nil) }
        case "g": visualGPending = true

        // Mode switches
        case "v":
            if mode == .visual {
                exitVisualMode()
            } else {
                mode = .visual
                updateVisualSelection()
            }
        case "V":
            if mode == .visualLine {
                exitVisualMode()
            } else {
                // Switching from charwise → linewise: track cursor position
                let sel = textView?.selectedRange() ?? NSRange()
                if visualAnchor <= sel.location {
                    visualLineCursorPos = NSMaxRange(sel) - 1
                } else {
                    visualLineCursorPos = sel.location
                }
                mode = .visualLine
                updateVisualLineSelection()
            }

        // Operations
        case "d", "x": deleteVisualSelection()
        case "y": yankVisualSelection()
        case "p": replaceVisualSelection()

        default:
            return true // consume all keys
        }
        return true
    }

    private func exitVisualMode() {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let pos = min(visualAnchor, max(0, text.length - 1))
        tv.setSelectedRange(NSRange(location: pos, length: 0))
        visualGPending = false
        mode = .normal
        updateBlockCursor()
    }

    private func moveCursorInVisual(_ motion: (WritingNSTextView) -> Void) {
        guard let tv = textView else { return }
        // Determine which end of selection is the moving cursor (not the anchor)
        let sel = tv.selectedRange()
        let cursorPos: Int
        if visualAnchor <= sel.location {
            // Anchor is at start, cursor is at end
            cursorPos = NSMaxRange(sel) - (mode == .visual ? 1 : 0)
        } else {
            // Anchor is at end, cursor is at start
            cursorPos = sel.location
        }
        // Collapse to cursor position, apply motion, then reselect
        tv.setSelectedRange(NSRange(location: cursorPos, length: 0))
        motion(tv)
        if mode == .visual {
            updateVisualSelection()
        } else {
            updateVisualLineSelection()
        }
    }

    private func updateVisualSelection() {
        guard let tv = textView else { return }
        let cursor = tv.selectedRange().location
        let start = min(visualAnchor, cursor)
        let end = max(visualAnchor, cursor)
        // Vim visual mode is inclusive
        let len = max(1, end - start + 1)
        let text = tv.string as NSString
        let clampedLen = min(len, text.length - start)
        tv.setSelectedRange(NSRange(location: start, length: max(0, clampedLen)))
    }

    /// Move cursor by logical lines in V-LINE mode (not visual/wrapped lines).
    private func advanceVisualLineCursor(forward: Bool) {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        guard text.length > 0 else { return }

        let clampedPos = min(visualLineCursorPos, max(0, text.length - 1))
        let cursorLineRange = text.lineRange(for: NSRange(location: clampedPos, length: 0))

        if forward {
            let nextLineStart = NSMaxRange(cursorLineRange)
            if nextLineStart >= text.length { return }
            visualLineCursorPos = nextLineStart
        } else {
            if cursorLineRange.location == 0 { return }
            visualLineCursorPos = cursorLineRange.location - 1
        }

        // Set cursor so updateVisualLineSelection can read it
        tv.setSelectedRange(NSRange(location: visualLineCursorPos, length: 0))
        updateVisualLineSelection()
    }

    private func updateVisualLineSelection() {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let cursor = tv.selectedRange().location
        let anchorLineRange = text.lineRange(for: NSRange(location: min(visualAnchor, text.length - 1), length: 0))
        let cursorLineRange = text.lineRange(for: NSRange(location: min(cursor, max(0, text.length - 1)), length: 0))
        let start = min(anchorLineRange.location, cursorLineRange.location)
        let end = max(NSMaxRange(anchorLineRange), NSMaxRange(cursorLineRange))
        tv.setSelectedRange(NSRange(location: start, length: end - start))
    }

    private func deleteVisualSelection() {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { exitVisualMode(); return }
        let text = tv.string as NSString
        let yanked = text.substring(with: sel)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        isLinewiseYank = mode == .visualLine
        tv.insertText("", replacementRange: sel)
        visualGPending = false
        mode = .normal
        updateBlockCursor()
    }

    private func yankVisualSelection() {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { exitVisualMode(); return }
        let text = tv.string as NSString
        let yanked = text.substring(with: sel)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        isLinewiseYank = mode == .visualLine
        // Cursor goes to start of selection
        tv.setSelectedRange(NSRange(location: sel.location, length: 0))
        visualGPending = false
        mode = .normal
        updateBlockCursor()
    }

    private func replaceVisualSelection() {
        guard let tv = textView,
              let content = NSPasteboard.general.string(forType: .string) else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { exitVisualMode(); return }
        // Save selection, replace with paste content, then put old selection on pasteboard
        let text = tv.string as NSString
        let yanked = text.substring(with: sel)
        isLinewiseYank = mode == .visualLine
        tv.insertText(content, replacementRange: sel)
        // Put deleted selection on pasteboard (enables swap: select A, yank, select B, p → swaps)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        // Cursor at start of pasted text
        tv.setSelectedRange(NSRange(location: sel.location, length: 0))
        visualGPending = false
        mode = .normal
        updateBlockCursor()
    }

    // MARK: - Line Operations

    private func deleteLine(count n: Int) {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        guard text.length > 0 else { return }
        let loc = tv.selectedRange().location
        var lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
        for _ in 1..<n {
            let end = NSMaxRange(lineRange)
            if end < text.length {
                lineRange = text.lineRange(for: NSRange(location: lineRange.location, length: end - lineRange.location + 1))
            }
        }
        let yanked = text.substring(with: lineRange)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        isLinewiseYank = true
        tv.insertText("", replacementRange: lineRange)
    }

    private func yankLine(count n: Int) {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        guard text.length > 0 else { return }
        let loc = tv.selectedRange().location
        var lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
        for _ in 1..<n {
            let end = NSMaxRange(lineRange)
            if end < text.length {
                lineRange = text.lineRange(for: NSRange(location: lineRange.location, length: end - lineRange.location + 1))
            }
        }
        let yanked = text.substring(with: lineRange)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        isLinewiseYank = true
    }

    // MARK: - Motion-Based Operations

    /// Delete from cursor to where the motion moves it.
    private func deleteMotion(_ motion: (WritingNSTextView?) -> Void) {
        guard let tv = textView else { return }
        let start = tv.selectedRange().location
        collapseSelection()
        motion(tv)
        let end = tv.selectedRange().location
        guard start != end else { return }
        let lo = min(start, end)
        let hi = max(start, end)
        let range = NSRange(location: lo, length: hi - lo)
        let yanked = (tv.string as NSString).substring(with: range)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        isLinewiseYank = false
        tv.insertText("", replacementRange: range)
    }

    /// Yank from cursor to where the motion moves it, then return cursor.
    private func yankMotion(count n: Int = 1, _ motion: (WritingNSTextView?) -> Void) {
        guard let tv = textView else { return }
        let start = tv.selectedRange().location
        collapseSelection()
        times(n) { motion(tv) }
        let end = tv.selectedRange().location
        guard start != end else { return }
        let lo = min(start, end)
        let hi = max(start, end)
        let range = NSRange(location: lo, length: hi - lo)
        let yanked = (tv.string as NSString).substring(with: range)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yanked, forType: .string)
        lastYankedContent = yanked
        isLinewiseYank = false
        tv.setSelectedRange(NSRange(location: start, length: 0))
    }

    // MARK: - Paste

    private func pasteAfter() {
        guard let tv = textView,
              let content = NSPasteboard.general.string(forType: .string) else { return }
        collapseSelection()
        // Linewise if vim-yanked linewise content is still on pasteboard,
        // OR if the content ends with a newline (e.g. system Cmd+C of a full line)
        let linewise = (isLinewiseYank && content == lastYankedContent) || content.hasSuffix("\n")
        if linewise {
            tv.moveToEndOfParagraph(nil)
            let text = tv.string as NSString
            let loc = tv.selectedRange().location
            if loc < text.length {
                tv.moveRight(nil) // Past the newline
                let insertLoc = tv.selectedRange().location
                tv.insertText(content, replacementRange: NSRange(location: insertLoc, length: 0))
                tv.setSelectedRange(NSRange(location: insertLoc, length: 0))
            } else {
                // At end of document — add newline first
                tv.insertText("\n" + content, replacementRange: NSRange(location: loc, length: 0))
                tv.setSelectedRange(NSRange(location: loc + 1, length: 0))
            }
        } else {
            tv.moveRight(nil)
            let loc = tv.selectedRange().location
            tv.insertText(content, replacementRange: NSRange(location: loc, length: 0))
            // Cursor after pasted text, then back one (vim behavior)
            let afterLoc = loc + (content as NSString).length
            tv.setSelectedRange(NSRange(location: max(loc, afterLoc - 1), length: 0))
        }
    }

    private func pasteBefore() {
        guard let tv = textView,
              let content = NSPasteboard.general.string(forType: .string) else { return }
        collapseSelection()
        let linewise = (isLinewiseYank && content == lastYankedContent) || content.hasSuffix("\n")
        if linewise {
            tv.moveToBeginningOfParagraph(nil)
            let loc = tv.selectedRange().location
            tv.insertText(content, replacementRange: NSRange(location: loc, length: 0))
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        } else {
            let loc = tv.selectedRange().location
            tv.insertText(content, replacementRange: NSRange(location: loc, length: 0))
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    // MARK: - Helpers

    // MARK: - Bounded Character Movement

    /// Move right without crossing newline (vim `l` behavior).
    /// `pastLastChar: false` prevents landing on the last char before `\n`
    /// (used in visual mode where the selection shouldn't include `\n`).
    private func moveRightBounded(pastLastChar: Bool = true) {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let loc = tv.selectedRange().location
        guard loc < text.length else { return }
        if text.character(at: loc) == 0x0A { return }
        if !pastLastChar {
            // Don't move if next char is \n or end of document
            if loc + 1 >= text.length || text.character(at: loc + 1) == 0x0A { return }
        }
        tv.moveRight(nil)
    }

    /// Move left without crossing to previous line (vim `h` behavior).
    private func moveLeftBounded() {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let loc = tv.selectedRange().location
        guard loc > 0 else { return }
        let lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
        if loc > lineRange.location {
            tv.moveLeft(nil)
        }
    }

    // MARK: - Bounded Word Movement

    /// Move forward by one word, respecting vim character classes (word chars
    /// vs punctuation) and stopping at line boundaries.
    /// If `forOperator` is true, allows landing at the newline position (needed for dw/yw).
    private func moveWordForwardBounded(forOperator: Bool = false) {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let loc = tv.selectedRange().location
        guard loc < text.length else { return }

        let startChar = text.character(at: loc)
        if startChar == 0x0A { return }

        var pos = loc

        // Step 1: skip current character class
        if isWhitespace(startChar) {
            // On whitespace — skip to next non-whitespace
            while pos < text.length {
                let c = text.character(at: pos)
                if c == 0x0A || !isWhitespace(c) { break }
                pos += 1
            }
        } else if isWordChar(startChar) {
            // Skip word chars, then any trailing whitespace
            while pos < text.length {
                let c = text.character(at: pos)
                if !isWordChar(c) { break }
                pos += 1
            }
            while pos < text.length {
                let c = text.character(at: pos)
                if c == 0x0A || !isWhitespace(c) { break }
                pos += 1
            }
        } else {
            // Punctuation — skip punct, then any trailing whitespace
            while pos < text.length {
                let c = text.character(at: pos)
                if c == 0x0A || isWordChar(c) || isWhitespace(c) { break }
                pos += 1
            }
            while pos < text.length {
                let c = text.character(at: pos)
                if c == 0x0A || !isWhitespace(c) { break }
                pos += 1
            }
        }

        // For operators: allow landing at newline (so dw deletes to end of line)
        if forOperator {
            if pos != loc {
                tv.setSelectedRange(NSRange(location: pos, length: 0))
            }
            return
        }
        // For movement: if no next word on this line, go to last content char
        if pos >= text.length || text.character(at: pos) == 0x0A {
            var target = pos - 1
            while target > loc && isWhitespace(text.character(at: target)) {
                target -= 1
            }
            if target > loc {
                tv.setSelectedRange(NSRange(location: target, length: 0))
            }
            return
        }
        if pos != loc {
            tv.setSelectedRange(NSRange(location: pos, length: 0))
        }
    }

    /// Move backward by one word, respecting vim character classes and
    /// stopping at start of line.
    private func moveWordBackwardBounded() {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let loc = tv.selectedRange().location
        guard loc > 0 else { return }

        let lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
        let lineStart = lineRange.location

        if loc <= lineStart { return }

        var pos = loc
        // Skip whitespace backward
        while pos > lineStart && isWhitespace(text.character(at: pos - 1)) {
            pos -= 1
        }

        guard pos > lineStart else {
            tv.setSelectedRange(NSRange(location: lineStart, length: 0))
            return
        }

        let prevChar = text.character(at: pos - 1)
        if isWordChar(prevChar) {
            // Skip word chars backward
            while pos > lineStart && isWordChar(text.character(at: pos - 1)) {
                pos -= 1
            }
        } else {
            // Skip punctuation backward
            while pos > lineStart {
                let c = text.character(at: pos - 1)
                if isWordChar(c) || isWhitespace(c) { break }
                pos -= 1
            }
        }
        tv.setSelectedRange(NSRange(location: pos, length: 0))
    }

    private func isWhitespace(_ char: unichar) -> Bool {
        char == 0x20 || char == 0x09
    }

    private func isWordChar(_ char: unichar) -> Bool {
        (char >= 0x61 && char <= 0x7A) || // a-z
        (char >= 0x41 && char <= 0x5A) || // A-Z
        (char >= 0x30 && char <= 0x39) || // 0-9
        char == 0x5F ||                    // _
        char > 0x7F                        // non-ASCII (accented, CJK, etc.)
    }

    private func moveToFirstNonWhitespace() {
        guard let tv = textView else { return }
        tv.moveToBeginningOfLine(nil)
        let text = tv.string as NSString
        var loc = tv.selectedRange().location
        while loc < text.length {
            let c = text.character(at: loc)
            if c != 0x20 && c != 0x09 { break }
            loc += 1
        }
        tv.setSelectedRange(NSRange(location: loc, length: 0))
    }

    /// In normal mode, cursor should be ON the last character, not past it.
    private func nudgeBackIfNeeded() {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        let loc = tv.selectedRange().location
        if loc > 0 && (loc >= text.length || text.character(at: max(0, loc - 1)) != 0x0A) {
            // Only nudge back if we're past the last char (not at a newline)
            if loc > 0 && loc == text.length {
                tv.moveLeft(nil)
            }
        }
    }

    func updateBlockCursor() {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        guard text.length > 0 else { return }
        var loc = tv.selectedRange().location
        if loc >= text.length {
            loc = text.length - 1
        }
        // Don't sit on \n when there's content before it on the same line —
        // back up to the last real char. But allow \n on blank lines (nothing
        // else to select).
        if text.character(at: loc) == 0x0A {
            let lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
            if lineRange.location < loc {
                loc -= 1
            }
        }
        tv.setSelectedRange(NSRange(location: loc, length: 1))
    }

    private func collapseSelection() {
        guard let tv = textView else { return }
        let loc = tv.selectedRange().location
        tv.setSelectedRange(NSRange(location: loc, length: 0))
    }

    private func times(_ n: Int, _ action: () -> Void) {
        for _ in 0..<n { action() }
    }

    /// Reset to insert mode (e.g. when vim mode is toggled off).
    func reset() {
        countBuffer = ""
        isLinewiseYank = false
        lastYankedContent = nil
        cancelJBuffer(insert: false)
        visualGPending = false
        mode = .insert
        collapseSelection()
    }
}
