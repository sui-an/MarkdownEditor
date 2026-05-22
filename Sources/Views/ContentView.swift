import SwiftUI

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
    @AppStorage("previewOnly") private var previewOnly = false

    /// Stored in UserDefaults so sidebar visibility survives
    /// the 2-col / 3-col layout swap triggered by Preview Only.
    @AppStorage("sidebarVis") private var sidebarVis = 0

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { intToVis(sidebarVis) },
            set: { sidebarVis = visToInt($0) }
        )
    }

    var body: some View {
        Group {
            if previewOnly {
                NavigationSplitView(columnVisibility: columnVisibility) {
                    sidebarContent
                } detail: {
                    previewContent
                }
            } else {
                NavigationSplitView(columnVisibility: columnVisibility) {
                    sidebarContent
                } content: {
                    editorContent
                } detail: {
                    previewContent
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle(windowTitle)
        .environment(appState)
        .focusedSceneValue(\.currentAppState, appState)
        .toolbar(id: "main") {
            ToolbarItem(id: "previewToggle", placement: .primaryAction) {
                Button {
                    previewOnly.toggle()
                } label: {
                    Image(systemName: previewOnly
                          ? "doc.richtext"
                          : "doc.plaintext")
                }
                .help(previewOnly ? "Show Editor (⇧⌘P)" : "Preview Only (⇧⌘P)")
            }
        }
    }

    private var sidebarContent: some View {
        SidebarView()
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 400)
    }

    private var editorContent: some View {
        EditorContainerView()
            .frame(minWidth: 400, idealWidth: 1000)
    }

    private var previewContent: some View {
        PreviewWebView(
            html: appState.renderedHTML,
            hasFile: appState.currentFileURL != nil
        )
            .frame(minWidth: 250, idealWidth: 500)
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
