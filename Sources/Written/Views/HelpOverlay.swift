import SwiftUI

// MARK: - Sidebar Help

struct SidebarHelpView: View {
    let theme: Theme
    let onDismiss: () -> Void

    private var textColor: Color { Color(nsColor: theme.sidebarTextColor) }

    private let bindings: [(key: String, label: String)] = [
        ("j / k", "Navigate"),
        ("Enter", "Open"),
        ("r", "Rename"),
        ("d", "Delete"),
        ("s", "Sort"),
        ("/", "Filter"),
        ("n", "New file"),
        ("\u{2318}1-9", "Jump to file"),
        ("?", "Help"),
        ("Esc", "Close sidebar"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("KEYBOARD")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(textColor.opacity(0.5))
                    .tracking(0.5)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(textColor.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            ForEach(bindings, id: \.key) { binding in
                HStack(spacing: 0) {
                    Text(binding.key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor.opacity(0.7))
                        .frame(width: 60, alignment: .leading)
                    Text(binding.label)
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.5))
                }
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: theme.sidebarTextColor).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: theme.sidebarTextColor).opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Welcome Help

private enum WelcomeHelpTab: String, CaseIterable {
    case about = "About"
    case controls = "Controls"
    case licenses = "Licenses"
}

struct WelcomeHelpView: View {
    let textColor: Color
    let onDismiss: () -> Void
    var onShowTutorial: (() -> Void)?
    @State private var selectedTab: WelcomeHelpTab = .about
    @State private var appInApplications = false
    @State private var cliInstalled = false
    @State private var cliError: String?
    @FocusState private var panelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(WelcomeHelpTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .medium : .regular))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background {
                                    if selectedTab == tab {
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

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                switch selectedTab {
                case .about:
                    aboutTab
                case .controls:
                    controlsTab
                case .licenses:
                    licensesTab
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 400)
        .modifier(WelcomeHelpGlassModifier())
        .focusable()
        .focusEffectDisabled()
        .focused($panelFocused)
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .escape:
                onDismiss()
                return .handled
            case .tab:
                let allTabs = WelcomeHelpTab.allCases
                guard let idx = allTabs.firstIndex(of: selectedTab) else { return .ignored }
                let next: Int
                if press.modifiers.contains(.shift) {
                    next = (idx - 1 + allTabs.count) % allTabs.count
                } else {
                    next = (idx + 1) % allTabs.count
                }
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = allTabs[next]
                }
                return .handled
            default:
                guard press.modifiers == .command else { return .ignored }
                switch press.characters {
                case "1":
                    if !appInApplications { moveToApplications() }
                    return .handled
                case "2":
                    if !cliInstalled && appInApplications { installCLI() }
                    return .handled
                case "t":
                    onShowTutorial?()
                    return onShowTutorial != nil ? .handled : .ignored
                case "g":
                    NSWorkspace.shared.open(Self.githubURL)
                    return .handled
                default:
                    return .ignored
                }
            }
        }
        .onAppear {
            appInApplications = Bundle.main.bundlePath.hasPrefix("/Applications")
            cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/written")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                panelFocused = true
            }
        }
    }

    // MARK: - About

    private static let githubURL = URL(string: "https://github.com/heheoppsy/written")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.3"
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Written")
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(.primary)

            Text(appVersion)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text("A distraction-free writing app for macOS.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Status badges
            VStack(alignment: .leading, spacing: 6) {
                statusRow(
                    passed: appInApplications,
                    label: "App in Applications",
                    hint: "\u{2318}1",
                    actionLabel: appInApplications ? nil : "Move",
                    action: moveToApplications
                )

                statusRow(
                    passed: cliInstalled,
                    label: "CLI installed",
                    hint: "\u{2318}2",
                    actionLabel: cliInstalled ? nil : (!appInApplications ? nil : (cliError != nil ? nil : "Install")),
                    action: installCLI,
                    disabled: !appInApplications && !cliInstalled
                )

                if !appInApplications && !cliInstalled {
                    Text("Move to Applications first")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 22)
                } else if let error = cliError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 22)
                }
            }
            .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.open(Self.githubURL)
                }) {
                    HStack(spacing: 4) {
                        Text("GitHub")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)

                Text("\u{2318}G")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)

                if onShowTutorial != nil {
                    Spacer().frame(width: 4)

                    Button(action: { onShowTutorial?() }) {
                        HStack(spacing: 4) {
                            Text("Show Tutorial")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Text("\u{2318}T")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Helpers

    private func statusRow(passed: Bool, label: String, hint: String, actionLabel: String?, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12))
                .foregroundColor(passed ? .green : (disabled ? .secondary.opacity(0.3) : .red.opacity(0.6)))

            Text(label)
                .font(.system(size: 12))
                .opacity(disabled ? 0.3 : 1)
                .foregroundStyle(.secondary)

            Spacer()

            if let actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }

            Text(hint)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    private func moveToApplications() {
        let currentPath = Bundle.main.bundlePath
        let appName = (currentPath as NSString).lastPathComponent
        let destURL = URL(fileURLWithPath: "/Applications/\(appName)")
        let sourceURL = URL(fileURLWithPath: currentPath)

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) {
                _ = try fm.replaceItemAt(destURL, withItemAt: sourceURL)
            } else {
                try fm.moveItem(at: sourceURL, to: destURL)
            }
            relaunchFromApplications(appPath: destURL.path, show: "help")
        } catch {
            // Silently fail — user can drag manually
        }
    }

    private func relaunchFromApplications(appPath: String, show: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "sleep 1 && exec \"$0\" \"$@\"",
                             "/usr/bin/open", appPath, "--args", "--show", show]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func installCLI() {
        cliError = nil

        guard let execURL = Bundle.main.executableURL else {
            cliError = "Could not locate app executable"
            return
        }
        let cliSource = execURL.deletingLastPathComponent().appendingPathComponent("WrittenCLI").path

        guard cliSource.hasPrefix(Bundle.main.bundlePath + "/") else {
            cliError = "CLI binary path outside app bundle"
            return
        }

        guard FileManager.default.fileExists(atPath: cliSource) else {
            cliError = "WrittenCLI binary not found"
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let osaURL = tempDir.appendingPathComponent("written-install-cli.applescript")

        let asEscaped = cliSource
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osaScript = """
        set src to "\(asEscaped)"
        do shell script "mkdir -p /usr/local/bin && cp " & quoted form of src & " /usr/local/bin/written && chmod +x /usr/local/bin/written" with administrator privileges
        """

        do {
            try osaScript.write(to: osaURL, atomically: true, encoding: .utf8)
        } catch {
            cliError = "Failed to prepare installer"
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [osaURL.path]

            do {
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: osaURL)

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        cliInstalled = true
                    } else {
                        cliError = "Installation cancelled"
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: osaURL)
                DispatchQueue.main.async {
                    cliError = "Failed to run installer"
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlSection("Welcome", [
                ("n", "New document"),
                ("o", "Open file"),
                ("f", "Open folder"),
                ("\u{2318}1-4", "Open recent"),
                ("?", "Help"),
            ])

            controlSection("Editor", [
                ("\u{2318}S", "Save"),
                ("\u{2318}B", "Sidebar"),
                ("\u{2318},", "Settings"),
                ("\u{2318}W", "Close"),
                ("\u{2318}\u{21E7}C", "Spellcheck"),
                ("\u{2318}F", "Find"),
            ])

            controlSection("Settings", [
                ("h/j/k/l", "Navigate"),
                ("Enter", "Activate"),
                ("Tab", "Next tab"),
                ("Esc", "Close"),
            ])
        }
    }

    private func controlSection(_ title: String, _ items: [(key: String, label: String)]) -> some View {
        let paired = makePairs(items)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.7))
                .tracking(0.5)
                .padding(.bottom, 2)

            ForEach(0..<paired.count, id: \.self) { rowIdx in
                controlRow(paired[rowIdx])
            }
        }
    }

    private func makePairs(_ items: [(key: String, label: String)]) -> [[(key: String, label: String)]] {
        stride(from: 0, to: items.count, by: 2).map { i in
            if i + 1 < items.count {
                return [items[i], items[i + 1]]
            }
            return [items[i]]
        }
    }

    private func controlRow(_ pair: [(key: String, label: String)]) -> some View {
        HStack(spacing: 0) {
            controlItem(pair[0])
            if pair.count > 1 {
                controlItem(pair[1])
            } else {
                Spacer().frame(maxWidth: .infinity)
            }
        }
    }

    private func controlItem(_ item: (key: String, label: String)) -> some View {
        HStack(spacing: 4) {
            Text(item.key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 56, alignment: .leading)
            Text(item.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Licenses

    private var licensesTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            licenseEntry(
                "MIT License",
                "Written is released under the MIT License."
            )

            licenseEntry(
                "SIL Open Font License 1.1",
                "Bundled fonts are provided under the SIL Open Font License 1.1. This applies to all included typefaces sourced from Google Fonts."
            )

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func licenseEntry(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.7))
                .tracking(0.5)

            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }
}

// MARK: - Glass Modifier (matches settings panel style)

private struct WelcomeHelpGlassModifier: ViewModifier {
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
