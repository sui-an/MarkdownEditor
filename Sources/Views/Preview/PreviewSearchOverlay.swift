import SwiftUI
import WebKit

// MARK: - Preview-Only Search Overlay

/// A lightweight search bar overlaid at the top of the preview area.
/// Used exclusively in Preview Only mode — performs search entirely
/// via JavaScript on the WKWebView, with no dependency on NSTextView.
struct PreviewSearchOverlay: View {
    let webView: () -> WKWebView?
    var viewRefs: ViewRefs?
    var onClose: (() -> Void)?

    @State private var query = ""
    @State private var currentMatchIndex = 0
    @State private var totalMatches = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 12)

            TextField("Search preview", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit {
                    if totalMatches == 0 {
                        performSearch()
                    } else {
                        findNext()
                    }
                }
                .onChange(of: query) { _, _ in
                    performSearch()
                }

            if !query.isEmpty {
                Text(matchLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 32, alignment: .trailing)

                Button { findPrevious() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(totalMatches == 0)
                .help("Previous Match (⇧⏎)")

                Button { findNext() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(totalMatches == 0)
                .help("Next Match (⏎)")

                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            } else {
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: 420)
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { close() }
    }

    // MARK: - Helpers

    private var matchLabel: String {
        guard totalMatches > 0 else { return "0/0" }
        return "\(currentMatchIndex + 1)/\(totalMatches)"
    }

    // MARK: - Actions

    private func close() {
        viewRefs?.lastSearchQuery = ""
        webView()?.evaluateJavaScript("""
        document.querySelectorAll('mark.search-result').forEach(function(m) {
            m.replaceWith(m.textContent);
        });
        """)
        onClose?()
    }

    private func performSearch() {
        guard !query.isEmpty else {
            clearHighlights()
            totalMatches = 0
            currentMatchIndex = 0
            return
        }
        currentMatchIndex = 0
        viewRefs?.lastSearchQuery = query
        highlightAndScroll(index: 0)
    }

    private func findNext() {
        guard totalMatches > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % totalMatches
        highlightAndScroll(index: currentMatchIndex)
    }

    private func findPrevious() {
        guard totalMatches > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + totalMatches) % totalMatches
        highlightAndScroll(index: currentMatchIndex)
    }

    // MARK: - JavaScript

    private func highlightAndScroll(index: Int) {
        guard let wv = webView() else { return }
        let escapedQuery = (try? JSONEncoder().encode(query))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

        let js = """
        (function() {
            document.querySelectorAll('mark.search-result').forEach(function(m) {
                m.replaceWith(m.textContent);
            });
            if (!\(escapedQuery)) return '{"count":0}';
            var q = \(escapedQuery);
            var targetIdx = \(index);
            var lowerQ = q.toLowerCase();
            var root = document.getElementById('md-content') || document.body;
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
            var nodes = [];
            while (walker.nextNode()) { nodes.push(walker.currentNode); }
            var matchCount = 0;
            for (var n = 0; n < nodes.length; n++) {
                var node = nodes[n];
                var text = node.textContent;
                if (!text) continue;
                var lower = text.toLowerCase();
                var ci = 0;
                var fragments = [];
                var lastEnd = 0;
                while ((ci = lower.indexOf(lowerQ, ci)) !== -1) {
                    if (ci > lastEnd) {
                        fragments.push(document.createTextNode(text.substring(lastEnd, ci)));
                    }
                    var mark = document.createElement('mark');
                    var isCurrent = (matchCount === targetIdx);
                    mark.className = 'search-result' + (isCurrent ? ' current-match' : '');
                    if (isCurrent) mark.id = 'search-current-match';
                    mark.textContent = text.substring(ci, ci + q.length);
                    fragments.push(mark);
                    ci += q.length;
                    lastEnd = ci;
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
            return JSON.stringify({count: matchCount});
        })();
        """

        wv.evaluateJavaScript(js) { result, error in
            guard error == nil,
                  let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = json["count"] as? Int else { return }
            DispatchQueue.main.async {
                totalMatches = count
                if count == 0 { currentMatchIndex = 0 }
            }
        }
    }

    private func clearHighlights() {
        guard let wv = webView() else { return }
        wv.evaluateJavaScript("""
        document.querySelectorAll('mark.search-result').forEach(function(m) {
            m.replaceWith(m.textContent);
        });
        """)
    }
}
