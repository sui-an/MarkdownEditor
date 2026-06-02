import SwiftUI

struct FolderHeaderView: View {
    let folder: FileTreeItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(folder.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .contextMenu {
            Button("Remove Folder") { onRemove() }
        }
    }
}
