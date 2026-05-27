# MarkdownEditor

A native macOS Markdown editor styled after Apple Notes, with live preview, syntax highlighting, Mermaid diagram support, and image drag-and-drop.

<img width="1512" height="859" alt="PixPin_2026-05-27_20-56-07" src="https://github.com/user-attachments/assets/aef8956a-4654-4a88-a6e8-f2efb854fa28" />

## Features

- **Three-pane layout** — Sidebar (file browser) | Editor (source) | Preview (rendered HTML)
- **Live preview** — Markdown renders in real time as you type; full HTML template with dark/light mode support
- **Syntax highlighting in editor** — Headers, bold, italic, code, links, blockquotes, strikethrough, and images highlighted inline via `NSTextStorage`
- **Mermaid diagrams** — ````mermaid``` blocks render as SVG diagrams in the preview using [Mermaid](https://mermaid.js.org/) (v10)
- **Code syntax highlighting in preview** — Fenced code blocks highlighted via [highlight.js](https://highlightjs.org/) (v11)
- **GFM rendering** — Tables, strikethrough, task lists, autolinks via [cmark-gfm](https://github.com/github/cmark-gfm) (with regex fallback when unavailable)
- **Image drag-and-drop / paste** — Drag images from Finder or paste from clipboard; embedded as base64 data URIs for self-contained `.md` files
- **File browser sidebar** — Browse all `.md` files in a folder recursively; pin frequently accessed files as individual tabs
- **Multi-window** — Cmd+Shift+N opens a new window, each with independent state
- **Session restore** — Last opened file is restored on next launch automatically
- **External change detection** — Prompts to reload when a file is modified by another app
- **Line numbers** — Gutter with efficient O(log n) newline-position cache for large files
- **Search & Replace** — Cmd+F opens floating search panel with match navigation (▲/▼) and replace support; works in both editor and preview-only mode
- **Outline panel** — Cmd+Shift+O shows a floating heading navigator; click to scroll to section in preview
- **Preview-only mode** — Hide the editor pane for distraction-free reading; search overlay available
- **Performance** — LRU caches for file content (20 entries) and rendered HTML (NSCache + secondary dictionary), cancellation-based async HTML generation, debounced preview updates
- **Apple Notes-like aesthetic** — Clean, minimal interface with system accent color

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (arm64) — Intel Macs are not currently supported

## Installation

### Download DMG

1. Download the latest `MarkdownEditor.dmg` from the [Releases](https://github.com/your-org/MarkdownEditor/releases) page
2. Open the DMG and drag `MarkdownEditor.app` into your `Applications` folder
3. Right-click `MarkdownEditor.app` and select **Open** (first launch only — Apple Gatekeeper may block unsigned apps)

> [!NOTE]
> The app is ad-hoc code-signed. On first launch, you may need to right-click → Open to bypass Gatekeeper.

### Build from source

```bash
# Clone the repository
git clone https://github.com/your-org/MarkdownEditor.git
cd MarkdownEditor

# (Optional) Install cmark-gfm for GFM table/strikethrough support
brew install cmark-gfm

# Build the .app bundle
bash build.sh

# (Optional) Package as DMG
bash package.sh
```

The built app will be at `MarkdownEditor.app` and the DMG at `MarkdownEditor.dmg` in the project root.

## Usage

| Action | Shortcut |
|--------|----------|
| Open File | `Cmd+O` |
| Open Folder | (Sidebar button) |
| New Window | `Cmd+Shift+N` |
| Save | `Cmd+S` |
| Search | `Cmd+F` |
| Toggle Outline | `Cmd+Shift+O` |
| Toggle Preview Only | (View menu) |

### Search & Replace

1. Press `Cmd+F` to open the floating search panel
2. Type your query — matches are highlighted in both editor and preview
3. Navigate with ▲/▼ buttons or `Enter`/`Shift+Enter`
4. Click **Replace** to expand the replace row
5. Use **Replace** or **Replace All** to modify text

### Mermaid Diagrams

````markdown
```mermaid
graph TD
    A-->B
    A-->C
    B-->D
    C-->D
