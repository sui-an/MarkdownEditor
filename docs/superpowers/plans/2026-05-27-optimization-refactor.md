# MarkdownEditor 全面优化重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解决卡顿、清理冗余、优化内存、提升稳定性、添加过渡动画

**Architecture:** 按性能 > 稳定性 > 内存 > 冗余代码 > 动画顺序，每个 task 独立可构建可测试

**Tech Stack:** Swift 5, SwiftUI, AppKit (NSTextView/NSView), NSRegularExpression, NSCache, NSAnimationContext

---

## 文件修改总览

| 文件 | 改动 |
|------|------|
| `MarkdownTextStorage.swift` | 正则预编译 |
| `LineNumberSideView.swift` | 行号缓存优化 |
| `FileTreeItem.swift` | 删除 allMarkdownFiles |
| `AppState.swift` | flatMarkdownFiles 缓存、OSAtomic 替换、HTML 缓存简化 |
| `FileService.swift` | scanDirectory 优化、删除死代码、合并对话框 |
| `SidebarView.swift` | 使用 flatMarkdownFiles、调用 FileService 对话框 |
| `MarkdownTextView.swift` | 删除 EditorScrollView、图片异步化、降低缓存 |
| `LineNumberRulerView.swift` | 删除整个文件 |
| `SearchPanelView.swift` | 修复关闭逻辑 |
| `PreviewWebView.swift` | 缩减缓存、修复 force unwrap |
| `MarkdownParser.swift` | 静态化 mermaid 正则、删除 parseToHTMLBody |
| `ContentView.swift` | 添加过渡动画 |
| `ResizableHSplitView.swift` | 添加折叠动画 |
| `FileRowView.swift` | 选中动画 |
| `MarkdownEditorApp.swift` | 调用 FileService 对话框 |
| `build.sh` | 移除 LineNumberRulerView.swift |

---

### Task 1: 正则表达式预编译（性能，最高优先级）

**Files:**
- Modify: `Sources/Views/Editor/MarkdownTextStorage.swift`

- [ ] **Step 1: 添加 static regex 属性**

在 `MarkdownTextStorage` 类内部、`suppressHighlighting` 属性下方添加：

```swift
// MARK: - Pre-compiled regex (compiled once, reused on every keystroke)

private static let headerRegex = try! NSRegularExpression(
    pattern: #"^(#{1,6})(?=\s)"#, options: .anchorsMatchLines
)
private static let blockquoteRegex = try! NSRegularExpression(
    pattern: #"^>\s.*$"#, options: .anchorsMatchLines
)
private static let codeBlockRegex = try! NSRegularExpression(
    pattern: #"```[\s\S]*?```"#, options: []
)
private static let boldRegex = try! NSRegularExpression(
    pattern: #"\*\*(.+?)\*\*"#, options: []
)
private static let italicRegex = try! NSRegularExpression(
    pattern: #"(\*|_)(.+?)\1"#, options: []
)
private static let linkRegex = try! NSRegularExpression(
    pattern: #"\[(.+?)\]\((.+?)\)"#, options: []
)
private static let imageRegex = try! NSRegularExpression(
    pattern: #"!\[(.+?)\]\((.+?)\)"#, options: []
)
private static let strikeRegex = try! NSRegularExpression(
    pattern: #"~~(.+?)~~"#, options: []
)
```

- [ ] **Step 2: 修改 highlightHeaders 方法**

替换 `highlightHeaders` 方法中动态编译的 regex 为静态引用：

```swift
private func highlightHeaders(in text: NSString, length: Int, range: NSRange? = nil) {
    let searchRange = range ?? NSRange(location: 0, length: length)
    for match in Self.headerRegex.matches(in: text as String, range: searchRange) {
        backingStore.addAttribute(.foregroundColor, value: HighlightColors.header, range: match.range)
    }
}
```

- [ ] **Step 3: 修改 highlightBlockquotes 方法**

```swift
private func highlightBlockquotes(in text: NSString, length: Int, range: NSRange? = nil) {
    let searchRange = range ?? NSRange(location: 0, length: length)
    for match in Self.blockquoteRegex.matches(in: text as String, range: searchRange) {
        backingStore.addAttribute(.foregroundColor, value: HighlightColors.quote, range: match.range)
    }
}
```

