import Foundation

struct RecentItem: Identifiable, Codable, Equatable {
    var id: String { url }
    let url: String
    let name: String
    let isDirectory: Bool
}

@MainActor
final class RecentItemsService: ObservableObject {
    static let shared = RecentItemsService()

    @Published private(set) var items: [RecentItem] = []
    private let key = "recentItems"
    private let maxItems = 4

    private init() {
        load()
    }

    func remove(_ item: RecentItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func add(url: URL) {
        let item = RecentItem(
            url: url.path,
            name: url.lastPathComponent,
            isDirectory: url.hasDirectoryPath
        )
        items.removeAll { $0.url == item.url }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) else {
            return
        }
        // Filter out items that no longer exist
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.url) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
