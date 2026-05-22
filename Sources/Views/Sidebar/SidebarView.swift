import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: Bindable(appState).selectedFileID) {
            // Action buttons — like Notes compose button
            Section {
                SidebarActionButton(
                    icon: "doc.badge.plus",
                    label: "Open File",
                    action: openFileDialog
                )
                SidebarActionButton(
                    icon: "folder.badge.plus",
                    label: "Open Folder",
                    action: openFolderDialog
                )
            }

            // Opened individual files
            if !appState.openFiles.isEmpty {
                Section("Opened Files") {
                    ForEach(appState.openFiles) { item in
                        FileRowView(
                            item: item,
                            isSelected: appState.selectedFileID == item.id,
                            onSelect: { appState.selectFile(id: item.id) }
                        )
                        .contextMenu {
                            Button("Close") {
                                appState.openFiles.removeAll { $0.id == item.id }
                                if appState.selectedFileID == item.id {
                                    appState.saveCurrentFileIfDirty()
                                    appState.selectedFileID = nil
                                }
                            }
                        }
                    }
                }
            }

            // Folders
            ForEach(appState.rootFolders) { folder in
                Section {
                    FolderHeaderView(
                        folder: folder,
                        onRemove: { appState.removeFolder(id: folder.id) }
                    )
                } header: {
                    EmptyView()
                }

                ForEach(folder.allMarkdownFiles) { file in
                    FileRowView(
                        item: file,
                        isSelected: appState.selectedFileID == file.id,
                        onSelect: { appState.selectFile(id: file.id) }
                    )
                    .padding(.leading, 4)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Markdown File"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.openFile(url: url)
    }

    private func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.openFolder(url: url)
    }
}

// MARK: - Sidebar Action Button

private struct SidebarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
