import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var settings: AppSettings
    @StateObject private var wordCounter = DebouncedWordCounter()
    @StateObject private var vimState = VimModeState()
    var overlayActive: Bool = false
    var isFullscreen: Bool = false

    private let fadeHeight: CGFloat = 40

    var body: some View {
        ZStack(alignment: .trailing) {
            WritingTextView(
                viewModel: viewModel,
                settings: settings,
                overlayActive: overlayActive,
                wordCounter: wordCounter,
                vimState: vimState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: fadeHeight)

                    Rectangle().fill(.white)

                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: fadeHeight)
                }
            )

            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        if vimState.enabled {
                            Text(vimState.countBuffer.isEmpty ? vimState.mode.label : vimState.countBuffer)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(nsColor: settings.currentTheme.textColor).opacity(0.25))
                        }
                        if settings.showWordCount {
                            Text("\(wordCounter.wordCount) words")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color(nsColor: settings.currentTheme.textColor).opacity(0.2))
                        }
                    }
                }
                .padding(.top, isFullscreen ? 8 : -24)
                .padding(.trailing, 25)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Debounced Word Counter

@MainActor
final class DebouncedWordCounter: ObservableObject {
    @Published var wordCount: Int = 0
    var getText: (() -> String?)?
    private var pollTask: Task<Void, Never>?

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if let text = self.getText?() {
                    let count = await Task.detached {
                        Self.countWords(in: text)
                    }.value
                    guard !Task.isCancelled else { break }
                    if self.wordCount != count {
                        self.wordCount = count
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    nonisolated private static func countWords(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
