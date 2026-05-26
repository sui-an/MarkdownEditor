import SwiftUI
import AppKit
import WebKit

// MARK: - Search Panel Window

final class SearchPanelWindow: NSWindow {
    private let hostingView: NSHostingView<SearchPanelContent>
    private let searchState: SearchState

    init(searchState: SearchState, textView: @escaping () -> NSTextView?, webView: @escaping () -> WKWebView?) {
        self.searchState = searchState
        let content = SearchPanelContent(searchState: searchState, textView: textView, webView: webView)
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let size = NSSize(width: 400, height: 120)
        let screenFrame = NSScreen.main?.frame ?? .zero
        let origin = NSPoint(
            x: (screenFrame.width - size.width) / 2,
            y: screenFrame.height - size.height - 60
        )

        self.hostingView = hosting
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        contentView = hosting
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle]
        makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: self)
    }

    @objc private func windowWillClose() {
        searchState.isVisible = false
    }
}

// MARK: - Search Panel Content

private struct SearchPanelContent: View {
    let searchState: SearchState
    let textView: () -> NSTextView?
    let webView: () -> WKWebView?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                searchField
                matchCounter
                navButtons
                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !searchState.query.isEmpty {
                replaceRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .frame(width: 400)
        .background(
            VisualEffectView(material: .menu, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.15), lineWidth: 0.5)
        )
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            TextField("Search", text: Bindable(searchState).query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit {
                    if searchState.matches.isEmpty {
                        searchState.queryDidChange(textView: textView())
                    } else {
                        searchState.findNext(textView: textView())
                        scrollToMatch(textView: textView())
                    }
                    highlightPreview()
                }
                .onChange(of: searchState.query) { _, _ in
                    searchState.queryDidChange(textView: textView())
                    highlightPreview()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.separatorColor).opacity(0.25), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Match Counter

    @ViewBuilder
    private var matchCounter: some View {
        if !searchState.query.isEmpty {
            Text(searchState.matchLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 32, alignment: .trailing)
        }
    }

    // MARK: - Navigation Buttons

    private var navButtons: some View {
        HStack(spacing: 2) {
            Button(action: {
                searchState.findPrevious(textView: textView())
                scrollToMatch(textView: textView())
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(searchState.matches.isEmpty)
            .help("Previous Match (⇧⏎)")

            Button(action: {
                searchState.findNext(textView: textView())
                scrollToMatch(textView: textView())
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(searchState.matches.isEmpty)
            .help("Next Match (⏎)")
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: closePanel) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Close")
    }

    // MARK: - Replace Row

    private var replaceRow: some View {
        HStack(spacing: 8) {
            Text("Replace")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)

            TextField("", text: Bindable(searchState).replacement)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor).opacity(0.2), lineWidth: 0.5)
                )

            Button("Replace") {
                searchState.replace(textView: textView())
                highlightPreview()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(searchState.matches.isEmpty)

            Button("All") {
                searchState.replaceAll(textView: textView())
                highlightPreview()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(searchState.matches.isEmpty)
        }
        .padding(.top, 2)
    }

    // MARK: - Preview Search Highlighting (JS)

    private func highlightPreview() {
        guard let wv = webView() else { return }
        let query = searchState.query
        let escapedQuery = (try? JSONEncoder().encode(query))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        let js = """
        (function() {
            // Remove all previous search marks
            document.querySelectorAll('mark.search-result').forEach(function(m) {
                m.replaceWith(m.textContent);
            });
            if (!\(escapedQuery)) return;
            var q = \(escapedQuery);
            var lowerQ = q.toLowerCase();
            var walker = document.createTreeWalker(document.getElementById('md-content') || document.body, NodeFilter.SHOW_TEXT, null, false);
            var nodes = [];
            while (walker.nextNode()) { nodes.push(walker.currentNode); }
            for (var n = 0; n < nodes.length; n++) {
                var node = nodes[n];
                var text = node.textContent;
                var lower = text.toLowerCase();
                var idx = 0;
                var fragments = [];
                var lastEnd = 0;
                while ((idx = lower.indexOf(lowerQ, idx)) !== -1) {
                    if (idx > lastEnd) {
                        fragments.push(document.createTextNode(text.substring(lastEnd, idx)));
                    }
                    var mark = document.createElement('mark');
                    mark.className = 'search-result';
                    mark.textContent = text.substring(idx, idx + q.length);
                    fragments.push(mark);
                    idx += q.length;
                    lastEnd = idx;
                }
                if (lastEnd < text.length) {
                    fragments.push(document.createTextNode(text.substring(lastEnd)));
                }
                if (fragments.length > 0) {
                    var parent = node.parentNode;
                    var container = document.createElement('span');
                    fragments.forEach(function(f) { container.appendChild(f); });
                    parent.replaceChild(container, node);
                    nodes[n] = container; // avoid re-traversal
                }
            }
        })();
        """

        DispatchQueue.main.async {
            wv.evaluateJavaScript(js) { _, error in
                if let error = error {
                    // Silently fail — webView may be mid-reload
                    #if DEBUG
                    print("Preview highlight JS error: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    // MARK: - Scroll to Match

    private func scrollToMatch(textView: NSTextView?) {
        guard let range = searchState.currentMatchRange, let tv = textView else { return }
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(range)
    }

    // MARK: - Close

    private func closePanel() {
        // Step 1: clear state before closing window
        searchState.isVisible = false

        // Step 2: close the window on next runloop to avoid
        // tearing down the SwiftUI view while still executing
        DispatchQueue.main.async { [weak searchState, weak wv = webView(), weak tv = textView()] in
            // Clear editor highlights
            if let tv = tv {
                searchState?.clearHighlights(textView: tv)
            }
            // Clear preview highlights
            if let wv = wv {
                wv.evaluateJavaScript("""
                document.querySelectorAll('mark.search-result').forEach(function(m) {
                    m.replaceWith(m.textContent);
                });
                """)
            }
            // Close the window
            for win in NSApp.windows {
                if win is SearchPanelWindow {
                    win.close()
                }
            }
        }
    }
}

// MARK: - Visual Effect Background

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
