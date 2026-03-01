import Foundation

struct WrittenDocument: Sendable {
    var text: String
    var fileURL: URL?

    init(text: String = "", fileURL: URL? = nil) {
        self.text = text
        self.fileURL = fileURL
    }

    static func load(from url: URL) throws -> WrittenDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        return WrittenDocument(text: text, fileURL: url)
    }
}
