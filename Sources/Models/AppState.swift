import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

// MARK: - URL Helpers

extension URL {
    var isHTMLEditorFile: Bool {
        let ext = pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }
}

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
    var selectedDirectoryID: String?
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

    /// Set of directory URL paths that are collapsed in the sidebar.
    var collapsedFolderPaths: Set<String> = []

    var isCurrentFileHTML: Bool {
        currentFileURL?.isHTMLEditorFile ?? false
    }

    /// Returns true when the currently selected file still exists in the file index
    /// (i.e. was not removed by a folder removal or structural change).
    var isSelectedFileValid: Bool {
        guard let id = selectedFileID else { return false }
        return fileIndex[id] != nil
    }

    /// Consumer check: whether the content area should show file content.
    /// Returns false only when a file IS selected but its ID no longer exists in the index.
    var hasValidContent: Bool {
        guard currentFileURL != nil else { return false }
        if let id = selectedFileID, fileIndex[id] == nil { return false }
        return true
    }

    /// Returns true when the currently selected directory still exists in any
    /// remaining root folder tree.
    var isSelectedDirectoryValid: Bool {
        guard let id = selectedDirectoryID else { return false }
        return rootFolders.contains { folder in itemExists(id: id, in: folder) }
    }

    /// Recursively searches for an item by ID in a folder tree.
    private func itemExists(id: String, in item: FileTreeItem) -> Bool {
        if item.id == id { return true }
        guard let children = item.children else { return false }
        return children.contains { itemExists(id: id, in: $0) }
    }

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
    private var isRenaming = false

    /// Per-window WebView cache (replaces global singleton)
    let webViewCache = WebViewCache()

    // MARK: - In-memory file content cache

    /// All open file contents kept in memory so switching tabs requires zero disk IO.
    /// Populated by loadFileContent, updated by user edits, evicted on file close.
    private var fileContents: [URL: String] = [:]
    /// Maximum entries in fileContents — matches htmlCache countLimit.
    private let fileContentCacheLimit = 20

    // MARK: - Performance: HTML cache + operation cancellation

    /// LRU HTML cache keyed by file URL. NSCache handles eviction under memory pressure.
    private let htmlCache = NSCache<NSString, CachedHTML>()

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
        applyFontSizeToTextView(newSize)
    }

    private func changeFontSize(to size: CGFloat) {
        fontSize = size
        UserDefaults.standard.set(size, forKey: "editorFontSize")
        applyFontSizeToTextView(size)
    }

    private func applyFontSizeToTextView(_ size: CGFloat) {
        guard let tv = viewRefs.textView else { return }
        tv.font = NSFont.systemFont(ofSize: size)
        if let storage = tv.textStorage as? MarkdownTextStorage, storage.length > 0 {
            storage.baseFontSize = size
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
            storage.rehighlightAll(isDark: isDark)
        }
        tv.needsDisplay = true
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
        let ext = url.pathExtension.lowercased()
        guard FileService.isSupportedFileExtension(ext) else {
            let alert = NSAlert()
            alert.messageText = "Unsupported file type"
            alert.informativeText = "MarkdownEditor only supports .md and .html files."
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

    // MARK: - Reload File

    func reloadFile(id: String) {
        guard let item = openFiles.first(where: { $0.id == id }) else { return }
        let url = item.url

        guard FileManager.default.fileExists(atPath: url.path) else {
            let alert = NSAlert()
            alert.messageText = "File Not Found"
            alert.informativeText = "The file no longer exists on disk."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        evictFileFromAllCaches(url)

        do {
            let content = try FileService.readFile(at: url)
            let cacheKey = quickHashForCacheCheck(url: url)
            cacheFileContent(content, for: url, cacheKey: cacheKey)
            if selectedFileID == id {
                currentFileContent = content
                lastSavedContent = content
                isFileDirty = false
                regenerateHTML()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Reload File"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Close File

    func closeFile(id: String) {
        saveCurrentFileIfDirty()
        if let item = openFiles.first(where: { $0.id == id }) {
            evictFileFromAllCaches(item.url)
        }
        openFiles.removeAll { $0.id == id }
        fileIndex.removeValue(forKey: id)
        if selectedFileID == id {
            clearSelection()
        }
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

    // MARK: - Reload Folder

    func reloadFolder(id: String) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == id }) else { return }
        let folderURL = rootFolders[idx].url
        let oldFolder = rootFolders[idx]

        let savedCollapsed = collapsedFolderPaths

        guard let newRoot = try? FileService.scanDirectory(at: folderURL) else {
            let alert = NSAlert()
            alert.messageText = "Cannot Reload Folder"
            alert.informativeText = "Failed to read folder contents from disk."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let oldFiles = Set(oldFolder.allFiles.filter { !$0.isDirectory }.map { $0.url })
        let newFiles = Set(newRoot.allFiles.filter { !$0.isDirectory }.map { $0.url })
        for fileURL in oldFiles.subtracting(newFiles) {
            evictFileFromAllCaches(fileURL)
        }

        let updatedRoot = FileTreeItem(
            url: newRoot.url,
            name: newRoot.name,
            isDirectory: true,
            parentID: nil,
            children: newRoot.children
        )

        rootFolders[idx] = updatedRoot
        collapsedFolderPaths = savedCollapsed
        rebuildFileIndex()
    }

    // MARK: - Remove Folder

    func removeFolder(id: String) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == id }) else { return }

        let folder = rootFolders[idx]

        // Check whether the current selection falls inside the removed
        // folder, using BOTH the tree-based lookup (fast path) and a
        // URL-path-prefix fallback (handles files whose ids aren't in the
        // tree structure, e.g. files added by openFile after folder scan).
        let selectedWasInRemovedFolder: Bool
        if let id = selectedFileID {
            selectedWasInRemovedFolder = folder.containsFile(withID: id)
                || (currentFileURL?.path.hasPrefix(folder.url.path + "/") ?? false)
        } else if let url = currentFileURL {
            selectedWasInRemovedFolder = url.path.hasPrefix(folder.url.path + "/")
        } else {
            selectedWasInRemovedFolder = false
        }

        for file in folder.allFiles {
            evictFileFromAllCaches(file.url)
        }

        folderWatchers[id]?.stop()
        folderWatchers.removeValue(forKey: id)
        rootFolders.remove(at: idx)
        rebuildFileIndex()

        // Only clear content when the selected file was inside the removed folder.
        if selectedWasInRemovedFolder {
            currentFileURL = nil
            currentFileContent = ""
            lastSavedContent = ""
            isFileDirty = false
            pendingHTMLWork?.cancel()
            pendingHTMLWork = nil
            renderedHTML = ""
            renderedBodyHTML = ""
            selectedFileID = nil
        }
        if !isSelectedDirectoryValid {
            selectedDirectoryID = nil
        }
    }

    // MARK: - Rename Item

    func renameItem(id: String, newName: String) {
        guard !newName.isEmpty, !newName.contains("/"), !newName.contains(":") else { return }

        // Check fileIndex first (files), then search rootFolders tree (directories)
        var item = fileIndex[id]
        if item == nil {
            for folder in rootFolders {
                if let found = findItem(id: id, in: folder) {
                    item = found
                    break
                }
            }
        }
        guard let item else { return }
        let oldURL = item.url
        let parentURL = oldURL.deletingLastPathComponent()
        let newURL = parentURL.appendingPathComponent(newName)

        guard oldURL != newURL else { return }

        isRenaming = true
        defer { isRenaming = false }

        do {
            try FileService.renameItem(at: oldURL, to: newURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Rename"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let updatedChildren = item.children?.map { rebuidSubtree($0, oldParentURL: oldURL, newParentURL: newURL) }
        let updatedItem = FileTreeItem(url: newURL, name: newName, isDirectory: item.isDirectory, parentID: item.parentID, children: updatedChildren)

        // Update in rootFolders tree
        for idx in rootFolders.indices {
            if replaceInTree(root: &rootFolders[idx], oldURL: oldURL, new: updatedItem) {
                break
            }
        }

        // Update fileIndex
        fileIndex.removeValue(forKey: id)
        if item.isDirectory {
            // For directories, rebuild entire fileIndex from tree
            fileIndex.removeAll()
            for folder in rootFolders {
                for item in folder.allFiles where !item.isDirectory {
                    fileIndex[item.id] = item
                }
            }
            for item in openFiles {
                fileIndex[item.id] = item
            }
        } else {
            fileIndex[updatedItem.id] = updatedItem
        }

        // Update flatFolderFilesByFolder
        if item.isDirectory {
            // For directories, rebuild flat lists from the updated tree
            flatFolderFilesByFolder.removeAll()
            for rootFolder in rootFolders {
                var rootFlat: [FlatFolderFile] = []
                if !collapsedFolderPaths.contains(rootFolder.url.path) {
                    collectFlatFiles(from: rootFolder, depth: 0, into: &rootFlat, collapsedPaths: collapsedFolderPaths)
                }
                flatFolderFilesByFolder[rootFolder.id] = rootFlat
            }
        } else {
            // For files, targeted single-row replacement
            for (folderID, files) in flatFolderFilesByFolder {
                if let fileIdx = files.firstIndex(where: { $0.item.id == id }) {
                    var newFiles = files
                    newFiles[fileIdx] = FlatFolderFile(item: updatedItem, depth: files[fileIdx].depth)
                    flatFolderFilesByFolder[folderID] = newFiles
                    break
                }
            }
        }

        // Update openFiles if it's an opened individual file
        if let openIdx = openFiles.firstIndex(where: { $0.id == id }) {
            openFiles[openIdx] = updatedItem
        }

        // Update folderWatchers if this is a root folder
        if let watcher = folderWatchers.removeValue(forKey: id) {
            folderWatchers[updatedItem.id] = watcher
        }

        // If renamed item is currently open, update URL references without touching content
        if currentFileURL == oldURL {
            currentFileURL = newURL
            selectedFileURL = newURL
            selectedFileID = updatedItem.id
            // Migrate cache keys
            if let content = fileContents.removeValue(forKey: oldURL) {
                fileContents[newURL] = content
            }
            if let hash = cachedContentHash.removeValue(forKey: oldURL) {
                cachedContentHash[newURL] = hash
            }
            if let cached = htmlCache.object(forKey: oldURL.path as NSString) {
                htmlCache.removeObject(forKey: oldURL.path as NSString)
                htmlCache.setObject(cached, forKey: newURL.path as NSString, cost: cached.html.utf8.count)
            }
        } else {
            // Clean up caches for non-current renamed item
            evictFileFromAllCaches(oldURL)
        }

        // Update selectedDirectoryID if it was the renamed item
        if selectedDirectoryID == id {
            selectedDirectoryID = updatedItem.id
        }
    }

    /// Recursively replaces a FileTreeItem in the tree by matching oldURL.
    /// Returns true if the replacement was made.
    private func replaceInTree(root: inout FileTreeItem, oldURL: URL, new item: FileTreeItem) -> Bool {
        if root.url == oldURL {
            root = item
            return true
        }
        guard var children = root.children else { return false }
        for i in children.indices {
            if replaceInTree(root: &children[i], oldURL: oldURL, new: item) {
                root.children = children
                return true
            }
        }
        return false
    }

    /// Recursively finds a FileTreeItem by ID in the tree.
    private func findItem(id: String, in item: FileTreeItem) -> FileTreeItem? {
        if item.id == id { return item }
        guard let children = item.children else { return nil }
        for child in children {
            if let found = findItem(id: id, in: child) { return found }
        }
        return nil
    }

    /// Recursively rebuilds a subtree with updated parent URLs.
    private func rebuidSubtree(_ item: FileTreeItem, oldParentURL: URL, newParentURL: URL) -> FileTreeItem {
        let newURL = newParentURL.appendingPathComponent(item.name)
        let newChildren = item.children?.map { rebuidSubtree($0, oldParentURL: item.url, newParentURL: newURL) }
        return FileTreeItem(url: newURL, name: item.name, isDirectory: item.isDirectory, parentID: nil, children: newChildren)
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
            if !collapsedFolderPaths.contains(folder.url.path) {
                collectFlatFiles(from: folder, depth: 0, into: &flat, collapsedPaths: collapsedFolderPaths)
            }
            flatFiles[folder.id] = flat
            for item in folder.allFiles where !index.keys.contains(item.id) { index[item.id] = item }
        }
        fileIndex = index
        flatFolderFilesByFolder = flatFiles
    }

    /// Recursively flattens a directory tree into a list of files AND
    /// directories.  Directories are included so the sidebar can render
    /// collapse/expand controls at every level.  Children of a collapsed
    /// directory are skipped and do not appear in the result.
    private func collectFlatFiles(from item: FileTreeItem, depth: Int, into result: inout [FlatFolderFile], collapsedPaths: Set<String>) {
        guard let children = item.children else { return }
        for child in children {
            if child.isDirectory {
                result.append(FlatFolderFile(item: child, depth: depth))
                if !collapsedPaths.contains(child.url.path) {
                    collectFlatFiles(from: child, depth: depth + 1, into: &result, collapsedPaths: collapsedPaths)
                }
            } else {
                result.append(FlatFolderFile(item: child, depth: depth))
            }
        }
    }

    func toggleFolderCollapsed(_ path: String) {
        if collapsedFolderPaths.contains(path) {
            collapsedFolderPaths.remove(path)
        } else {
            collapsedFolderPaths.insert(path)
        }
        rebuildFileIndex()
    }

    /// Phase 1 of file switching — lightweight preparation that runs
    /// synchronously inside `.onChange(of: selectedFileID)` to cancel
    /// in-flight work and advance the generation counter so stale async
    /// results from the previous file are discarded.
    /// NOTE: currentFileURL is intentionally NOT set here — it must remain
    /// pointing to the old file so loadFileContent can detect type transitions
    /// (HTML ↔ markdown) and clear the preview accordingly.
    func prepareFileSwitch(to id: String) {
        guard let item = fileIndex[id] else { return }
        pendingHTMLWork?.cancel()
        pendingHTMLWork = nil
        pendingOutlineWork?.cancel()
        pendingOutlineWork = nil
        generation &+= 1
        selectedFileURL = item.url
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

        // Save old URL before overwriting, for type-transition detection.
        // Same-type transitions (markdown→markdown, HTML→HTML) can keep
        // the old renderedHTML visible until async generation completes,
        // avoiding a blank preview flash.  Different-type transitions
        // (HTML→markdown, markdown→HTML) must clear the preview to
        // prevent content-format leaking into the wrong template.
        let oldURL = currentFileURL
        let oldIsHTML = oldURL?.isHTMLEditorFile ?? false
        let newIsHTML = url.isHTMLEditorFile
        let typeChanged = oldIsHTML != newIsHTML

        selectedFileURL = url
        currentFileURL = url

        // Try cache FIRST — in-memory content cache (zero disk IO) then HTML cache.
        let cacheKey = quickHashForCacheCheck(url: url)
        if let cachedContent = fileContents[url],
            cachedContentHash[url] == cacheKey {
            // In-memory content cache hit — same content as on disk.
            // Zero IO: content was kept from previous load or edit.
            if let cached = htmlCache.object(forKey: url.path as NSString),
               cachedContentHash[url] == cacheKey {
                renderedHTML = cached.html
                renderedBodyHTML = cached.bodyHTML
                // Defer editor-side state to next cycle so the sidebar
                // highlight updates immediately (no same-cycle objectWillChange
                // cascade from currentFileContent dragging sidebar re-eval).
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    lastSavedContent = cachedContent
                    isFileDirty = false
                    currentFileContent = cachedContent
                }
                return
            }
            // Content cached but HTML not — clear preview only on type
            // transition to avoid stale-format leak, then generate async.
            if typeChanged {
                renderedHTML = ""
                renderedBodyHTML = ""
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.generation else { return }
                lastSavedContent = cachedContent
                isFileDirty = false
                currentFileContent = cachedContent
            }
            startAsyncHTMLGeneration(content: cachedContent, url: url, token: token, cacheKey: cacheKey)
            return
        }

        // Cache miss — clear stale preview only on TYPE TRANSITION.
        // Same-type transitions keep the old rendered content visible
        // (no flash) until the async disk-read + HTML generation completes.
        if typeChanged {
            renderedHTML = ""
            renderedBodyHTML = ""
        }
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

                if url.isHTMLEditorFile {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        guard token == self.generation else { return }
                        renderedHTML = content
                        renderedBodyHTML = content
                    }
                    return
                }

                let (bodyHTML, fullHTML) = MarkdownParser.parseToHTML(content)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let cached = CachedHTML(html: fullHTML, bodyHTML: bodyHTML)
                    htmlCache.setObject(cached, forKey: url.path as NSString, cost: fullHTML.utf8.count)
                    cachedContentHash[url] = cacheKey
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
        if url.isHTMLEditorFile {
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.generation else { return }
                renderedHTML = content
                renderedBodyHTML = content
            }
            return
        }
        let (bodyHTML, fullHTML) = MarkdownParser.parseToHTML(content)
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            let cached = CachedHTML(html: fullHTML, bodyHTML: bodyHTML)
            self.htmlCache.setObject(cached, forKey: url.path as NSString, cost: fullHTML.utf8.count)
            self.cachedContentHash[url] = cacheKey
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
            guard let self else { return }
            let isHTML = currentFileURL?.isHTMLEditorFile ?? false
            let headings = isHTML ? HeadingParser.parseHTML(content) : HeadingParser.parse(content)
            DispatchQueue.main.async {
                guard token == self.outlineGeneration else { return }
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
        if let tv = viewRefs.textView {
            if tv.string.contains("\u{FFFC}"), let storage = tv.textStorage {
                content = MarkdownTextView.Coordinator.buildCleanMarkdown(from: storage)
            } else {
                content = tv.string
            }
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
            cachedContentHash[url] = quickHashForCacheCheck(url: url)
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
        cachedContentHash[url] = cacheKey
        if fileContents.count > fileContentCacheLimit,
           let evicted = fileContents.keys.first {
            fileContents.removeValue(forKey: evicted)
            cachedContentHash.removeValue(forKey: evicted)
            htmlCache.removeObject(forKey: evicted.path as NSString)
        }
    }

    /// Evicts all cache entries for a given file URL.
    private func evictFileFromAllCaches(_ url: URL) {
        htmlCache.removeObject(forKey: url.path as NSString)
        cachedContentHash.removeValue(forKey: url)
        fileContents.removeValue(forKey: url)
    }

    // MARK: - File System Changes

    private func handleFileSystemChanges(rootFolderID: String, urls: [URL]) {
        guard !isRenaming else { return }
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        let folderURL = rootFolders[idx].url

        var didChange = false
        for url in urls {
            if !url.path.hasPrefix(folderURL.path + "/") && url.path != folderURL.path { continue }
            let ext = url.pathExtension.lowercased()

            if FileService.isSupportedFileExtension(ext) {
                let fm = FileManager.default
                if !fm.fileExists(atPath: url.path) {
                    removeFileFromFolder(rootFolderID: rootFolderID, url: url)
                    didChange = true
                } else {
                    addFileToFolder(rootFolderID: rootFolderID, url: url)
                    didChange = true
                }
            }

            if selectedFileURL == url {
                if FileManager.default.fileExists(atPath: url.path) {
                    let cacheKey = quickHashForCacheCheck(url: url)
                    if cachedContentHash[url] != cacheKey {
                        promptExternalChange(for: url)
                    }
                } else {
                    clearSelection()
                }
            }
        }
        if didChange { rebuildFileIndex() }
    }

    private func removeFileFromFolder(rootFolderID: String, url: URL) {
        guard let idx = rootFolders.firstIndex(where: { $0.id == rootFolderID }) else { return }
        removeFileRecursively(from: &rootFolders[idx], url: url)
        evictFileFromAllCaches(url)
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
        let existing = rootFolders[idx].allFiles
        if existing.contains(where: { $0.url == url }) { return }

        let name = url.lastPathComponent
        let parentURL = url.deletingLastPathComponent()
        let parentID = findParentID(in: rootFolders[idx], for: parentURL) ?? rootFolderID
        let newFile = FileTreeItem(url: url, name: name, isDirectory: false, parentID: parentID)

        insertInTree(root: &rootFolders[idx], item: newFile, url: url)
    }

    private func findParentID(in item: FileTreeItem, for url: URL) -> String? {
        if item.url == url { return item.id }
        guard let children = item.children else { return nil }
        for child in children where child.isDirectory {
            if let found = findParentID(in: child, for: url) { return found }
        }
        return nil
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
        cachedContentHash.removeAll()
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
        evictFileFromAllCaches(url)
        do {
            let content = try FileService.readFile(at: url)
            let cacheKey = quickHashForCacheCheck(url: url)
            cacheFileContent(content, for: url, cacheKey: cacheKey)
            currentFileContent = content
            lastSavedContent = content
            isFileDirty = false
            regenerateHTML()
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Reload Failed"
                alert.informativeText = "Could not reload \"\(url.lastPathComponent)\": \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
