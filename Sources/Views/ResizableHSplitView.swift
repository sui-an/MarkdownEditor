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

            HStack(spacing: 0) {
                left
                    .frame(width: leftW)
                    .clipped()
                    .opacity(collapsed ? 0 : 1)

                if !collapsed {
                    // Divider sits directly in HStack layout flow — no offset/position
                    // trickery, so onHover tracking area always matches visual position.
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle()
                            .fill(isActive ? Color.accentColor : Color(nsColor: .separatorColor))
                            .opacity(isDragging ? 0.8 : isActive ? 0.6 : 0.5)
                            .frame(width: isDragging ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                    .frame(width: dividerW)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
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
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }

                right
                    .frame(width: rightW)
            }
        }
    }
}
