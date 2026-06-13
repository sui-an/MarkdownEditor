import SwiftUI
import AppKit

struct FolderHeaderView: View {
    let folder: FileTreeItem
    let onRemove: () -> Void
    let onReload: () -> Void
    let onToggle: () -> Void
    let isSelected: Bool
    let onSelect: () -> Void
    @Binding var renameTarget: RenameTarget?
    let appState: AppState

    private var isRenamingThis: Bool {
        renameTarget?.id == folder.id
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(folder.name)
                .foregroundStyle(.primary)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onToggle() }
        .contextMenu {
            Button("Rename") {
                renameTarget = RenameTarget(
                    id: folder.id,
                    name: folder.name,
                    isDirectory: true,
                    parentURL: folder.url.deletingLastPathComponent()
                )
            }
            Button("Reload from Disk") { onReload() }
            Divider()
            Button("Remove Folder") { onRemove() }
        }
        .popover(isPresented: Binding(
            get: { isRenamingThis },
            set: { if !$0 { renameTarget = nil } }
        )) {
            if let target = renameTarget, target.id == folder.id {
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
