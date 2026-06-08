import SwiftUI
import AppKit
import WebKit

// MARK: - Outline Panel Window

final class OutlinePanelWindow: NSWindow {
    private let hostingView: NSHostingView<OutlinePanelContent>
    private let textViewProvider: () -> NSTextView?
    private let webViewProvider: () -> WKWebView?
    private let onClose: (() -> Void)?

    init(headings: [HeadingItem], textView: @escaping () -> NSTextView?, webView: @escaping () -> WKWebView?, onClose: (() -> Void)? = nil) {
        self.textViewProvider = textView
        self.webViewProvider = webView
        self.onClose = onClose
        let content = OutlinePanelContent(
            headings: headings,
            textView: textView,
            webView: webView
        )
        let hosting = NSHostingView(rootView: content)
        self.hostingView = hosting

        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = 650

        let appWindow = NSApp.mainWindow ?? NSApp.keyWindow

        // Restore saved frame or compute default position
        let panelFrame: NSRect
        if let saved = UserDefaults.standard.string(forKey: "outlinePanelFrame") {
            panelFrame = NSRectFromString(saved)
        } else {
            let windowFrame = appWindow?.frame ?? .zero
            panelFrame = NSRect(
                x: windowFrame.maxX - panelWidth - 16,
                y: windowFrame.maxY - panelHeight - 60,
                width: panelWidth,
                height: panelHeight
            )
        }

        super.init(
            contentRect: panelFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        contentView = hosting
        collectionBehavior = [.ignoresCycle]
        if let appWindow {
            appWindow.addChildWindow(self, ordered: NSWindow.OrderingMode.above)
        }
        isReleasedWhenClosed = false
        orderFront(nil)
    }

    func updateHeadings(_ headings: [HeadingItem]) {
        hostingView.rootView = OutlinePanelContent(
            headings: headings,
            textView: textViewProvider,
            webView: webViewProvider
        )
    }

    /// When the user clicks the close button, just hide the window instead of
    /// releasing it.  The panel is owned by ContentView's @State outlinePanel
    /// and will be deallocated when the view goes away.  Hiding instead of
    /// closing allows makeKeyAndOrderFront to re-show it seamlessly.
    override func close() {
        onClose?()
        orderOut(nil)
    }
}

// MARK: - Outline Panel Content

private struct OutlinePanelContent: View {
    let headings: [HeadingItem]
    let textView: () -> NSTextView?
    let webView: () -> WKWebView?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Outline")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if headings.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No headings found")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(flattenHeadings(headings)) { flat in
                            HeadingRow(
                                item: flat.item,
                                depth: flat.depth,
                                onTap: { jumpToHeading(flat.item) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 200, minHeight: 200)
    }

    private struct FlatHeading: Identifiable {
        let id = UUID()
        let item: HeadingItem
        let depth: Int
    }

    private func flattenHeadings(_ items: [HeadingItem], depth: Int = 0) -> [FlatHeading] {
        var result: [FlatHeading] = []
        for item in items {
            result.append(FlatHeading(item: item, depth: depth))
            if !item.children.isEmpty {
                result.append(contentsOf: flattenHeadings(item.children, depth: depth + 1))
            }
        }
        return result
    }

    private func jumpToHeading(_ item: HeadingItem) {
        // Scroll editor
        if let tv = textView() {
            let nsText = tv.string as NSString
            var charIndex = 0
            var currentLine = 0
            while currentLine < item.lineIndex && charIndex < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))
                charIndex = NSMaxRange(lineRange)
                currentLine += 1
            }
            let range = NSRange(location: charIndex, length: 0)
            tv.scrollRangeToVisible(range)
            tv.setSelectedRange(range)
            // Flash highlight in editor
            let lineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))
            if lineRange.location + lineRange.length <= nsText.length {
                tv.showFindIndicator(for: lineRange)
            }
        }
        // Scroll preview — use JSON encoder for safe JS string interpolation
        if let wv = webView(),
           let slugData = try? JSONEncoder().encode("heading-\(item.slug)"),
           let slugJS = String(data: slugData, encoding: .utf8) {
            wv.evaluateJavaScript("""
                var el = document.getElementById(\(slugJS));
                if (el) {
                    el.scrollIntoView({behavior: 'smooth', block: 'start'});
                    el.style.transition = 'background-color 0.6s';
                    el.style.backgroundColor = 'rgba(255, 255, 0, 0.35)';
                    setTimeout(function() {
                        el.style.backgroundColor = 'transparent';
                    }, 800);
                }
            """)
        }
    }
}

// MARK: - Heading Row

private struct HeadingRow: View {
    let item: HeadingItem
    let depth: Int
    let onTap: () -> Void

    private var fontSize: CGFloat {
        [16, 14, 13, 12, 11, 11][min(max(item.level - 1, 0), 5)]
    }

    private var fontWeight: Font.Weight {
        item.level <= 2 ? .semibold : .regular
    }

    var body: some View {
        Button(action: onTap) {
            Text(item.title)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.leading, CGFloat(12 + depth * 12))
                .padding(.trailing, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
