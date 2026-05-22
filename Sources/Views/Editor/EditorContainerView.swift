import SwiftUI

struct EditorContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.selectedFileID != nil {
            MarkdownTextView(
                text: Bindable(appState).currentFileContent,
                currentFileURL: appState.currentFileURL
            )
            .onChange(of: appState.currentFileContent) { _, newValue in
                appState.updateContent(newValue)
            }
        } else {
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
}
