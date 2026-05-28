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
    @AppStorage("previewOnly") private var previewOnly = false
    @AppStorage("previewContentWide") private var previewContentWide = false
    @AppStorage("themeMode") private var themeMode: String = "system"
    @State private var outlinePanel: OutlinePanelWindow?
    @State private var searchPanel: SearchPanel?
    @State private var showPreviewSearch = false

    /// Stored in UserDefaults so sidebar visibility survives app restarts.
    @AppStorage("sidebarVis") private var sidebarVis = 0

    private var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func applyAppearance() {
        switch themeMode {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }
    }

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
                applyAppearance()
                // Check for a file dropped on Dock during cold launch
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
                   let url = appDelegate.consumePendingFileURL() {
                    appState.openFile(url: url)
                }
                // Session restore — only on first appear, skip if Dock drop handled above
                guard !didRestore else { return }
                didRestore = true
                if let url = SessionRestoreService.restoreLastOpened() {
                    appState.openFile(url: url)
                }
            }
            .onChange(of: themeMode) { _, _ in
                applyAppearance()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
                if let url = notification.object as? URL {
                    appState.openFile(url: url)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                        if let nsurl = item as? NSURL {
                            DispatchQueue.main.async {
                                self.appState.openFile(url: nsurl as URL)
                            }
                        }
                    }
                }
                return true
            }
            .onDisappear {
                appState.cleanup()
            }
            .preferredColorScheme(preferredColorScheme)
            .onChange(of: appState.outlineHeadings) { _, headings in
                outlinePanel?.updateHeadings(headings)
            }
            .overlay(alignment: .top) {
                if previewOnly && showPreviewSearch {
                    PreviewSearchOverlay(
                        webView: { [viewRefs] in viewRefs.webView },
                        viewRefs: viewRefs,
                        onClose: {
                            showPreviewSearch = false
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.15), value: showPreviewSearch)
                    .zIndex(100)
                }
            }
            .toolbar(id: "main") {
                ToolbarItem(id: "sidebarToggle", placement: .navigation) {
                    Button {
                        sidebarVis = sidebarVis == 3 ? 1 : 3
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .help("Toggle Sidebar (⌘⌥S)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .padding(.leading, 12)
                }

                ToolbarItem(id: "newNote", placement: .navigation) {
                    Button {
                        appState.createNewNote()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .help("New Note (⌘N)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: 20)
                    .padding(.trailing, 36)
                }

                if previewOnly {
                    ToolbarItem(id: "contentWidthToggle", placement: .primaryAction) {
                        Button {
                            previewContentWide.toggle()
                        } label: {
                            Image(systemName: previewContentWide
                                  ? "rectangle.3.group"
                                  : "rectangle.dashed")
                        }
                        .help(previewContentWide ? "Normal Width (⌘W)" : "Widest Width (⌘W)")
                    }
                }

                ToolbarItem(id: "outlineToggle", placement: .primaryAction) {
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
                Button("") { toggleContentWidth() }
                    .keyboardShortcut("w", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            if previewOnly {
                Button("") { toggleOutline() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func toggleSearch() {
        if previewOnly {
            showPreviewSearch = true
        } else {
            if searchPanel?.isVisible == true {
                searchPanel?.close()
                searchPanel = nil
            } else {
                searchPanel?.close()
                let panel = SearchPanel(
                    searchState: appState.searchState,
                    textView: { [viewRefs] in viewRefs.textView },
                    webView: { [viewRefs] in viewRefs.webView },
                    viewRefs: viewRefs
                )
                searchPanel = panel
            }
        }
    }

    private func toggleOutline() {
        guard appState.selectedFileID != nil else { return }
        if let panel = outlinePanel, panel.isVisible {
            panel.orderOut(nil)
            appState.isOutlineVisible = false
        } else {
            appState.isOutlineVisible = true
            openOutlinePanel()
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
            onClose: { [weak appState] in appState?.isOutlineVisible = false }
        )
        outlinePanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func togglePreviewOnly() {
        previewOnly.toggle()
    }

    private func toggleContentWidth() {
        previewContentWide.toggle()
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
            viewRefs: viewRefs,
            previewContentWide: previewContentWide
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
