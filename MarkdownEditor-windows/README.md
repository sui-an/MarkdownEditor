# MarkdownEditor

A cross-platform Markdown editor for Windows, ported from the native macOS app. Built with Electron, CodeMirror 6, and Apple Notes-inspired design.

## Features

- **Three-pane layout** — Sidebar (file browser) | Editor | Live preview
- **Live Markdown preview** — Renders in real-time with GFM support
- **Mermaid diagrams** — Render ` ```mermaid ` blocks as SVG
- **Code syntax highlighting** — In-editor (CodeMirror) + preview (highlight.js)
- **File browser sidebar** — Recursive `.md` file tree, open/close files and folders
- **Multi-window** — Each window has independent state
- **Search** — Global search (Cmd+F) highlights matches in both editor and preview
- **Outline panel** — Floating heading navigator; click to scroll both panes
- **Preview-only mode** — Distraction-free reading with adjustable content width (720px / 960px / full)
- **Image drag & drop / paste** — Automatic base64 embedding
- **Themes** — System / Light / Dark modes
- **Session restore** — Reopens files from last session
- **External change detection** — Watches files for external modifications
- **Custom titlebar** — macOS-style traffic-light buttons + toolbar
- **Resizable panes** — Draggable dividers between all panels
- **Font size** — Adjustable (9px–72px) via keyboard shortcuts

## Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- npm

## Setup

```bash
git clone <repo-url>
cd MarkdownEditor-windows
npm install
```

## Development

Start the Vite dev server with HMR:

```bash
npm run dev
```

This opens an Electron window pointing to localhost:5173.

## Build

### Production build only (no packaging)

```bash
npm run build
```

Output goes to `.vite/build/`.

### Windows portable executable (.exe)

```bash
npm run package
```

Or use the shell script:

```bash
./build-win.sh
```

Output: `dist/MarkdownEditor-0.0.4.exe`

### Windows NSIS installer

```bash
npm run package:nsis
```

> Building for Windows from macOS is supported — electron-builder cross-compiles using Wine.

## Project Structure

```
src/
├── main/              # Electron main process
│   ├── index.ts       # App entry, BrowserWindow
│   ├── ipc-handlers.ts
│   ├── menu.ts        # Application menu
│   ├── file-watcher.ts
│   └── session-store.ts
├── preload/
│   └── index.ts       # contextBridge API
├── renderer/          # Frontend (Vite)
│   ├── app.ts         # Main orchestrator
│   ├── editor.ts      # CodeMirror 6 wrapper
│   ├── preview.ts     # iframe preview pane
│   ├── sidebar.ts     # File browser
│   ├── outline.ts     # Heading navigator
│   ├── state.ts       # State management
│   ├── theme.ts       # Light/dark/system
│   ├── markdown-parser.ts
│   ├── styles/        # CSS (theme, layout, components)
│   └── preview-assets/ # Injected into preview iframe
│       ├── preview.css
│       ├── mermaid.min.js
│       ├── highlight.min.js
│       └── search.js
└── shared/
    └── types.ts       # Shared interfaces
```

## Technologies

| Layer | Library |
|---|---|
| Desktop shell | Electron 33 |
| Build | Vite 6 + vite-plugin-electron |
| Editor | CodeMirror 6 |
| Markdown | marked 15 |
| Diagrams | Mermaid 10 |
| Preview highlight | highlight.js 11 |
| File watching | chokidar 3 |
| Session storage | electron-store 8 |
| Packaging | electron-builder 25 |
| Language | TypeScript 5 (strict) |

## macOS Original

This is an Electron port of the native macOS app at `../MarkdownEditor/` (Swift + SwiftUI + AppKit). The feature set is identical; the preview assets (Mermaid, highlight.js, CSS, search.js) and app icon are reused as-is.
