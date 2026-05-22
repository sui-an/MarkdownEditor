import Foundation
import Observation
import AppKit

@Observable
final class AppState {
    var rootFolders: [FileTreeItem] = []
    var openFiles: [FileTreeItem] = []
    var selectedFileID: UUID?
    var currentFileContent: String = ""
    var currentFileURL: URL?
    var renderedHTML: String = ""
    var isFileDirty: Bool = false
    var isLoadingFile: Bool = false

    // Cache for already-read file contents and rendered HTML
    private struct FileCache {
        var fullContent: String
        var strippedContent: String
        var base64Segments: [String]
        var renderedHTML: String?
        var lastAccess: Date
    }
    private var fileCache: [URL: FileCache] = [:]
    private let maxCacheSize = 50

    private var folderWatchers: [UUID: FolderWatcher] = [:]
    private var selectedFileURL: URL?
    private var lastSavedContent: String = ""
    private var fullFileContent: String = ""
    private var base64Segments: [String] = []

    // MARK: - Open File

    func openFile(url: URL) {
        guard url.pathExtension.lowercased() == "md" else { return }

        if let existing = openFiles.first(where: { $0.url == url }) {
            selectFile(id: existing.id)
            return
        }

        let item = FileTreeItem(url: url, name: url.lastPathComponent, isDirectory: false, parentID: nil)
        openFiles.append(item)
        isLoadingFile = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let content = try FileService.readFile(at: url)
                let stripped = Self.stripBase64Segments(from: content)
                let cache = FileCache(fullContent: content, strippedContent: stripped.stripped, base64Segments: stripped.segments, renderedHTML: nil, lastAccess: Date())
                DispatchQueue.main.async {
                    self.fileCache[url] = cache
                    self.evictCacheIfNeeded()
                    self.isLoadingFile = false
                    self.setCurrentFile(url: url, content: content, strippedContent: stripped.stripped, segments: stripped.segments, id: item.id)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingFile = false
                    self.openFiles.removeAll { $0.id == item.id }
                    let alert = NSAlert()
                    alert.messageText = "Cannot Open File"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Open Folder

    func openFolder(url: URL) {
        if rootFolders.contains(where: { $0.url == url }) { return }

        do {
            let root = try FileService.scanDirectory(at: url)
            rootFolders.append(root)

            let watcher = FolderWatcher(paths: [url.path]) { [weak self] changedURLs in
                self?.handleFileSystemChanges(rootFolderID: root.id, urls: changedURLs)
            }
            watcher.start()
            folderWatchers[root.id] = watcher
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Open Folder"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Close File

    func closeFile(id: UUID) {
        saveCurrentFileIfDirty()
        // Clean cache before removing the item
        if let item = openFiles.first(where: { $0.id == id }) {
            fileCache.removeValue(forKey: item.url)
        }
        openFiles.removeAll { $0.id == id }
        if selectedFileID == id {
            clearSelection()
        }
    }

    // MARK: - Remove Folder

    func removeFolder(id: UUID) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == id }) else { return }

        let folder = rootFolders[idx]

        if let selectedID = selectedFileID {
            let fileIDs = folder.allMarkdownFiles.map { $0.id }
            if fileIDs.contains(selectedID) {
                clearSelection()
            }
        }

        // Clean cache for all files in this folder
        for file in folder.allMarkdownFiles {
            fileCache.removeValue(forKey: file.url)
        }

        folderWatchers[id]?.stop()
        folderWatchers.removeValue(forKey: id)
        rootFolders.remove(at: idx)
    }

    // MARK: - Select File

    func selectFile(id: UUID) {
        guard id != selectedFileID else { return }

        saveCurrentFileIfDirty()

        let allItems = allAvailableFiles()
        guard let item = allItems.first(where: { $0.id == id }) else { return }

        // Use cache if available — avoids disk read and HTML re-parse
        if var cached = fileCache[item.url] {
            cached.lastAccess = Date()
            fileCache[item.url] = cached
            setCurrentFile(url: item.url, content: cached.fullContent, strippedContent: cached.strippedContent, segments: cached.base64Segments, id: item.id, cachedHTML: cached.renderedHTML)
            return
        }

        isLoadingFile = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let content = try FileService.readFile(at: item.url)
                let stripped = Self.stripBase64Segments(from: content)
                let cache = FileCache(fullContent: content, strippedContent: stripped.stripped, base64Segments: stripped.segments, renderedHTML: nil, lastAccess: Date())
                DispatchQueue.main.async {
                    self.fileCache[item.url] = cache
                    self.evictCacheIfNeeded()
                    self.isLoadingFile = false
                    self.setCurrentFile(url: item.url, content: content, strippedContent: stripped.stripped, segments: stripped.segments, id: item.id)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingFile = false
                    let alert = NSAlert()
                    alert.messageText = "Cannot Open File"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Content Updates

    func updateContent(_ newContent: String) {
        currentFileContent = newContent
        fullFileContent = restoreFullContent(from: newContent)
        // Invalidate cached HTML and update access time
        if let url = currentFileURL {
            fileCache[url]?.renderedHTML = nil
            fileCache[url]?.lastAccess = Date()
        }
        let wasDirty = isFileDirty
        isFileDirty = fullFileContent != lastSavedContent
        // Skip regeneration if we're loading a file (no content actually changed).
        // On programmatic file load, fullFileContent == lastSavedContent, so isFileDirty stays false.
        // On user edit, isFileDirty transitions from false → true.
        guard isFileDirty || wasDirty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.regenerateHTML()
        }
    }

    private func regenerateHTML() {
        let content = fullFileContent
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let html = MarkdownParser.parseToHTML(content)
            DispatchQueue.main.async {
                guard let self else { return }
                self.renderedHTML = html
                if let url = self.currentFileURL {
                    self.fileCache[url]?.renderedHTML = html
                }
            }
        }
    }

    // MARK: - Save

    func saveCurrentFile() {
        guard let url = currentFileURL, isFileDirty else { return }
        do {
            try FileService.writeFile(fullFileContent, to: url)
            lastSavedContent = fullFileContent
            isFileDirty = false
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Save File"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func saveCurrentFileIfDirty() {
        guard isFileDirty else { return }
        saveCurrentFile()
    }

    // MARK: - Internal

    private func setCurrentFile(url: URL, content: String, strippedContent: String, segments: [String], id: UUID, cachedHTML: String? = nil) {
        saveCurrentFileIfDirty()
        selectedFileID = id
        selectedFileURL = url
        currentFileURL = url
        fullFileContent = content
        currentFileContent = strippedContent
        base64Segments = segments
        lastSavedContent = content
        isFileDirty = false
        if let cachedHTML {
            renderedHTML = cachedHTML
        } else {
            regenerateHTML()
        }
    }

    private func evictCacheIfNeeded() {
        guard fileCache.count > maxCacheSize else { return }
        let sorted = fileCache.sorted { $0.value.lastAccess < $1.value.lastAccess }
        let toRemove = sorted.prefix(max(1, fileCache.count / 4))
        for (url, _) in toRemove {
            fileCache.removeValue(forKey: url)
        }
    }

    private func clearSelection() {
        saveCurrentFileIfDirty()
        selectedFileID = nil
        selectedFileURL = nil
        currentFileURL = nil
        currentFileContent = ""
        fullFileContent = ""
        lastSavedContent = ""
        isFileDirty = false
        renderedHTML = ""
        base64Segments = []
    }

    func allAvailableFiles() -> [FileTreeItem] {
        var all = openFiles
        for folder in rootFolders {
            all += folder.allMarkdownFiles
        }
        return all
    }

    private func handleFileSystemChanges(rootFolderID: UUID, urls: [URL]) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        let folderURL = rootFolders[idx].url

        for url in urls {
            if !url.path.hasPrefix(folderURL.path) { continue }
            let ext = url.pathExtension.lowercased()

            if ext == "md" {
                let fm = FileManager.default
                if !fm.fileExists(atPath: url.path) {
                    fileCache.removeValue(forKey: url)
                    removeFileFromFolder(rootFolderID: rootFolderID, url: url)
                } else {
                    addFileToFolder(rootFolderID: rootFolderID, url: url)
                }
            }

            if selectedFileURL == url && !FileManager.default.fileExists(atPath: url.path) {
                DispatchQueue.main.async { [weak self] in
                    self?.clearSelection()
                }
            }

            if selectedFileURL == url {
                DispatchQueue.main.async { [weak self] in
                    self?.promptExternalChange(for: url)
                }
            }
        }
    }

    private func removeFileFromFolder(rootFolderID: UUID, url: URL) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        removeFileRecursively(from: &rootFolders[idx], url: url)
    }

