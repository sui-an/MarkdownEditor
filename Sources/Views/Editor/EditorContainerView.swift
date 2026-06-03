import SwiftUI

struct EditorContainerView: View {
    let appState: AppState
    var viewRefs: ViewRefs?
    var themeMode: String = "system"

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
            .opacity(appState.selectedFileID == nil ? 0 : 1)

            if appState.selectedFileID != nil && appState.isLoadingFile {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if appState.selectedFileID == nil {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No File Selected")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Open a .md file or folder to begin editing")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.none, value: appState.selectedFileID)
    }
}
