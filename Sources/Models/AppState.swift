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

    private var folderWatchers: [UUID: FolderWatcher] = [:]
    private var selectedFileURL: URL?
    private var lastSavedContent: String = ""

    // MARK: - Open File

    func openFile(url: URL) {
        guard url.pathExtension.lowercased() == "md" else { return }

        if let existing = openFiles.first(where: { $0.url == url }) {
            selectFile(id: existing.id)
            return
        }

        do {
            let content = try FileService.readFile(at: url)
            let item = FileTreeItem(url: url, name: url.lastPathComponent, isDirectory: false, parentID: nil)
            openFiles.append(item)
            setCurrentFile(url: url, content: content, id: item.id)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Open File"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
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

        do {
            let content = try FileService.readFile(at: item.url)
            setCurrentFile(url: item.url, content: content, id: item.id)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Open File"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Content Updates

    func updateContent(_ newContent: String) {
        currentFileContent = newContent
        isFileDirty = newContent != lastSavedContent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.regenerateHTML()
        }
    }

    private func regenerateHTML() {
        let content = currentFileContent
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let html = MarkdownParser.parseToHTML(content)
            DispatchQueue.main.async {
                self?.renderedHTML = html
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

    private func setCurrentFile(url: URL, content: String, id: UUID) {
        saveCurrentFileIfDirty()
        selectedFileID = id
        selectedFileURL = url
        currentFileURL = url
        currentFileContent = content
        lastSavedContent = content
        isFileDirty = false
        regenerateHTML()
    }

    private func clearSelection() {
        saveCurrentFileIfDirty()
        selectedFileID = nil
        selectedFileURL = nil
        currentFileURL = nil
        currentFileContent = ""
        lastSavedContent = ""
        isFileDirty = false
        renderedHTML = ""
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
                currentFileContent = content
                lastSavedContent = content
                isFileDirty = false
                regenerateHTML()
            } catch {}
        }
    }
}
