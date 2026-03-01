import SwiftUI

enum WindowMode {
    case welcome
    case editor
}

enum FocusTarget {
    case editor
    case sidebar
    case sidebarFilter
}

struct MainContentView: View {
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var settings: AppSettings
    @StateObject private var sidebarVM = SidebarViewModel()
    @State private var sidebarVisible: Bool
    @State private var windowMode: WindowMode
    @State private var editorNeedsFocus = false
    @State private var settingsVisible = false
    @State private var settingsTab: SettingsTab = .general
    @State private var sidebarSelectedIndex: Int?
    @State private var showSavedFlash = false
    @State private var isFullscreen = false
    @State private var renamingNodeURL: URL?
    @State private var deletingNodeURL: URL?
    @State private var showSidebarHelp = false
    @State private var showWelcomeHelp = false
    @State private var showTutorial = false
    @State private var showTutorialFlash = false
    @State private var tutorialFlashText = ""
    @State private var saveModalState: SaveModalState?
    @State private var showNewFilePrompt = false
    @State private var sidebarFilterText = ""
    @State private var focusReturnTarget: FocusTarget = .editor
    @State private var updateAvailable: UpdateChecker.Update?
    @State private var edgeHovering = false
    @State private var sidebarButtonHovered = false
    @FocusState private var sidebarFocused: Bool
    @FocusState private var sidebarFilterFocused: Bool
    let onOpenFolder: () -> Void

    private var overlayActive: Bool { sidebarVisible || settingsVisible || showSavedFlash || saveModalState != nil || showNewFilePrompt }
    private var modalOverlayActive: Bool { settingsVisible || showWelcomeHelp || showTutorial || showTutorialFlash || saveModalState != nil || showNewFilePrompt }

    /// Whether the sidebar is in a modal sub-state (rename, delete, help) where normal nav keys should be suppressed.
    private var sidebarModal: Bool { renamingNodeURL != nil || deletingNodeURL != nil || showSidebarHelp || sidebarFilterFocused }

    /// Sidebar file list filtered by the current search text (mirrors SidebarView's filteredNodes).
    private var sidebarFilteredNodes: [FileNode] {
        let nodes = sidebarVM.fileOnlyNodes
        guard !sidebarFilterText.isEmpty else { return nodes }
        let query = sidebarFilterText.lowercased()
        return nodes.filter { $0.name.lowercased().contains(query) }
    }

    private let initialOverlay: String?