- [ ] **Step 4: 修改 highlightCodeBlocks 方法**

```swift
private func highlightCodeBlocks(in text: NSString, length: Int, range: NSRange? = nil) {
    let searchRange = range ?? NSRange(location: 0, length: length)
    for match in Self.codeBlockRegex.matches(in: text as String, range: searchRange) {
        backingStore.addAttribute(.foregroundColor, value: HighlightColors.code, range: match.range)
    }
}
```

- [ ] **Step 5: 修改 highlightInlinePatterns 方法**

将方法内 5 个动态 regex 替换为 `Self.boldRegex`、`Self.italicRegex`、`Self.linkRegex`、`Self.imageRegex`、`Self.strikeRegex`。

完整替换 `highlightInlinePatterns` 方法体为：

```swift
private func highlightInlinePatterns(in text: NSString, length: Int, range: NSRange? = nil) {
    let searchRange = range ?? NSRange(location: 0, length: length)

    for match in Self.boldRegex.matches(in: text as String, range: searchRange) {
        if match.range(at: 1).location != NSNotFound {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.bold, range: match.range(at: 1))
        }
    }
    for match in Self.italicRegex.matches(in: text as String, range: searchRange) {
        if match.range(at: 2).location != NSNotFound {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.italic, range: match.range(at: 2))
        }
    }
    for match in Self.linkRegex.matches(in: text as String, range: searchRange) {
        if match.range(at: 1).location != NSNotFound {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.link, range: match.range(at: 1))
        }
    }
    for match in Self.imageRegex.matches(in: text as String, range: searchRange) {
        if match.range(at: 1).location != NSNotFound {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.image, range: match.range(at: 1))
        }
    }
    for match in Self.strikeRegex.matches(in: text as String, range: searchRange) {
        if match.range(at: 1).location != NSNotFound {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.strike, range: match.range(at: 1))
        }
    }
}
```

- [ ] **Step 6: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```
Expected: 无 error 输出

- [ ] **Step 7: 提交**

```bash
git add Sources/Views/Editor/MarkdownTextStorage.swift
git commit -m "perf: pre-compile regex patterns in MarkdownTextStorage"
```

---

### Task 2: 行号绘制缓存优化（性能）

**Files:**
- Modify: `Sources/Views/Editor/LineNumberSideView.swift`

- [ ] **Step 1: 添加缓存属性和重建方法**

在 `LineNumberSideView` 类中添加：

```swift
private var newlinePositions: [Int] = []
private var cachedTextLength: Int = 0
private var textChangeObserver: Any?

init(textView: NSTextView) {
    self.textView = textView
    super.init(frame: .zero)
    textChangeObserver = NotificationCenter.default.addObserver(
        forName: NSText.didChangeNotification,
        object: textView,
        queue: .main
    ) { [weak self] _ in
        self?.invalidateNewlineCache()
    }
}

deinit {
    if let o = textChangeObserver { NotificationCenter.default.removeObserver(o) }
}

private func invalidateNewlineCache() {
    cachedTextLength = 0
    newlinePositions.removeAll()
    needsDisplay = true
}

