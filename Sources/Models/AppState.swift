import Foundation
import Observation
import AppKit

// MARK: - HTML Cache Entry

private final class CachedHTML {
    let html: String
    let bodyHTML: String

    init(html: String, bodyHTML: String) {
        self.html = html
        self.bodyHTML = bodyHTML
    }
}

// MARK: - AppState

@Observable
final class AppState {
    var rootFolders: [FileTreeItem] = []
    var openFiles: [FileTreeItem] = []
    var selectedFileID: UUID?
    var currentFileContent: String = ""
    var currentFileURL: URL?
    var renderedHTML: String = ""
    /// Body-only HTML for incremental preview DOM updates (avoids WKWebView
    /// full-page reload via loadHTMLString on every keystroke).
    var renderedBodyHTML: String = ""
    /// Callback to reset scroll positions when switching files.
    var onFileSwitch: (() -> Void)?
    var isFileSwitching: Bool = false
    var isFileDirty: Bool = false
    var isLoadingFile: Bool = false

    private var folderWatchers: [UUID: FolderWatcher] = [:]
    private var selectedFileURL: URL?
    private var lastSavedContent: String = ""

    // MARK: - Performance: HTML cache + operation cancellation

    /// LRU HTML cache keyed by file URL. NSCache handles eviction under memory pressure.
    private let htmlCache = NSCache<NSURL, CachedHTML>()

    /// Monotonically increasing generation counter. Incremented on each file switch;
    /// stale background tasks whose token no longer matches silently discard results.
    private var generation: Int64 = 0

    /// Active HTML-generation work item. Cancelled on file switch to avoid wasted work.
    private var pendingHTMLWork: DispatchWorkItem?

    /// Content hash of the last cached version for a given URL. Avoids re-parsing
    /// when content hasn't actually changed (e.g. switching tabs).
    private var cachedContentHash: [URL: String] = [:]

    init() {
        htmlCache.countLimit = 20
        htmlCache.totalCostLimit = 30 * 1024 * 1024  // 30 MB
    }

    // MARK: - Open File

    func openFile(url: URL) {
        guard url.pathExtension.lowercased() == "md" else { return }

        if let existing = openFiles.first(where: { $0.url == url }) {
            selectFile(id: existing.id)
            return
        }

        let item = FileTreeItem(url: url, name: url.lastPathComponent, isDirectory: false, parentID: nil)
        openFiles.append(item)
        loadFileContent(url: url, id: item.id)
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
        if let item = openFiles.first(where: { $0.id == id }) {
            cachedContentHash.removeValue(forKey: item.url)
        }
        openFiles.removeAll { $0.id == id }
        if selectedFileID == id {
            clearSelection()
        }
    }

    // MARK: - Remove Folder