    private func removeFileRecursively(from item: inout FileTreeItem, url: URL) {
        if let children = item.children {
            item.children = children.compactMap { child in
                var mutableChild = child
                if mutableChild.url == url && !mutableChild.isDirectory {
                    return nil
                }
                if mutableChild.isDirectory {
                    removeFileRecursively(from: &mutableChild, url: url)
                }
                return mutableChild
            }
        }
    }

    private func addFileToFolder(rootFolderID: UUID, url: URL) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        let existing = rootFolders[idx].allMarkdownFiles
        if existing.contains(where: { $0.url == url }) { return }

        let name = url.lastPathComponent
        let newFile = FileTreeItem(url: url, name: name, isDirectory: false, parentID: rootFolderID)
        rootFolders[idx].children?.append(newFile)

        let all = rootFolders[idx].allMarkdownFiles
        rootFolders[idx].children = all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func promptExternalChange(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "File Changed Externally"
        alert.informativeText = "The file \"\(url.lastPathComponent)\" was modified by another application. Reload?"
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep Current")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                let content = try FileService.readFile(at: url)
                let stripped = Self.stripBase64Segments(from: content)
                fullFileContent = content
                currentFileContent = stripped.stripped
                base64Segments = stripped.segments
                lastSavedContent = content
                isFileDirty = false
                // Invalidate cache so next switch re-reads fresh content
                fileCache.removeValue(forKey: url)
                regenerateHTML()
            } catch {}
        }
    }

    // MARK: - Base64 Handling

    private static func stripBase64Segments(from content: String) -> (stripped: String, segments: [String]) {
        let pattern = #"!\[([^\]]*)\]\((data:[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (content, [])
        }
        let nsContent = content as NSString
        var segments: [String] = []
        var result = content
        var offset = 0
        for match in regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
            let url = nsContent.substring(with: match.range(at: 2))
            segments.append(url)
            let marker = "\u{2318}BS64_\(segments.count - 1)\u{2318}"
            let alt = nsContent.substring(with: match.range(at: 1))
            let replacement = "![\(alt)](\(marker))"
            let adjRange = NSRange(location: match.range.location + offset, length: match.range.length)
            result = (result as NSString).replacingCharacters(in: adjRange, with: replacement)
            offset += replacement.utf16.count - match.range.length
        }
        return (result, segments)
    }

    private func restoreFullContent(from displayContent: String) -> String {
        var result = displayContent
        for (index, segment) in base64Segments.enumerated().reversed() {
            let marker = "\u{2318}BS64_\(index)\u{2318}"
            result = result.replacingOccurrences(of: marker, with: segment)
        }
        return result
    }
}
