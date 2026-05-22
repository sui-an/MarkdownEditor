import SwiftUI

struct FolderHeaderView: View {
    let folder: FileTreeItem
    let onRemove: () -> Void

    @State private var showConfirm = false

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

            Button(action: { showConfirm = true }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove folder from sidebar")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .alert("Remove Folder", isPresented: $showConfirm) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(folder.name)\" from the sidebar? The folder and its files will not be deleted from disk.")
        }
    }
}
