import AppKit

@MainActor
final class FileWatcher {
    private var observer: Any?

    /// Called when the file on disk is newer than our last known version.
    var onExternalChange: ((_ fileURL: URL, _ diskText: String, _ diskModDate: Date) -> Void)?

    private var watchedFileURL: URL?
    private var knownModDate: Date?

    func watch(fileURL: URL?, lastModDate: Date?) {
        watchedFileURL = fileURL
        knownModDate = lastModDate
    }

    func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForExternalChanges()
            }
        }
    }

    func checkForExternalChanges() {
        guard let fileURL = watchedFileURL, let knownDate = knownModDate else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let diskModDate = attrs[.modificationDate] as? Date
        else { return }

        if diskModDate > knownDate {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            onExternalChange?(fileURL, text, diskModDate)
        }
    }

    func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
