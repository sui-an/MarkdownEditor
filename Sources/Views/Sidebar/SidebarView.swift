import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    let appState: AppState
    @State private var renameTarget: RenameTarget?

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
                        OpenFilesList(appState: appState, renameTarget: $renameTarget)
                    }
                }

                // Folders
                ForEach(appState.rootFolders) { folder in
                    Section {
                        let flatFiles = appState.flatFolderFilesByFolder[folder.id] ?? []
                        ForEach(flatFiles, id: \.item.id) { flatFile in
                            if flatFile.item.isDirectory {
                                DirectoryRowView(
                                    item: flatFile.item,
                                    depth: flatFile.depth,
                                    isCollapsed: appState.collapsedFolderPaths.contains(flatFile.item.url.path),
                                    isSelected: appState.selectedDirectoryID == flatFile.item.id,
                                    onToggle: { appState.toggleFolderCollapsed(flatFile.item.url.path) },
                                    onSelect: { appState.selectedDirectoryID = flatFile.item.id; appState.selectedFileID = nil },
                                    renameTarget: $renameTarget,
                                    appState: appState
                                )
                            } else {
                                FolderFileRow(
                                    item: flatFile.item,
                                    depth: flatFile.depth,
                                    isSelected: appState.selectedFileID == flatFile.item.id,
                                    renameTarget: $renameTarget,
                                    appState: appState
                                )
                            }
                        }
                    } header: {
                        FolderHeaderView(
                            folder: folder,
                            onRemove: { appState.removeFolder(id: folder.id) },
                            onReload: { appState.reloadFolder(id: folder.id) },
                            onToggle: { appState.toggleFolderCollapsed(folder.url.path) },
                            isSelected: appState.selectedDirectoryID == folder.id,
                            onSelect: {
                                appState.selectedDirectoryID = folder.id
                                appState.selectedFileID = nil
                            },
                            renameTarget: $renameTarget,
                            appState: appState
                        )
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 180)
        .onChange(of: appState.selectedFileID) { _, newValue in
            guard let id = newValue else { return }
            appState.selectedDirectoryID = nil
            appState.prepareFileSwitch(to: id)
            appState.selectFile(id: id)
        }
    }

    private func startRenaming(item: FileTreeItem) {
        renameTarget = RenameTarget(
            id: item.id,
            name: item.name,
            isDirectory: item.isDirectory,
            parentURL: item.url.deletingLastPathComponent()
        )
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

// MARK: - Folder File Row (with rename popover)

private struct FolderFileRow: View {
    let item: FileTreeItem
    let depth: Int
    let isSelected: Bool
    @Binding var renameTarget: RenameTarget?
    let appState: AppState

    private var isRenamingThis: Bool {
        renameTarget?.id == item.id
    }

    var body: some View {
        FileRowView(
            item: item,
            isSelected: isSelected
        )
        .padding(.leading, CGFloat(depth * 12))
        .contentShape(Rectangle())
        .tag(item.id)
        .contextMenu {
            Button("Rename") {
                renameTarget = RenameTarget(
                    id: item.id,
                    name: item.name,
                    isDirectory: item.isDirectory,
                    parentURL: item.url.deletingLastPathComponent()
                )
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { }
            }
        )
        .popover(isPresented: Binding(
            get: { isRenamingThis },
            set: { if !$0 { renameTarget = nil } }
        )) {
            if let target = renameTarget, target.id == item.id {
                RenamePopover(
                    currentName: target.name,
                    isDirectory: target.isDirectory,
                    parentDirectoryURL: target.parentURL,
                    onConfirm: { newName in
                        appState.renameItem(id: target.id, newName: newName)
                        renameTarget = nil
                    },
                    onCancel: {
                        renameTarget = nil
                    }
                )
            }
        }
    }
}

// MARK: - Open Files List

private struct OpenFilesList: View {
    let appState: AppState
    @Binding var renameTarget: RenameTarget?

    var body: some View {
        ForEach(appState.openFiles) { item in
            OpenFileRow(
                item: item,
                isSelected: appState.selectedFileID == item.id,
                renameTarget: $renameTarget,
                appState: appState
            )
        }
    }
}

// MARK: - Open File Row (with rename popover)

private struct OpenFileRow: View {
    let item: FileTreeItem
    let isSelected: Bool
    @Binding var renameTarget: RenameTarget?
    let appState: AppState

    private var isRenamingThis: Bool {
        renameTarget?.id == item.id
    }

    var body: some View {
        FileRowView(
            item: item,
            isSelected: isSelected
        )
        .contentShape(Rectangle())
        .tag(item.id)
        .contextMenu {
            Button("Rename") {
                renameTarget = RenameTarget(
                    id: item.id,
                    name: item.name,
                    isDirectory: item.isDirectory,
                    parentURL: item.url.deletingLastPathComponent()
                )
            }
            Button("Reload from Disk") {
                appState.reloadFile(id: item.id)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Close") {
                appState.closeFile(id: item.id)
            }
        }
        .popover(isPresented: Binding(
            get: { isRenamingThis },
            set: { if !$0 { renameTarget = nil } }
        )) {
            if let target = renameTarget, target.id == item.id {
                RenamePopover(
                    currentName: target.name,
                    isDirectory: target.isDirectory,
                    parentDirectoryURL: target.parentURL,
                    onConfirm: { newName in
                        appState.renameItem(id: target.id, newName: newName)
                        renameTarget = nil
                    },
                    onCancel: {
                        renameTarget = nil
                    }
                )
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
