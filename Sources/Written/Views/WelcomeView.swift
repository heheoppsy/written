import SwiftUI

struct WelcomeView: View {
    let isDarkTheme: Bool
    let themeTextColor: Color
    let onOpenFolder: () -> Void
    let onOpenFile: () -> Void
    let onNewText: () -> Void
    let onOpenRecent: (RecentItem) -> Void
    let hideFileExtensions: Bool
    var onShowHelp: (() -> Void)?
    var overlayActive: Bool = false
    @ObservedObject var recents: RecentItemsService
    @FocusState private var isFocused: Bool
    @State private var meows: [MeowBubble] = []
    @State private var logoBounce = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Logo + title
            VStack(spacing: 8) {
                ZStack {
                    if let logoURL = Bundle.main.url(forResource: isDarkTheme ? "written-ico-light" : "written-ico", withExtension: "png"),
                       let nsImage = NSImage(contentsOf: logoURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .opacity(0.85)
                            .rotationEffect(.degrees(logoBounce ? 4 : 0))
                            .animation(.easeInOut(duration: 0.08).repeatCount(5, autoreverses: true), value: logoBounce)
                            .onTapGesture { spawnMeow() }
                    }

                    ForEach(meows) { meow in
                        Text("meow :3")
                            .font(.system(size: 12, weight: .light, design: .serif))
                            .foregroundStyle(themeTextColor.opacity(meow.opacity))
                            .offset(x: meow.x, y: meow.y)
                            .animation(.easeOut(duration: 1.5), value: meow.opacity)
                    }
                }
                .frame(height: 100)

                Text("Written")
                    .font(.system(size: 28, weight: .ultraLight, design: .default))
                    .foregroundStyle(themeTextColor)
            }

            // Action buttons
            VStack(spacing: 8) {
                WelcomeButton(title: "Open File", hint: "O", textColor: themeTextColor, action: onOpenFile)
                WelcomeButton(title: "Open Folder", hint: "F", textColor: themeTextColor, action: onOpenFolder)
                WelcomeButton(title: "New Document", hint: "N", textColor: themeTextColor, action: onNewText)
            }

            // Recents
            if !recents.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(themeTextColor.opacity(0.35))
                        .tracking(0.5)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)

                    ForEach(Array(recents.items.enumerated()), id: \.element.id) { index, item in
                        RecentButton(item: item, index: index + 1, textColor: themeTextColor, hideExtension: hideFileExtensions && !item.isDirectory) {
                            onOpenRecent(item)
                        } onRemove: {
                            recents.remove(item)
                        }
                    }
                }
                .frame(width: 260)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if onShowHelp != nil {
                Button(action: { onShowHelp?() }) {
                    Text("?")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(themeTextColor.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: overlayActive) {
            if !overlayActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            }
        }
        .onKeyPress("?") {
            onShowHelp?()
            return onShowHelp != nil ? .handled : .ignored
        }
        .onKeyPress("n") {
            onNewText()
            return .handled
        }
        .onKeyPress("o") {
            onOpenFile()
            return .handled
        }
        .onKeyPress("f") {
            onOpenFolder()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard press.modifiers == .command else { return .ignored }
            switch press.characters {
            case "1": return openRecent(at: 0)
            case "2": return openRecent(at: 1)
            case "3": return openRecent(at: 2)
            case "4": return openRecent(at: 3)
            default: return .ignored
            }
        }
    }

    private func openRecent(at index: Int) -> KeyPress.Result {
        guard index < recents.items.count else { return .ignored }
        onOpenRecent(recents.items[index])
        return .handled
    }
}

// MARK: - Meow Easter Egg

private struct MeowBubble: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var opacity: Double = 0
}

extension WelcomeView {
    func spawnMeow() {
        // Bounce the logo
        logoBounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            logoBounce = false
        }

        let x = CGFloat.random(in: -40...40)
        let bubble = MeowBubble(x: x, y: 0)
        meows.append(bubble)
        let bubbleID = bubble.id

        // Fade in and float up
        withAnimation(.easeOut(duration: 1.5)) {
            if let i = meows.firstIndex(where: { $0.id == bubbleID }) {
                meows[i].opacity = 0.7
                meows[i].y = CGFloat.random(in: -50 ... -30)
                meows[i].x += CGFloat.random(in: -10...10)
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 1.0)) {
                if let i = meows.firstIndex(where: { $0.id == bubbleID }) {
                    meows[i].opacity = 0
                }
            }
        }

        // Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            meows.removeAll { $0.id == bubbleID }
        }
    }
}

// MARK: - Welcome Button

private struct WelcomeButton: View {
    let title: String
    let hint: String
    let textColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(textColor)
                Spacer()
                Text(hint)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .frame(width: 260, height: 36)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(textColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Button

private struct RecentButton: View {
    let item: RecentItem
    let index: Int
    let textColor: Color
    var hideExtension: Bool = false
    let action: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var displayName: String {
        if hideExtension {
            return (item.name as NSString).deletingPathExtension
        }
        return item.name
    }

    var body: some View {
        HStack(spacing: 0) {
            // Remove button — visible on hover
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(textColor.opacity(isHovered ? 0.4 : 0))
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: item.isDirectory ? "folder" : "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(textColor.opacity(0.5))
                        .frame(width: 16)

                    Text(displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\u{2318}\(index)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.25))
                }
                .padding(.trailing, 12)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onHover { isHovered = $0 }
    }
}
