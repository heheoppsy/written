import SwiftUI

// MARK: - Tutorial Slide

enum TutorialSlide: Int, CaseIterable {
    case hello
    case welcome
    case workFolders
    case fullscreen
    case vim
    case ready

    var isFirst: Bool { self == .hello }
    var isLast: Bool { self == .ready }
}

// MARK: - Tutorial View

struct TutorialView: View {
    let textColor: Color
    /// Called with `true` when the user completes the tutorial, `false` when skipped.
    let onDismiss: (Bool) -> Void

    @State private var currentSlide: TutorialSlide = .hello
    @State private var appInApplications = false
    @State private var cliInstalled = false
    @State private var moveError: String?
    @State private var cliError: String?
    @State private var isFullscreen = false
    @FocusState private var isFocused: Bool

    private static let githubURL = URL(string: "https://github.com/heheoppsy/written")!

    var body: some View {
        ZStack {
            // Backdrop tap-to-dismiss (slides 1-4)
            if !currentSlide.isFirst {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture { skipTutorial() }
            }

            // Glass panel
            panelContent
                .contentShape(Rectangle())
                .onTapGesture {} // Block click-through
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            checkAppLocation()
            checkCLI()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
    }

    // MARK: - Panel

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Skip button — always reserve space, invisible on slide 0
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Button(action: {
                        if currentSlide.isLast {
                            onDismiss(true)
                        } else {
                            skipTutorial()
                        }
                    }) {
                        Text(currentSlide.isLast ? "Goodbye!" : "I Don't Care")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    Text("esc")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.2))
                }
                .opacity(currentSlide.isFirst ? 0 : 1)
                .allowsHitTesting(!currentSlide.isFirst)
            }
            .padding(.bottom, 8)

            // Slide content
            slideContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 20)

            // Navigation bar
            navigationBar
        }
        .padding(24)
        .frame(width: 460, height: 360)
        .modifier(TutorialGlassModifier())
    }

    // MARK: - Slide Content

    @ViewBuilder
    private var slideContent: some View {
        switch currentSlide {
        case .hello: helloSlide
        case .welcome: welcomeSlide
        case .workFolders: workFoldersSlide
        case .fullscreen: fullscreenSlide
        case .vim: vimSlide
        case .ready: readySlide
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button(action: { goBack() }) {
                Text("← h")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(textColor.opacity(currentSlide.isFirst ? 0 : 0.25))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!currentSlide.isFirst)

            Spacer()

            HStack(spacing: 6) {
                ForEach(TutorialSlide.allCases, id: \.rawValue) { slide in
                    Circle()
                        .fill(textColor.opacity(slide == currentSlide ? 0.7 : 0.2))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            Button(action: { goForward() }) {
                Text("l →")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Slide 0: Hello

    private var helloSlide: some View {
        VStack(spacing: 16) {
            Text("Hello!")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(textColor)

            Text("Before we get started, let's make sure things are set up.")
                .font(.system(size: 14))
                .foregroundStyle(textColor.opacity(0.6))
                .lineSpacing(4)

            VStack(spacing: 10) {
                // App location check
                setupRow(
                    passed: appInApplications,
                    label: "App in Applications",
                    hint: "\u{2318}1",
                    actionLabel: moveError ?? "Move to Applications",
                    showAction: !appInApplications,
                    isError: moveError != nil,
                    action: moveToApplications
                )

                // CLI check — requires app in Applications first
                setupRow(
                    passed: cliInstalled,
                    label: "CLI installed",
                    hint: "\u{2318}2",
                    actionLabel: !appInApplications ? "Move to Applications first" : (cliError ?? "Install CLI"),
                    showAction: !cliInstalled,
                    isError: cliError != nil || !appInApplications,
                    action: installCLI
                )
            }
            .padding(.top, 4)

            cliBlurb
        }
    }

    private func setupRow(passed: Bool, label: String, hint: String, actionLabel: String, showAction: Bool, isError: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(passed ? .green : .red.opacity(0.6))

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(textColor.opacity(0.8))

            Spacer()

            if showAction {
                if isError {
                    Text(actionLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(textColor.opacity(0.35))
                } else {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(textColor.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(hint)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor.opacity(0.2))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(textColor.opacity(0.04))
        )
    }

    // MARK: - Slide 1: Welcome

    private var welcomeSlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Written")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(textColor)

            VStack(alignment: .leading, spacing: 12) {
                Text("(you know, like Kitten)")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(textColor.opacity(0.4))

                Text("A keyboard-focused, minimal plaintext editor. Almost everything is accessible with arrow keys, vim bindings, or other shortcuts.")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Slide 2: Work Folders

    private var workFoldersSlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Work Folders")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(textColor)

            VStack(alignment: .leading, spacing: 12) {
                Text("Open a folder to get a sidebar file list. Save a file and its parent becomes your work folder.")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)

                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow("\u{2318}B", "Toggle sidebar")
                    shortcutRow("j / k", "Navigate files")
                    shortcutRow("Enter", "Open file")
                    shortcutRow("n", "New file")
                    shortcutRow("/", "Filter files")
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Slide 3: Fullscreen

    private var fullscreenSlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Visuals")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(textColor)

            VStack(alignment: .leading, spacing: 12) {
                Text("In fullscreen, translucent themes switch to their opaque background for a distraction-free writing experience.")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)

                Text("Open settings anytime with \u{2318} + , to change themes, fonts, and layout.")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)

                shortcutRow("fn F", "Toggle fullscreen")
                    .padding(.top, 4)

                Button(action: {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11))
                        Text(isFullscreen ? "Exit Fullscreen" : "Try Fullscreen")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(textColor.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(textColor.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Slide 4: Vim Mode

    private var vimSlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vim Mode")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(textColor)

            VStack(alignment: .leading, spacing: 12) {
                Text("Enable lightweight vim bindings in settings. Normal mode, visual mode, operators (d/y/p), word motions, and counts — all the essentials.")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)

                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow("Esc / jj", "Normal mode")
                    shortcutRow("i / a", "Insert mode")
                    shortcutRow("v / V", "Visual mode")
                    shortcutRow("h/j/k/l", "Movement")
                }
                .padding(.top, 4)

                Text("Enable in Settings \u{2192} General \u{2192} Vim")
                    .font(.system(size: 12))
                    .foregroundStyle(textColor.opacity(0.4))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Slide 5: You're Ready

    private var readySlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You're Ready")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(textColor)

            VStack(alignment: .leading, spacing: 12) {
                Text("A few more things to remember:")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)

                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow("?", "Help (welcome & sidebar)")
                    shortcutRow("\u{2318},", "Settings")
                }
                .padding(.top, 2)

                Text("Please submit any bugs you wish to have fixed, features added, etc on Github. I hope this little app helps you :)")
                    .font(.system(size: 14))
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineSpacing(4)
                    .padding(.top, 4)

                Button(action: {
                    NSWorkspace.shared.open(Self.githubURL)
                }) {
                    HStack(spacing: 4) {
                        Text("github.com/heheoppsy/written")
                            .font(.system(size: 12))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(textColor.opacity(0.4))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
    }

    // MARK: - Helpers

    private var cliBlurb: some View {
        let plain: (String) -> Text = { str in
            Text(str)
                .font(.system(size: 12))
                .foregroundStyle(textColor.opacity(0.4))
        }
        let code: (String) -> Text = { str in
            Text(str)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor.opacity(0.5))
        }
        return (plain("The CLI lets you open files and folders from your terminal — type ")
            + code("written")
            + plain(" to open the current folder, or ")
            + code("written note.txt")
            + plain(" to open or create a file."))
            .lineSpacing(3)
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: 0) {
            Text(key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(textColor.opacity(0.5))
        }
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .rightArrow, "l":
            goForward()
            return .handled
        case .return:
            goForward()
            return .handled
        case .leftArrow, "h":
            goBack()
            return .handled
        case .escape:
            if currentSlide.isFirst { return .handled }
            if currentSlide.isLast {
                onDismiss(true)
            } else {
                skipTutorial()
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
            default:
                return .ignored
            }
        }
    }

    // MARK: - Navigation

    private func goForward() {
        if currentSlide.isLast {
            onDismiss(true)
            return
        }
        if let next = TutorialSlide(rawValue: currentSlide.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentSlide = next
            }
        }
    }

    private func goBack() {
        guard !currentSlide.isFirst else { return }
        if let prev = TutorialSlide(rawValue: currentSlide.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentSlide = prev
            }
        }
    }

    private func skipTutorial() {
        onDismiss(false)
    }

    // MARK: - System Checks

    private func checkAppLocation() {
        appInApplications = Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    private func checkCLI() {
        cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/written")
    }

    private func moveToApplications() {
        let currentPath = Bundle.main.bundlePath
        let appName = (currentPath as NSString).lastPathComponent
        let destURL = URL(fileURLWithPath: "/Applications/\(appName)")
        let sourceURL = URL(fileURLWithPath: currentPath)

        moveError = nil

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) {
                // Atomic replace — old copy goes to trash, not deleted
                _ = try fm.replaceItemAt(destURL, withItemAt: sourceURL)
            } else {
                try fm.moveItem(at: sourceURL, to: destURL)
            }
            relaunchFromApplications(appPath: destURL.path, show: "tutorial")
        } catch {
            moveError = "Drag Written.app to Applications manually"
        }
    }

    private func relaunchFromApplications(appPath: String, show: String) {
        // Delay relaunch so the current process can exit cleanly.
        // Uses /bin/sleep + open as separate processes to avoid shell interpolation.
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

        // Validate the source is inside our app bundle
        guard cliSource.hasPrefix(Bundle.main.bundlePath + "/") else {
            cliError = "CLI binary path outside app bundle"
            return
        }

        guard FileManager.default.fileExists(atPath: cliSource) else {
            cliError = "WrittenCLI binary not found"
            return
        }

        // Write AppleScript to a temp file to avoid interpolating paths into
        // inline -e strings. AppleScript's `quoted form of` handles shell escaping.
        let tempDir = FileManager.default.temporaryDirectory
        let osaURL = tempDir.appendingPathComponent("written-install-cli.applescript")

        // Escape for AppleScript string literal: \ → \\, " → \"
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
}

// MARK: - Glass Modifier

private struct TutorialGlassModifier: ViewModifier {
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
