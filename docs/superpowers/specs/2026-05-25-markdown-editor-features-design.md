# MarkdownEditor: 5 Feature Enhancements

Date: 2026-05-25
Status: Approved

## Overview

Add 5 new features to the existing macOS MarkdownEditor app (SwiftUI + AppKit hybrid):

1. **Preview-Only Mode** — Polished distraction-free reading
2. **Session Restore** — Remember last opened document
3. **Markdown Outline View** — Floating heading-navigation panel
4. **New Note Creation** — In-app .md file creation
5. **Search & Replace** — Floating window, editor + preview

## Implementation Order

1. Feature 2 (Session Restore) — independent, foundational
2. Feature 4 (New Note) — independent, small
3. Feature 1 (Preview-Only polish) — touches ContentView
4. Feature 5 (Search & Replace) — medium complexity
5. Feature 3 (Outline View) — most complex, last

## Detailed Design

### Feature 1: Preview-Only Mode
- **Files changed**: `ContentView.swift`, `AppState.swift`
- Toggle `previewOnly` → auto-hide sidebar (`detailOnly` view visibility)
- Exit toggle → restore sidebar
- Keep toolbar button + ⇧⌘P shortcut

### Feature 2: Session Restore
- **Files**: `SessionRestoreService.swift` (new), `MarkdownEditorApp.swift`, `AppState.swift`
- On file open: save `url.bookmarkData()` to `UserDefaults`
- On launch: resolve bookmark → auto-open if file exists
- Silent fallback if file deleted

### Feature 3: Outline View (Floating Panel)
- **Files**: `HeadingParser.swift` (new), `HeadingItem.swift` (new), `OutlinePanelView.swift` (new), `MarkdownParser.swift` (mod), `AppState.swift` (mod), `ContentView.swift` (mod)
- Parse `^#{1,6}\s+(.+)$` per line → hierarchical tree
- Inject `id="heading-{slug}"` into HTML `<h1>`-`<h6>` in parser
- Floating NSWindow panel, opens from toolbar button
- Click → `scrollRangeToVisible` (editor) + `scrollIntoView` (preview)

### Feature 4: New Note
- **Files changed**: `SidebarView.swift`, `AppState.swift`
- "+" button at sidebar top
- `NSSavePanel` → create `.md` with default template
- Auto-open created file

### Feature 5: Search & Replace
- **Files**: `SearchState.swift` (new), `SearchPanelView.swift` (new), `MarkdownTextView.swift` (mod), `PreviewWebView.swift` (mod), `ContentView.swift` (mod), `AppState.swift` (mod)
- Floating NSWindow with find + replace fields
- Editor: `NSString` range search, temporary attribute highlights
- Preview: `WKWebView.find(from:...)` native highlights
- Cmd+F open, Esc close
