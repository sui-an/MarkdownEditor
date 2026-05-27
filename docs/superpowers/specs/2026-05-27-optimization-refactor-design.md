# MarkdownEditor 全面优化重构设计方案

## 目标

解决软件卡顿、冗余代码、内存占用、稳定性问题，添加过渡动画提升流畅度。

执行顺序：**性能 > 稳定性 > 内存 > 冗余代码 > 动画**

---

## 第一部分：性能优化

### 1.1 正则表达式预编译（最高优先级，影响最大）

**问题**: `MarkdownTextStorage.swift` 的 `applyHighlighting` 每次调用重新编译 8 个 `NSRegularExpression`，按键时 ~10次/秒。

**方案**: 将所有 regex 移到 `static let` 属性，类级别预编译一次。

修改文件: `Sources/Views/Editor/MarkdownTextStorage.swift`

具体改动:
- 在 `MarkdownTextStorage` 类顶部添加 8 个 `private static let` 正则属性
- `highlightHeaders`: `static let headerRegex`
- `highlightBlockquotes`: `static let blockquoteRegex`
- `highlightCodeBlocks`: `static let codeBlockRegex`
- `highlightInlinePatterns`: 5 个 static let（bold, italic, link, image, strikethrough）
- `highlightMermaidBlocks`: `static let mermaidBlockRegex`
- 所有方法内 `try? NSRegularExpression(pattern:)` 替换为引用 static 属性

### 1.2 行号绘制优化

**问题**: `LineNumberSideView.swift` 每次 draw 从字符位置 0 扫描到可见区域，大文件滚动卡顿。

**方案**: 缓存换行符位置数组，滚动时二分查找。

修改文件: `Sources/Views/Editor/LineNumberSideView.swift`

具体改动:
- 添加 `private var newlinePositions: [Int] = []` 和 `private var cachedTextLength: Int = 0`
- 添加 `func rebuildNewlineCache()` 方法，仅在文本变化时重建
- 添加 `private var cacheObserver: Any?` 监听 `NSText.didChangeNotification` 触发缓存重建
- `draw(_:)` 中用二分查找确定可见区域的起始行号
- `EditorWrapperView` 中 scroll observer 同时调用 `lineNumberView.needsDisplay = true`（已有）

### 1.3 文件树 allMarkdownFiles 缓存

**问题**: `FileTreeItem.allMarkdownFiles` 每次访问递归遍历整棵树，SidebarView 在每次 SwiftUI body 评估时调用。

**方案**: 在 `AppState` 中维护一个扁平的 `[URL]` 缓存，文件树变化时增量更新。

修改文件:
- `Sources/Models/FileTreeItem.swift` — 删除 `allMarkdownFiles` 计算属性
- `Sources/Models/AppState.swift` — 添加 `var flatMarkdownFiles: [URL] = []`，在 `rootFolders` 变化时（通过 `didSet`）重建缓存
- `Sources/Views/Sidebar/SidebarView.swift` — 使用 `appState.flatMarkdownFiles` 替代 `allMarkdownFiles`

### 1.4 FileService.scanDirectory 优化

**问题**: 构建文件树时 `children.firstIndex(where:)` 是 O(n) 线性查找，整体 O(n²)。

**方案**: 用 `[URL: Int]` 字典映射父节点 URL 到 children 数组索引。

修改文件: `Sources/Services/FileService.swift`

具体改动:
- `scanDirectory` 内部维护 `var parentIndexMap: [URL: Int] = [:]`
- 每次 append 后更新 map
- 查找父节点时用 O(1) 字典查找替代 O(n) 线性扫描

### 1.5 图片缩放异步化

**问题**: `processInlineImages` 中 `lockFocus()`/`unlockFocus()` 在主线程同步执行，大图片阻塞。

**方案**: 图片解码和缩放移到后台队列，完成后回主线程更新 textStorage。

修改文件: `Sources/Views/Editor/MarkdownTextView.swift`

