import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

// MARK: - HTML Cache Entry

private final class CachedHTML {
    let html: String
    let bodyHTML: String

    init(html: String, bodyHTML: String) {
        self.html = html
        self.bodyHTML = bodyHTML
    }
}

// MARK: - Flat Folder File

struct FlatFolderFile {
    let item: FileTreeItem
    let depth: Int
}

// MARK: - AppState

@Observable
final class AppState {
    let instanceID = UUID().uuidString.prefix(8)
    var rootFolders: [FileTreeItem] = []
    var openFiles: [FileTreeItem] = []
    var selectedFileID: String?
    var currentFileContent: String = ""
    var currentFileURL: URL?
    var renderedHTML: String = ""
    /// Body-only HTML for incremental preview DOM updates (avoids WKWebView
    /// full-page reload via loadHTMLString on every keystroke).
    var renderedBodyHTML: String = ""
    var isFileDirty: Bool = false
    var searchState: SearchState
    var outlineHeadings: [HeadingItem] = []
    var isOutlineVisible = false

    /// Per-window preferences (moved from @AppStorage)
    var previewOnly = true
    var previewContentWidth = 0
    var sidebarVis = 0

    /// Per-window state migrated from ContentView's @State to eliminate
    /// cross-NSHostingController state sharing on macOS 14.
    let viewRefs = ViewRefs()
    var fontSize: CGFloat = AppState.loadFontSize()
    var themeChangeCount = 0
    var showPreviewSearch = false
    @ObservationIgnored var outlinePanel: OutlinePanelWindow?
    @ObservationIgnored var searchPanel: SearchPanel?
    @ObservationIgnored var windowSessionID: UUID?
    @ObservationIgnored private var themeObserver: Any?

    private var folderWatchers: [String: FolderWatcher] = [:]
    private var selectedFileURL: URL?
    private var lastSavedContent: String = ""

    /// Per-window WebView cache (replaces global singleton)
    let webViewCache = WebViewCache()

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
    /// stale background tasks whose token no longer match silently discard results.
    private var generation: Int64 = 0

    /// Active HTML-generation work item. Cancelled on file switch to avoid wasted work.
    private var pendingHTMLWork: DispatchWorkItem?

    /// Active outline-parsing work item. Cancelled on new keystroke.
    private var pendingOutlineWork: DispatchWorkItem?

    /// Re-entrancy guard for loadFileContent. Prevents double-loading when
    /// the .onChange(of: selectedFileID) handler re-invokes loadFileContent
    /// immediately after we set selectedFileID.
    private var isOpeningFile = false

    /// Separate monotonically increasing counter for outline generation.
    /// Using the same generation counter as HTML would let stale outline
    /// results overwrite fresh ones (since outline doesn't increment it).
    private var outlineGeneration: Int64 = 0

    /// Content hash of the last cached version for a given URL. Avoids re-parsing
    /// when content hasn't actually changed (e.g. switching tabs).
    private var cachedContentHash: [URL: String] = [:]

    /// Secondary HTML cache — deterministic LRU, NOT affected by memory pressure
    /// (unlike NSCache which may purge entries at any time). Ensures recently
    /// rendered HTML is available instantly on file switch, even after a cache purge.
    private var cachedHTML = LRUCache<URL, CachedHTML>(limit: 10)

