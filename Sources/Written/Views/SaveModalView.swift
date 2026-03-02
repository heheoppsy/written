import SwiftUI

// MARK: - Save Modal State

enum SaveModalState: Equatable {
    case save           // Cmd+S on unsaved doc
    case closeConfirm   // Cmd+W on unsaved doc — s/d/Esc
    case closeAndSave   // User pressed 's' from closeConfirm
}

// MARK: - Close Confirmation View

struct CloseConfirmationView: View {
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onCancel: () -> Void
    @FocusState private var panelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save before closing?")
                .font(.system(size: 16, weight: .medium))

            HStack(spacing: 12) {
                modalButton("s", label: "save", action: onSave)
                modalButton("d", label: "discard", action: onDiscard)
                modalButton("Esc", label: "cancel", action: onCancel)
            }
        }
        .padding(24)
        .frame(width: 360)
        .modifier(SaveModalGlassModifier())
        .focusable()
        .focusEffectDisabled()
        .focused($panelFocused)
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case "s":
                onSave()
                return .handled
            case "d":
                onDiscard()
                return .handled
            case .escape:
                onCancel()
                return .handled
            default:
                return .handled // Swallow other keys
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .unfocusEditor, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                panelFocused = true
            }
        }
    }
}

// MARK: - Save Modal View

struct SaveModalView: View {
    let initialFilename: String
    let directoryURL: URL
    let onSave: (URL) -> Void
    let onCancel: () -> Void
    let onSystemSave: () -> Void

    @State private var filename: String
    @State private var directoryPath: String
    @State private var errorMessage: String?
    @FocusState private var focusedField: SaveField?

    private enum SaveField: Hashable {
        case filename
        case directory
    }

    init(initialFilename: String, directoryURL: URL, onSave: @escaping (URL) -> Void, onCancel: @escaping () -> Void, onSystemSave: @escaping () -> Void) {
        self.initialFilename = initialFilename
        self.directoryURL = directoryURL
        self.onSave = onSave
        self.onCancel = onCancel
        self.onSystemSave = onSystemSave
        self._filename = State(initialValue: initialFilename)
        self._directoryPath = State(initialValue: Self.tildeAbbreviated(directoryURL.path))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save")
                .font(.system(size: 16, weight: .medium))

            // Filename field
            HStack(spacing: 0) {
                TextField("Filename", text: $filename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .focused($focusedField, equals: .filename)
                    .onSubmit { attemptSave() }

                Text(".txt")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        focusedField == .filename ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: focusedField == .filename ? 1.5 : 1
                    )
            )

            // Directory field
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                TextField("Directory", text: $directoryPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($focusedField, equals: .directory)
                    .onSubmit { attemptSave() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        focusedField == .directory ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: focusedField == .directory ? 1.5 : 0.5
                    )
            )

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }

            // Actions
            HStack(spacing: 12) {
                modalButton("Enter", label: "save", action: attemptSave)
                modalButton("Esc", label: "cancel", action: onCancel)
                modalButton("\u{21E7}\u{2318}S", label: "system", action: onSystemSave)
            }
        }
        .padding(24)
        .frame(width: 360)
        .modifier(SaveModalGlassModifier())
        .onKeyPress(keys: [KeyEquivalent("s"), KeyEquivalent("S")]) { press in
            if press.modifiers.contains(.command) && press.modifiers.contains(.shift) {
                onSystemSave()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            NotificationCenter.default.post(name: .unfocusEditor, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedField = .filename
            }
        }
        .onChange(of: focusedField) {
            // Keep Tab trapped inside the modal — if focus escapes both fields, return to filename
            if focusedField == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    focusedField = .filename
                }
            }
        }
        .onExitCommand { onCancel() }
    }

    private func attemptSave() {
        let trimmed = filename.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Filename cannot be empty"
            return
        }
        guard !trimmed.contains("/"), !trimmed.contains("..") else {
            errorMessage = "Invalid filename"
            return
        }

        let expandedPath = (directoryPath as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            errorMessage = "Directory not found"
            return
        }

        let fileURL = dirURL.appendingPathComponent(trimmed + ".txt")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            errorMessage = "File already exists"
            return
        }

        errorMessage = nil
        onSave(fileURL)
    }

    private static func tildeAbbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - New File Name View

struct NewFileNameView: View {
    let directoryURL: URL
    let onCreate: (URL) -> Void
    let onCancel: () -> Void

    @State private var filename: String = ""
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New File")
                .font(.system(size: 16, weight: .medium))

            HStack(spacing: 0) {
                TextField("Filename", text: $filename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .focused($fieldFocused)
                    .onSubmit { attemptCreate() }

                Text(".txt")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        fieldFocused ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: fieldFocused ? 1.5 : 1
                    )
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }

            HStack(spacing: 12) {
                modalButton("Enter", label: "create", action: attemptCreate)
                modalButton("Esc", label: "cancel", action: onCancel)
            }
        }
        .padding(24)
        .frame(width: 360)
        .modifier(SaveModalGlassModifier())
        .onAppear {
            NotificationCenter.default.post(name: .unfocusEditor, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                fieldFocused = true
            }
        }
        .onExitCommand { onCancel() }
    }

    private func attemptCreate() {
        let trimmed = filename.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Filename cannot be empty"
            return
        }
        guard !trimmed.contains("/"), !trimmed.contains("..") else {
            errorMessage = "Invalid filename"
            return
        }

        let fileURL = directoryURL.appendingPathComponent(trimmed + ".txt")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            errorMessage = "File already exists"
            return
        }

        errorMessage = nil
        onCreate(fileURL)
    }
}

// MARK: - Modal Button

@MainActor
func modalButton(_ key: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.7))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    .buttonStyle(.plain)
}

// MARK: - Glass Modifier

struct SaveModalGlassModifier: ViewModifier {
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
