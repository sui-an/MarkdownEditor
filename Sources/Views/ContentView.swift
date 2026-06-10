import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    let appState: AppState

    init(appState: AppState = AppState()) {
        self.appState = appState
    }

    @AppStorage("themeMode") private var themeMode: String = "system"

    private var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return NSApp.effectiveAppearance.name == .darkAqua ? .dark : .light
        }
    }

    private var widthIcon: String {
        switch appState.previewContentWidth {
        case 1: return "rectangle"
        case 2: return "rectangle.3.group"
        default: return "rectangle.dashed"
        }
    }

    private var widthHelp: String {
        switch appState.previewContentWidth {
        case 1: return "Full Width (⌘W)"
        case 2: return "Normal Width (⌘W)"
        default: return "Wide Width (⌘W)"
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { intToVis(appState.sidebarVis) },
            set: { appState.sidebarVis = visToInt($0) }
        )
    }

    var body: some View {
        let _ = appState.themeChangeCount
        ZStack {
            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView(appState: appState)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 400)
            } detail: {
                ResizableHSplitView(
                    minLeftWidth: 200,
                    minRightWidth: 200,
                    collapsed: appState.previewOnly,
                    left: EditorContainerView(appState: appState, viewRefs: appState.viewRefs, themeMode: themeMode),
                    right: PreviewWithFontSizeView(
                        appState: appState,
                        themeMode: themeMode,
                        webViewCache: appState.webViewCache
                    )
                    .frame(minWidth: 200)
                )
            }
            .navigationSplitViewStyle(.balanced)
            .navigationTitle(windowTitle)
            .animation(.none, value: appState.sidebarVis)
            .focusedSceneValue(\.currentAppState, appState)
            .onAppear {
                onViewAppear()
            }
            .onChange(of: appState.openFiles) { _, files in
                guard let id = appState.windowSessionID else { return }
                WindowSessionCoordinator.shared.update(
                    id: id,
                    files: files.map { $0.url }
                )
            }
            .onChange(of: themeMode) { _, _ in
                ThemeManager.shared.applyCurrentTheme()
            }
            .onDrop(of: [UTType.fileURL], isTargeted: .constant(false)) { providers in
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
                if let id = appState.windowSessionID {
                    WindowSessionCoordinator.shared.unregister(id)
                }
                appState.cleanup()
            }
            .preferredColorScheme(preferredColorScheme)
            .onChange(of: appState.outlineHeadings) { _, headings in
                appState.outlinePanel?.updateHeadings(headings)
            }
            .overlay(alignment: Alignment.top) {
                if appState.previewOnly && appState.showPreviewSearch {
                    PreviewSearchOverlay(
                        webView: { [appState] in appState.viewRefs.webView },
                        viewRefs: appState.viewRefs,
                        onClose: {
                            appState.showPreviewSearch = false
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.15), value: appState.showPreviewSearch)
                    .zIndex(100)
                }
            }
            .toolbar(id: "main") {
                ToolbarItem(id: "sidebarToggle", placement: .navigation) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            appState.sidebarVis = appState.sidebarVis == 3 ? 1 : 3
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Toggle Sidebar (⌘⌥S)")
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
                }

                if appState.previewOnly {
                    ToolbarItem(id: "contentWidthToggle", placement: .primaryAction) {
                        Button {
                            appState.previewContentWidth = (appState.previewContentWidth + 1) % 3
                        } label: {
                            Image(systemName: widthIcon)
                        }
                        .help(widthHelp)
                    }
                }

                ToolbarItem(id: "outlineToggle", placement: .primaryAction) {
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

                ToolbarItem(id: "previewToggle", placement: .primaryAction) {
                    Button {
                        togglePreviewOnly()
                    } label: {
                        Image(systemName: appState.previewOnly
                              ? "doc.richtext"
                              : "doc.plaintext")
                    }
                    .help(appState.previewOnly ? "Show Editor (⇧⌘P)" : "Preview Only (⇧⌘P)")
                }
            }

            // Hidden keyboard shortcut handlers
            Button("") {
                withAnimation(.easeInOut(duration: 0.22)) {
                    appState.sidebarVis = appState.sidebarVis == 3 ? 1 : 3
                }
            }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { toggleSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { appState.closeCurrentFile() }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { toggleContentWidth() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            if appState.previewOnly {
                Button("") { toggleOutline() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func onViewAppear() {
        ThemeManager.shared.applyCurrentTheme()
        if let appDelegate = NSApp.delegate as? AppDelegate,
           let window = NSApp.keyWindow {
            appDelegate.focusedAppState = appState
            objc_setAssociatedObject(
                window,
                &AppDelegate.focusedStateHandle,
                appState,
                .OBJC_ASSOCIATION_RETAIN
            )
        }

        let pending = FileOpenCoordinator.shared.claimFiles()
        if !pending.isEmpty {
            for url in pending {
                appState.openFile(url: url)
            }
        } else {
            let restored = SessionRestoreCoordinator.shared.claimNextFiles()
            for url in restored {
                appState.openFile(url: url)
            }
        }

        appState.windowSessionID = WindowSessionCoordinator.shared.register(
            files: appState.openFiles.map { $0.url }
        )
    }

    private func toggleSearch() {
        if appState.previewOnly {
            appState.showPreviewSearch = true
        } else {
            if appState.searchPanel?.isVisible == true {
                appState.searchPanel?.close()
                appState.searchPanel = nil
            } else {
                appState.searchPanel?.close()
                let panel = SearchPanel(
                    searchState: appState.searchState,
                    textView: { [appState] in appState.viewRefs.textView },
                    webView: { [appState] in appState.viewRefs.webView },
                    viewRefs: appState.viewRefs
                )
                appState.searchPanel = panel
            }
        }
    }

    private func toggleOutline() {
        guard appState.isSelectedFileValid else { return }
        if let panel = appState.outlinePanel, panel.isVisible {
            panel.orderOut(nil)
            appState.isOutlineVisible = false
        } else {
            appState.isOutlineVisible = true
            openOutlinePanel()
        }
    }

    private func openOutlinePanel() {
        let mainWindow = NSApp.keyWindow
        if let existing = appState.outlinePanel {
            existing.updateHeadings(appState.outlineHeadings)
            // Re-establish child window relationship so the panel stays
            // above the main window even after clicking the editor/preview.
            if let mainWindow {
                mainWindow.addChildWindow(existing, ordered: .above)
            }
            existing.orderFront(nil)
            return
        }
        let panel = OutlinePanelWindow(
            headings: appState.outlineHeadings,
            textView: { [appState] in appState.viewRefs.textView },
            webView: { [appState] in appState.viewRefs.webView },
            onClose: { [weak appState] in
                appState?.isOutlineVisible = false
                // Save panel frame for session persistence
                if let frame = appState?.outlinePanel?.frame {
                    UserDefaults.standard.set(NSStringFromRect(frame), forKey: "outlinePanelFrame")
                }
            }
        )
        appState.outlinePanel = panel
        if let mainWindow {
            mainWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    private func togglePreviewOnly() {
        appState.previewOnly.toggle()
    }

    private func toggleContentWidth() {
        appState.previewContentWidth = (appState.previewContentWidth + 1) % 3
    }

    private var windowTitle: String {
        if appState.isSelectedFileValid, let url = appState.currentFileURL {
            let base = url.lastPathComponent
            if appState.isFileDirty && !appState.previewOnly {
                return "\(base) — Edited"
            }
            return base
        }
        return "MarkdownEditor"
    }
}

// MARK: - Preview wrapper that isolates fontSize dependency
//
// Prevents ContentView.body from re-evaluating on every font-size change
// (which would diff the entire NavigationSplitView + sidebar unnecessarily).
private struct PreviewWithFontSizeView: View {
    let appState: AppState
    let themeMode: String
    let webViewCache: WebViewCache

    /// Only show the preview when there is actual rendered content —
    /// prevents flashing stale WebView content during file transitions.
    private var showPreview: Bool {
        guard appState.hasValidContent else { return false }
        return !appState.renderedHTML.isEmpty || !appState.renderedBodyHTML.isEmpty
    }

    var body: some View {
        PreviewWebView(
            html: appState.renderedHTML,
            bodyHTML: appState.renderedBodyHTML,
            hasFile: showPreview,
            baseURL: appState.currentFileURL?.deletingLastPathComponent(),
            fileURL: appState.currentFileURL,
            fileID: appState.currentFileURL?.absoluteString,
            isHTMLFile: appState.isCurrentFileHTML,
            viewRefs: appState.viewRefs,
            previewContentWidth: appState.previewContentWidth,
            themeMode: themeMode,
            fontSize: appState.fontSize,
            webViewCache: webViewCache
        )
    }
}