private func ensureNewlineCache() {
    guard let textView = textView else { return }
    let text = textView.string as NSString
    let currentLength = text.length
    guard cachedTextLength != currentLength else { return }

    var positions: [Int] = []
    for i in 0..<currentLength {
        if text.character(at: i) == 0x0A {
            positions.append(i)
        }
    }
    newlinePositions = positions
    cachedTextLength = currentLength
}
```

- [ ] **Step 2: 重写 draw 方法使用缓存**

替换 `draw(_:)` 中的行号计算部分。将：

```swift
var lineNumber = 1
let scanEnd = min(charRange.location, textLength)
for i in 0..<scanEnd {
    if textContent.character(at: i) == 0x0A {
        lineNumber += 1
    }
}
```

替换为：

```swift
ensureNewlineCache()
// Binary search: find how many newline positions are before charRange.location
let lineNumber: Int
if charRange.location == 0 {
    lineNumber = 1
} else {
    var lo = 0, hi = newlinePositions.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if newlinePositions[mid] < charRange.location {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    lineNumber = lo + 1
}
```

- [ ] **Step 3: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 4: 提交**

```bash
git add Sources/Views/Editor/LineNumberSideView.swift
git commit -m "perf: cache newline positions with binary search in line number drawing"
```

---

### Task 3: 文件树 flatMarkdownFiles 缓存（性能）

**Files:**
- Modify: `Sources/Models/FileTreeItem.swift`
- Modify: `Sources/Models/AppState.swift`
- Modify: `Sources/Views/Sidebar/SidebarView.swift`

- [ ] **Step 1: FileTreeItem 添加扁平收集方法**

将 `FileTreeItem.swift` 中的 `allMarkdownFiles` 计算属性替换为静态方法：

```swift
// 删除: var allMarkdownFiles: [FileTreeItem] { ... }

// 新增静态方法:
static func collectMarkdownFiles(from item: FileTreeItem) -> [FileTreeItem] {
    guard item.isDirectory else { return [item] }
    return item.children?.flatMap { collectMarkdownFiles(from: $0) } ?? []
}
```

- [ ] **Step 2: AppState 添加 flatMarkdownFiles 缓存**

在 `AppState` 中 `rootFolders` 声明下方添加：

```swift
var rootFolders: [FileTreeItem] = [] {
    didSet { rebuildFlatFiles() }
}
var flatMarkdownFiles: [FileTreeItem] = []

private func rebuildFlatFiles() {
    flatMarkdownFiles = rootFolders.flatMap { FileTreeItem.collectMarkdownFiles(from: $0) }
}
```

- [ ] **Step 3: 替换 AppState 中 allMarkdownFiles 调用**

在 `AppState.swift` 中，将以下调用替换：

- `removeFolder` 中 `folder.allMarkdownFiles.map { $0.id }` → `flatMarkdownFiles.filter { ... }.map { $0.id }`（需要按 folder 过滤）
- `allAvailableFiles()` 中 `folder.allMarkdownFiles` → 遍历 folder 的 children，用 `FileTreeItem.collectMarkdownFiles`
- `addFileToFolder` 中 `rootFolders[idx].allMarkdownFiles` → `FileTreeItem.collectMarkdownFiles(from: rootFolders[idx])`

具体 `removeFolder` 替换：
```swift
// 旧: let fileIDs = folder.allMarkdownFiles.map { $0.id }
// 新:
let fileIDs = FileTreeItem.collectMarkdownFiles(from: folder).map { $0.id }
```

具体 `allAvailableFiles` 替换：
```swift
func allAvailableFiles() -> [FileTreeItem] {
    var all = openFiles
    for folder in rootFolders {
        all += FileTreeItem.collectMarkdownFiles(from: folder)
    }
    return all
}
```

`addFileToFolder` 替换：
```swift
// 旧: let existing = rootFolders[idx].allMarkdownFiles
// 新: let existing = FileTreeItem.collectMarkdownFiles(from: rootFolders[idx])

// 旧: let all = rootFolders[idx].allMarkdownFiles
// 新: let all = FileTreeItem.collectMarkdownFiles(from: rootFolders[idx])
```

`removeFolder` 的 cache 清理循环：
```swift
// 旧: for file in folder.allMarkdownFiles {
// 新: for file in FileTreeItem.collectMarkdownFiles(from: folder) {
```

- [ ] **Step 4: SidebarView 使用 flatMarkdownFiles**

在 `SidebarView.swift` 中将：

```swift
ForEach(folder.allMarkdownFiles) { file in
```

替换为：

```swift
ForEach(appState.flatMarkdownFiles.filter { file in
    // Show files that belong to this folder (by URL prefix)
    file.url.path.hasPrefix(folder.url.path)
}) { file in
```

- [ ] **Step 5: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 6: 提交**

```bash
git add Sources/Models/FileTreeItem.swift Sources/Models/AppState.swift Sources/Views/Sidebar/SidebarView.swift
git commit -m "perf: cache flat file list in AppState to avoid recursive tree traversal"
```

---

### Task 4: FileService.scanDirectory 优化（性能）

**Files:**
- Modify: `Sources/Services/FileService.swift`

- [ ] **Step 1: 用字典替代线性查找**

将 `scanDirectory` 方法中的两处 `children.firstIndex(where:)` 替换为字典查找。修改方法内部：

```swift
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
    // O(1) lookup: parent URL → index in children array
    var childIndexMap: [URL: Int] = [:]

    for case let fileURL as URL in enumerator {
        let parentURL = fileURL.deletingLastPathComponent()
        guard let parentItem = dirCache[parentURL] else { continue }

        let itemName = fileURL.lastPathComponent
        var isDir: ObjCBool = false
        fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)

        if isDir.boolValue {
            let dirItem = FileTreeItem(
                url: fileURL, name: itemName, isDirectory: true,
                parentID: parentItem.id, children: []
            )
            dirCache[fileURL] = dirItem

            if parentItem.url == url {
                children.append(dirItem)
                childIndexMap[fileURL] = children.count - 1
            } else if let idx = childIndexMap[parentItem.url] {
                children[idx].children?.append(dirItem)
            }
        } else if fileURL.pathExtension.lowercased() == "md" {
            let fileItem = FileTreeItem(
                url: fileURL, name: itemName, isDirectory: false,
                parentID: parentItem.id, children: nil
            )
            if parentItem.url == url {
                children.append(fileItem)
            } else if let idx = childIndexMap[parentItem.url] {
                children[idx].children?.append(fileItem)
            }
        }
    }

    root.children = children
    return root
}
```

- [ ] **Step 2: 删除死代码**

删除 `FileService.swift` 中以下未使用的方法：
- `readFileCached` (行 11-13)
- `ensureAssetsDirectory` (行 88-98)
- `saveImage` (行 100-109)
- `relativePath` (行 111-128)

同时删除不再使用的 `let components = relPath.components(separatedBy: "/")` 和 `var p = parentItem`。

- [ ] **Step 3: 合并重复对话框代码**

在 `FileService` 中添加：

```swift
static func openFileDialog(completion: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.plainText, .text]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.title = "Open Markdown File"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    DispatchQueue.main.async { completion(url) }
}

