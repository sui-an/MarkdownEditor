import SwiftUI

struct FolderTreeView: View {
    let items: [FileTreeItem]
    let appState: AppState

    var body: some View {
        ForEach(items) { item in
            if item.isDirectory {
                DisclosureGroup {
                    if let children = item.children {
                        FolderTreeView(items: children, appState: appState)
                    }
                } label: {
                    FolderHeaderView(folder: item, onRemove: { appState.removeFolder(id: item.id) })
                }
            } else {
                FileRowView(item: item, isSelected: appState.selectedFileID == item.id)
                    .tag(item.id)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                    }
            }
        }
    }
}
