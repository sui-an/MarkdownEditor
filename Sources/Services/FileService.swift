import Foundation

enum FileService {
    /// Read file content with UTF-8 encoding.
    static func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Synchronous read used only during cache-hit fast path (main thread safe because
    /// the file is already known to exist and is small enough for instant read).
    static func readFileCached(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func writeFile(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func scanDirectory(at url: URL) throws -> FileTreeItem {
        let fm = FileManager.default
        let name = url.lastPathComponent
        var root = FileTreeItem(url: url, name: name, isDirectory: true, parentID: nil)
        var children: [FileTreeItem] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            root.children = []
            return root
        }

        var dirCache: [URL: FileTreeItem] = [url: root]

        for case let fileURL as URL in enumerator {
            let parentURL = fileURL.deletingLastPathComponent()
            guard let parentItem = dirCache[parentURL] else { continue }

            let itemName = fileURL.lastPathComponent

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)

            if isDir.boolValue {
                let dirItem = FileTreeItem(
                    url: fileURL,
                    name: itemName,
                    isDirectory: true,
                    parentID: parentItem.id,
                    children: []
                )
                dirCache[fileURL] = dirItem

                if parentItem.url == url {
                    children.append(dirItem)
                } else if let idx = children.firstIndex(where: { $0.url == parentItem.url }) {
                    children[idx].children?.append(dirItem)
                }
            } else if fileURL.pathExtension.lowercased() == "md" {
                let fileItem = FileTreeItem(
                    url: fileURL,
                    name: itemName,
                    isDirectory: false,
                    parentID: parentItem.id,
                    children: nil
                )
                if parentItem.url == url {
                    children.append(fileItem)
                } else {
                    if let idx = children.firstIndex(where: { $0.url == parentItem.url }) {
                        children[idx].children?.append(fileItem)
                    }
                }
            }
        }

        root.children = children
        return root
    }

    static func ensureAssetsDirectory(for mdFileURL: URL) throws -> URL {
        let assetsURL = mdFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("assets", isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: assetsURL.path) {
            try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        }
        return assetsURL
    }

    static func saveImage(_ data: Data, extension ext: String, relativeTo mdFileURL: URL) throws -> URL {
        let assetsURL = try ensureAssetsDirectory(for: mdFileURL)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "image_\(timestamp).\(ext)"
        let fileURL = assetsURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    static func relativePath(from mdFileURL: URL, to imageURL: URL) -> String {
        let mdDir = mdFileURL.deletingLastPathComponent().path
        let imgPath = imageURL.path
        var mdComponents = mdDir.components(separatedBy: "/")
        var imgComponents = imgPath.components(separatedBy: "/")

        while !mdComponents.isEmpty && !imgComponents.isEmpty && mdComponents[0] == imgComponents[0] {
            mdComponents.removeFirst()
            imgComponents.removeFirst()
        }

        var relative = ""
        for _ in mdComponents {
            relative += "../"
        }
        relative += imgComponents.joined(separator: "/")
        return relative
    }
}
