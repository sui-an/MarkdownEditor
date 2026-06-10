import SwiftUI

struct EditorContainerView: View {
    let appState: AppState
    var viewRefs: ViewRefs?
    var themeMode: String = "system"

    /// True when there is enough content to show the editor — prevents
    /// flashing stale content when state changes are batched by SwiftUI.
    private var showEditor: Bool {
        appState.hasValidContent
    }

    var body: some View {
        ZStack {
                MarkdownTextView(
                    text: Bindable(appState).currentFileContent,
                    currentFileURL: appState.currentFileURL,
                    viewRefs: viewRefs,
                    themeMode: themeMode,
                    fontSize: appState.fontSize,
                    onFontSizeChange: { delta in
                        appState.changeFontSize(by: delta)
                    }
                )
                .onChange(of: appState.currentFileContent) { _, newValue in
                    appState.updateContent(newValue)
                }
                .opacity(showEditor ? 1 : 0)

                if !showEditor {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No File Selected")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Open a .md or .html file to begin editing")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
        .animation(.none, value: appState.currentFileURL)
    }
}

