import SwiftUI
import AppKit

private func visToInt(_ v: NavigationSplitViewVisibility) -> Int {
    switch v {
    case .detailOnly: return 3
    case .doubleColumn: return 2
    case .all: return 1
    case .automatic: return 0
    default: return 0
    }
}

private func intToVis(_ i: Int) -> NavigationSplitViewVisibility {
    switch i {
    case 1: return .all
    case 2: return .doubleColumn
    case 3: return .detailOnly
    default: return .automatic
    }
}

struct ContentView: View {
    @State private var appState = AppState()
    @State private var viewRefs = ViewRefs()
    @State private var didRestore = false
    @State private var savedSidebarVis = 0
    @AppStorage("previewOnly") private var previewOnly = false
    @State private var outlinePanel: OutlinePanelWindow?
    @State private var searchPanel: SearchPanelWindow?
    @State private var isTogglingOutline = false

    /// Stored in UserDefaults so sidebar visibility survives app restarts.
    @AppStorage("sidebarVis") private var sidebarVis = 0

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { intToVis(sidebarVis) },
            set: { sidebarVis = visToInt($0) }
        )
    }

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: columnVisibility) {
                sidebarContent
            } detail: {
                ResizableHSplitView(
                    minLeftWidth: 200,
                    minRightWidth: 200,
                    collapsed: previewOnly,
                    left: { editorContent },
                    right: { previewContent }
                )
            }
            .navigationSplitViewStyle(.prominentDetail)
            .navigationTitle(windowTitle)
            .environment(appState)
            .focusedSceneValue(\.currentAppState, appState)
            .onAppear {
                guard !didRestore else { return }
                didRestore = true
                if let url = SessionRestoreService.restoreLastOpened() {
                    appState.openFile(url: url)
                }
            }
            .onChange(of: appState.outlineHeadings) { _, headings in
                outlinePanel?.updateHeadings(headings)
            }
            .toolbar(id: "main") {
                ToolbarItem(id: "newNote", placement: .navigation) {
                    Button {
                        appState.createNewNote()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Note (⌘N)")
                }

                ToolbarItem(id: "outlineToggle", placement: .secondaryAction) {
                    if appState.selectedFileID != nil {
                        Button {
                            toggleOutline()
                        } label: {
                            Image(systemName: appState.isOutlineVisible
                                  ? "list.bullet.indent.fill"
                                  : "list.bullet.indent")
                        }
                        .help("Outline (⇧⌘O)")
                        .foregroundStyle(appState.isOutlineVisible ? Color.accentColor : .secondary)
                    }
                }

                ToolbarItem(id: "previewToggle", placement: .primaryAction) {
                    Button {
                        togglePreviewOnly()
                    } label: {
                        Image(systemName: previewOnly
                              ? "doc.richtext"
                              : "doc.plaintext")
                    }
                    .help(previewOnly ? "Show Editor (⇧⌘P)" : "Preview Only (⇧⌘P)")
                }
            }

            // Hidden keyboard shortcut handlers
            Button("") { toggleSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            if appState.selectedFileID != nil {
                Button("") { toggleOutline() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func toggleSearch() {
        appState.searchState.isVisible.toggle()
        if appState.searchState.isVisible {
            openSearchPanel()
        } else {
            closeSearchPanel()
        }
    }

    private func openSearchPanel() {
        closeSearchPanel()
        NSApp.activate(ignoringOtherApps: true)
        let panel = SearchPanelWindow(
            searchState: appState.searchState,
            textView: { [viewRefs] in viewRefs.textView },
            webView: { [viewRefs] in viewRefs.webView }
        )
        searchPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeSearchPanel() {
        searchPanel?.close()
        searchPanel = nil
    }

    private func toggleOutline() {
        guard appState.selectedFileID != nil, !isTogglingOutline else { return }
        isTogglingOutline = true
        if let panel = outlinePanel, panel.isVisible {
            // Hide existing panel without closing. Keeping the panel alive
            // avoids dealloc racing with SwiftUI internal dispatch sources
            // that hold references into the NSHostingView.
            panel.orderOut(nil)
            appState.isOutlineVisible = false
            // outlinePanel stays set — the panel is NOT deallocated
        } else if let panel = outlinePanel {
            panel.makeKeyAndOrderFront(nil)
            if panel.isVisible {
                panel.updateHeadings(appState.outlineHeadings)
                appState.isOutlineVisible = true
            } else {
                // Panel was closed by the user's close button — create a new one.
                // Defer the old panel's dealloc to avoid racing with SwiftUI
                // internal dispatch sources.
                appState.isOutlineVisible = true
                let oldPanel = outlinePanel
                outlinePanel = nil
                openOutlinePanel()
                DispatchQueue.main.async { [oldPanel] in
                    _ = oldPanel
                }
            }
        } else {
            appState.isOutlineVisible = true
            openOutlinePanel()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isTogglingOutline = false
        }
    }

    private func openOutlinePanel() {
        if let existing = outlinePanel {
            existing.updateHeadings(appState.outlineHeadings)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = OutlinePanelWindow(
            headings: appState.outlineHeadings,
            textView: { [viewRefs] in viewRefs.textView },
            webView: { [viewRefs] in viewRefs.webView },
            onClose: { [appState] in appState.isOutlineVisible = false }
        )
        outlinePanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func togglePreviewOnly() {
        if previewOnly {
            previewOnly = false
            // Restore sidebar without animation to avoid layout conflict
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                sidebarVis = savedSidebarVis
            }
        } else {
            savedSidebarVis = sidebarVis
            previewOnly = true
            // Hide sidebar without animation to avoid layout conflict
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                sidebarVis = visToInt(.detailOnly)
            }
        }
    }

    private var sidebarContent: some View {
        SidebarView()
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 400)
    }

    private var editorContent: some View {
        EditorContainerView(viewRefs: viewRefs)
    }

    private var previewContent: some View {
        PreviewWebView(
            html: appState.renderedHTML,
            bodyHTML: appState.renderedBodyHTML,
            hasFile: appState.currentFileURL != nil,
            baseURL: appState.currentFileURL?.deletingLastPathComponent(),
            fileURL: appState.currentFileURL,
            fileID: appState.selectedFileID,
            viewRefs: viewRefs
        )
            .frame(minWidth: 200)
    }

    private var windowTitle: String {
        if let url = appState.currentFileURL {
            let base = url.lastPathComponent
            if appState.isFileDirty && !previewOnly {
                return "\(base) — Edited"
            }
            return base
        }
        return "MarkdownEditor"
    }
}
