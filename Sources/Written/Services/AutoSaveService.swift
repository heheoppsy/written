import Foundation

@MainActor
final class AutoSaveService {
    private var saveTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(500)

    func textDidChange(text: String, fileURL: URL) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            do {
                try Self.withTrailingNewline(text).write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Auto-save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveImmediately(text: String, fileURL: URL) {
        saveTask?.cancel()
        try? Self.withTrailingNewline(text).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func withTrailingNewline(_ text: String) -> String {
        if text.isEmpty || text.hasSuffix("\n") { return text }
        return text + "\n"
    }

    deinit {
        saveTask?.cancel()
    }
}
