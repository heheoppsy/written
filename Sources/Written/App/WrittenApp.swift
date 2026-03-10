import SwiftUI

@main
struct WrittenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Invisible scene just to host SwiftUI commands (for liquid glass menus).
        // The actual window is managed by AppDelegate + WindowFactory.
        WindowGroup(id: "unused") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
        .commands {
            WrittenCommands()
        }
    }
}

struct WrittenCommands: Commands {
    @ObservedObject private var settings = AppSettings.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                NotificationCenter.default.post(name: .newDocument, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    if url.hasDirectoryPath {
                        NotificationCenter.default.post(name: .folderSelected, object: url)
                    } else {
                        NotificationCenter.default.post(name: .openFileInWindow, object: url)
                    }
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Close") {
                NotificationCenter.default.post(name: .closeAction, object: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                NotificationCenter.default.post(name: .saveDocument, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .toggleSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit Written") {
                NotificationCenter.default.post(name: .quitApp, object: nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find...") {
                let item = NSMenuItem()
                item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(settings.spellCheckEnabled ? "Spellcheck (On)" : "Spellcheck") {
                settings.spellCheckEnabled.toggle()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            Button("Column Mode") {
                settings.layoutMode = .column
            }
            .keyboardShortcut("u", modifiers: .command)

            Button("Full Width Mode") {
                settings.layoutMode = .fullWidth
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button(settings.typewriterScrolling ? "Typewriter Scrolling (On)" : "Typewriter Scrolling") {
                settings.typewriterScrolling.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button(settings.showWordCount ? "Word Count (On)" : "Word Count") {
                settings.showWordCount.toggle()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Divider()

            Menu("Theme") {
                ForEach(Theme.presets) { theme in
                    Button {
                        settings.currentThemeID = theme.id
                    } label: {
                        if settings.currentThemeID == theme.id {
                            Label(theme.name, systemImage: "checkmark")
                        } else {
                            Text(theme.name)
                        }
                    }
                }
            }
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Written") {
                NotificationCenter.default.post(name: .showWelcomeHelp, object: nil)
            }
        }

        CommandGroup(replacing: .help) {
            Button("Written Help") {
                NotificationCenter.default.post(name: .showWelcomeHelp, object: nil)
            }
        }
    }
}
