import SwiftUI

struct ResizableHSplitView<Left: View, Right: View>: View {
    @State private var ratio: CGFloat = 0.5
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragOffset: CGFloat = 0

    let minLeftWidth: CGFloat
    let minRightWidth: CGFloat
    var collapsed: Bool = false
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    private var isActive: Bool { isDragging || isHovering }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dividerW: CGFloat = 5
            let availableW = w - dividerW
            let raw = availableW * ratio
            let clampedLeft = max(minLeftWidth, min(raw, availableW - minRightWidth))

            // When collapsed: left = 0, right takes all space (instant)
            // When expanded: both get calculated widths (instant)
            let leftW = collapsed ? 0 : clampedLeft
            let rightW = collapsed ? w : (w - leftW - dividerW)
            let dividerX = isDragging ? leftW + dragOffset : leftW

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    left
                        .frame(width: leftW)
                        .opacity(collapsed ? 0 : 1)
                    if !collapsed {
                        Color.clear.frame(width: dividerW)
                    }
                    right
                        .frame(width: rightW)
                }

                if !collapsed {
                    // Drag handle
                    Color.clear
                        .frame(width: 12, height: geo.size.height)
                        .contentShape(Rectangle())
                        .offset(x: dividerX - 3.5)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        dragOffset = 0
                                        NSCursor.resizeLeftRight.set()
                                    }
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let newRatio = ratio + value.translation.width / availableW
                                    ratio = max(
                                        minLeftWidth / availableW,
                                        min(newRatio, 1 - minRightWidth / availableW)
                                    )
                                    isDragging = false
                                    dragOffset = 0
                                    NSCursor.pop()
                                }
                        )
                        .onHover { hovering in
                            isHovering = hovering
                            if !isDragging {
                                if hovering {
                                    NSCursor.resizeLeftRight.set()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }

                    // Visual divider line
                    Rectangle()
                        .fill(isActive ? Color.accentColor : Color(nsColor: .separatorColor))
                        .opacity(isDragging ? 0.8 : isActive ? 0.6 : 0.5)
                        .frame(width: isDragging ? 2 : 1, height: geo.size.height)
                        .offset(x: dividerX)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
