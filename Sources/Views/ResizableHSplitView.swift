import SwiftUI

struct ResizableHSplitView<Left: View, Right: View>: View {
    @State private var ratio: CGFloat = 0.5
    @State private var isDragging = false
    @State private var isHoveringDivider = false
    @State private var dragStartRatio: CGFloat = 0.5

    let minLeftWidth: CGFloat
    let minRightWidth: CGFloat
    var collapsed: Bool = false
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dividerW: CGFloat = collapsed ? 0 : 1
            let availableW = w - dividerW
            let editorLeft = max(minLeftWidth, availableW * ratio)
            let editorRight = max(minRightWidth, availableW - editorLeft)
            let clampedLeft = collapsed ? 0 : availableW - editorRight
            let rightW = collapsed ? w : editorRight

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    left
                        .frame(width: clampedLeft)
                        .clipped()
                    Color.clear
                        .frame(width: dividerW)
                    right
                        .frame(width: rightW)
                }

                if !collapsed {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 2)
                        .position(x: clampedLeft + 1,
                                  y: geo.size.height / 2)
                        .opacity(isHoveringDivider ? 0.7 : 0.4)
                        .allowsHitTesting(false)

                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 40)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active:
                                guard !isDragging else { return }
                                isHoveringDivider = true
                                NSCursor.resizeLeftRight.set()
                            case .ended:
                                isHoveringDivider = false
                            }
                        }
                        .position(x: clampedLeft + 20,
                                  y: geo.size.height / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        dragStartRatio = ratio
                                    }
                                    ratio = max(0.1, min(0.9,
                                        dragStartRatio + value.translation.width / w))
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
        }
    }
}
