import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            EditorContainerView()
                .frame(minWidth: 200)
        } detail: {
            PreviewWebView(
                html: appState.renderedHTML,
                hasFile: appState.currentFileURL != nil
            )
                .frame(minWidth: 150)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle(windowTitle)
        .environment(appState)
        .focusedSceneValue(\.currentAppState, appState)
    }

    private var windowTitle: String {
        if let url = appState.currentFileURL {
            if appState.isFileDirty {
                return "\(url.lastPathComponent) — Edited"
            }
            return url.lastPathComponent
        }
        return "MarkdownEditor"
    }
}