具体改动:
- `processInlineImages` 中，图片加载 (`loadImage`) 和缩放移到 `DispatchQueue.global(qos: .userInitiated)`
- 后台完成缩放后 `DispatchQueue.main.async` 回主线程做 textStorage 替换
- 缓存写入在后台完成（NSCache 线程安全）

---

## 第二部分：稳定性

### 2.1 替换废弃的 OSAtomicIncrement64

**问题**: `AppState.swift` 使用已废弃的 `OSAtomicIncrement64`。

**方案**: 使用 `NSLock` 保护 generation 计数器。

修改文件: `Sources/Models/AppState.swift`

具体改动:
- 添加 `private let generationLock = NSLock()`
- `private var _generation: Int64 = 0`
- `var generation: Int64` 用 lock 保护的 get/set
- 删除 `import` 中对 `OSAtomicIncrement64` 的依赖（如果有）

### 2.2 修复搜索面板关闭逻辑

**问题**: `SearchPanelView.swift` 关闭时遍历 `NSApp.windows` 关闭所有 `SearchPanelWindow` 实例。

**方案**: 用 window identifier 精确匹配当前窗口。

修改文件: `Sources/Views/SearchPanelView.swift`

具体改动:
- 给 `SearchPanelWindow` 添加 identifier（如 `"SearchPanel_\(uuid)"`)
- `closePanel` 只关闭匹配当前 identifier 的窗口

### 2.3 消除危险的 force unwrap

**方案**: 将所有非安全的 `!` 替换为 `guard let` + `return`。

修改文件及位置:
- `LineNumberRulerView.swift:10` — 已废弃（删除文件），自动解决
- `PreviewWebView.swift:128` — 改为 `guard let state = states[...] else { return defaultValue }`

保留的安全 force unwrap（常量正则、类型转换）不做改动。

---

## 第三部分：内存优化

### 3.1 降低图片缓存上限

**方案**: `imageCache.totalCostLimit` 从 100MB 降到 50MB。

修改文件: `Sources/Views/Editor/MarkdownTextView.swift`
- 行 ~349: `cache.totalCostLimit = 50 * 1024 * 1024`

### 3.2 WebView 缓存缩减

**方案**: `WebViewCache.maxCount` 从 10 降到 5。

修改文件: `Sources/Views/Preview/PreviewWebView.swift`
- 大文件夹切换时少缓存 5 个 WebView，节省 ~18MB JS 内存

### 3.3 HTML 缓存简化

**方案**: 保留 NSCache 层（内存压力时自动淘汰），删除手动 Dictionary LRU 层。

修改文件: `Sources/Models/AppState.swift`
- 删除 `cachedHTML: [URL: CachedHTML]` 字典和 `CachedHTML` 结构体
- 只保留 `htmlCache: NSCache<NSURL, CachedHTMLObject>`，增大到 30 条
- `CachedHTMLObject` 同时存储 bodyHTML 和 fullHTML

---

## 第四部分：冗余代码清理

### 4.1 删除死代码

删除以下文件/代码:

| 目标 | 文件 | 行数 |
|------|------|------|
| `EditorScrollView` 类 | `MarkdownTextView.swift:80-164` | ~84 行 |
| `LineNumberRulerView` 文件 | `LineNumberRulerView.swift` | 97 行 |
| `readFileCached` | `FileService.swift:11-13` | 3 行 |
| `saveImage` + `ensureAssetsDirectory` + `relativePath` | `FileService.swift:88-128` | ~41 行 |
| `restoreImageAttachmentsToMarkdown` | `MarkdownTextView.swift` | ~7 行 |
| `parseToHTMLBody` | `MarkdownParser.swift:92-102` | ~11 行 |

从 `build.sh` SOURCES 中移除 `LineNumberRulerView.swift`。

### 4.2 合并重复的打开对话框代码

**方案**: 提取到 `FileService` 的静态方法中，两处调用方都引用。

修改文件:
- `Sources/Services/FileService.swift` — 添加 `static func openFileDialog()` 和 `static func openFolderDialog()`
- `Sources/MarkdownEditorApp.swift` — 调用 `FileService.openFileDialog()`
- `Sources/Views/Sidebar/SidebarView.swift` — 调用 `FileService.openFileDialog()`