```
````

Mermaid diagrams render as SVGs in the preview pane. No external setup required — Mermaid is bundled with the app.

### Images

Drag an image from Finder into the editor, or copy an image from another app and paste with `Cmd+V`. Images are embedded as base64 data URIs, keeping the `.md` file fully self-contained.

## Project Structure

```
MarkdownEditor/
├── Sources/
│   ├── MarkdownEditorApp.swift      # App entry, menu commands
│   ├── Models/
│   │   ├── AppState.swift           # Global state, caches, file operations
│   │   ├── FileTreeItem.swift       # File/directory tree model
│   │   ├── HeadingItem.swift        # Outline heading model
│   │   ├── SearchState.swift        # Search logic, match tracking
│   │   └── ViewRefs.swift           # Weak references to editor/preview views
│   ├── Services/
│   │   ├── FileService.swift        # File I/O, directory scanning
│   │   ├── FolderWatcher.swift      # FSEvents for external change detection
│   │   ├── HeadingParser.swift      # Markdown heading extraction
│   │   ├── ImageHandler.swift       # Image drag/paste → base64 data URI
│   │   ├── MarkdownParser.swift     # Markdown → HTML (cmark-gfm + regex fallback)
│   │   └── SessionRestoreService.swift  # Bookmark-based session persistence
│   ├── Views/
│   │   ├── ContentView.swift        # Root view, search/outline panel management
│   │   ├── InlineSearchView.swift   # Floating search panel (NSPanel)
│   │   ├── OutlinePanelView.swift   # Floating outline window
│   │   ├── ResizableHSplitView.swift # Custom split view between editor/preview
│   │   ├── Editor/
│   │   │   ├── EditorContainerView.swift  # Editor entry point
│   │   │   ├── LineNumberSideView.swift   # Efficient line number gutter
│   │   │   ├── MarkdownTextStorage.swift  # NSTextStorage with inline highlighting
│   │   │   └── MarkdownTextView.swift     # NSTextView subclass with image support
│   │   ├── Preview/
│   │   │   ├── PreviewWebView.swift       # WKWebView management + WebView cache
│   │   │   └── PreviewSearchOverlay.swift  # Preview-only search bar
│   │   └── Sidebar/
│   │       ├── FileRowView.swift          # File list item
│   │       ├── FolderHeaderView.swift     # Folder header with remove action
│   │       └── SidebarView.swift          # File browser sidebar
│   └── CCmarkGfm/
│       └── module.modulemap               # C interop module map for cmark-gfm
├── Resources/
│   ├── Assets.xcassets/                    # App icon assets
│   ├── mermaid.min.js                      # Mermaid rendering (3.2MB, bundled)
│   └── highlight.min.js                    # Code syntax highlighting (120KB, bundled)
├── build.sh                                # Build script (swiftc)
└── package.sh                              # DMG packaging script
```

## Architecture

### Build system

The project uses a plain `swiftc` invocation via `build.sh` rather than Xcode. This keeps the build fast and reproducible without requiring Xcode to be installed. An Xcode project can be generated via `generate_xcodeproj.rb` if needed.

```
build.sh → swiftc -O → .app bundle → codesign
```

### Rendering pipeline

```
User types in NSTextView
  → @Binding updates AppState.currentFileContent
    → onChange fires AppState.updateContent()
      → Debounced (200ms / 500ms for large files)
        → MarkdownParser.parseToHTML() on background queue
          → cmark-gfm (preferred) or regex fallback
            → PreviewWebView.updateBodyViaJS()
              → WKWebView sets innerHTML, re-runs hljs + mermaid
```

### Caching

- **File content**: LRU dictionary (20 entries), updated on edit, zero disk IO on file switch
- **Rendered HTML**: `NSCache` (memory-pressure aware, 30MB cost limit) + secondary LRU dictionary (survives NSCache eviction, 10 entries)
- **WebView**: Per-fileID WKWebView cache (10 entries), preserves scroll position and JS state across file switches
- **Cache invalidation**: Generation counter (`OSAtomicIncrement64`) cancels stale async computations when the user switches files faster than rendering completes

### Observability

The app uses Swift 5.9 `@Observable` macro for state management. No Combine or ObservableObject. Views automatically subscribe to observed properties through SwiftUI's observation framework.

## Dependencies

| Dependency | Version | Purpose | Bundled |
|-----------|---------|---------|---------|
| [cmark-gfm](https://github.com/github/cmark-gfm) | 0.29 | GFM Markdown → HTML | No (Homebrew) |
| [Mermaid](https://mermaid.js.org/) | 10 | Diagram rendering | Yes (3.2MB) |
| [highlight.js](https://highlightjs.org/) | 11.9 | Code syntax highlighting | Yes (120KB) |

> **cmark-gfm** is optional. The app falls back to a built-in regex parser when cmark-gfm is not installed. Table/strikethrough/tasklist rendering quality is reduced in fallback mode.

## Troubleshooting

### App won't open (Gatekeeper)

```bash
# Remove the quarantine attribute
xattr -d com.apple.quarantine /Applications/MarkdownEditor.app
```

### cmark-gfm not detected

```bash
brew install cmark-gfm
bash build.sh   # Rebuild — the script auto-detects Homebrew installations
```

Mermaid JS injection
```
Resources/
├── Info.plist
├── Assets.xcassets/AppIcon.appiconset/
└── mermaid.min.js         # Download separately (run download_mermaid.sh)
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+O | Open a `.md` file |
| Cmd+S | Save current file |
| Cmd+Shift+N | New window |
| Cmd+V | Paste (auto-detects images) |

## License

MIT
