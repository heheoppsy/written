import AppKit

final class WritingNSTextView: NSTextView {

    // MARK: - Configuration

    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((Int) -> Void)?
    var onVimModeChange: ((VimMode) -> Void)?
    var onVimCountChange: ((String) -> Void)?
    var typewriterScrolling: Bool = false
    var typewriterFollowCursor: Bool = true
    /// Set during programmatic scrolls to suppress scroll observer feedback loops.
    var isProgrammaticScroll: Bool = false

    // MARK: - Current Line Highlight

    var currentLineHighlight: Bool = false {
        didSet { needsDisplay = true }
    }
    private var highlightColor: NSColor = NSColor.white.withAlphaComponent(0.15)

    func updateHighlightColor(from theme: Theme) {
        highlightColor = theme.textColor.withAlphaComponent(0.15)
        if currentLineHighlight { needsDisplay = true }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard currentLineHighlight else { return }

        // Get the full logical line range (the whole paragraph, not just the wrapped fragment)
        let text = string as NSString
        guard text.length > 0 else { return }
        let cursorLoc = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: min(cursorLoc, max(0, text.length - 1)), length: 0))

        // Get bounding rect spanning all wrapped fragments of this logical line
        let paraRect = boundingRect(forCharacterRange: lineRange)
        guard paraRect != .zero else { return }

        let containerOrigin = textContainerOrigin
        let lineY = paraRect.origin.y + containerOrigin.y
        let lineH = paraRect.height

        // Soft glow band: solid center + single line-height fade on each edge
        let singleLineH = font?.pointSize ?? 18
        let fadeH = singleLineH * 1.5
        let bandX: CGFloat = -200
        let bandW = bounds.width + 400

        let centerColor = highlightColor
        let edgeColor = highlightColor.withAlphaComponent(0)

        // Top fade
        let topRect = NSRect(x: bandX, y: lineY - fadeH, width: bandW, height: fadeH)
        NSGradient(starting: edgeColor, ending: centerColor)?.draw(in: topRect, angle: 90)

        // Solid center (the full logical line)
        let centerRect = NSRect(x: bandX, y: lineY, width: bandW, height: lineH)
        centerColor.setFill()
        centerRect.fill()

        // Bottom fade
        let bottomRect = NSRect(x: bandX, y: lineY + lineH, width: bandW, height: fadeH)
        NSGradient(starting: centerColor, ending: edgeColor)?.draw(in: bottomRect, angle: 90)
    }

    // MARK: - Vim

    var vimEnabled: Bool = false {
        didSet {
            if vimEnabled && vimEngine == nil {
                let engine = VimEngine()
                engine.textView = self
                engine.onModeChange = { [weak self] mode in
                    self?.onVimModeChange?(mode)
                }
                engine.onCountChange = { [weak self] count in
                    self?.onVimCountChange?(count)
                }
                vimEngine = engine
            }
            if !vimEnabled, let engine = vimEngine {
                engine.reset()
                vimEngine = nil
                onVimModeChange?(.insert)
            }
        }
    }
    private(set) var vimEngine: VimEngine?

    var overlayActive: Bool = false {
        didSet {
            guard oldValue != overlayActive else { return }
            updateTrackingAreas()
            if overlayActive {
                NSCursor.arrow.set()
            }
        }
    }

    override func updateTrackingAreas() {
        if overlayActive {
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        } else {
            super.updateTrackingAreas()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if overlayActive {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    func applyTheme(_ theme: Theme) {
        drawsBackground = false
        backgroundColor = .clear
        insertionPointColor = theme.caretColor
        selectedTextAttributes = [
            .backgroundColor: theme.selectionColor,
            .foregroundColor: theme.textColor,
        ]
        textColor = theme.textColor

        if let textStorage = textStorage, textStorage.length > 0 {
            textStorage.addAttribute(
                .foregroundColor,
                value: theme.textColor,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }

        enclosingScrollView?.drawsBackground = false
        enclosingScrollView?.borderType = .noBorder

        needsDisplay = true
    }

    func applyFont(_ font: NSFont) {
        self.font = font
        if let textStorage = textStorage, textStorage.length > 0 {
            textStorage.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }
    }

    private var lastLayoutFont: NSFont?
    private var lastLayoutMode: LayoutMode = .column
    private var lastColumnWidthPercent: Double = 80

    func applyColumnLayout(font: NSFont, mode: LayoutMode, columnWidthPercent: Double) {
        lastLayoutFont = font
        lastLayoutMode = mode
        lastColumnWidthPercent = columnWidthPercent
        applyColumnLayoutInternal()
    }

    private func applyColumnLayoutInternal() {
        guard let scrollView = enclosingScrollView, let container = textContainer,
              let font = lastLayoutFont else { return }

        let viewportH = scrollView.contentView.bounds.height

        let insets = ColumnLayoutHelper.insets(
            for: font,
            containerWidth: scrollView.contentSize.width,
            mode: lastLayoutMode,
            columnWidthPercent: lastColumnWidthPercent
        )
        if typewriterScrolling {
            let halfHeight = viewportH / 2
            scrollView.contentInsets = NSEdgeInsets(top: halfHeight, left: 0, bottom: halfHeight, right: 0)
        } else {
            scrollView.contentInsets = NSEdgeInsets()
        }
        textContainerInset = insets
        container.widthTracksTextView = false
        let containerWidth = max(1, scrollView.contentSize.width - insets.width * 2)
        container.containerSize = NSSize(width: containerWidth, height: .greatestFiniteMagnitude)
        invalidateTextContainerOrigin()
        if let tlm = textLayoutManager, let docRange = tlm.textContentManager?.documentRange {
            tlm.invalidateLayout(for: docRange)
        }
        needsDisplay = true
    }

    func applyTextAlignment(_ centered: Bool) {
        let alignment: NSTextAlignment = centered ? .center : .natural
        let style = (defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        defaultParagraphStyle = style

        if let textStorage = textStorage, textStorage.length > 0 {
            textStorage.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }

        var attrs = typingAttributes
        attrs[.paragraphStyle] = style
        typingAttributes = attrs
    }

    // MARK: - Setup

    func configureForWriting() {
        isRichText = true
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        applyLineSpacing(4)

        enclosingScrollView?.hasVerticalScroller = true
        enclosingScrollView?.scrollerStyle = .overlay

        #if DEBUG
        if textLayoutManager == nil { print("WARNING: TextKit 2 not active") }
        #endif
    }

    func applyLineSpacing(_ spacing: CGFloat) {
        let style = (defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = spacing
        defaultParagraphStyle = style

        if let textStorage = textStorage, textStorage.length > 0 {
            textStorage.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }

        var attrs = typingAttributes
        attrs[.paragraphStyle] = style
        typingAttributes = attrs
    }

    // MARK: - Layout Settling

    private var settleWorkItem: DispatchWorkItem?

    /// True while settling layout — prevents the frame observer from
    /// re-triggering layout changes during a settle.
    var isSettlingLayout = false

    /// Tracks scroll view width so the frame observer can skip
    /// height-only changes (e.g. find bar open/close).
    var lastKnownWidth: CGFloat = 0

    /// Lightweight layout fix: preserves the current scroll position through
    /// TK2's deferred layout pass, then nudges the cursor to finalize.
    /// No fade, no timer — use for settings changes, overlay close, resize.
    func nudgeLayout() {
        guard let scrollView = enclosingScrollView else { return }
        let savedOrigin = scrollView.contentView.bounds.origin
        // After TK2's deferred layout pass (triggered by invalidateLayout)
        // runs on the next display cycle, restore scroll and nudge cursor.
        DispatchQueue.main.async { [weak self] in
            guard let self, let scrollView = self.enclosingScrollView else { return }
            // Restore scroll position that TK2's layout pass disrupted
            self.isProgrammaticScroll = true
            scrollView.contentView.setBoundsOrigin(savedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            self.isProgrammaticScroll = false
            // Now nudge
            let sel = self.selectedRange()
            if sel.location > 0 {
                self.moveLeft(nil)
                self.moveRight(nil)
            } else if (self.string as NSString).length > 0 {
                self.moveRight(nil)
                self.moveLeft(nil)
            }
            self.ensureCursorVisible()
        }
    }

    /// Debounced layout settle with fade transition. Hides the editor,
    /// waits for layout changes to finish, then nudges the cursor to
    /// trigger NSTextView's internal layout cycle and fades back in.
    /// Use for document loads and initial setup.
    func scheduleSettleLayout() {
        isSettlingLayout = true
        settleWorkItem?.cancel()
        if let layer = enclosingScrollView?.layer {
            layer.removeAnimation(forKey: "fadeIn")
            layer.opacity = 0
        }
        let item = DispatchWorkItem { [weak self] in
            self?.settleLayout()
        }
        settleWorkItem = item
        let delay: Double = (string as NSString).length > 500_000 ? 0.5 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func settleLayout() {
        isSettlingLayout = true
        applyColumnLayoutInternal()
        scrollRangeToVisible(selectedRange())
        layoutSubtreeIfNeeded()
        // Nudge the cursor to trigger NSTextView's full internal layout cycle
        // (the same path typing/arrow keys take). Text is hidden so the user
        // doesn't see it. moveLeft/moveRight don't affect undo history.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sel = self.selectedRange()
            if sel.location > 0 {
                self.moveLeft(nil)
                self.moveRight(nil)
            } else if (self.string as NSString).length > 0 {
                self.moveRight(nil)
                self.moveLeft(nil)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isSettlingLayout = false
                if !self.typewriterScrolling {
                    self.scrollRangeToVisible(self.selectedRange())
                }
                self.ensureCursorVisible()
                self.fadeInEditor()
            }
        }
    }

    private func fadeInEditor() {
        guard let layer = enclosingScrollView?.layer else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.opacity
        anim.toValue = 1
        anim.duration = 0.2
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 1
        layer.add(anim, forKey: "fadeIn")
    }

    // MARK: - TextKit 2 Layout Helpers

    private func textLocation(for characterIndex: Int) -> NSTextLocation? {
        guard let tcm = textLayoutManager?.textContentManager else { return nil }
        return tcm.location(tcm.documentRange.location, offsetBy: characterIndex)
    }

    private func lineFragmentFrame(forCharacterAt charIndex: Int) -> NSRect {
        guard let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let location = textLocation(for: charIndex) else { return .zero }
        var result: NSRect = .zero

        func extractLineRect(from fragment: NSTextLayoutFragment) {
            let origin = fragment.layoutFragmentFrame.origin
            let offsetInFragment = tcm.offset(from: fragment.rangeInElement.location, to: location)
            // Drill into visual lines to find the exact wrapped line
            for lineFragment in fragment.textLineFragments {
                if offsetInFragment >= lineFragment.characterRange.location {
                    result = NSRect(
                        x: origin.x,
                        y: origin.y + lineFragment.typographicBounds.origin.y,
                        width: fragment.layoutFragmentFrame.width,
                        height: lineFragment.typographicBounds.height
                    )
                }
            }
            if result == .zero {
                result = fragment.layoutFragmentFrame
            }
        }

        // Forward: finds fragments starting at or after the location
        tlm.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            extractLineRect(from: fragment)
            return false
        }
        // Reverse fallback: cursor at end of a fragment (half-open range excludes it
        // from forward enumeration). Walk backward to find the fragment that ends here.
        if result == .zero {
            tlm.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout, .reverse]) { fragment in
                // If cursor follows a newline, it's on the empty line BELOW this fragment
                if charIndex > 0 && (self.string as NSString).character(at: charIndex - 1) == 0x0A {
                    let lineH = fragment.textLineFragments.last?.typographicBounds.height
                        ?? self.font?.pointSize ?? 16
                    result = NSRect(
                        x: fragment.layoutFragmentFrame.origin.x,
                        y: fragment.layoutFragmentFrame.maxY,
                        width: fragment.layoutFragmentFrame.width,
                        height: lineH
                    )
                } else {
                    extractLineRect(from: fragment)
                }
                return false
            }
        }
        return result
    }

    private func boundingRect(forCharacterRange range: NSRange) -> NSRect {
        guard let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let start = tcm.location(tcm.documentRange.location, offsetBy: range.location),
              let end = tcm.location(tcm.documentRange.location, offsetBy: NSMaxRange(range)),
              let textRange = NSTextRange(location: start, end: end) else { return .zero }
        var result: NSRect = .zero
        tlm.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            result = result == .zero ? frame : result.union(frame)
            return fragment.rangeInElement.endLocation.compare(textRange.endLocation) == .orderedAscending
        }
        return result
    }

    // MARK: - Cursor Scrolling

    /// Ensures the cursor line is visible, scrolling if needed.
    /// In typewriter mode, centers the cursor vertically.
    /// In normal mode, scrolls just enough to keep the cursor in view.
    func ensureCursorVisible() {
        guard let scrollView = enclosingScrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let maxScrollY = max(0, docHeight + scrollView.contentInsets.bottom - visibleRect.height)
        let minScrollY = -scrollView.contentInsets.top

        isProgrammaticScroll = true
        defer { isProgrammaticScroll = false }

        if typewriterScrolling {
            // Use the insertion indicator's actual Y for stable centering.
            // lineFragmentFrame computes different positions for empty vs text
            // lines, causing jitter. The system-placed indicator is consistent.
            var indicatorY: CGFloat?
            for subview in subviews where subview is NSTextInsertionIndicator {
                indicatorY = subview.frame.origin.y
                break
            }
            // Fall back to lineFragmentFrame if indicator isn't laid out yet
            // (e.g. during document load). Still centers rather than just
            // scrolling into view.
            let caretY: CGFloat
            if let iy = indicatorY {
                caretY = iy
            } else {
                let lineRect = lineFragmentFrame(forCharacterAt: selectedRange().location)
                guard lineRect != .zero else {
                    scrollRangeToVisible(selectedRange())
                    return
                }
                caretY = lineRect.origin.y + textContainerInset.height
            }
            let stableHeight: CGFloat = if let f = font { ceil(f.ascender - f.descender + f.leading) } else { 18 }
            let targetY = caretY + stableHeight / 2 - visibleRect.height / 2
            let clampedY = max(minScrollY, min(targetY, maxScrollY))
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            scrollRangeToVisible(selectedRange())
            let insertionPoint = selectedRange().location
            let lineRect = lineFragmentFrame(forCharacterAt: insertionPoint)
            guard lineRect != .zero else { return }
            let cursorY = lineRect.origin.y + textContainerInset.height
            let cursorBottom = cursorY + lineRect.height
            let margin: CGFloat = 40

            if cursorY < visibleRect.origin.y + margin {
                let targetY = max(0, cursorY - margin)
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else if cursorBottom > visibleRect.origin.y + visibleRect.height - margin {
                let targetY = cursorBottom - visibleRect.height + margin
                let clampedY = min(targetY, maxScrollY)
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting && !isSettlingLayout {
            onSelectionChange?(selectedRange().location)
            if currentLineHighlight { needsDisplay = true }
        }
        // Only auto-scroll when we have focus — don't fight NSTextFinder's
        // scrolling when the find bar is driving selection changes.
        let weHaveFocus = window?.firstResponder === self
        if typewriterScrolling && typewriterFollowCursor && !stillSelecting && !isSettlingLayout && weHaveFocus {
            DispatchQueue.main.async { [weak self] in
                self?.ensureCursorVisible()
            }
        }
    }

    // MARK: - Vim Key Handling

    override func keyDown(with event: NSEvent) {
        if let engine = vimEngine, engine.handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let nsString = string as NSString

        // Select the clicked word (standard macOS behavior) and offer spelling suggestions
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        if charIndex < nsString.length {
            // Expand click to word boundaries and select it
            let wordRange = selectionRange(forProposedRange: NSRange(location: charIndex, length: 0), granularity: .selectByWord)
            if wordRange.length > 0 {
                setSelectedRange(wordRange)

                if isContinuousSpellCheckingEnabled {
                    let word = nsString.substring(with: wordRange)
                    let checker = NSSpellChecker.shared
                    let misspelledRange = checker.checkSpelling(of: word, startingAt: 0)
                    if misspelledRange.location != NSNotFound {
                        let guesses = checker.guesses(forWordRange: misspelledRange, in: word, language: checker.language(), inSpellDocumentWithTag: 0) ?? []
                        for guess in guesses.prefix(5) {
                            let item = NSMenuItem(title: guess, action: #selector(applySuggestion(_:)), keyEquivalent: "")
                            item.representedObject = wordRange
                            item.target = self
                            menu.addItem(item)
                        }
                        if !guesses.isEmpty {
                            menu.addItem(.separator())
                        }
                        let learn = NSMenuItem(title: "Learn Spelling", action: #selector(learnSpelling(_:)), keyEquivalent: "")
                        learn.representedObject = word
                        learn.target = self
                        menu.addItem(learn)

                        let ignore = NSMenuItem(title: "Ignore Spelling", action: #selector(ignoreSpelling(_:)), keyEquivalent: "")
                        ignore.representedObject = word
                        ignore.target = self
                        menu.addItem(ignore)

                        menu.addItem(.separator())
                    }
                }
            }
        }

        menu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")

        menu.addItem(.separator())

        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebarFromMenu), keyEquivalent: "b")
        sidebarItem.keyEquivalentModifierMask = .command
        sidebarItem.target = self
        menu.addItem(sidebarItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsFromMenu), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    @objc private func toggleSidebarFromMenu() {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    @objc private func settingsFromMenu() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil)
    }

    @objc private func applySuggestion(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange else { return }
        insertText(sender.title, replacementRange: range)
    }

    @objc private func learnSpelling(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        NSSpellChecker.shared.learnWord(word)
    }

    // MARK: - Text Change Notifications

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
        if !typewriterScrolling {
            scrollRangeToVisible(selectedRange())
            ensureCursorVisible()
        } else if typewriterFollowCursor {
            ensureCursorVisible()
        }
    }
}
