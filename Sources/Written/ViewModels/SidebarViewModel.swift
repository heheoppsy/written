import Foundation

struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

enum SortMode: String, CaseIterable {
    case alphabetical
    case byDate
}

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var folderURL: URL?
    @Published var hiddenFileCount: Int = 0
    @Published var hiddenDirCount: Int = 0
    @Published var sortMode: SortMode = .alphabetical

    private let supportedExtensions: Set<String> = ["txt"]
    private let maxFiles = 500

    func clear() {
        rootNodes = []
        folderURL = nil
        hiddenFileCount = 0
        hiddenDirCount = 0
    }

    func loadFolder(_ url: URL) {
        folderURL = url
        hiddenFileCount = 0
        hiddenDirCount = 0
        rootNodes = scanFolder(url)
    }

    func refresh() {
        guard let url = folderURL else { return }
        loadFolder(url)
    }

    /// Flat list of all files (used for navigation and Cmd+1-9 shortcuts).
    var flattenedVisibleNodes: [FileNode] { rootNodes }

    /// Alias kept for clarity at call sites.
    var fileOnlyNodes: [FileNode] { rootNodes }

    func toggleSortMode() {
        sortMode = sortMode == .alphabetical ? .byDate : .alphabetical
        refresh()
    }

    // MARK: - File Operations

    func renameFile(at url: URL, to newName: String) -> URL? {
        guard !newName.contains("/"), !newName.contains("..") else { return nil }
        let fm = FileManager.default
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fm.fileExists(atPath: newURL.path) else { return nil }
        do {
            try fm.moveItem(at: url, to: newURL)
            refresh()
            return newURL
        } catch {
            print("Rename failed: \(error)")
            return nil
        }
    }

    func deleteFile(at url: URL) {
        let fm = FileManager.default
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            refresh()
        } catch {
            print("Delete failed: \(error)")
        }
    }

    // MARK: - File Creation

    func createNewFile() -> URL? {
        guard let folder = folderURL else { return nil }
        let ext = "txt"
        let baseName = "Untitled"
        var url = folder.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        refresh()
        return url
    }

    // MARK: - Private

    private func scanFolder(_ url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []

        for itemURL in contents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                hiddenDirCount += 1
            } else if supportedExtensions.contains(itemURL.pathExtension.lowercased()) {
                files.append(itemURL)
            } else {
                hiddenFileCount += 1
            }
        }

        let sorted: [URL]
        switch sortMode {
        case .alphabetical:
            sorted = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        case .byDate:
            sorted = files.sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }
        }

        return sorted.prefix(maxFiles).map { FileNode(name: $0.lastPathComponent, url: $0) }
    }
}
