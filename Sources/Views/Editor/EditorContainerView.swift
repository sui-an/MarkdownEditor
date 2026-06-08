import SwiftUI

struct EditorContainerView: View {
    let appState: AppState
    var viewRefs: ViewRefs?
    var themeMode: String = "system"

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            if !appState.openFiles.isEmpty {
                FileTabBar(appState: appState)
            }

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
        }
        .animation(.none, value: appState.selectedFileID)
    }
}

// MARK: - File Tab Bar

private struct FileTabBar: View {
    let appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Tabs for individually opened files
                ForEach(appState.openFiles) { file in
                    FileTab(
                        name: file.name,
                        isSelected: appState.selectedFileID == file.id,
                        canClose: true,
                        onSelect: { appState.selectFile(id: file.id) },
                        onClose: { appState.closeFile(id: file.id) }
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .background(Color(.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}

private struct FileTab: View {
    let name: String
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 8)

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 4)
        .background(isSelected ? Color(.textBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
