import SwiftUI

struct RenameTarget: Identifiable {
    let id: String
    let name: String
    let isDirectory: Bool
    let parentURL: URL
}

struct DirectoryRowView: View {
    let item: FileTreeItem
    let depth: Int
    let isCollapsed: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    @Binding var renameTarget: RenameTarget?
    let appState: AppState

    private var isRenamingThis: Bool {
        renameTarget?.id == item.id
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 8)
                .onTapGesture { onToggle(); onSelect() }
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename") {
                renameTarget = RenameTarget(
                    id: item.id,
                    name: item.name,
                    isDirectory: true,
                    parentURL: item.url.deletingLastPathComponent()
                )
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
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .padding(.leading, CGFloat(depth * 12))
    }
}