static func openFolderDialog(completion: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.title = "Open Folder"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    DispatchQueue.main.async { completion(url) }
}
```

- [ ] **Step 4: SidebarView 使用 FileService 对话框**

替换 `SidebarView.swift` 中的 `openFileDialog()` 和 `openFolderDialog()`：

```swift
private func openFileDialog() {
    FileService.openFileDialog { url in
        appState.openFile(url: url)
    }
}

private func openFolderDialog() {
    FileService.openFolderDialog { url in
        appState.openFolder(url: url)
    }
}
```

- [ ] **Step 5: MarkdownEditorApp 使用 FileService 对话框**

替换 `MarkdownEditorApp.swift` 中 `OpenFileCommand` 的 `openFileDialog()` 和 `OpenFolderCommand` 的 `openFolderDialog()`：

```swift
// OpenFileCommand
private func openFileDialog() {
    FileService.openFileDialog { url in
        appState?.openFile(url: url)
    }
}

// OpenFolderCommand
private func openFolderDialog() {
    FileService.openFolderDialog { url in
        appState?.openFolder(url: url)
    }
}
```

- [ ] **Step 6: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 7: 提交**

```bash
git add Sources/Services/FileService.swift Sources/Views/Sidebar/SidebarView.swift Sources/MarkdownEditorApp.swift
git commit -m "perf: optimize scanDirectory with dict lookup; extract shared dialog code to FileService; remove dead code"
```

---

### Task 5: 图片缩放异步化（性能）

**Files:**
- Modify: `Sources/Views/Editor/MarkdownTextView.swift`

- [ ] **Step 1: 将图片加载和缩放移到后台线程**

在 `processInlineImages` 方法中，将图片解码和缩放逻辑包裹到后台队列。将方法中从 `for match in matches.reversed()` 到 `textStorage.endEditing()` 之间的代码重构。

核心改动：在 `for match` 循环中，对于非缓存命中的图片，先在后台完成 `loadImage` 和缩放，再回主线程做 textStorage 替换。

实际改法：将整个 `processInlineImages` 的替换逻辑分为两阶段——先收集需要处理的 match 信息和图片数据（后台），再统一替换 textStorage（主线程）。

修改 `processInlineImages` 方法中 `guard !matches.isEmpty` 之后的代码为：

```swift
// Collect matches that need processing (not in cache)
var toProcess: [(NSRange, NSRange, String)] = []
for match in matches {
    let fullMatchRange = match.range(at: 0)
    let urlRange = match.range(at: 2)
    guard fullMatchRange.location != NSNotFound,
          urlRange.location != NSNotFound,
          urlRange.length > 0 else { continue }
    let urlStr = nsString.substring(with: urlRange)
    if Self.imageCache.object(forKey: urlStr as NSString) == nil {
        toProcess.append((fullMatchRange, urlRange, urlStr))
    }
}

