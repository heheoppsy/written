import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    let theme: Theme
    let selectedIndex: Int?
    let hideExtensions: Bool
    let renamingURL: URL?
    let deletingURL: URL?
    let showHelp: Bool
    let onSelectFile: (URL) -> Void
    let onNewFile: () -> Void
    let onRename: (URL) -> Void
    let onDelete: (URL) -> Void
    let onRenameCommit: (URL, String) -> Void
    let onRenameCancel: () -> Void
    let onDeleteConfirm: () -> Void
    let onDeleteCancel: () -> Void
    let onToggleSort: () -> Void
    let onToggleHelp: () -> Void
    var onClose: (() -> Void)?
    var onFilterDismiss: (() -> Void)?
    @Binding var filterText: String
    @FocusState.Binding var filterFocused: Bool

    private var hiddenSummary: String {
        var parts: [String] = []
        if viewModel.hiddenDirCount > 0 {
            parts.append("\(viewModel.hiddenDirCount) dir\(viewModel.hiddenDirCount == 1 ? "" : "s")")
        }
        if viewModel.hiddenFileCount > 0 {
            parts.append("\(viewModel.hiddenFileCount) file\(viewModel.hiddenFileCount == 1 ? "" : "s")")
        }
        return "Not shown: " + parts.joined(separator: ", ")
    }

    private var hasFolder: Bool { viewModel.folderURL != nil }

    private var fileShortcuts: [URL: Int] {
        var map: [URL: Int] = [:]
        for (i, node) in filteredNodes.prefix(9).enumerated() {
            map[node.url] = i + 1
        }
        return map
    }

    private var textColor: Color { Color(nsColor: theme.sidebarTextColor) }

    private var filteredNodes: [FileNode] {
        let nodes = viewModel.flattenedVisibleNodes
        guard !filterText.isEmpty else { return nodes }
        let query = filterText.lowercased()
        return nodes.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Close button
                if let onClose {
                    HStack {
                        Spacer()
                        SidebarCloseButton(textColor: textColor, action: onClose)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Header with sort indicator and help button
                HStack(spacing: 6) {
                    Text(viewModel.folderURL?.lastPathComponent ?? "Files")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textColor.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .lineLimit(1)

                    Spacer()

                    if hasFolder {
                        Button(action: onToggleSort) {
                            Text(viewModel.sortMode == .alphabetical ? "A\u{2013}Z" : "Recent")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(textColor.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onToggleHelp) {
                        Text("?")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, onClose != nil ? 8 : 40)
                .padding(.bottom, 8)

                // Filter bar
                if hasFolder {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 10))
                            .foregroundStyle(textColor.opacity(0.35))

                        TextField("Filter (/)", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(textColor)
                            .focused($filterFocused)
                            .onSubmit {
                                filterFocused = false
                                onFilterDismiss?()
                            }
                            .onExitCommand {
                                filterText = ""
                                filterFocused = false
                                onFilterDismiss?()
                            }

                        if !filterText.isEmpty {
                            Button(action: {
                                filterText = ""
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(textColor.opacity(0.35))
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(textColor.opacity(0.12), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                if hasFolder {
                    // File list
                    let shortcuts = fileShortcuts
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                let flatNodes = filteredNodes
                                ForEach(Array(flatNodes.enumerated()), id: \.element.id) { index, node in
                                    if renamingURL == node.url {
                                        InlineRenameRow(
                                            node: node,
                                            theme: theme,
                                            hideExtension: hideExtensions,
                                            onCommit: { newName in onRenameCommit(node.url, newName) },
                                            onCancel: onRenameCancel
                                        )
                                        .id(node.id)
                                    } else {
                                        FileNodeRow(
                                            node: node,
                                            theme: theme,
                                            isSelected: selectedIndex == index,
                                            hideExtension: hideExtensions,
                                            shortcut: shortcuts[node.url],
                                            onTap: { onSelectFile(node.url) },
                                            onRename: { onRename(node.url) },
                                            onDelete: { onDelete(node.url) }
                                        )
                                        .id(node.id)
                                    }
                                }

                                if viewModel.hiddenDirCount > 0 || viewModel.hiddenFileCount > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.slash")
                                            .font(.system(size: 9))
                                        Text(hiddenSummary)
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(textColor.opacity(0.35))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 8)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: selectedIndex) {
                            guard let idx = selectedIndex else { return }
                            let nodes = viewModel.flattenedVisibleNodes
                            guard idx >= 0, idx < nodes.count else { return }
                            withAnimation {
                                proxy.scrollTo(nodes[idx].id, anchor: .center)
                            }
                        }
                    }
                } else {
                    // Empty state hint
                    VStack(spacing: 8) {
                        Spacer()
                        Text("Save or open a file\nto browse its folder")
                            .font(.system(size: 12))
                            .foregroundColor(textColor.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                // New file button
                if hasFolder {
                    HStack(spacing: 12) {
                        Button(action: { onNewFile() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("New .txt")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("n")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .opacity(0.5)
                            }
                            .foregroundColor(textColor.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(maxHeight: .infinity)
            .blur(radius: (showHelp || deletingURL != nil) ? 4 : 0)
            .allowsHitTesting(!showHelp && deletingURL == nil)

            // Delete confirmation overlay
            if let url = deletingURL {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                DeleteConfirmationView(
                    fileName: url.deletingPathExtension().lastPathComponent,
                    theme: theme,
                    onConfirm: onDeleteConfirm,
                    onCancel: onDeleteCancel
                )
            }

            // Help overlay
            if showHelp {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        SidebarHelpView(theme: theme, onDismiss: onToggleHelp)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Close Button

private struct SidebarCloseButton: View {
    let textColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isHovered ? textColor.opacity(0.8) : textColor.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(textColor.opacity(isHovered ? 0.15 : 0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - File Node Row

private struct FileNodeRow: View {
    let node: FileNode
    let theme: Theme
    let isSelected: Bool
    var hideExtension: Bool = false
    var shortcut: Int?
    let onTap: () -> Void
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    private var displayName: String {
        if hideExtension {
            return (node.name as NSString).deletingPathExtension
        }
        return node.name
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: theme.sidebarTextColor))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let shortcut {
                    Text("\u{2318}\(shortcut)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: theme.sidebarTextColor).opacity(0.25))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: theme.sidebarTextColor).opacity(isSelected ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .if(onRename != nil && onDelete != nil) { view in
            view.contextMenu {
                Button("Rename") { onRename?() }
                Button("Delete") { onDelete?() }
            }
        }
    }
}

// MARK: - Inline Rename Row

private struct InlineRenameRow: View {
    let node: FileNode
    let theme: Theme
    let hideExtension: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    private var stem: String {
        (node.name as NSString).deletingPathExtension
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $editText, onCommit: {
                let trimmed = editText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { onCancel(); return }
                onCommit(trimmed + ".txt")
            })
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(Color(nsColor: theme.sidebarTextColor))
            .focused($isFocused)
            .onExitCommand { onCancel() }

            Text(".txt")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: theme.sidebarTextColor).opacity(0.3))

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: theme.sidebarTextColor).opacity(0.12))
        )
        .onAppear {
            editText = stem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}

// MARK: - Delete Confirmation

private struct DeleteConfirmationView: View {
    let fileName: String
    let theme: Theme
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var textColor: Color { Color(nsColor: theme.sidebarTextColor) }

    var body: some View {
        VStack(spacing: 10) {
            Text("Delete \"\(fileName)\"?")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            HStack(spacing: 10) {
                sidebarModalButton("y", label: "confirm", color: textColor, action: onConfirm)
                sidebarModalButton("n", label: "cancel", color: textColor, action: onCancel)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: theme.sidebarTextColor).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: theme.sidebarTextColor).opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private func sidebarModalButton(_ key: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundColor(color.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(color.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