    init(viewModel: EditorViewModel, settings: AppSettings, showSidebar: Bool = false, startInEditor: Bool = false, initialOverlay: String? = nil, onOpenFolder: @escaping () -> Void) {
        self.viewModel = viewModel
        self.settings = settings
        self._sidebarVisible = State(initialValue: showSidebar)
        self._windowMode = State(initialValue: startInEditor ? .editor : .welcome)
        self.initialOverlay = initialOverlay
        self.onOpenFolder = onOpenFolder
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                themeBackground

                switch windowMode {
                case .welcome:
                    WelcomeView(
                        isDarkTheme: settings.currentTheme.isDark,
                        themeTextColor: Color(nsColor: settings.currentTheme.textColor),
                        onOpenFolder: { onOpenFolder() },
                        onOpenFile: { openFileFromPanel() },
                        onNewText: { newDocument() },
                        onOpenRecent: { item in openRecentItem(item) },
                        hideFileExtensions: settings.hideFileExtensions,
                        onShowHelp: { showWelcomeHelp.toggle() },
                        overlayActive: modalOverlayActive,
                        recents: RecentItemsService.shared
                    )
                    .blur(radius: modalOverlayActive ? 6 : 0)
                    .allowsHitTesting(!modalOverlayActive)

                case .editor:
                    ZStack(alignment: .leading) {
                        // Editor — always fills the window
                        EditorView(viewModel: viewModel, settings: settings, overlayActive: overlayActive, isFullscreen: isFullscreen)
                            .blur(radius: overlayActive ? 6 : 0)
                            .allowsHitTesting(!overlayActive)
                            .animation(.easeInOut(duration: 0.2), value: overlayActive)

                        // Sidebar mouse triggers
                        if !sidebarVisible && !overlayActive && settings.showSidebarButton {
                            // Left edge hover zone
                            HStack(spacing: 0) {
                                Color.clear
                                    .frame(width: 6)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        edgeHovering = hovering
                                    }
                                Spacer()
                            }

                            // Sidebar toggle button
                            VStack {
                                HStack {
                                    Button(action: {
                                        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                                    }) {
                                        Image(systemName: "sidebar.left")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color(nsColor: settings.currentTheme.textColor).opacity(sidebarButtonHovered ? 0.35 : 0.12))
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { hovering in
                                        sidebarButtonHovered = hovering
                                    }
                                    .padding(12)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }

                        // Sidebar overlays on top as a floating glass panel
                        if sidebarVisible {
                            SidebarView(
                                viewModel: sidebarVM,
                                theme: settings.currentTheme,
                                selectedIndex: sidebarSelectedIndex,
                                hideExtensions: settings.hideFileExtensions,
                                renamingURL: renamingNodeURL,
                                deletingURL: deletingNodeURL,
                                showHelp: showSidebarHelp,
                                onSelectFile: { url in loadFile(url) },
                                onNewFile: { createAndOpenNewFile() },
                                onRename: { url in startRename(url) },
                                onDelete: { url in startDelete(url) },
                                onRenameCommit: { url, newName in commitRename(url: url, newName: newName) },
                                onRenameCancel: { renamingNodeURL = nil; refocusSidebar() },
                                onDeleteConfirm: { confirmDelete() },
                                onDeleteCancel: { deletingNodeURL = nil; refocusSidebar() },
                                onToggleSort: { sidebarVM.toggleSortMode() },
                                onToggleHelp: { showSidebarHelp.toggle(); if !showSidebarHelp { refocusSidebar() } },
                                onClose: { NotificationCenter.default.post(name: .toggleSidebar, object: nil) },
                                onFilterDismiss: { refocusSidebar() },
                                filterText: $sidebarFilterText,
                                filterFocused: $sidebarFilterFocused
                            )
                            .frame(width: 260)
                            .modifier(GlassSidebarModifier())
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                            .padding(.leading, 12)
                            .transition(.move(edge: .leading))
                            .focusable()
                            .focusEffectDisabled()
                            .focused($sidebarFocused)
                            .onAppear {
                                NotificationCenter.default.post(name: .unfocusEditor, object: nil)
                                preselectCurrentFile()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    sidebarFocused = true
                                }
                            }
                            // Navigation keys — suppressed during modal states
                            .onKeyPress(.downArrow) { guard !sidebarModal else { return .ignored }; moveSidebarSelection(by: 1); return .handled }
                            .onKeyPress(.upArrow) { guard !sidebarModal else { return .ignored }; moveSidebarSelection(by: -1); return .handled }
                            .onKeyPress(.return) { guard !sidebarModal else { return .ignored }; handleSidebarEnter(); return .handled }
                            .onKeyPress(characters: CharacterSet(charactersIn: "j")) { _ in guard !sidebarModal else { return .ignored }; moveSidebarSelection(by: 1); return .handled }
                            .onKeyPress(characters: CharacterSet(charactersIn: "k")) { _ in guard !sidebarModal else { return .ignored }; moveSidebarSelection(by: -1); return .handled }
                            .onKeyPress(characters: CharacterSet(charactersIn: "n")) { _ in guard !sidebarModal else { return .ignored }; createAndOpenNewFile(); return .handled }
                            // Rename
                            .onKeyPress(characters: CharacterSet(charactersIn: "r")) { _ in
                                guard !sidebarModal else { return .ignored }
                                guard let index = sidebarSelectedIndex else { return .ignored }
                                let nodes = sidebarVM.flattenedVisibleNodes
                                guard index >= 0, index < nodes.count else { return .ignored }
                                startRename(nodes[index].url)
                                return .handled
                            }
                            // Delete
                            .onKeyPress(characters: CharacterSet(charactersIn: "d")) { _ in
                                guard !sidebarModal else { return .ignored }
                                guard let index = sidebarSelectedIndex else { return .ignored }
                                let nodes = sidebarVM.flattenedVisibleNodes
                                guard index >= 0, index < nodes.count else { return .ignored }
                                startDelete(nodes[index].url)
                                return .handled
                            }
                            // Delete confirmation keys (Y/N)
                            .onKeyPress(characters: CharacterSet(charactersIn: "y")) { _ in
                                guard deletingNodeURL != nil else { return .ignored }
                                confirmDelete()
                                return .handled
                            }
                            .onKeyPress(characters: CharacterSet(charactersIn: "nN")) { _ in
                                guard deletingNodeURL != nil else { return .ignored }
                                deletingNodeURL = nil
                                return .handled
                            }
                            // Sort
                            .onKeyPress(characters: CharacterSet(charactersIn: "s")) { _ in
                                guard !sidebarModal else { return .ignored }
                                sidebarVM.toggleSortMode()
                                return .handled
                            }
                            // Filter
                            .onKeyPress(characters: CharacterSet(charactersIn: "/")) { _ in
                                guard !sidebarModal else { return .ignored }
                                sidebarFilterFocused = true
                                return .handled
                            }
                            // Help
                            .onKeyPress(characters: CharacterSet(charactersIn: "?")) { _ in
                                guard deletingNodeURL == nil, renamingNodeURL == nil else { return .ignored }
                                showSidebarHelp.toggle()
                                if !showSidebarHelp { refocusSidebar() }
                                return .handled
                            }
                            // Escape — dismiss modals or close sidebar
                            .onKeyPress(.escape) {
                                if showSidebarHelp {
                                    showSidebarHelp = false
                                    refocusSidebar()
                                    return .handled
                                }
                                if deletingNodeURL != nil {
                                    deletingNodeURL = nil
                                    refocusSidebar()
                                    return .handled
                                }
                                if renamingNodeURL != nil {
                                    return .ignored // TextField's onExitCommand handles this
                                }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    sidebarVisible = false
                                    dismissSidebarModals()
                                }
                                editorNeedsFocus = true
                                return .handled
                            }
                            // Cmd+1-9 jump (respects active filter)
                            .onKeyPress(characters: .decimalDigits) { press in
                                guard press.modifiers == .command else { return .ignored }
                                guard let digit = Int(press.characters), digit >= 1, digit <= 9 else { return .ignored }
                                let files = sidebarFilteredNodes
                                let index = digit - 1
                                guard index < files.count else { return .ignored }
                                loadFile(files[index].url)
                                return .handled
                            }
                        }

                        // "Saved" flash overlay
                        if showSavedFlash {
                            savedFlashView
                                .transition(.opacity)
                        }

                    }
                    .animation(.easeInOut(duration: 0.2), value: sidebarVisible)
                    .animation(.easeInOut(duration: 0.15), value: showSavedFlash)
                }

