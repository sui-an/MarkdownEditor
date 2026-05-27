import SwiftUI
import AppKit
import WebKit

// MARK: - Floating Search Panel

final class SearchPanel: NSPanel {
    private let searchState: SearchState
    private let textView: () -> NSTextView?
    private let webView: () -> WKWebView?
    private let viewRefs: ViewRefs?


    init(searchState: SearchState, textView: @escaping () -> NSTextView?, webView: @escaping () -> WKWebView?, viewRefs: ViewRefs?) {
        self.searchState = searchState
        self.textView = textView
        self.webView = webView
        self.viewRefs = viewRefs

        let size = NSSize(width: 420, height: 120)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 80
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear

        let content = InlineSearchView(
            searchState: searchState,
            textView: textView,
            webView: webView,
            viewRefs: viewRefs
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting

        // Wire close callback (no retain cycle)
        hosting.rootView.onClose = { [weak self] in self?.close() }

        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func close() {
        // Clear editor highlights
        if let storage = textView()?.textStorage {
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
            for layoutManager in storage.layoutManagers {
                layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
            }
        }
        // Clear preview highlights
        viewRefs?.lastSearchQuery = ""
        webView()?.evaluateJavaScript("""
        document.querySelectorAll('mark.search-result').
        """)
        searchState.isVisible = false
        super.close()
    }
}

// MARK: - Search View (used inside the panel)

struct InlineSearchView: View {
    let searchState: SearchState
    let textView: () -> NSTextView?
    let webView: () -> WKWebView?
    var viewRefs: ViewRefs?
    var onClose: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var isReplaceExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                searchField
                if !searchState.query.isEmpty {
                    replaceToggle
                }
                matchCounter
                navButtons
                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isReplaceExpanded && !searchState.query.isEmpty {
                replaceRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.15), lineWidth: 0.5)
        )
        .frame(width: 420)
        .onAppear {
            searchState.query = ""
            searchState.matches = []
            DispatchQueue.main.async { isFocused = true }
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
                        scrollToMatch()
                    }
                    highlightPreview()
                }
                .onChange(of: searchState.query) { _, _ in
                    searchState.queryDidChange(textView: textView())
                    highlightPreview()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
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
            Button {
                searchState.findPrevious(textView: textView())
                scrollToMatch()
                highlightPreview()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(searchState.matches.isEmpty)

            Button {
                searchState.findNext(textView: textView())
                scrollToMatch()
                highlightPreview()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(searchState.matches.isEmpty)
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            onClose?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Replace Toggle

    private var replaceToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                isReplaceExpanded.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isReplaceExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                Text("Replace")
                    .font(.system(size: 11))
            }
            .foregroundStyle(isReplaceExpanded ? Color.accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isReplaceExpanded ? Color.accentColor.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(isReplaceExpanded ? "Hide Replace" : "Show Replace")
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
                .padding(.vertical, 3)
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
    }

    // MARK: - Actions

    private func scrollToMatch() {
        guard let range = searchState.currentMatchRange, let tv = textView() else { return }
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(range)
    }

    private func highlightPreview() {
        guard let wv = webView() else { return }
        let query = searchState.query
        let currentIdx = searchState.matches.isEmpty ? -1 : searchState.currentMatchIndex
        viewRefs?.lastSearchQuery = query
        let escapedQuery = (try? JSONEncoder().encode(query))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        let js = """
        (function() {
            document.querySelectorAll('mark.search-result').forEach(function(m) {
                m.replaceWith(m.textContent);
            });
            if (!\(escapedQuery)) return;
            var q = \(escapedQuery);
            var currentIdx = \(currentIdx);
            var lowerQ = q.toLowerCase();
            var walker = document.createTreeWalker(document.getElementById('md-content') || document.body, NodeFilter.SHOW_TEXT, null, false);
            var nodes = [];
            while (walker.nextNode()) { nodes.push(walker.currentNode); }
            var matchCount = 0;
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
                    var isCurrent = (matchCount === currentIdx);
                    mark.className = isCurrent ? 'search-result current-match' : 'search-result';
                    if (isCurrent) mark.id = 'search-current-match';
                    mark.textContent = text.substring(idx, idx + q.length);
                    fragments.push(mark);
                    idx += q.length;
                    lastEnd = idx;
                    matchCount++;
                }
                if (lastEnd < text.length) {
                    fragments.push(document.createTextNode(text.substring(lastEnd)));
                }
                if (fragments.length > 0) {
                    var parent = node.parentNode;
                    var container = document.createElement('span');
                    fragments.forEach(function(f) { container.appendChild(f); });
                    parent.replaceChild(container, node);
                    nodes[n] = container;
                }
            }
            var currentEl = document.getElementById('search-current-match');
            if (currentEl) {
                currentEl.scrollIntoView({ behavior: 'instant', block: 'center' });
            }
        })();
        """

        DispatchQueue.main.async {
            wv.evaluateJavaScript(js) { _, _ in }
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

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
