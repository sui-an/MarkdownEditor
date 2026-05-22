# MarkdownEditor

A macOS-native Markdown editor styled after Apple Notes, with live preview, syntax highlighting, Mermaid diagram support, and image drag-and-drop.

## Features

- **Three-pane layout** — Sidebar (file browser) | Editor (source) | Preview (rendered HTML)
- **Live preview** — Markdown renders in real time as you type
- **Syntax highlighting** — Headers, bold, italic, code, links, blockquotes, and more
- **Mermaid diagrams** — ````mermaid` blocks render as SVG diagrams in the preview
- **Image drag-and-drop / paste** — Drag images from Finder or paste from clipboard; saved to an `assets/` folder next to the markdown file
- **Open folders** — Browse all `.md` files in a folder recursively; remove folders from the sidebar at any time
- **Multi‑window** — Cmd+Shift+N opens a new window, each with independent state
- **External change detection** — Prompts to reload when a file is modified by another app
- **Line numbers** — Gutter with line numbers in the editor
- **Dark mode** — Preview and UI follow the system appearance

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.4 or later

## Build & Run

```bash
# 1. Download the Mermaid library (optional, for diagram rendering)
bash download_mermaid.sh

# 2. Open the project in Xcode
open MarkdownEditor.xcodeproj

# 3. Press Cmd+R to build and run
```

## Project Structure

```
Sources/
├── MarkdownEditorApp.swift          # @main entry, multi-window, menu commands
├── Models/
│   ├── AppState.swift               # Central state (@Observable), per-window instance
│   └── FileTreeItem.swift           # File/folder tree node model
├── Services/
│   ├── FileService.swift            # File I/O, directory scanning, image save
│   ├── MarkdownParser.swift         # Markdown → HTML, Mermaid block rewriting
│   ├── ImageHandler.swift           # Drag/paste image → assets/ → ![]() syntax
│   └── FolderWatcher.swift          # FSEvents-based external change monitoring
├── Views/
│   ├── ContentView.swift            # NavigationSplitView three-pane shell
│   ├── Sidebar/
│   │   ├── SidebarView.swift        # File browser (opened files + folder trees)
│   │   ├── FileRowView.swift        # Single file row
│   │   └── FolderHeaderView.swift   # Folder section header with remove button
│   ├── Editor/
│   │   ├── EditorContainerView.swift     # Empty-state / editor switch
│   │   ├── MarkdownTextView.swift        # NSTextView + image drop/paste handling
│   │   ├── MarkdownTextStorage.swift     # Debounced regex syntax highlighting
│   │   └── LineNumberRulerView.swift     # Line number gutter
│   └── Preview/
│       └── PreviewWebView.swift          # WKWebView + Mermaid JS injection
Resources/
├── Info.plist
├── Assets.xcassets/AppIcon.appiconset/
└── mermaid.min.js                   # Download separately (run download_mermaid.sh)
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
