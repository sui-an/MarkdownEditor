import SwiftUI

struct ResizableHSplitView<Left: View, Right: View>: View {
    @State private var ratio: CGFloat = 0.5
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragOffset: CGFloat = 0

    let minLeftWidth: CGFloat
    let minRightWidth: CGFloat
    var collapsed: Bool = false
    let left: Left
    let right: Right

    private var isActive: Bool { isDragging || isHovering }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dividerW: CGFloat = 12
            let availableW = w - dividerW
            let raw = availableW * ratio
            let clampedLeft = max(minLeftWidth, min(raw, availableW - minRightWidth))
            let leftW = collapsed ? 0 : clampedLeft
            let rightW = collapsed ? w : (w - leftW - dividerW)
            let lineX = collapsed ? 0 : leftW + (isDragging ? dragOffset : 0)

            HStack(spacing: 0) {
                left
                    .frame(width: leftW)
                    .clipped()
                    .opacity(collapsed ? 0 : 1)

                if !collapsed {
                    Color.clear
                        .frame(width: dividerW)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHovering = hovering
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else if !isDragging {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        dragOffset = 0
                                        NSCursor.resizeLeftRight.push()
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
                }

                right
                    .frame(width: rightW)
            }
            .overlay(alignment: .topLeading) {
                if !collapsed {
                    Rectangle()
                        .fill(isActive ? Color.accentColor : Color(nsColor: .separatorColor))
                        .opacity(isDragging ? 0.8 : isActive ? 0.6 : 0.5)
                        .frame(width: isDragging ? 2 : 1)
                        .offset(x: lineX)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
