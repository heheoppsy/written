import Foundation
import CommonCrypto
import os.log

private let shadowLog = Logger(subsystem: "com.written.app", category: "ShadowFileManager")

@MainActor
final class ShadowFileManager {
    static let shared = ShadowFileManager()

    /// Whether the shadows directory was created successfully.
    /// If false, crash recovery is unavailable and the user should be warned.
    private(set) var isReady: Bool = false

    static let shadowsDir: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Written/Shadows", isDirectory: true)
    }()

    private init() {
        ensureDirectory()
    }

    /// Attempt to create (or verify) the shadows directory. Returns success.
    @discardableResult
    func ensureDirectory() -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.shadowsDir, withIntermediateDirectories: true)
            isReady = true
            return true
        } catch {
            shadowLog.error("Failed to create shadows directory: \(error.localizedDescription)")
            // Check if it already exists (createDirectory can fail even when dir is present)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: Self.shadowsDir.path, isDirectory: &isDir), isDir.boolValue {
                isReady = true
                return true
            }
            isReady = false
            return false
        }
    }

    // MARK: - Meta Sidecar

    struct ShadowMeta: Codable {
        let realFilePath: String?     // nil for untitled
        let lastDiskModDate: Date?    // mod date of real file when we last read/saved it
        let shadowWriteDate: Date     // when the shadow was last written
    }

    // MARK: - Path Mapping

    func shadowURL(for fileURL: URL) -> URL {
        let path = fileURL.standardizedFileURL.path
        let hash = sha256Prefix(path)
        let name = "\(hash)_\(fileURL.lastPathComponent)"
        return Self.shadowsDir.appendingPathComponent(name)
    }

    func shadowURLForUntitled(id: UUID) -> URL {
        Self.shadowsDir.appendingPathComponent("untitled_\(id.uuidString).txt")
    }

    // MARK: - CRUD

    func writeShadow(text: String, shadowURL: URL, meta: ShadowMeta) {
        guard isReady else { return }
        let textToWrite = text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
        do {
            try textToWrite.write(to: shadowURL, atomically: true, encoding: .utf8)
        } catch {
            shadowLog.error("Shadow write failed for \(shadowURL.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: metaURL(for: shadowURL), options: .atomic)
        } catch {
            shadowLog.error("Shadow meta write failed for \(shadowURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func readShadow(at shadowURL: URL) -> (text: String, meta: ShadowMeta)? {
        guard let text = try? String(contentsOf: shadowURL, encoding: .utf8),
              let metaData = try? Data(contentsOf: metaURL(for: shadowURL)),
              let meta = try? JSONDecoder().decode(ShadowMeta.self, from: metaData)
        else { return nil }
        return (text, meta)
    }

    func deleteShadow(at shadowURL: URL) {
        try? FileManager.default.removeItem(at: shadowURL)
        try? FileManager.default.removeItem(at: metaURL(for: shadowURL))
    }

    // MARK: - Discovery (crash recovery)

    func allShadows() -> [(url: URL, meta: ShadowMeta)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.shadowsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "txt" }
            .compactMap { shadowURL in
                guard let metaData = try? Data(contentsOf: metaURL(for: shadowURL)),
                      let meta = try? JSONDecoder().decode(ShadowMeta.self, from: metaData)
                else { return nil }
                return (shadowURL, meta)
            }
    }

    func removeAllShadows() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.shadowsDir, includingPropertiesForKeys: nil
        ) else { return }
        for file in files { try? fm.removeItem(at: file) }
    }

    // MARK: - Private

    private func metaURL(for shadowURL: URL) -> URL {
        let name = shadowURL.deletingPathExtension().lastPathComponent + ".meta.json"
        return Self.shadowsDir.appendingPathComponent(name)
    }

    private func sha256Prefix(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
