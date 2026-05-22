import AppKit
import SwiftUI
import UniformTypeIdentifiers

let defaultMarkdown = """
# Welcome to MarkdownEditor

A native Markdown editor for macOS.

---

## Text Formatting

- **Bold** and *italic* text
- ~~Strikethrough~~ and ==highlight==
- `Inline code` and code blocks
- [Links](https://example.com)

## Code

```swift
func greet(name: String) -> String {
    return "Hello, \\(name)!"
}
```

## Blockquotes

> The best way to predict the future is to create it.
> — Peter Drucker

## Lists

1. First item
2. Second item
3. Third item

## Tables

| Feature | Status |
|---------|--------|
| Tables | ✅ |
| Task Lists | ✅ |
| Math | ✅ |

- [x] Completed task
- [ ] Pending task

## Math

Inline: $E = mc^2$

Display:

$$
\\\\sum_{n=1}^{\\\\infty} \\\\frac{1}{n^2} = \\\\frac{\\\\pi^2}{6}
$$

## Diagrams

```mermaid
flowchart LR
  A[Start] --> B[Process]
  B --> C[End]
```
"""

@MainActor
class DocumentController: ObservableObject {
    @Published var currentFile: URL?
    @Published var pendingContent: String?
    @Published var pendingClear: Bool = false
    @Published var workspaceURL: URL?
    @Published var workspaceFiles: [URL] = []
    @Published var workspaceSelectedFile: URL?

    private let defaults = UserDefaults.standard
    private let lastFileKey = "lastOpenedFilePath"
    private let lastWorkspaceKey = "lastWorkspacePath"

    /// Directory in Application Support where we keep a private copy of the last
    /// file content.  The app always has access to its own container, so reading
    /// this copy on relaunch never hits macOS permission issues.
    private var savedContentDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MarkdownEditor", isDirectory: true)
    }
    private var savedContentURL: URL {
        savedContentDir.appendingPathComponent("lastSession.md")
    }

    var fileName: String {
        currentFile?.lastPathComponent ?? "Untitled"
    }

    init() {
        restoreLastSession()
    }

    // MARK: - Last Session Persistence

    private func restoreLastSession() {
        if let workspacePath = defaults.string(forKey: lastWorkspaceKey) {
            let url = URL(fileURLWithPath: workspacePath)
            if FileManager.default.fileExists(atPath: workspacePath) {
                workspaceURL = url
                reloadWorkspaceFiles(url)
            }
        }

        if let filePath = defaults.string(forKey: lastFileKey) {
            let url = URL(fileURLWithPath: filePath)
            if FileManager.default.fileExists(atPath: filePath) {
                currentFile = url
                // Try the original file first.  On a normal relaunch within the
                // same login session the original file is usually accessible.
                // macOS 14+ may revoke NSOpenPanel temp access across runs —
                // in that case String(contentsOf:) silently fails and we fall
                // back to the private cache we kept in ~/Library/Application
                // Support.
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    pendingContent = content
                } else if let cachedContent = try? String(contentsOf: savedContentURL, encoding: .utf8) {
                    pendingContent = cachedContent
                }
            }
        }
    }

    /// Persists session metadata AND a private copy of the file content.
    /// The private copy is what gets read on the next launch so we don't depend
    /// on macOS temporary file-access grants from a previous NSOpenPanel call.
    private func saveLastSession(withContent content: String? = nil) {
        if let file = currentFile {
            defaults.set(file.path, forKey: lastFileKey)

            // Write the private content copy
            let text = content ?? pendingContent ?? (try? String(contentsOf: file, encoding: .utf8))
            if let text {
                try? FileManager.default.createDirectory(at: savedContentDir, withIntermediateDirectories: true)
                try? text.write(to: savedContentURL, atomically: true, encoding: .utf8)
            }
        } else {
            defaults.removeObject(forKey: lastFileKey)
            try? FileManager.default.removeItem(at: savedContentURL)
        }
        if let workspace = workspaceURL {
            defaults.set(workspace.path, forKey: lastWorkspaceKey)
        } else {
            defaults.removeObject(forKey: lastWorkspaceKey)
        }
    }

    private var newFileTask: Task<Void, Never>?

    func newFile() {
        guard newFileTask == nil else { return }
        currentFile = nil
        workspaceSelectedFile = nil
        pendingContent = nil
        pendingClear = true
        saveLastSession()
        newFileTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            newFileTask = nil
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Open Markdown File"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                self.currentFile = url
                self.pendingContent = content
                self.saveLastSession()
            }
        }
    }

    func saveFile(text: String) {
        guard let url = currentFile else {
            saveFileAs(text: text)
            return
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.createDirectory(at: savedContentDir, withIntermediateDirectories: true)
        try? text.write(to: savedContentURL, atomically: true, encoding: .utf8)
    }

    func saveFileAs(text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.title = "Save Markdown File"
        panel.nameFieldStringValue = currentFile?.lastPathComponent ?? "Untitled.md"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
            self.currentFile = url
            self.saveLastSession(withContent: text)
        }
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Open Folder"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.workspaceURL = url
            reloadWorkspaceFiles(url)
            if let first = workspaceFiles.first {
                selectFile(first)
            }
            saveLastSession()
        }
    }

    func selectFile(_ url: URL) {
        workspaceSelectedFile = url
        currentFile = url
        pendingContent = try? String(contentsOf: url, encoding: .utf8)
        saveLastSession()
    }

    private func reloadWorkspaceFiles(_ url: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else { return }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" || ext == "txt" {
                files.append(fileURL)
            }
        }
        workspaceFiles = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

struct DocumentControllerKey: FocusedValueKey {
    typealias Value = DocumentController
}

extension FocusedValues {
    var documentController: DocumentController? {
        get { self[DocumentControllerKey.self] }
        set { self[DocumentControllerKey.self] = newValue }
    }
}