guard !toProcess.isEmpty else {
    // All images in cache — do replacements on main thread directly
    performCachedReplacements(matches: matches, nsString: nsString, textStorage: textStorage)
    return
}

// Load and resize images on background thread
DispatchQueue.global(qos: .userInitiated).async {
    var processedImages: [String: NSImage] = [:]
    for (_, _, urlStr) in toProcess {
        guard let image = self.loadImage(from: urlStr) else { continue }
        var size = image.size
        let maxW: CGFloat = 400, maxH: CGFloat = 300
        if size.width > maxW || size.height > maxH {
            let scale = min(maxW / size.width, maxH / size.height)
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }
        if size.width < 20 { size.width = 20 }
        if size.height < 20 { size.height = 20 }

        let displayImage = NSImage(size: size)
        displayImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        displayImage.unlockFocus()

        Self.imageCache.setObject(displayImage, forKey: urlStr as NSString,
                                  cost: Int(size.width * size.height * 4))
        processedImages[urlStr] = displayImage
    }

    DispatchQueue.main.async {
        self.performCachedReplacements(matches: matches, nsString: nsString, textStorage: textStorage)
    }
}
```

同时提取 `performCachedReplacements` 方法（主线程上执行 textStorage 替换，复用现有逻辑）。

- [ ] **Step 2: 降低图片缓存上限**

在 `MarkdownTextView.swift` 的 Coordinator 类中，将 `imageCache` 的 `totalCostLimit` 从 `100 * 1024 * 1024` 改为 `50 * 1024 * 1024`。

- [ ] **Step 3: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 4: 提交**

```bash
git add Sources/Views/Editor/MarkdownTextView.swift
git commit -m "perf: move image loading/resizing to background thread; reduce image cache to 50MB"
```

---

### Task 6: 稳定性 — 替换 OSAtomic + 修复面板关闭 + 消除 force unwrap

**Files:**
- Modify: `Sources/Models/AppState.swift`
- Modify: `Sources/Views/SearchPanelView.swift`
- Modify: `Sources/Views/Preview/PreviewWebView.swift`

- [ ] **Step 1: 替换 OSAtomicIncrement64**

在 `AppState.swift` 中，将 `generation` 相关代码替换：

```swift
// 删除: private var generation: Int64 = 0

