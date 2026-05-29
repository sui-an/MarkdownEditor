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
    /// Shared instance used by the AppDelegate when files are opened via Finder.
    /// ContentView references this same instance via `@State`.
    static let shared = AppState()

    var rootFolders: [FileTreeItem] = []
    var openFiles: [FileTreeItem] = []
    var selectedFileID: UUID?
    var currentFileContent: String = ""
    var currentFileURL: URL?
    var renderedHTML: String = ""
    /// Body-only HTML for incremental preview DOM updates (avoids WKWebView
    /// full-page reload via loadHTMLString on every keystroke).
    var renderedBodyHTML: String = ""
    var isFileDirty: Bool = false
    var isLoadingFile: Bool = false
    var searchState: SearchState
    var outlineHeadings: [HeadingItem] = []
    var isOutlineVisible = false

    private var folderWatchers: [UUID: FolderWatcher] = [:]
    private var selectedFileURL: URL?
    private var lastSavedContent: String = ""

    // MARK: - In-memory file content cache

    /// All open file contents kept in memory so switching tabs requires zero disk IO.
    /// Populated by loadFileContent, updated by user edits, evicted on file close.
    private var fileContents: [URL: String] = [:]
    /// LRU access order for fileContents eviction (most recent at end).
    private var fileContentAccessOrder: [URL] = []
    /// Maximum entries in fileContents — matches htmlCache countLimit.
    private let fileContentCacheLimit = 20
    /// Content hash of the last saved/loaded version for each file.
    /// Used to detect external file modifications (via folder watcher).
    private var fileSavedHashes: [URL: String] = [:]

    // MARK: - Performance: HTML cache + operation cancellation

    /// LRU HTML cache keyed by file URL. NSCache handles eviction under memory pressure.
    private let htmlCache = NSCache<NSURL, CachedHTML>()

    /// Monotonically increasing generation counter. Incremented on each file switch;
    /// stale background tasks whose token no longer matches silently discard results.
    private var generation: Int64 = 0

    /// Active HTML-generation work item. Cancelled on file switch to avoid wasted work.
    private var pendingHTMLWork: DispatchWorkItem?

    /// Active outline-parsing work item. Cancelled on new keystroke.
    private var pendingOutlineWork: DispatchWorkItem?

    /// Content hash of the last cached version for a given URL. Avoids re-parsing
    /// when content hasn't actually changed (e.g. switching tabs).
    private var cachedContentHash: [URL: String] = [:]

    /// Secondary HTML cache — deterministic LRU, NOT affected by memory pressure
    /// (unlike NSCache which may purge entries at any time). Ensures recently
    /// rendered HTML is available instantly on file switch, even after a cache purge.
    private var cachedHTML: [URL: CachedHTML] = [:]
    private var cachedHTMLAccessOrder: [URL] = []
    private let cachedHTMLCacheLimit = 10

    init() {
        htmlCache.countLimit = 20
        htmlCache.totalCostLimit = 30 * 1024 * 1024  // 30 MB
        // Initialize with empty closure first — @Observable macro requires
        // all stored properties to be initialized before accessing self.
        searchState = SearchState { "" }
        searchState.setContent { [weak self] in self?.currentFileContent ?? "" }
    }

    // MARK: - New Note

    func createNewNote() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Untitled.md"
        panel.title = "New Note"
        panel.message = "Choose where to save the new markdown file"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "md" else {
            let alert = NSAlert()
            alert.messageText = "Invalid Extension"
            alert.informativeText = "Please use a .md file extension"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        // Create file with empty content
        let template = ""
        do {
            try FileService.writeFile(template, to: url)
            openFile(url: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Create Note"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
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
            fileContents.removeValue(forKey: item.url)
            fileSavedHashes.removeValue(forKey: item.url)
            cachedHTML.removeValue(forKey: item.url)
            cachedHTMLAccessOrder.removeAll { $0 == item.url }
        }
        openFiles.removeAll { $0.id == id }
        if selectedFileID == id {
            clearSelection()
        }
        WebViewCache.shared.remove(for: id)
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

        for file in folder.allMarkdownFiles {
            htmlCache.removeObject(forKey: file.url as NSURL)
            cachedContentHash.removeValue(forKey: file.url)
            cachedHTML.removeValue(forKey: file.url)
            cachedHTMLAccessOrder.removeAll { $0 == file.url }
        }

        folderWatchers[id]?.stop()
        folderWatchers.removeValue(forKey: id)
        rootFolders.remove(at: idx)
    }

    // MARK: - Select File

    func selectFile(id: UUID) {
        // Don't guard against selectedFileID — the List(selection:) binding
        // may already have set it before onChange fires. Always proceed
        // to loadFileContent; it caches aggressively so re-selection is fast.
        saveCurrentFileIfDirty()

        let allItems = allAvailableFiles()
        guard let item = allItems.first(where: { $0.id == id }) else { return }

        loadFileContent(url: item.url, id: item.id)
    }

    // MARK: - Shared file loading (cancellation-aware)

    private func loadFileContent(url: URL, id: UUID) {
        // Cancel any in-flight work for the previous file
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil
        pendingOutlineWork?.cancel()
        pendingOutlineWork = nil

        // Advance generation so stale async blocks discard results
        let token = OSAtomicIncrement64(&generation)

        // Signal loading state immediately — editor switches to new file at once
        isLoadingFile = true
        selectedFileID = id
        selectedFileURL = url
        currentFileURL = url
        renderedHTML = ""
        renderedBodyHTML = ""

        // Try cache FIRST — in-memory content cache (zero disk IO) then HTML cache.
        let cacheKey = quickHashForCacheCheck(url: url)
        if let cachedContent = fileContents[url],
           fileSavedHashes[url] == cacheKey {
            // In-memory content cache hit — same content as on disk.
            // Zero IO: content was kept from previous load or edit.
            if let cached = htmlCache.object(forKey: url as NSURL),
               cachedContentHash[url] == cacheKey {
                // Full cache hit: content + HTML both cached
                lastSavedContent = cachedContent
                isFileDirty = false
                isLoadingFile = false
                currentFileContent = cachedContent
                renderedHTML = cached.html
                renderedBodyHTML = cached.bodyHTML
                updateContent(cachedContent)
                return
            }
            // Try secondary LRU cache (survives NSCache memory-pressure purges)
            if let cached = cachedHTML[url],
               cachedContentHash[url] == cacheKey {
                lastSavedContent = cachedContent
                isFileDirty = false
                isLoadingFile = false
                currentFileContent = cachedContent
                renderedHTML = cached.html
                renderedBodyHTML = cached.bodyHTML
                updateContent(cachedContent)
                return
            }
            // HTML cache miss — content ready, generate on background
            currentFileContent = cachedContent
            updateContent(cachedContent)
            startAsyncHTMLGeneration(content: cachedContent, url: url, token: token, cacheKey: cacheKey)
            return
        }

        // In-memory cache miss — read file on background, editor gets content first.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, token == self.generation else { return }

            do {
                let content = try FileService.readFile(at: url)

                // Always cache content — if the user switched away during the read,
                // the cache ensures the next switch to this file is zero-IO.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.cacheFileContent(content, for: url, cacheKey: cacheKey)
                }

                guard token == self.generation else { return }

                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    self.lastSavedContent = content
                    self.isFileDirty = false
                    self.isLoadingFile = false
                    self.currentFileContent = content
                    self.updateContent(content)
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

                // Generate HTML on background
                self.generateAndCacheHTML(content: content, url: url, token: token, cacheKey: cacheKey)
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

    // MARK: - Shared HTML generation (called from both cache-hit and cache-miss paths)

    /// Called when in-memory content cache hit but HTML cache miss.
    /// Content is ready (no disk IO needed), just generate HTML on background.
    private func startAsyncHTMLGeneration(content: String, url: URL, token: Int64, cacheKey: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, token == self.generation else { return }
            self.generateAndCacheHTML(content: content, url: url, token: token, cacheKey: cacheKey)
        }
    }

    /// Generate HTML from markdown content, cache it, and update rendered properties.
    private func generateAndCacheHTML(content: String, url: URL, token: Int64, cacheKey: String) {
        let (bodyHTML, fullHTML) = MarkdownParser.parseToHTML(content)
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            let cached = CachedHTML(html: fullHTML, bodyHTML: bodyHTML)
            self.htmlCache.setObject(cached, forKey: url as NSURL, cost: fullHTML.utf8.count)
            self.cachedContentHash[url] = cacheKey
            self.cacheRenderedHTML(cached, for: url)
            self.renderedHTML = fullHTML
            self.renderedBodyHTML = bodyHTML
        }
    }

    // MARK: - Content Updates (editing)

    func updateContent(_ newContent: String) {
        // currentFileContent is already set by the @Binding before onChange fires.
        if let url = currentFileURL {
            let cacheKey = quickHashForCacheCheck(url: url)
            cacheFileContent(newContent, for: url, cacheKey: cacheKey)
        }
        isFileDirty = newContent != lastSavedContent

        // Always refresh outline — even on file load (isFileDirty = false)
        refreshOutline(newContent)

        // Programmatic changes (file switches) already have HTML from
        // loadFileContent — skip duplicate generation and cache invalidation.
        guard isFileDirty else { return }

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
        guard let url = currentFileURL else { return }
        let token = generation  // capture current generation
        let cacheKey = quickHashForCacheCheck(url: url)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, token == self.generation else { return }
            self.generateAndCacheHTML(content: content, url: url, token: token, cacheKey: cacheKey)
        }
    }

    // MARK: - Outline

    private func refreshOutline(_ content: String) {
        let token = generation
        pendingOutlineWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let headings = HeadingParser.parse(content)
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.outlineHeadings = headings
            }
        }
        pendingOutlineWork = work
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    // MARK: - Save

    func saveCurrentFile() {
        guard let url = currentFileURL, isFileDirty else { return }
        do {
            try FileService.writeFile(currentFileContent, to: url)
            lastSavedContent = currentFileContent
            isFileDirty = false
            // Update saved hash so in-memory cache stays valid
            fileSavedHashes[url] = quickHashForCacheCheck(url: url)
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

    /// Stores file content in the in-memory cache and enforces LRU eviction
    /// so the dictionary doesn't grow unboundedly as files are opened over time.
    private func cacheFileContent(_ content: String, for url: URL, cacheKey: String) {
        fileContents[url] = content
        fileSavedHashes[url] = cacheKey
        if let idx = fileContentAccessOrder.firstIndex(of: url) {
            fileContentAccessOrder.remove(at: idx)
        }
        fileContentAccessOrder.append(url)
        if fileContents.count > fileContentCacheLimit,
           let evicted = fileContentAccessOrder.first {
            fileContentAccessOrder.removeFirst()
            fileContents.removeValue(forKey: evicted)
            fileSavedHashes.removeValue(forKey: evicted)
            cachedContentHash.removeValue(forKey: evicted)
            htmlCache.removeObject(forKey: evicted as NSURL)
            cachedHTML.removeValue(forKey: evicted)
            cachedHTMLAccessOrder.removeAll { $0 == evicted }
        }
    }

    /// Stores rendered HTML in the secondary LRU cache (survives NSCache purges).
    private func cacheRenderedHTML(_ cached: CachedHTML, for url: URL) {
        cachedHTML[url] = cached
        if let idx = cachedHTMLAccessOrder.firstIndex(of: url) {
            cachedHTMLAccessOrder.remove(at: idx)
        }
        cachedHTMLAccessOrder.append(url)
        if cachedHTML.count > cachedHTMLCacheLimit,
           let evicted = cachedHTMLAccessOrder.first {
            cachedHTMLAccessOrder.removeFirst()
            cachedHTML.removeValue(forKey: evicted)
        }
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

            if selectedFileURL == url {
                if FileManager.default.fileExists(atPath: url.path) {
                    promptExternalChange(for: url)
                } else {
                    clearSelection()
                }
            }
        }
    }

    private func removeFileFromFolder(rootFolderID: UUID, url: URL) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        removeFileRecursively(from: &rootFolders[idx], url: url)
        htmlCache.removeObject(forKey: url as NSURL)
        cachedContentHash.removeValue(forKey: url)
        fileContents.removeValue(forKey: url)
        fileSavedHashes.removeValue(forKey: url)
        fileContentAccessOrder.removeAll { $0 == url }
        cachedHTML.removeValue(forKey: url)
        cachedHTMLAccessOrder.removeAll { $0 == url }
        WebViewCache.shared.removeWebView(for: url)
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

    /// Break observation chains before deinit to prevent SwiftUI StoredLocation
    /// recursive deallocation crashes during view hierarchy teardown.
    /// Call when the owning view disappears or is about to be deallocated.
    func cleanup() {
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil
        pendingOutlineWork?.cancel()
        pendingOutlineWork = nil
        folderWatchers.values.forEach { $0.stop() }
        folderWatchers.removeAll()
        rootFolders.removeAll()
        openFiles.removeAll()
        fileContents.removeAll()
        fileContentAccessOrder.removeAll()
        fileSavedHashes.removeAll()
        cachedContentHash.removeAll()
        cachedHTML.removeAll()
        cachedHTMLAccessOrder.removeAll()
        htmlCache.removeAllObjects()
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
                let cacheKey = quickHashForCacheCheck(url: url)
                cacheFileContent(content, for: url, cacheKey: cacheKey)
                currentFileContent = content
                lastSavedContent = content
                isFileDirty = false
                regenerateHTML()
            } catch {
            print("Failed to reload externally-changed file: \(error)")
        }
        }
    }
}
