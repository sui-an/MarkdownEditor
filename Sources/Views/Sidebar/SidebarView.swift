import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
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
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            List(selection: Bindable(appState).selectedFileID) {

                // Opened individual files
                if !appState.openFiles.isEmpty {
                    Section("Opened Files") {
                        OpenFilesList(appState: appState)
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

                    if let children = folder.children {
                        FolderTreeView(items: children, appState: appState)
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0))
                    }
                }
            }
            .listStyle(.sidebar)
            .listRowInsets(EdgeInsets())
        }
        .frame(minWidth: 180)
        .onChange(of: appState.selectedFileID) { _, newValue in
            guard let id = newValue else { return }
            appState.selectFile(id: id)
        }
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [mdType, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Markdown File"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.main.async {
            appState.openFile(url: url)
        }
    }

    private func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.main.async {
            appState.openFolder(url: url)
        }
    }
}

// MARK: - Open Files List

private struct OpenFilesList: View {
    let appState: AppState

    var body: some View {
        ForEach(appState.openFiles) { item in
            FileRowView(
                item: item,
                isSelected: appState.selectedFileID == item.id
            )
            .tag(item.id)
            .contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Button("Close") {
                    appState.closeFile(id: item.id)
                }
            }
        }
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