// 新增:
private let generationLock = NSLock()
private var _generation: Int64 = 0
private var generation: Int64 {
    get { generationLock.withLock { _generation } }
    set { generationLock.withLock { _generation = newValue } }
}
```

将 `loadFileContent` 中的：
```swift
let token = OSAtomicIncrement64(&generation)
```
替换为：
```swift
generationLock.lock()
_generation += 1
let token = _generation
generationLock.unlock()
```

- [ ] **Step 2: 修复 SearchPanelWindow 关闭逻辑**

在 `SearchPanelView.swift` 中，找到 `SearchPanelWindow` 类，在其 `init` 中添加 identifier：

```swift
// 在 SearchPanelWindow init 中添加:
self.identifier = NSUserInterfaceItemIdentifier("SearchPanel")
```

将 `closePanel` 方法中：
```swift
for win in NSApp.windows {
    if win is SearchPanelWindow {
        win.close()
    }
}
```
替换为：
```swift
// Close only this window, not all search panels
if let win = NSApp.windows.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("SearchPanel") }) {
    win.close()
}
```

- [ ] **Step 3: 消除 PreviewWebView force unwrap**

在 `PreviewWebView.swift` 的 `state(for:)` 方法中，将：

```swift
private func state(for webView: WKWebView) -> WebViewState {
    states[ObjectIdentifier(webView)]!
}
```

替换为：

```swift
private func state(for webView: WKWebView) -> WebViewState {
    guard let state = states[ObjectIdentifier(webView)] else {
        let state = WebViewState()
        states[ObjectIdentifier(webView)] = state
        return state
    }
    return state
}
```

- [ ] **Step 4: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 5: 提交**

```bash
git add Sources/Models/AppState.swift Sources/Views/SearchPanelView.swift Sources/Views/Preview/PreviewWebView.swift
git commit -m "fix: replace deprecated OSAtomicIncrement64 with NSLock; fix panel close logic; remove force unwrap"
```

---

### Task 7: 内存 — HTML 缓存简化 + WebView 缓存缩减

**Files:**
- Modify: `Sources/Models/AppState.swift`
- Modify: `Sources/Views/Preview/PreviewWebView.swift`

- [ ] **Step 1: 删除 AppState 中的二级 HTML 缓存**

在 `AppState.swift` 中删除以下属性：
```swift
// 删除:
private var cachedHTML: [URL: CachedHTML] = [:]
private var cachedHTMLAccessOrder: [URL] = []
private let cachedHTMLCacheLimit = 10
```

删除 `cacheRenderedHTML` 方法。

删除 `loadFileContent` 中的二级缓存查找：
```swift
// 删除这段:
if let cached = cachedHTML[url],
   cachedContentHash[url] == cacheKey {
    ...
    return
}
```

删除所有 `cachedHTML.removeValue` 和 `cachedHTMLAccessOrder.removeAll` 调用（在 `closeFile`、`removeFolder`、`cacheFileContent`、`removeFileFromFolder`、`cleanup` 中）。

删除 `CachedHTML` 类，将 `CachedHTMLObject` 改为 `NSCache` 值类型：

```swift
private final class CachedHTMLObject {
    let html: String
    let bodyHTML: String
    init(html: String, bodyHTML: String) {
        self.html = html
        self.bodyHTML = bodyHTML
    }
}
```

将 `htmlCache` 声明改为 `NSCache<NSURL, CachedHTMLObject>`，`countLimit` 增大到 30。

在 `generateAndCacheHTML` 中将 `CachedHTML(html:fullHTML, bodyHTML:bodyHTML)` 改为 `CachedHTMLObject(html:fullHTML, bodyHTML:bodyHTML)`。

- [ ] **Step 2: 缩减 WebView 缓存**

在 `PreviewWebView.swift` 中将 `maxEntries` 从 10 改为 5。

- [ ] **Step 3: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 4: 提交**

```bash
git add Sources/Models/AppState.swift Sources/Views/Preview/PreviewWebView.swift
git commit -m "perf: simplify HTML cache to single NSCache layer; reduce WebView cache to 5"
```

---

### Task 8: 删除死代码

**Files:**
- Modify: `Sources/Views/Editor/MarkdownTextView.swift`
- Delete: `Sources/Views/Editor/LineNumberRulerView.swift`
- Modify: `Sources/Services/MarkdownParser.swift`
- Modify: `build.sh`

- [ ] **Step 1: 删除 EditorScrollView**

在 `MarkdownTextView.swift` 中删除 `EditorScrollView` 类（从 `// MARK: - Scroll View that preserves...` 到类结束，约行 78-164）。

- [ ] **Step 2: 删除 restoreImageAttachmentsToMarkdown**

在 `MarkdownTextView.swift` 的 Coordinator 中删除 `restoreImageAttachmentsToMarkdown` 方法。

- [ ] **Step 3: 删除 LineNumberRulerView 文件**

```bash
rm Sources/Views/Editor/LineNumberRulerView.swift
```

- [ ] **Step 4: 从 build.sh 移除 LineNumberRulerView.swift**

删除 `build.sh` SOURCES 数组中的 `"$PROJECT_DIR/Sources/Views/Editor/LineNumberRulerView.swift"` 行。

- [ ] **Step 5: 删除 MarkdownParser.parseToHTMLBody**

在 `MarkdownParser.swift` 中删除 `parseToHTMLBody` 方法（约行 91-102）。

- [ ] **Step 6: 静态化 mermaid 正则**

在 `MarkdownParser.swift` 中，将 `extractMermaidBlocks` 中的动态 regex 替换为 static 属性：

```swift
// 在 base64ImageRegex 之后添加:
private static let mermaidBlockRegex = try! NSRegularExpression(
    pattern: #"```mermaid\s*\n([\s\S]*?)```"#,
    options: .caseInsensitive
)
```