    func removeFolder(id: UUID) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == id }) else { return }

        if let selectedID = selectedFileID {
            let folder = rootFolders[idx]
            let fileIDs = folder.allMarkdownFiles.map { $0.id }
            if fileIDs.contains(selectedID) {
                clearSelection()
            }
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

        // Set file switching flag for instant response
        isFileSwitching = true
        loadFileContent(url: item.url, id: item.id, isSwitching: true)
    }

    // MARK: - Scroll position reset

    /// Reset scroll position in both editor and preview to the top.
    /// Call this when switching files to ensure a clean view.
    func resetScrollPositions() {
        // Editor scroll reset — access through PreviewWebView coordinator
        // This is handled in ContentView by observing file changes
    }

    // MARK: - Shared file loading (cancellation-aware)

    private func loadFileContent(url: URL, id: UUID, isSwitching: Bool = false) {
        // Cancel any in-flight work for the previous file
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil

        // Advance generation so stale async blocks discard results
        let token = OSAtomicIncrement64(&generation)

        // Signal loading state immediately — editor switches to new file at once
        isLoadingFile = true
        selectedFileID = id
        selectedFileURL = url
        currentFileURL = url

        // Try cache FIRST (synchronous — file is already known to exist and
        // unchanged, so read is near-instant from the OS page cache).
        let cacheKey = quickHashForCacheCheck(url: url)
        if let cached = htmlCache.object(forKey: url as NSURL),
           cachedContentHash[url] == cacheKey {
            currentFileContent = FileService.readFileCached(at: url)
            lastSavedContent = currentFileContent
            isFileDirty = false
            renderedHTML = cached.html
            renderedBodyHTML = cached.bodyHTML
            isLoadingFile = false
            return
        }

        // Cache miss — read file on background, editor gets content first
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, token == self.generation else { return }

            do {
                let content = try FileService.readFile(at: url)

                // Push content to editor immediately (don't wait for HTML)
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    self.currentFileContent = content
                    self.lastSavedContent = content
                    self.isFileDirty = false
                    self.isLoadingFile = false
                }

                // Check cache again (may have been cached by another window since outer check)
                if let cached = self.htmlCache.object(forKey: url as NSURL),
                   self.cachedContentHash[url] == cacheKey {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, token == self.generation else { return }
                        self.renderedHTML = cached.html
                    }
                    return
                }

                // Generate HTML on background — single parse pass returns both
                // the body-only fragment (for incremental JS injection into the
                // preview) and the full document (for initial loadHTMLString).
                let (bodyHTML, fullHTML) = MarkdownParser.parseToHTML(content)

                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    let cached = CachedHTML(html: fullHTML, bodyHTML: bodyHTML)
                    self.htmlCache.setObject(cached, forKey: url as NSURL, cost: fullHTML.utf8.count)
                    self.cachedContentHash[url] = cacheKey
                    self.renderedHTML = fullHTML
                    self.renderedBodyHTML = bodyHTML
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    self.isLoadingFile = false
                    self.openFiles.removeAll { $0.id == id }
                    let alert = NSAlert()
                    alert.messageText = "Cannot Open File"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Content Updates (editing)

    func updateContent(_ newContent: String) {
        currentFileContent = newContent
        isFileDirty = newContent != lastSavedContent

        // Cancel any pending debounced HTML regeneration
        pendingHTMLWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.regenerateHTML()
        }
        pendingHTMLWork = work

        // Longer debounce for large files to reduce CPU while typing
        let delay: TimeInterval = newContent.utf8.count > 100_000 ? 0.5 : 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func regenerateHTML() {
        let content = currentFileContent
        let url = currentFileURL
        let token = generation  // capture current generation

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, token == self.generation else { return }
            let (bodyHTML, fullHTML) = MarkdownParser.parseToHTML(content)
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.generation else { return }
                self.renderedHTML = fullHTML
                self.renderedBodyHTML = bodyHTML
                // Invalidate cache for this URL since content changed
                if let url {
                    self.cachedContentHash.removeValue(forKey: url)
                    self.htmlCache.removeObject(forKey: url as NSURL)
                }
            }
        }
    }

    // MARK: - Save

    func saveCurrentFile() {
        guard let url = currentFileURL, isFileDirty else { return }
        do {
            try FileService.writeFile(currentFileContent, to: url)
            lastSavedContent = currentFileContent
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

    private func clearSelection() {
        saveCurrentFileIfDirty()
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil
        selectedFileID = nil
        selectedFileURL = nil
        currentFileURL = nil
        currentFileContent = ""
        lastSavedContent = ""
        isFileDirty = false
        renderedHTML = ""
        renderedBodyHTML = ""
    }

    func allAvailableFiles() -> [FileTreeItem] {
        var all = openFiles
        for folder in rootFolders {
            all += folder.allMarkdownFiles
        }
        return all
    }

    // MARK: - Cache helpers

    /// Fast file-modification check without reading content. Returns "" if file doesn't exist.
    private func quickHashForCacheCheck(url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int else { return "" }
        return "\(size):\(Int(modDate.timeIntervalSince1970))"
    }

    // MARK: - File System Changes

    private func handleFileSystemChanges(rootFolderID: UUID, urls: [URL]) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        let folderURL = rootFolders[idx].url

        for url in urls {
            if !url.path.hasPrefix(folderURL.path) { continue }
            let ext = url.pathExtension.lowercased()

            if ext == "md" {
                let fm = FileManager.default
                if !fm.fileExists(atPath: url.path) {
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
        htmlCache.removeObject(forKey: url as NSURL)
        cachedContentHash.removeValue(forKey: url)
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
            htmlCache.removeObject(forKey: url as NSURL)
            cachedContentHash.removeValue(forKey: url)
            do {
                let content = try FileService.readFile(at: url)
                currentFileContent = content
                lastSavedContent = content
                isFileDirty = false
                regenerateHTML()
            } catch {}
        }
    }
}