    init() {
        htmlCache.countLimit = 20
        htmlCache.totalCostLimit = 30 * 1024 * 1024  // 30 MB
        // Initialize with empty closure first — @Observable macro requires
        // all stored properties to be initialized before accessing self.
        searchState = SearchState { "" }
        searchState.setContent { [weak self] in self?.currentFileContent ?? "" }

        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.themeChangeCount &+= 1
        }
    }

    static func loadFontSize() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: "editorFontSize")
        return saved >= 9 ? saved : 13
    }

    func changeFontSize(by delta: CGFloat) {
        let newSize = max(9, min(72, fontSize + delta))
        guard newSize != fontSize else { return }
        let oldSize = fontSize
        fontSize = newSize
        UserDefaults.standard.set(newSize, forKey: "editorFontSize")
        // Register undo for Cmd+Z support
        viewRefs.textView?.undoManager?.registerUndo(withTarget: self) { target in
            target.changeFontSize(to: oldSize)
        }
        // Update text view font and apply to all existing text immediately
        if let tv = viewRefs.textView {
            tv.font = NSFont.systemFont(ofSize: newSize)
            if let storage = tv.textStorage, storage.length > 0 {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: newSize), range: NSRange(location: 0, length: storage.length))
            }
            tv.needsDisplay = true
        }
    }

    private func changeFontSize(to size: CGFloat) {
        fontSize = size
        UserDefaults.standard.set(size, forKey: "editorFontSize")
        if let tv = viewRefs.textView {
            tv.font = NSFont.systemFont(ofSize: size)
            if let storage = tv.textStorage, storage.length > 0 {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size), range: NSRange(location: 0, length: storage.length))
            }
            tv.needsDisplay = true
        }
    }

    func resetFontSize() {
        changeFontSize(by: 13 - fontSize)
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - New Note

    func createNewNote() {
        let panel = NSSavePanel()
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [mdType, .plainText, .text]
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
        guard url.pathExtension.lowercased() == "md" else {
            let alert = NSAlert()
            alert.messageText = "Unsupported file type"
            alert.informativeText = "MarkdownEditor only supports .md files."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        if let existing = openFiles.first(where: { $0.url == url }) {
            selectedFileID = existing.id
            return
        }

        let item = FileTreeItem(url: url, name: url.lastPathComponent, isDirectory: false, parentID: nil)
        openFiles.append(item)
        fileIndex[item.id] = item
        selectedFileID = item.id
    }

    // MARK: - Open Folder

    func openFolder(url: URL) {
        if rootFolders.contains(where: { $0.url == url }) { return }

        do {
            let root = try FileService.scanDirectory(at: url)
            rootFolders.append(root)
            rebuildFileIndex()

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

    func closeFile(id: String) {
        saveCurrentFileIfDirty()
        if let item = openFiles.first(where: { $0.id == id }) {
            cachedContentHash.removeValue(forKey: item.url)
            fileContents.removeValue(forKey: item.url)
            fileSavedHashes.removeValue(forKey: item.url)
            fileContentAccessOrder.removeAll { $0 == item.url }
            cachedHTML.removeValue(for: item.url)
        }
        openFiles.removeAll { $0.id == id }
        fileIndex.removeValue(forKey: id)
        if selectedFileID == id {
            clearSelection()
        }
        webViewCache.remove(for: id)
    }

    /// Close the currently selected file. For folder files, just deselect.
    func closeCurrentFile() {
        guard let id = selectedFileID else { return }
        if openFiles.contains(where: { $0.id == id }) {
            closeFile(id: id)
        } else {
            // File belongs to a folder — just clear the selection
            clearSelection()
        }
    }

    // MARK: - Remove Folder

    func removeFolder(id: String) {
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
            cachedHTML.removeValue(for: file.url)
        }

        folderWatchers[id]?.stop()
        folderWatchers.removeValue(forKey: id)
        rootFolders.remove(at: idx)
        rebuildFileIndex()
    }

    // MARK: - Select File

    /// Fast index of all available files by ID, rebuilt on structural changes.
    private var fileIndex: [String: FileTreeItem] = [:]

    /// Flat file list for folder files, keyed by root folder ID.  Pre-computed
    /// on structural changes (folder open/close, file add/remove) so that the
    /// sidebar can render folder files with a flat ForEach, avoiding recursive
    /// DisclosureGroup view-tree evaluation on every selection change.
    private(set) var flatFolderFilesByFolder: [String: [FlatFolderFile]] = [:]

    private func rebuildFileIndex() {
        var index: [String: FileTreeItem] = [:]
        var flatFiles: [String: [FlatFolderFile]] = [:]

        for item in openFiles { index[item.id] = item }
        for folder in rootFolders {
            var flat: [FlatFolderFile] = []
            collectFlatFiles(from: folder, depth: 0, into: &flat)
            flatFiles[folder.id] = flat
            for item in folder.allMarkdownFiles { index[item.id] = item }
        }
        fileIndex = index
        flatFolderFilesByFolder = flatFiles
    }

    private func collectFlatFiles(from item: FileTreeItem, depth: Int, into result: inout [FlatFolderFile]) {
        guard let children = item.children else { return }
        for child in children {
            if child.isDirectory {
                collectFlatFiles(from: child, depth: depth + 1, into: &result)
            } else {
                result.append(FlatFolderFile(item: child, depth: depth))
            }
        }
    }

    /// Phase 1 of file switching — lightweight preparation that runs
    /// synchronously inside `.onChange(of: selectedFileID)` to set
    /// currentFileURL immediately (matching preview behavior) and
    /// let the main thread process the next click event.
    func prepareFileSwitch(to id: String) {
        guard let item = fileIndex[id] else { return }
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil
        pendingOutlineWork?.cancel()
        pendingOutlineWork = nil
        generation &+= 1
        selectedFileURL = item.url
        currentFileURL = item.url
    }

    func selectFile(id: String) {
        // Note: saveCurrentFileIfDirty intentionally NOT called here to avoid
        // blocking the main thread during rapid file switching. The previous
        // file's dirty content is held in fileContents cache and saved when
        // the file is closed, the window is closed, or Cmd+S is pressed.
        guard let item = fileIndex[id] else { return }
        loadFileContent(url: item.url, id: item.id)
    }

    // MARK: - Shared file loading (cancellation-aware)

    private func loadFileContent(url: URL, id: String) {
        // Re-entrancy guard: setting selectedFileID below triggers
        // .onChange → selectFile → loadFileContent again on the same
        // call stack.  Return immediately so the second call is a no-op
        // and we avoid double file-reads and generation races.
        guard !isOpeningFile else { return }
        isOpeningFile = true
        defer { isOpeningFile = false }

        // Cancel any in-flight work for the previous file
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil
        pendingOutlineWork?.cancel()
        pendingOutlineWork = nil

        // Advance generation so stale async blocks discard results
        generation &+= 1
        let token = generation

        selectedFileURL = url
        currentFileURL = url

        // Try cache FIRST — in-memory content cache (zero disk IO) then HTML cache.
        let cacheKey = quickHashForCacheCheck(url: url)
        if let cachedContent = fileContents[url],
            fileSavedHashes[url] == cacheKey {
            // In-memory content cache hit — same content as on disk.
            // Zero IO: content was kept from previous load or edit.
            if let cached = htmlCache.object(forKey: url as NSURL),
               cachedContentHash[url] == cacheKey {
                lastSavedContent = cachedContent
                isFileDirty = false
                RunLoop.main.perform { [weak self] in
                    guard let self, selectedFileID == id else { return }
                    currentFileContent = cachedContent
                    renderedHTML = cached.html
                    renderedBodyHTML = cached.bodyHTML
                }
                return
            }
            if let cached = cachedHTML.value(for: url) {
                lastSavedContent = cachedContent
                isFileDirty = false
                RunLoop.main.perform { [weak self] in
                    guard let self, selectedFileID == id else { return }
                    currentFileContent = cachedContent
                    renderedHTML = cached.html
                    renderedBodyHTML = cached.bodyHTML
                }
                return
            }
            lastSavedContent = cachedContent
            isFileDirty = false
            RunLoop.main.perform { [weak self] in
                guard let self, selectedFileID == id else { return }
                currentFileContent = cachedContent
            }
            startAsyncHTMLGeneration(content: cachedContent, url: url, token: token, cacheKey: cacheKey)
            return
        }

        // Cache miss — read file on background, update content first, then HTML
        let isPreviewOnly = previewOnly
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let content = try FileService.readFile(at: url)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    cacheFileContent(content, for: url, cacheKey: cacheKey)
                    guard token == self.generation else { return }
                    lastSavedContent = content
                    isFileDirty = false
                    currentFileContent = content
                    if isPreviewOnly {
                        let escaped = content
                            .replacingOccurrences(of: "&", with: "&amp;")
                            .replacingOccurrences(of: "<", with: "&lt;")
                            .replacingOccurrences(of: ">", with: "&gt;")
                        renderedBodyHTML = "<pre>" + escaped + "</pre>"
                    }
                }

                let (bodyHTML, fullHTML) = MarkdownParser.parseToHTML(content)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let cached = CachedHTML(html: fullHTML, bodyHTML: bodyHTML)
                    htmlCache.setObject(cached, forKey: url as NSURL, cost: fullHTML.utf8.count)
                    cachedContentHash[url] = cacheKey
                    cacheRenderedHTML(cached, for: url)
                    guard token == self.generation else { return }
                    renderedHTML = fullHTML
                    renderedBodyHTML = bodyHTML
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
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
        isFileDirty = newContent != lastSavedContent

        // Only update cache on actual edits, not programmatic loads (file
        // switches) where loadFileContent already cached the content.
        if isFileDirty, let url = currentFileURL {
            let cacheKey = quickHashForCacheCheck(url: url)
            cacheFileContent(newContent, for: url, cacheKey: cacheKey)
        }

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
        outlineGeneration &+= 1
        let token = outlineGeneration
        pendingOutlineWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let headings = HeadingParser.parse(content)
            DispatchQueue.main.async {
                guard let self, token == self.outlineGeneration else { return }
                self.outlineHeadings = headings
            }
        }
        pendingOutlineWork = work
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    // MARK: - Save

    func saveCurrentFile() {
        guard let url = currentFileURL else { return }
        // Read clean markdown from the text storage (replaces \u{FFFC}
        // attachment chars with original markdown syntax).
        let content: String
        if let tv = viewRefs.textView, let storage = tv.textStorage {
            content = MarkdownTextView.Coordinator.buildCleanMarkdown(from: storage)
        } else {
            guard isFileDirty else { return }
            content = currentFileContent
        }
        do {
            try FileService.writeFile(content, to: url)
            lastSavedContent = content
            isFileDirty = false
            // Keep currentFileContent in sync
            currentFileContent = content
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
            cachedHTML.removeValue(for: evicted)
        }
    }

    /// Stores rendered HTML in the secondary LRU cache (survives NSCache purges).
    private func cacheRenderedHTML(_ cached: CachedHTML, for url: URL) {
        cachedHTML.set(cached, for: url)
    }

    // MARK: - File System Changes

    private func handleFileSystemChanges(rootFolderID: String, urls: [URL]) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        let folderURL = rootFolders[idx].url

        for url in urls {
            if !url.path.hasPrefix(folderURL.path + "/") && url.path != folderURL.path { continue }
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

    private func removeFileFromFolder(rootFolderID: String, url: URL) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        removeFileRecursively(from: &rootFolders[idx], url: url)
        rebuildFileIndex()
        htmlCache.removeObject(forKey: url as NSURL)
        cachedContentHash.removeValue(forKey: url)
        fileContents.removeValue(forKey: url)
        fileSavedHashes.removeValue(forKey: url)
        fileContentAccessOrder.removeAll { $0 == url }
        cachedHTML.removeValue(for: url)
        webViewCache.removeWebView(for: url)
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

    private func addFileToFolder(rootFolderID: String, url: URL) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        let existing = rootFolders[idx].allMarkdownFiles
        if existing.contains(where: { $0.url == url }) { return }

        let name = url.lastPathComponent
        let newFile = FileTreeItem(url: url, name: name, isDirectory: false, parentID: rootFolderID)

        insertInTree(root: &rootFolders[idx], item: newFile, url: url)
        rebuildFileIndex()
    }

    private func insertInTree(root: inout FileTreeItem, item: FileTreeItem, url: URL) {
        let parentURL = url.deletingLastPathComponent()
        if root.url == parentURL {
            root.children?.append(item)
            root.children?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return
        }
        guard var children = root.children else { return }
        for i in children.indices {
            if url.path.hasPrefix(children[i].url.path + "/") {
                insertInTree(root: &children[i], item: item, url: url)
                root.children = children
                return
            }
        }
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
        htmlCache.removeAllObjects()
        fileIndex.removeAll()
        selectedFileID = nil
        selectedFileURL = nil
        currentFileURL = nil
        currentFileContent = ""
        lastSavedContent = ""
        isFileDirty = false
        renderedHTML = ""
        renderedBodyHTML = ""
        outlinePanel?.close()
        outlinePanel = nil
        searchPanel?.close()
        searchPanel = nil
        windowSessionID = nil
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
            themeObserver = nil
        }
    }

    func promptExternalChange(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "File Changed Externally"
        alert.informativeText = "The file \"\(url.lastPathComponent)\" was modified by another application. Reload?"
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep Current")
        alert.alertStyle = .warning

        guard let window = viewRefs.textView?.window ?? NSApp.keyWindow else {
            if alert.runModal() == .alertFirstButtonReturn {
                reloadExternallyChangedFile(url: url)
            }
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.reloadExternallyChangedFile(url: url)
        }
    }

    private func reloadExternallyChangedFile(url: URL) {
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