将 `extractMermaidBlocks` 中的：
```swift
let pattern = try! NSRegularExpression(
    pattern: #"```mermaid\s*\n([\s\S]*?)```"#,
    options: .caseInsensitive
)
```
替换为：
```swift
let pattern = Self.mermaidBlockRegex
```

- [ ] **Step 7: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "chore: remove dead code (EditorScrollView, LineNumberRulerView, parseToHTMLBody); static-compile mermaid regex"
```

---

### Task 9: 过渡动画

**Files:**
- Modify: `Sources/Views/ContentView.swift`
- Modify: `Sources/Views/ResizableHSplitView.swift`
- Modify: `Sources/Views/Sidebar/FileRowView.swift`

- [ ] **Step 1: 侧边栏/预览切换动画**

修改 `ContentView.swift` 中的 `togglePreviewOnly()` 方法：

```swift
private func togglePreviewOnly() {
    withAnimation(.easeInOut(duration: 0.25)) {
        if previewOnly {
            previewOnly = false
            sidebarVis = savedSidebarVis
        } else {
            savedSidebarVis = sidebarVis
            previewOnly = true
            sidebarVis = visToInt(.detailOnly)
        }
    }
}
```

- [ ] **Step 2: 分屏折叠/展开动画**

修改 `ResizableHSplitView.swift`，在 `body` 中给 `clampedLeft` 和 `rightW` 的 frame 添加动画修饰符。在 `HStack` 的 `left` view 后添加：

```swift
left
    .frame(width: clampedLeft)
    .clipped()
    .animation(.easeInOut(duration: 0.2), value: collapsed)
```

- [ ] **Step 3: 搜索/大纲面板弹出动画**

修改 `ContentView.swift` 中的 `openSearchPanel`、`closeSearchPanel`、`openOutlinePanel`、`toggleOutline`：

```swift
private func openSearchPanel() {
    closeSearchPanel()
    NSApp.activate(ignoringOtherApps: true)
    let panel = SearchPanelWindow(
        searchState: appState.searchState,
        textView: { [viewRefs] in viewRefs.textView },
        webView: { [viewRefs] in viewRefs.webView }
    )
    searchPanel = panel
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        panel.animator().alphaValue = 1
    }
}

private func closeSearchPanel() {
    guard let panel = searchPanel else { return }
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.12
        panel.animator().alphaValue = 0
    }, completionHandler: {
        panel.close()
    })
    searchPanel = nil
}

private func openOutlinePanel() {
    if let existing = outlinePanel {
        existing.updateHeadings(appState.outlineHeadings)
        existing.alphaValue = 0
        existing.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            existing.animator().alphaValue = 1
        }
        return
    }
    let panel = OutlinePanelWindow(
        headings: appState.outlineHeadings,
        textView: { [viewRefs] in viewRefs.textView },
        webView: { [viewRefs] in viewRefs.webView },
        onClose: { [weak appState] in appState?.isOutlineVisible = false }
    )
    outlinePanel = panel
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        panel.animator().alphaValue = 1
    }
}

// 在 toggleOutline 的 orderOut 处改为:
private func toggleOutline() {
    guard appState.selectedFileID != nil else { return }
    if let panel = outlinePanel, panel.isVisible {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        appState.isOutlineVisible = false
    } else {
        appState.isOutlineVisible = true
        openOutlinePanel()
    }
}
```

- [ ] **Step 4: 文件行选中动画**

修改 `FileRowView.swift`：

```swift
.background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
.clipShape(RoundedRectangle(cornerRadius: 4))
.animation(.easeInOut(duration: 0.15), value: isSelected)
```

- [ ] **Step 5: 构建验证**

```bash
bash build.sh 2>&1 | grep -i error
```

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat: add transition animations for sidebar, split view, panels, and file selection"
```

---

## 构建和验证

每完成一个 Task 后执行：

```bash
# 构建
bash build.sh 2>&1

# 启动测试
open MarkdownEditor.app
```

## 完成后总验证

1. **性能**: 在 500+ 行文档中快速打字，无卡顿；快速滚动，行号流畅
2. **稳定性**: 快速切换 10+ 文档；打开/关闭搜索面板 20 次
3. **内存**: 活动监视器中观察基线内存和切换后的增长
4. **动画**: 预览切换、面板弹出、文件选中均有平滑过渡
