import SwiftUI
import AppKit

struct FolderHeaderView: View {
    let folder: FileTreeItem
    let onRemove: () -> Void
    let onToggle: () -> Void
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
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
        .overlay(RightClickCatcher(onRightClick: onSelect))
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onToggle() }
        .contextMenu {
            Button("Remove Folder") { onRemove() }
        }
    }
}

// MARK: - Right-Click Catcher

private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        CatcherView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onRightClick = onRightClick
    }
}

private final class CatcherView: NSView {
    var onRightClick: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
        super.rightMouseDown(with: event)
    }
}
