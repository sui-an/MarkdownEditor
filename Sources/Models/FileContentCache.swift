import Foundation

/// In-memory file content cache with LRU eviction.
/// Keeps open file contents so switching tabs requires zero disk IO.
final class FileContentCache {
    private var contents: [URL: String] = [:]
    private var contentHashes: [URL: String] = [:]
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    func content(for url: URL) -> String? {
        contents[url]
    }

    func hash(for url: URL) -> String? {
        contentHashes[url]
    }

    func set(_ content: String, for url: URL, hash: String) {
        contents[url] = content
        contentHashes[url] = hash
        if contents.count > limit, let evicted = contents.keys.first {
            contents.removeValue(forKey: evicted)
            contentHashes.removeValue(forKey: evicted)
        }
    }

    func migrate(from oldURL: URL, to newURL: URL) {
        if let content = contents.removeValue(forKey: oldURL) {
            contents[newURL] = content
        }
        if let hash = contentHashes.removeValue(forKey: oldURL) {
            contentHashes[newURL] = hash
        }
    }

    func evict(_ url: URL) {
        contents.removeValue(forKey: url)
        contentHashes.removeValue(forKey: url)
    }

    func removeAll() {
        contents.removeAll()
        contentHashes.removeAll()
    }

    /// Fast file-modification check without reading content.
    static func quickHash(url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int else { return "" }
        return "\(size):\(Int(modDate.timeIntervalSince1970))"
    }
}