                // Inline settings overlay — shared across welcome + editor
                if settingsVisible {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { dismissSettings() }

                    SettingsPanelContent(
                        settings: settings,
                        selectedTab: $settingsTab,
                        availableHeight: geo.size.height - 96,
                        onDismiss: { dismissSettings() }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {} // Block click-through to backdrop
                    .transition(.opacity)
                }

                // Welcome help overlay
                if showWelcomeHelp {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { dismissWelcomeHelp() }

                    WelcomeHelpView(
                        textColor: Color(nsColor: settings.currentTheme.textColor),
                        onDismiss: { dismissWelcomeHelp() },
                        onShowTutorial: {
                            dismissWelcomeHelp()
                            showTutorial = true
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {} // Block click-through to backdrop
                    .transition(.opacity)
                }

                // Tutorial overlay
                if showTutorial {
                    TutorialView(
                        textColor: Color(nsColor: settings.currentTheme.textColor),
                        onDismiss: { completed in dismissTutorial(completed: completed) }
                    )
                    .transition(.opacity)
                }

                // Tutorial flash (persists after panel closes, over blurred background)
                if showTutorialFlash {
                    Text(tutorialFlashText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(nsColor: settings.currentTheme.textColor).opacity(0.7))
                        .transition(.opacity)
                }

                // Update available banner
                if let update = updateAvailable {
                    VStack {
                        Spacer()
                        Button(action: {
                            NSWorkspace.shared.open(update.url)
                        }) {
                            Text("Written v\(update.version) available")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(nsColor: settings.currentTheme.textColor).opacity(0.5))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color(nsColor: settings.currentTheme.textColor).opacity(0.06))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color(nsColor: settings.currentTheme.textColor).opacity(0.1), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .padding(.bottom, 16)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
                }

                // Save / Close confirmation modals
                if let state = saveModalState {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { saveModalState = nil; refocusAfterModal() }

                    switch state {
                    case .closeConfirm:
                        CloseConfirmationView(
                            onSave: { saveModalState = .closeAndSave },
                            onDiscard: {
                                saveModalState = nil
                                viewModel.cleanupTempFile()
                                viewModel.document = WrittenDocument()
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    windowMode = .welcome
                                    sidebarVisible = false
                                }
                                updateWindowTitle()
                            },
                            onCancel: { saveModalState = nil; refocusAfterModal() }
                        )
                        .transition(.opacity)

                    case .save, .closeAndSave:
                        let defaultDir = viewModel.folderURL
                            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Documents", isDirectory: true)
                        let stem = viewModel.document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"

                        SaveModalView(
                            initialFilename: stem,
                            directoryURL: defaultDir,
                            onSave: { url in completeSave(url: url, thenClose: state == .closeAndSave) },
                            onCancel: { saveModalState = nil; refocusAfterModal() },
                            onSystemSave: {
                                let thenClose = state == .closeAndSave
                                saveModalState = nil
                                openSystemSavePanel(thenClose: thenClose)
                            }
                        )
                        .transition(.opacity)
                    }
                }

                // New file name prompt
                if showNewFilePrompt, let folderURL = viewModel.folderURL {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { showNewFilePrompt = false; refocusAfterModal() }

                    NewFileNameView(
                        directoryURL: folderURL,
                        onCreate: { url in
                            showNewFilePrompt = false
                            FileManager.default.createFile(atPath: url.path, contents: nil)
                            sidebarVM.refresh()
                            loadFile(url)
                        },
                        onCancel: { showNewFilePrompt = false; refocusAfterModal() }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: settingsVisible)
            .animation(.easeInOut(duration: 0.2), value: showWelcomeHelp)
            .animation(.easeInOut(duration: 0.15), value: showTutorial)
            .animation(.easeInOut(duration: 0.15), value: showTutorialFlash)
            .animation(.easeInOut(duration: 0.2), value: saveModalState)
            .animation(.easeInOut(duration: 0.2), value: showNewFilePrompt)
            .animation(.easeInOut(duration: 0.3), value: updateAvailable != nil)
        }
        .onAppear {
            if let folder = viewModel.folderURL {
                sidebarVM.loadFolder(folder)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateWindowTitle()
            }
            if let overlay = initialOverlay {
                if overlay == "tutorial" { showTutorial = true }
                else if overlay == "help" { showWelcomeHelp = true }
            } else if !settings.hasSeenTutorial && windowMode == .welcome {
                showTutorial = true
            }

            Task {
                try? await Task.sleep(for: .seconds(3))
                if let update = await UpdateChecker.checkForUpdate() {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        updateAvailable = update
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            guard !modalOverlayActive else { return }
            guard windowMode == .editor else { return }
            let wasVisible = sidebarVisible
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarVisible.toggle()
                if !sidebarVisible {
                    dismissSidebarModals()
                }
            }
            if wasVisible && !sidebarVisible {
                editorNeedsFocus = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .folderSelected)) { notification in
            guard !modalOverlayActive else { return }
            if let url = notification.object as? URL {
                RecentItemsService.shared.add(url: url)
                viewModel.folderURL = url
                sidebarVM.loadFolder(url)
                withAnimation(.easeInOut(duration: 0.3)) {
                    windowMode = .editor
                    sidebarVisible = true
                }
                preselectCurrentFile()
                updateWindowTitle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileInWindow)) { notification in
            guard !modalOverlayActive else { return }
            if let url = notification.object as? URL {
                RecentItemsService.shared.add(url: url)
                loadFile(url)
                let parentDir = url.deletingLastPathComponent()
                viewModel.folderURL = parentDir
                sidebarVM.loadFolder(parentDir)
                withAnimation(.easeInOut(duration: 0.3)) {
                    windowMode = .editor
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newDocument)) { _ in
            guard !modalOverlayActive else { return }
            newDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSettings)) { _ in
            if settingsVisible {
                dismissSettings()
            } else {
                guard !modalOverlayActive else { return }
                focusReturnTarget = currentFocusTarget
                settingsVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsClosed)) { _ in
            if settingsVisible { dismissSettings() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveDocument)) { _ in
            guard !modalOverlayActive else { return }
            saveCurrentDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeAction)) { _ in
            handleCloseAction()
        }
        .onChange(of: edgeHovering) {
            if edgeHovering && settings.showSidebarButton {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if edgeHovering && !sidebarVisible && !overlayActive && settings.showSidebarButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarVisible = true
                        }
                    }
                }
            }
        }
        .onChange(of: editorNeedsFocus) {
            if editorNeedsFocus {
                editorNeedsFocus = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .focusEditor, object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOverlay)) { notification in
            if let mode = notification.object as? String {
                if mode == "tutorial" { showTutorial = true }
                else if mode == "help" { showWelcomeHelp = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcomeHelp)) { _ in
            guard !showWelcomeHelp else { return }
            showWelcomeHelp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
    }

    // MARK: - Pre-select Current File

    private func preselectCurrentFile() {
        if let fileURL = viewModel.document.fileURL {
            let nodes = sidebarVM.flattenedVisibleNodes
            sidebarSelectedIndex = nodes.firstIndex(where: { $0.url == fileURL })
        } else {
            sidebarSelectedIndex = nil
        }
    }

    // MARK: - Sidebar Keyboard

    private func moveSidebarSelection(by delta: Int) {
        let nodes = sidebarVM.flattenedVisibleNodes
        guard !nodes.isEmpty else { return }

        if let current = sidebarSelectedIndex {
            sidebarSelectedIndex = max(0, min(current + delta, nodes.count - 1))
        } else {
            sidebarSelectedIndex = delta > 0 ? 0 : nodes.count - 1
        }
    }

    private func handleSidebarEnter() {
        let nodes = sidebarVM.flattenedVisibleNodes
        guard let index = sidebarSelectedIndex, index >= 0, index < nodes.count else { return }
        loadFile(nodes[index].url)
    }

    private func createAndOpenNewFile() {
        guard viewModel.folderURL != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible = false
            dismissSidebarModals()
        }
        showNewFilePrompt = true
    }

    // MARK: - Rename

    private func startRename(_ url: URL) {
        renamingNodeURL = url
    }

    private func commitRename(url: URL, newName: String) {
        guard let newURL = sidebarVM.renameFile(at: url, to: newName) else {
            renamingNodeURL = nil
            refocusSidebar()
            return
        }
        if viewModel.document.fileURL == url {
            viewModel.document.fileURL = newURL
            updateWindowTitle()
        }
        renamingNodeURL = nil
        refocusSidebar()
    }

    // MARK: - Delete

    private func startDelete(_ url: URL) {
        deletingNodeURL = url
    }

    private func confirmDelete() {
        guard let url = deletingNodeURL else { return }
        let wasOpen = viewModel.document.fileURL == url

        // Capture the neighbor to open before the list changes
        var nextURL: URL? = nil
        if wasOpen {
            let nodes = sidebarVM.flattenedVisibleNodes
            if let idx = nodes.firstIndex(where: { $0.url == url }) {
                if idx + 1 < nodes.count {
                    nextURL = nodes[idx + 1].url
                } else if idx > 0 {
                    nextURL = nodes[idx - 1].url
                }
            }
        }

        sidebarVM.deleteFile(at: url)
        deletingNodeURL = nil

        if wasOpen {
            if let next = nextURL {
                loadFile(next)
            } else {
                // Folder is now empty — stay in editor with blank document
                viewModel.document = WrittenDocument()
                updateWindowTitle()
            }
        }

        // Adjust selection
        let nodes = sidebarVM.flattenedVisibleNodes
        if let idx = sidebarSelectedIndex, idx >= nodes.count {
            sidebarSelectedIndex = nodes.isEmpty ? nil : nodes.count - 1
        }
        refocusSidebar()
    }

    private func dismissSettings() {
        settingsVisible = false
        restoreFocus(focusReturnTarget)
        // Welcome screen handles its own focus via onAppear
    }

    private func dismissWelcomeHelp() {
        showWelcomeHelp = false
        // WelcomeView's internal focus needs a nudge since onAppear already fired
    }

    private func dismissTutorial(completed: Bool) {
        settings.hasSeenTutorial = true
        showTutorial = false
        tutorialFlashText = completed ? "Happy writing :)" : "Sorry ;_;"
        withAnimation(.easeInOut(duration: 0.15)) {
            showTutorialFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTutorialFlash = false
            }
        }
    }

    private func refocusSidebar() {
        guard sidebarVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sidebarFocused = true
        }
    }

    /// Snapshot current focus target before an overlay steals it.
    private var currentFocusTarget: FocusTarget {
        if sidebarFilterFocused { return .sidebarFilter }
        if sidebarFocused || sidebarVisible { return .sidebar }
        return .editor
    }

    /// Restore focus to a previously saved target.
    private func restoreFocus(_ target: FocusTarget) {
        switch target {
        case .sidebarFilter:
            guard sidebarVisible else { fallthrough }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sidebarFilterFocused = true
            }
        case .sidebar:
            guard sidebarVisible else { fallthrough }
            refocusSidebar()
        case .editor:
            editorNeedsFocus = true
        }
    }

    private func dismissSidebarModals() {
        renamingNodeURL = nil
        deletingNodeURL = nil
        showSidebarHelp = false
        sidebarFilterText = ""
        sidebarFilterFocused = false
    }

    // MARK: - Close Action

    private func handleCloseAction() {
        if showTutorial { return }
        if showNewFilePrompt {
            showNewFilePrompt = false
            refocusAfterModal()
        } else if saveModalState != nil {
            saveModalState = nil
            refocusAfterModal()
        } else if settingsVisible {
            dismissSettings()
        } else if showWelcomeHelp {
            dismissWelcomeHelp()
        } else if sidebarVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarVisible = false
                dismissSidebarModals()
            }
            editorNeedsFocus = true
        } else if windowMode == .editor {
            closeDocument()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    private func closeDocument() {
        let hasFileURL = viewModel.document.fileURL != nil
        let hasContent = !viewModel.document.text.isEmpty

        if hasFileURL {
            viewModel.saveImmediately()
            withAnimation(.easeInOut(duration: 0.15)) {
                showSavedFlash = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.document = WrittenDocument()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSavedFlash = false
                    windowMode = .welcome
                    sidebarVisible = false
                }
                updateWindowTitle()
            }
        } else if hasContent {
            saveModalState = .closeConfirm
        } else {
            viewModel.document = WrittenDocument()
            withAnimation(.easeInOut(duration: 0.3)) {
                windowMode = .welcome
                sidebarVisible = false
            }
            updateWindowTitle()
        }
    }

    // MARK: - Saved Flash

    @ViewBuilder
    private var savedFlashView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("Saved")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(nsColor: settings.currentTheme.textColor).opacity(0.7))
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func updateWindowTitle() {
        var title = windowMode == .welcome ? "Written" : viewModel.windowTitle
        if windowMode != .welcome && settings.hideFileExtensions {
            title = (title as NSString).deletingPathExtension
        }
        if title.count > 35 {
            title = String(title.prefix(35)) + "…"
        }
        NotificationCenter.default.post(name: .updateWindowTitle, object: title)
    }

    private func newDocument() {
        if windowMode == .editor, viewModel.folderURL != nil {
            showNewFilePrompt = true
            return
        }
        viewModel.document = WrittenDocument()
        viewModel.folderURL = nil
        sidebarVM.clear()
        withAnimation(.easeInOut(duration: 0.3)) {
            windowMode = .editor
            sidebarVisible = false
            editorNeedsFocus = true
        }
        updateWindowTitle()
    }

    private func loadFile(_ url: URL) {
        // Flush any debounced text so the current file is saved before switching
        NotificationCenter.default.post(name: .flushEditorText, object: nil)
        viewModel.saveCursorPosition()
        do {
            let doc = try WrittenDocument.load(from: url)
            viewModel.document = doc
            viewModel.restoreCursorPosition(for: url)
        } catch {
            print("Failed to open file: \(error)")
        }
        let parentDir = url.deletingLastPathComponent()
        if viewModel.folderURL != parentDir {
            viewModel.folderURL = parentDir
            sidebarVM.loadFolder(parentDir)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible = false
            dismissSidebarModals()
        }
        editorNeedsFocus = true
        updateWindowTitle()
    }

    private func saveCurrentDocument() {
        if viewModel.document.fileURL != nil {
            viewModel.saveImmediately()
            return
        }
        saveModalState = .save
    }

    private func completeSave(url: URL, thenClose: Bool) {
        saveModalState = nil
        viewModel.assignFile(url: url)
        viewModel.saveImmediately()
        RecentItemsService.shared.add(url: url)
        let parentDir = url.deletingLastPathComponent()
        viewModel.folderURL = parentDir
        sidebarVM.loadFolder(parentDir)
        updateWindowTitle()

        if thenClose {
            viewModel.document = WrittenDocument()
            withAnimation(.easeInOut(duration: 0.3)) {
                windowMode = .welcome
                sidebarVisible = false
            }
            updateWindowTitle()
        } else {
            editorNeedsFocus = true
        }
    }

    private func openSystemSavePanel(thenClose: Bool) {
        let panel = NSSavePanel()
        panel.directoryURL = viewModel.folderURL
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Documents", isDirectory: true)
        let stem = viewModel.document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = stem + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                refocusAfterModal()
                return
            }
            completeSave(url: url, thenClose: thenClose)
        }
    }

    private func refocusAfterModal() {
        if windowMode == .editor {
            editorNeedsFocus = true
        }
    }

    private func openFileFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            RecentItemsService.shared.add(url: url)
            loadFile(url)
            let parentDir = url.deletingLastPathComponent()
            viewModel.folderURL = parentDir
            sidebarVM.loadFolder(parentDir)
            withAnimation(.easeInOut(duration: 0.3)) {
                windowMode = .editor
            }
        }
    }

    private func openRecentItem(_ item: RecentItem) {
        let url = URL(fileURLWithPath: item.url, isDirectory: item.isDirectory)
        guard FileManager.default.fileExists(atPath: item.url) else { return }
        RecentItemsService.shared.add(url: url)
        if item.isDirectory {
            viewModel.folderURL = url
            sidebarVM.loadFolder(url)
            withAnimation(.easeInOut(duration: 0.3)) {
                windowMode = .editor
                sidebarVisible = true
            }
            updateWindowTitle()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                windowMode = .editor
            }
            loadFile(url)
            let parentDir = url.deletingLastPathComponent()
            viewModel.folderURL = parentDir
            sidebarVM.loadFolder(parentDir)
        }
    }

    @ViewBuilder
    private var themeBackground: some View {
        let theme = settings.currentTheme
        let bgColor = Color(nsColor: theme.backgroundColor)

        if theme.isTranslucent && !isFullscreen {
            let pct = settings.backgroundOpacityPct
            let material: NSVisualEffectView.Material = theme.vibrancyMaterial ?? .hudWindow
            ZStack {
                VisualEffectBackground(material: material)
                bgColor.opacity(pct / 100.0)
            }
            .ignoresSafeArea()
        } else {
            bgColor.ignoresSafeArea()
        }
    }
}

// MARK: - Glass Sidebar

private struct GlassSidebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let folderSelected = Notification.Name("folderSelected")
    static let openFileInWindow = Notification.Name("openFileInWindow")
    static let newDocument = Notification.Name("newDocument")
    static let toggleSettings = Notification.Name("toggleSettings")
    static let focusEditor = Notification.Name("focusEditor")
    static let saveDocument = Notification.Name("saveDocument")
    static let settingsClosed = Notification.Name("settingsClosed")
    static let closeAction = Notification.Name("closeAction")
    static let updateWindowTitle = Notification.Name("updateWindowTitle")
    static let unfocusEditor = Notification.Name("unfocusEditor")
    static let quitApp = Notification.Name("quitApp")
    static let showOverlay = Notification.Name("showOverlay")
    static let flushEditorText = Notification.Name("flushEditorText")
    static let showWelcomeHelp = Notification.Name("showWelcomeHelp")
}
