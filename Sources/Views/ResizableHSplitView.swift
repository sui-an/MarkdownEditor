import SwiftUI

struct ResizableHSplitView<Left: View, Right: View>: View {
    @State private var ratio: CGFloat = 0.5
    @State private var isDragging = false
    @State private var isHoveringDivider = false
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

                // Visual separator — 2pt vertical rule so it's always visible.
                // Combined hover+gesture hit area on the same view starts here
                // so there is no scrollbar overlap. NSTextView inside the
                // editor uses cursor rects that override NSCursor.push()/pop().
                // We use onContinuousHover + set() instead — set() fires on
                // every mouse move event, re-overriding the I-beam cursor as
                // long as the mouse stays in the hit area.
                Rectangle()
                    .fill(.separator)
                    .frame(width: 2)
                    .position(x: isDragging ? clampedLeft + dragOffset : clampedLeft + 1,
                              y: geo.size.height / 2)
                    .opacity(isHoveringDivider ? 0.7 : 0.4)
                    .allowsHitTesting(false)

                // Single hit/drag area — starts at clampedLeft, extends 40pt
                // right. No overlap with the editor scrollbar zone on the left.
                // onContinuousHover goes BEFORE position() — position() creates
                // a parent-filling frame that would make the tracking area
                // cover the entire ZStack. gesture() uses contentShape for
                // hit-testing so it stays after position().
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 40)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            // Skip during drag — gesture has mouse focus
                            // and every .set() hits the WindowServer, causing
                            // visible lag at 60hz drag rate.
                            guard !isDragging else { return }
                            isHoveringDivider = true
                            NSCursor.resizeLeftRight.set()
                        case .ended:
                            isHoveringDivider = false
                        }
                    }
                    .position(x: (isDragging ? clampedLeft + dragOffset : clampedLeft) + 20,
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
