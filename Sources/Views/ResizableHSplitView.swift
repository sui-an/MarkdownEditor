import SwiftUI

struct ResizableHSplitView<Left: View, Right: View>: View {
    @State private var ratio: CGFloat = 0.5
    @State private var isDragging = false
    @State private var dragStartRatio: CGFloat = 0.5
    @State private var dragOffset: CGFloat = 0

    let minLeftWidth: CGFloat
    let minRightWidth: CGFloat
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dividerW: CGFloat = 1
            let hitW: CGFloat = 30
            let availableW = w - dividerW
            // ratio only updates on drag end → views stay stable during drag
            let leftW = max(minLeftWidth, availableW * ratio)
            let rightW = max(minRightWidth, availableW - leftW)
            let clampedLeft = availableW - rightW

            ZStack(alignment: .topLeading) {
                // Content layer (stable during drag — no WKWebView reflow)
                HStack(spacing: 0) {
                    left
                        .frame(width: clampedLeft)
                    Color.clear
                        .frame(width: dividerW)
                    right
                        .frame(width: rightW)
                }

                // Divider + hit area — uses .position so layout & hit-test
                // follow the visual location (unlike .offset which only moves visuals).
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: hitW)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .overlay(alignment: .center) {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: dividerW)
                    }
                    .position(x: isDragging ? clampedLeft + dragOffset : clampedLeft,
                              y: geo.size.height / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartRatio = ratio
                            }
                            dragOffset = value.translation.width
                        }
                        .onEnded { _ in
                            ratio = max(0.1, min(0.9,
                                dragStartRatio + dragOffset / w))
                            isDragging = false
                            dragOffset = 0
                        }
                )
            }
        }
    }
}
