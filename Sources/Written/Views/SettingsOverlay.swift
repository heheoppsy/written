import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case theme = "Theme"
    case fonts = "Fonts"
}

// MARK: - Navigation Model

private enum NavRowID: Equatable {
    // General
    case layoutMode, columnWidth, textAlignment, typewriter, togglesRow1, togglesRow2, vimRow
    // Theme
    case themeRow(Int)
    case glassLevel
    // Fonts
    case fontCategory, fontPicker, fontSizeButtons, fontSizeSlider, lineSpacingSlider
}

private struct NavRow: Equatable {
    let id: NavRowID
    let count: Int

    var isSlider: Bool {
        switch id {
        case .columnWidth, .fontSizeSlider, .lineSpacingSlider: return true
        default: return false
        }
    }
}

// MARK: - Settings Panel Content

struct SettingsPanelContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var fontManager: FontManager = .shared
    @Binding var selectedTab: SettingsTab
    @State private var focusRow: Int = 0
    @State private var focusCol: Int = 0
    @State private var editingSlider: Bool = false
    @State private var showFontPicker: Bool = false
    @State private var fontPickerIndex: Int = 0
    @State private var selectedFontCategory: FontCategory
    @FocusState private var panelFocused: Bool
    var availableHeight: CGFloat = 540
    let onDismiss: () -> Void

    init(settings: AppSettings, selectedTab: Binding<SettingsTab>, availableHeight: CGFloat = 540, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self._selectedTab = selectedTab
        self.availableHeight = availableHeight
        self.onDismiss = onDismiss
        self._selectedFontCategory = State(initialValue: settings.currentFontCategory)
    }

    // MARK: - Navigation

    private var solidThemes: [Theme] { Theme.presets.filter { !$0.isTranslucent } }
    private var translucentThemes: [Theme] { Theme.presets.filter { $0.isTranslucent } }

    private var currentNavRows: [NavRow] {
        switch selectedTab {
        case .general:
            var rows: [NavRow] = [NavRow(id: .layoutMode, count: 2)]
            if settings.layoutMode == .column {
                rows.append(NavRow(id: .columnWidth, count: 1))
            }
            rows.append(contentsOf: [
                NavRow(id: .textAlignment, count: 2),
                NavRow(id: .typewriter, count: 2),
                NavRow(id: .togglesRow1, count: 2),
                NavRow(id: .togglesRow2, count: 2),
                NavRow(id: .vimRow, count: 2),
            ])
            return rows
        case .theme:
            let solidChunks = solidThemes.chunked(into: 4)
            var rows: [NavRow] = solidChunks.enumerated().map { idx, chunk in
                NavRow(id: .themeRow(idx), count: chunk.count)
            }
            rows.append(NavRow(id: .themeRow(solidChunks.count), count: translucentThemes.count))
            if settings.currentTheme.isTranslucent {
                rows.append(NavRow(id: .glassLevel, count: 3))
            }
            return rows
        case .fonts:
            return [
                NavRow(id: .fontCategory, count: 4),
                NavRow(id: .fontPicker, count: 1),
                NavRow(id: .fontSizeButtons, count: 2),
                NavRow(id: .fontSizeSlider, count: 1),
                NavRow(id: .lineSpacingSlider, count: 1),
            ]
        }
    }

    private func isFocused(_ id: NavRowID, col: Int) -> Bool {
        guard let idx = currentNavRows.firstIndex(where: { $0.id == id }) else { return false }
        return focusRow == idx && focusCol == col
    }

    // MARK: - Font Helpers

    private var fontsForCategory: [CuratedFont] {
        FontManager.catalog.filter { $0.category == selectedFontCategory }
    }

    private var displayedFontID: String {
        let globalID = settings.currentFontName.isEmpty ? "SF-Mono" : settings.currentFontName
        if fontsForCategory.contains(where: { $0.id == globalID }) {
            return globalID
        }
        let lastUsed = settings.lastUsedFont(for: selectedFontCategory)
        if fontsForCategory.contains(where: { $0.id == lastUsed }) {
            return lastUsed
        }
        return fontsForCategory.first?.id ?? "SF-Mono"
    }

    private var displayedFontName: String {
        FontManager.catalog.first(where: { $0.id == displayedFontID })?.displayName ?? "SF Mono"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GlassTabBar(selection: $selectedTab)

                Text("Tab")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)

                Spacer()

                VStack(spacing: 2) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("Esc")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                switch selectedTab {
                case .general:
                    generalTab
                case .theme:
                    themeTab
                case .fonts:
                    fontsTab
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: availableHeight)
        .modifier(GlassPanelModifier())
        .focusable()
        .focusEffectDisabled()
        .focused($panelFocused)
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onAppear {
            NotificationCenter.default.post(name: .unfocusEditor, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                panelFocused = true
            }
        }
    }

    // MARK: - Keyboard

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Tab always cycles tabs
        if press.key == .tab {
            showFontPicker = false
            editingSlider = false
            cycleTab(forward: !press.modifiers.contains(.shift))
            return .handled
        }

        // Font picker mode
        if showFontPicker {
            return handleFontPickerKey(press)
        }

        switch press.key {
        case .escape:
            if editingSlider {
                editingSlider = false
                return .handled
            }
            panelFocused = false
            onDismiss()
            return .handled
        case .return:
            activateCurrentItem()
            return .handled
        case .downArrow, "j":
            moveRow(by: 1)
            return .handled
        case .upArrow, "k":
            moveRow(by: -1)
            return .handled
        case .leftArrow, "h":
            if editingSlider {
                adjustSlider(by: -1)
            } else {
                moveCol(by: -1)
            }
            return .handled
        case .rightArrow, "l":
            if editingSlider {
                adjustSlider(by: 1)
            } else {
                moveCol(by: 1)
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func handleFontPickerKey(_ press: KeyPress) -> KeyPress.Result {
        let fonts = fontsForCategory
        switch press.key {
        case .escape:
            showFontPicker = false
            return .handled
        case .return:
            if fontPickerIndex < fonts.count {
                selectFontByID(fonts[fontPickerIndex].id)
            }
            showFontPicker = false
            return .handled
        case .downArrow, "j":
            fontPickerIndex = min(fontPickerIndex + 1, fonts.count - 1)
            return .handled
        case .upArrow, "k":
            fontPickerIndex = max(fontPickerIndex - 1, 0)
            return .handled
        default:
            return .handled // Swallow all other keys while picker is open
        }
    }

    private func cycleTab(forward: Bool) {
        let allTabs = SettingsTab.allCases
        guard let currentIndex = allTabs.firstIndex(of: selectedTab) else { return }
        let newIndex: Int
        if forward {
            newIndex = (currentIndex + 1) % allTabs.count
        } else {
            newIndex = (currentIndex - 1 + allTabs.count) % allTabs.count
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedTab = allTabs[newIndex]
        }
        focusRow = 0
        focusCol = 0
        editingSlider = false
    }

    private func moveRow(by delta: Int) {
        let rows = currentNavRows
        guard !rows.isEmpty else { return }
        focusRow = ((focusRow + delta) % rows.count + rows.count) % rows.count
        focusCol = min(focusCol, rows[focusRow].count - 1)
        editingSlider = false
    }

    private func moveCol(by delta: Int) {
        let rows = currentNavRows
        guard focusRow < rows.count else { return }
        let maxCol = rows[focusRow].count - 1
        focusCol = min(max(focusCol + delta, 0), maxCol)
    }

    private func clampFocus() {
        let rows = currentNavRows
        if rows.isEmpty {
            focusRow = 0
            focusCol = 0
            return
        }
        if focusRow >= rows.count {
            focusRow = rows.count - 1
        }
        focusCol = min(focusCol, rows[focusRow].count - 1)
    }

    private func activateCurrentItem() {
        let rows = currentNavRows
        guard focusRow < rows.count else { return }
        let row = rows[focusRow]

        if row.isSlider {
            editingSlider.toggle()
            return
        }

        switch row.id {
        // General
        case .layoutMode:
            if focusCol == 0 { settings.layoutMode = .column }
            else { settings.layoutMode = .fullWidth }
            clampFocus()
        case .textAlignment:
            if focusCol == 0 { settings.centeredText = false }
            else { settings.centeredText = true }
        case .typewriter:
            if focusCol == 0 {
                settings.typewriterScrolling.toggle()
                if settings.typewriterScrolling { settings.vimModeEnabled = false }
            } else {
                settings.typewriterFollowCursor.toggle()
            }
            clampFocus()
        case .togglesRow1:
            switch focusCol {
            case 0: settings.spellCheckEnabled.toggle()
            case 1: settings.showWordCount.toggle()
            default: break
            }
        case .togglesRow2:
            switch focusCol {
            case 0: settings.currentLineHighlight.toggle()
            case 1: settings.showSidebarButton.toggle()
            default: break
            }
        case .vimRow:
            switch focusCol {
            case 0:
                settings.vimModeEnabled.toggle()
                if settings.vimModeEnabled { settings.typewriterScrolling = false }
            case 1: settings.vimJJEscape.toggle()
            default: break
            }

        // Theme
        case .themeRow(let rowNum):
            let solidChunks = solidThemes.chunked(into: 4)
            if rowNum < solidChunks.count {
                guard focusCol < solidChunks[rowNum].count else { break }
                settings.currentThemeID = solidChunks[rowNum][focusCol].id
            } else {
                guard focusCol < translucentThemes.count else { break }
                settings.currentThemeID = translucentThemes[focusCol].id
            }
            clampFocus()
        case .glassLevel:
            switch focusCol {
            case 0: settings.backgroundOpacityPct = 20
            case 1: settings.backgroundOpacityPct = 40
            case 2: settings.backgroundOpacityPct = 75
            default: break
            }
        // Fonts
        case .fontCategory:
            let categories: [FontCategory] = [.serif, .sans, .mono, .system]
            guard focusCol < categories.count else { break }
            selectCategoryAndFont(categories[focusCol])
        case .fontPicker:
            showFontPicker = true
            fontPickerIndex = fontsForCategory.firstIndex(where: { $0.id == displayedFontID }) ?? 0
        case .fontSizeButtons:
            if focusCol == 0 {
                settings.currentFontSize = max(12, settings.currentFontSize - 1)
            } else {
                settings.currentFontSize = min(36, settings.currentFontSize + 1)
            }

        default: break
        }
    }

    private func adjustSlider(by direction: Int) {
        let rows = currentNavRows
        guard focusRow < rows.count else { return }
        switch rows[focusRow].id {
        case .columnWidth:
            settings.columnWidthPercent = min(max(settings.columnWidthPercent + Double(direction) * 5, 40), 95)
        case .fontSizeSlider:
            settings.currentFontSize = min(max(settings.currentFontSize + Double(direction), 12), 36)
        case .lineSpacingSlider:
            settings.lineSpacing = min(max(settings.lineSpacing + Double(direction), 0), 16)
        default: break
        }
    }

    // MARK: - Font Selection

    private func selectFontByID(_ fontID: String) {
        guard let font = FontManager.catalog.first(where: { $0.id == fontID }) else {
            if selectedFontCategory == .system {
                settings.currentFontName = fontID == "SF-Mono" ? "" : fontID
            }
            return
        }
        if font.isSystem {
            settings.currentFontName = font.id == "SF-Mono" ? "" : font.id
            return
        }
        fontManager.ensureFont(font) { success in
            if success {
                settings.currentFontName = font.id
                settings.setLastUsedFont(font.id, for: selectedFontCategory)
            }
        }
    }

    private func selectCategoryAndFont(_ category: FontCategory) {
        selectedFontCategory = category
        let lastFont = settings.lastUsedFont(for: category)
        selectFontByID(lastFont)
    }

    // MARK: - Focus Ring Helpers

    private func sliderFocusRing(_ id: NavRowID) -> some View {
        let focused = isFocused(id, col: 0)
        let editing = editingSlider && focused
        return RoundedRectangle(cornerRadius: 6)
            .strokeBorder(
                editing ? Color.accentColor : (focused ? Color.accentColor.opacity(0.7) : Color.clear),
                lineWidth: focused ? 2 : 0
            )
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Layout") {
                HStack(spacing: 8) {
                    SettingsToggle(
                        title: "Column",
                        isSelected: settings.layoutMode == .column,
                        isFocused: isFocused(.layoutMode, col: 0)
                    ) {
                        settings.layoutMode = .column
                        clampFocus()
                    }
                    SettingsToggle(
                        title: "Full Width",
                        isSelected: settings.layoutMode == .fullWidth,
                        isFocused: isFocused(.layoutMode, col: 1)
                    ) {
                        settings.layoutMode = .fullWidth
                        clampFocus()
                    }
                }
            }

            if settings.layoutMode == .column {
                SettingsSection(title: "Column Width") {
                    HStack(spacing: 12) {
                        Text("Thin")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Slider(value: $settings.columnWidthPercent, in: 40...95, step: 5)

                        Text("Wide")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                    .overlay(sliderFocusRing(.columnWidth))
                }
            }

            SettingsSection(title: "Text Alignment") {
                HStack(spacing: 8) {
                    SettingsToggle(
                        title: "Left",
                        isSelected: !settings.centeredText,
                        isFocused: isFocused(.textAlignment, col: 0)
                    ) {
                        settings.centeredText = false
                    }
                    SettingsToggle(
                        title: "Center",
                        isSelected: settings.centeredText,
                        isFocused: isFocused(.textAlignment, col: 1)
                    ) {
                        settings.centeredText = true
                    }
                }
            }

            SettingsSection(title: "Typewriter") {
                HStack(spacing: 8) {
                    SettingsToggle(
                        title: settings.typewriterScrolling ? "On" : "Off",
                        isSelected: settings.typewriterScrolling,
                        isFocused: isFocused(.typewriter, col: 0)
                    ) {
                        settings.typewriterScrolling.toggle()
                        if settings.typewriterScrolling { settings.vimModeEnabled = false }
                    }
                    SettingsToggle(
                        title: "Follow Cursor",
                        isSelected: settings.typewriterFollowCursor,
                        isFocused: isFocused(.typewriter, col: 1)
                    ) {
                        settings.typewriterFollowCursor.toggle()
                    }
                }
            }

            SettingsSection(title: "Toggles") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        SettingsToggle(
                            title: "Spellcheck",
                            isSelected: settings.spellCheckEnabled,
                            isFocused: isFocused(.togglesRow1, col: 0)
                        ) {
                            settings.spellCheckEnabled.toggle()
                        }
                        SettingsToggle(
                            title: "Word Count",
                            isSelected: settings.showWordCount,
                            isFocused: isFocused(.togglesRow1, col: 1)
                        ) {
                            settings.showWordCount.toggle()
                        }
                    }
                    HStack(spacing: 8) {
                        SettingsToggle(
                            title: "Line Focus",
                            isSelected: settings.currentLineHighlight,
                            isFocused: isFocused(.togglesRow2, col: 0)
                        ) {
                            settings.currentLineHighlight.toggle()
                        }
                        SettingsToggle(
                            title: "Sidebar Button",
                            isSelected: settings.showSidebarButton,
                            isFocused: isFocused(.togglesRow2, col: 1)
                        ) {
                            settings.showSidebarButton.toggle()
                        }
                    }
                }
            }

            SettingsSection(title: "Vim") {
                Text("Lightweight vim bindings: normal, visual, operators, motions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SettingsToggle(
                        title: settings.vimModeEnabled ? "On" : "Off",
                        isSelected: settings.vimModeEnabled,
                        isFocused: isFocused(.vimRow, col: 0)
                    ) {
                        settings.vimModeEnabled.toggle()
                        if settings.vimModeEnabled { settings.typewriterScrolling = false }
                    }
                    SettingsToggle(
                        title: "jj Escape",
                        isSelected: settings.vimJJEscape,
                        isFocused: isFocused(.vimRow, col: 1)
                    ) {
                        settings.vimJJEscape.toggle()
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Theme Tab

    private var themeTab: some View {
        let solidChunks = solidThemes.chunked(into: 4)

        return VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Solid") {
                VStack(spacing: 8) {
                    ForEach(Array(solidChunks.enumerated()), id: \.offset) { rowIdx, chunk in
                        HStack(spacing: 8) {
                            ForEach(Array(chunk.enumerated()), id: \.element.id) { colIdx, theme in
                                ThemeSwatch(
                                    theme: theme,
                                    isSelected: settings.currentThemeID == theme.id,
                                    isFocused: isFocused(.themeRow(rowIdx), col: colIdx)
                                ) {
                                    settings.currentThemeID = theme.id
                                    clampFocus()
                                }
                            }
                        }
                    }
                }
            }

            SettingsSection(title: "Translucent") {
                HStack(spacing: 8) {
                    ForEach(Array(translucentThemes.enumerated()), id: \.element.id) { colIdx, theme in
                        ThemeSwatch(
                            theme: theme,
                            isSelected: settings.currentThemeID == theme.id,
                            isFocused: isFocused(.themeRow(solidChunks.count), col: colIdx)
                        ) {
                            settings.currentThemeID = theme.id
                            clampFocus()
                        }
                    }
                }
            }

            if settings.currentTheme.isTranslucent {
                SettingsSection(title: "Glass") {
                    HStack(spacing: 8) {
                        SettingsToggle(
                            title: "Clear",
                            isSelected: settings.backgroundOpacityPct < 30,
                            isFocused: isFocused(.glassLevel, col: 0)
                        ) {
                            settings.backgroundOpacityPct = 20
                        }
                        .frame(maxWidth: .infinity)
                        SettingsToggle(
                            title: "Sheer",
                            isSelected: settings.backgroundOpacityPct >= 30 && settings.backgroundOpacityPct < 60,
                            isFocused: isFocused(.glassLevel, col: 1)
                        ) {
                            settings.backgroundOpacityPct = 40
                        }
                        .frame(maxWidth: .infinity)
                        SettingsToggle(
                            title: "Frosted",
                            isSelected: settings.backgroundOpacityPct >= 60,
                            isFocused: isFocused(.glassLevel, col: 2)
                        ) {
                            settings.backgroundOpacityPct = 75
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

        }
        .padding(.bottom, 8)
    }

    // MARK: - Fonts Tab

    private var fontsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Category pills
            SettingsSection(title: "Category") {
                HStack(spacing: 6) {
                    ForEach(Array([FontCategory.serif, .sans, .mono, .system].enumerated()), id: \.element) { idx, category in
                        SettingsToggle(
                            title: category.rawValue,
                            isSelected: selectedFontCategory == category,
                            isFocused: isFocused(.fontCategory, col: idx)
                        ) {
                            selectCategoryAndFont(category)
                        }
                    }
                }
            }

            // Font picker
            SettingsSection(title: "Font") {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: {
                        showFontPicker.toggle()
                        if showFontPicker {
                            fontPickerIndex = fontsForCategory.firstIndex(where: { $0.id == displayedFontID }) ?? 0
                        }
                    }) {
                        HStack {
                            Text(displayedFontName)
                                .font(.system(size: 13))
                            Spacer()
                            Image(systemName: showFontPicker ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isFocused(.fontPicker, col: 0) ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),
                                    lineWidth: isFocused(.fontPicker, col: 0) ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    if showFontPicker {
                        fontPickerList
                    }
                }
            }

            // Font Size
            SettingsSection(title: "Font Size") {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button(action: { settings.currentFontSize = max(12, settings.currentFontSize - 1) }) {
                            Image(systemName: "textformat.size.smaller")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isFocused(.fontSizeButtons, col: 0) ? Color.accentColor.opacity(0.7) : Color.clear,
                                    lineWidth: 2
                                )
                        )

                        Text("\(Int(settings.currentFontSize))")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .frame(width: 32)

                        Button(action: { settings.currentFontSize = min(36, settings.currentFontSize + 1) }) {
                            Image(systemName: "textformat.size.larger")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isFocused(.fontSizeButtons, col: 1) ? Color.accentColor.opacity(0.7) : Color.clear,
                                    lineWidth: 2
                                )
                        )
                    }

                    Slider(value: $settings.currentFontSize, in: 12...36, step: 1)
                        .padding(4)
                        .overlay(sliderFocusRing(.fontSizeSlider))
                }
            }

            // Line Spacing
            SettingsSection(title: "Line Spacing") {
                HStack(spacing: 12) {
                    Text("Tight")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Slider(value: $settings.lineSpacing, in: 0...16, step: 1)

                    Text("Loose")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(4)
                .overlay(sliderFocusRing(.lineSpacingSlider))
            }

            // Preview
            SettingsSection(title: "Preview") {
                FontPreview(settings: settings, fontManager: fontManager)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Font Picker List

    private var fontPickerList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(fontsForCategory.enumerated()), id: \.element.id) { idx, font in
                        HStack {
                            Text(font.displayName)
                                .font(.system(size: 13))
                            Spacer()
                            if font.id == displayedFontID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(idx == fontPickerIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectFontByID(font.id)
                            showFontPicker = false
                        }
                        .id(font.id)
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .onAppear {
                proxy.scrollTo(displayedFontID, anchor: .center)
            }
            .onChange(of: fontPickerIndex) {
                if fontPickerIndex < fontsForCategory.count {
                    withAnimation {
                        proxy.scrollTo(fontsForCategory[fontPickerIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Font Preview

private struct FontPreview: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var fontManager: FontManager

    private var isGoogleFont: Bool {
        let name = settings.currentFontName
        return !name.isEmpty && name != "SF-Mono" && name != "SF-Pro"
    }

    private var fontReady: Bool {
        !isGoogleFont || fontManager.availableFonts.contains(settings.currentFontName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fontReady {
                Text("The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.")
                    .font(Font(settings.editorFont))
                    .foregroundColor(Color(nsColor: settings.currentTheme.textColor))
                    .lineSpacing(CGFloat(settings.lineSpacing))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .frame(height: 120, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: settings.currentTheme.backgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            } else {
                Text("Download to preview")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

            // Font info
            HStack {
                let displayName = FontManager.catalog.first(where: { $0.id == settings.currentFontName })?.displayName
                    ?? (settings.currentFontName.isEmpty ? "SF Mono" : settings.currentFontName)
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\u{00B7}")
                    .foregroundStyle(.quaternary)

                Text("\(Int(settings.currentFontSize))pt")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selection == tab ? .medium : .regular))
                        .foregroundStyle(selection == tab ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(.primary.opacity(0.1))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.primary.opacity(0.05))
        )
    }
}

// MARK: - Glass Panel

private struct GlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        }
    }
}

// MARK: - Components

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool
    var isFocused: Bool = false
    let action: () -> Void

    private var borderColor: Color {
        if isFocused { return Color.accentColor }
        if isSelected { return Color.accentColor.opacity(0.6) }
        return Color.primary.opacity(0.15)
    }

    private var borderWidth: CGFloat {
        if isFocused { return 2.5 }
        if isSelected { return 2 }
        return 1
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: theme.backgroundColor))
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    )
                    .overlay(
                        Text("Aa")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(nsColor: theme.textColor))
                    )

                Text(theme.name)
                    .font(.system(size: 10))
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsToggle: View {
    let title: String
    let isSelected: Bool
    var isFocused: Bool = false
    let action: () -> Void

    private var borderColor: Color {
        if isFocused { return Color.accentColor }
        if isSelected { return Color.accentColor.opacity(0.5) }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        isFocused ? 2.5 : 1
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