---

## 第五部分：过渡动画

### 5.1 侧边栏/预览切换动画

修改文件: `Sources/Views/ContentView.swift`

具体改动:
- `togglePreviewOnly` 中移除 `Transaction(disablesAnimations: true)`，改为 `withAnimation(.easeInOut(duration: 0.25))`
- 侧边栏切换同理添加 `withAnimation`

### 5.2 分屏折叠/展开动画

修改文件: `Sources/Views/ResizableHSplitView.swift`

具体改动:
- `collapsed` 变化时用 `withAnimation(.easeInOut(duration: 0.2))` 包裹宽度变化
- 或使用 `.animation(.easeInOut, value: collapsed)` 修饰符

### 5.3 搜索/大纲面板弹出动画

修改文件: `Sources/Views/ContentView.swift`

具体改动:
- `openSearchPanel` / `openOutlinePanel`: `makeKeyAndOrderFront` 前设置 window.alphaValue = 0，然后 `NSAnimationContext.runAnimationGroup` 做 fade in
- `closeSearchPanel` / `closeOutlinePanel`: `NSAnimationContext.runAnimationGroup` 做 fade out，completion 中 `orderOut`

### 5.4 文件行选中动画

修改文件: `Sources/Views/Sidebar/FileRowView.swift`

具体改动:
- 背景色变化用 `.animation(.easeInOut(duration: 0.15), value: isSelected)` 包裹

### 5.5 编辑区占位文字淡入淡出

修改文件: `Sources/Views/Editor/MarkdownTextView.swift`

具体改动:
- `ImageDropTextView` 添加 `private var placeholderAlpha: CGFloat = 1.0`
- `draw(_:)` 中用 `NSAnimationContext` 控制 alpha 过渡
- 或改用 NSTextField 叠加在 textView 上层显示 placeholder，用 SwiftUI 动画控制显隐

---

## 修改文件汇总

| 文件 | 改动类型 |
|------|---------|
| `MarkdownTextStorage.swift` | 正则预编译 |
| `LineNumberSideView.swift` | 行号缓存优化 |
| `MarkdownTextView.swift` | 删除 EditorScrollView、图片异步化、降低缓存、删除死代码 |
| `LineNumberRulerView.swift` | 删除整个文件 |
| `AppState.swift` | OSAtomic 替换、HTML 缓存简化、flatMarkdownFiles 缓存 |
| `FileService.swift` | scanDirectory 优化、删除死代码、合并对话框代码 |
| `SidebarView.swift` | 使用 flatMarkdownFiles、调用 FileService 对话框 |
| `SearchPanelView.swift` | 修复关闭逻辑 |
| `ContentView.swift` | 添加过渡动画 |
| `ResizableHSplitView.swift` | 添加折叠动画 |
| `FileRowView.swift` | 选中动画 |
| `PreviewWebView.swift` | 缩减缓存、修复 force unwrap |
| `MarkdownParser.swift` | 静态化 mermaid 正则、删除 parseToHTMLBody |
| `MarkdownEditorApp.swift` | 调用 FileService 对话框 |
| `build.sh` | 移除 LineNumberRulerView.swift |

## 验证方案

### 性能验证
1. 打开一个 500+ 行的 markdown 文件，快速连续打字，观察是否卡顿
2. 滚动到长文档底部，观察行号绘制是否流畅
3. 在含多张图片的文档中编辑，观察是否卡顿

### 稳定性验证
1. 快速切换多个文档
2. 打开/关闭搜索面板多次
3. 切换侧边栏和预览面板

### 动画验证
1. 点击预览按钮 → 预览面板应平滑展开/收起
2. 点击搜索快捷键 → 面板应淡入淡出
3. 选择侧边栏文件 → 背景色有过渡

### 内存验证
1. 打开活动监视器，启动后基线内存
2. 切换 10+ 个文档后观察内存增长
3. 内存压力下 NSCache 应自动淘汰
