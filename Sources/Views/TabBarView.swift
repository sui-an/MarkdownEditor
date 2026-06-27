import SwiftUI

struct TabBarView: View {
    @Bindable var appState: AppState
    @State private var hoveredTabID: String?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(appState.tabOrder) { file in
                TabItemView(
                    file: file,
                    isActive: appState.selectedFileID == file.id,
                    isDirty: appState.selectedFileID == file.id && appState.isFileDirty,
                    isHovered: hoveredTabID == file.id,
                    onSelect: { appState.selectedFileID = file.id },
                    onClose: { appState.closeTab(id: file.id) }
                )
                .onHover { hovering in
                    hoveredTabID = hovering ? file.id : nil
                }
            }

            Button(action: { appState.openNewTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(height: 32)
    }
}

// MARK: - Tab Item

private struct TabItemView: View {
    let file: FileTreeItem
    let isActive: Bool
    let isDirty: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isCloseHovered = false

    private var showCloseButton: Bool {
        isHovered || isActive
    }

    var body: some View {
        HStack(spacing: 4) {
            if isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            Text(file.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? .primary : .secondary)

            if showCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(isCloseHovered ? .primary : .secondary)
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(isCloseHovered
                                    ? Color(nsColor: .separatorColor)
                                    : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color(nsColor: .separatorColor) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
