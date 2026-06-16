import Foundation

enum FileService {
    /// Read file content with UTF-8 encoding.
    static func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func writeFile(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func renameItem(at oldURL: URL, to newURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !fm.fileExists(atPath: newURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.moveItem(at: oldURL, to: newURL)
    }

    static func scanDirectory(at url: URL) throws -> FileTreeItem {
        let fm = FileManager.default
        let name = url.lastPathComponent
        var root = FileTreeItem(url: url, name: name, isDirectory: true, parentID: nil, children: [])

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
            guard dirCache[parentURL] != nil else { continue }

            let itemName = fileURL.lastPathComponent

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)

            if isDir.boolValue {
                let dirItem = FileTreeItem(
                    url: fileURL,
                    name: itemName,
                    isDirectory: true,
                    parentID: dirCache[parentURL]?.id,
                    children: []
                )
                dirCache[fileURL] = dirItem
                appendToTree(root: &root, item: dirItem, parentURL: parentURL)
            } else if isSupportedFileExtension(fileURL.pathExtension) {
                let fileItem = FileTreeItem(
                    url: fileURL,
                    name: itemName,
                    isDirectory: false,
                    parentID: dirCache[parentURL]?.id,
                    children: nil
                )
                appendToTree(root: &root, item: fileItem, parentURL: parentURL)
            }
        }

        sortChildren(of: &root)
        return root
    }

    private static func sortChildren(of item: inout FileTreeItem) {
        item.children?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let children = item.children else { return }
        for i in children.indices where children[i].isDirectory {
            sortChildren(of: &item.children![i])
        }
    }

    private static func appendToTree(root: inout FileTreeItem, item: FileTreeItem, parentURL: URL) {
        if root.url == parentURL {
            root.children?.append(item)
            return
        }
        guard var children = root.children else { return }
        for i in children.indices {
            if parentURL.path.hasPrefix(children[i].url.path + "/") || children[i].url == parentURL {
                appendToTree(root: &children[i], item: item, parentURL: parentURL)
                root.children = children
                return
            }
        }
    }

    static func isSupportedFileExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "md", "markdown", "mkd", "html", "htm": return true
        default: return false
        }
    }

    }
