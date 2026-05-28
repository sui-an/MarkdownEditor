import SwiftUI
import AppKit

/// AppKit NSSplitView wrapper that matches macOS Notes sidebar behavior:
/// animation only moves the divider; content subviews are NOT resized
/// frame-by-frame. They snap to the final size once the animation commits.
struct NativeSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    @Binding var showSidebar: Bool
    let sidebarWidth: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSplitView {
        let sv = NSSplitView()
        sv.isVertical = true
        sv.dividerStyle = .thin
        sv.delegate = context.coordinator

        let sidebarHost = NSHostingView(rootView: sidebar())
        sidebarHost.identifier = NSUserInterfaceItemIdentifier("sb")
        sv.addSubview(sidebarHost)

        let detailHost = NSHostingView(rootView: detail())
        sv.addSubview(detailHost)

        // Prevent sidebar from collapsing below minimum
        sidebarHost.autoresizingMask = [.width, .height]
        detailHost.autoresizingMask = [.width, .height]

        return sv
    }

    func updateNSView(_ sv: NSSplitView, context: Context) {
        guard let sidebarHost = sv.arrangedSubviews.first(where: { $0.identifier?.rawValue == "sb" }) as? NSHostingView<Sidebar> else { return }
        sidebarHost.rootView = sidebar()

        for sub in sv.arrangedSubviews where sub.identifier?.rawValue != "sb" {
            (sub as? NSHostingView<Detail>)?.rootView = detail()
        }

        guard context.coordinator.lastShow != showSidebar else { return }
        context.coordinator.lastShow = showSidebar

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            sidebarHost.animator().isHidden = !showSidebar
            if showSidebar {
                sidebarHost.animator().frame.size.width = sidebarWidth
            } else {
                sidebarHost.animator().frame.size.width = 0
            }
            sv.layoutSubtreeIfNeeded()
        }
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var lastShow: Bool?

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Don't allow sidebar to be dragged smaller than 160
            return proposedMinimumPosition + 160
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Don't allow sidebar to exceed 400
            return min(proposedMaximumPosition, 400)
        }

        func splitView(_ splitView: NSSplitView, canCollapse subview: NSView) -> Bool {
            subview.identifier?.rawValue == "sb"
        }
    }
}
