import SwiftUI

struct FileRowView: View {
    let item: FileTreeItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
