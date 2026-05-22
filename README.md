# MarkdownEditor

A native macOS Markdown editor with live preview, KaTeX math, Mermaid diagrams, and syntax highlighting.

Built with SwiftUI + AppKit, compiled entirely without Xcode.

## Features

- **Live preview** — WebKit-based rendered preview with KaTeX, Mermaid, and Prism.js
- **Split view** — Side-by-side editor and preview, toggleable
- **Find** — Cmd+F in editor (native NSTextFinder) or preview (JS `window.find()`)
- **Outline panel** — Auto-generated heading navigation, click to scroll editor & preview
- **File management** — Open individual `.md` files or entire folders as workspaces
- **Auto-save** — 1-second debounced save when a file is open
- **Lock protection** — Prevents accidental edits
- **Statistics** — Lines, words, characters, UTF-8 encoding in status bar
- **App icon** — Custom icon with Markdown `#` symbol

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (arm64) — can be cross-compiled for Intel

## Build & Run

```bash
./build.sh
open build/MarkdownEditor.app
```

The build script compiles all Swift files, bundles the icon into `.app`, and generates a proper `Info.plist`.

## Project Structure

```
MarkdownEditor/
├── Sources/MarkdownEditor/
│   ├── App.swift              # App lifecycle, menu commands, find actions
│   ├── DocumentController.swift # File open/save, workspace management
│   ├── AST.swift              # Markdown AST types
│   ├── Parser.swift           # Markdown → AST parser
│   ├── HTMLRenderer.swift     # AST → HTML with KaTeX/Mermaid/Prism
│   ├── TraceLog.swift         # Debug logging utility
│   └── Views/
│       ├── SplitView.swift     # Main layout, toolbar, outline, status bar
│       ├── Editor/
│       │   └── EditorView.swift    # NSTextView-based editor
│       └── Preview/
│           └── WebPreviewView.swift  # WKWebView preview with find
├── MarkdownEditor.icns        # App icon
├── build.sh                   # Build script
└── .gitignore
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+O` | Open file |
| `Cmd+Shift+O` | Open folder |
| `Cmd+S` | Save |
| `Cmd+Shift+S` | Save As… |
| `Cmd+F` | Find (routed to editor or preview by focus) |
| `Cmd+G` | Find next |
| `Cmd+Shift+G` | Find previous |
| `Cmd+Shift+E` | Toggle editor pane |

## macOS Notes‑Style Titlebar

The app uses SwiftUI's `.windowStyle(.hiddenTitleBar)`, giving the toolbar a transparent background with frosted-glass vibrancy — matching the look of Apple Notes. The filename is displayed in the toolbar center.

## License

MIT
