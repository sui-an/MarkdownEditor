import Foundation

extension String {
    private static let jsEncoder = JSONEncoder()

    static func jsLiteral(_ value: String) -> String {
        (try? Self.jsEncoder.encode(value))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

enum SearchJS {
    static func highlight(query: String, currentIndex: Int = -1) -> String {
        let q = String.jsLiteral(query)
        let idx = currentIndex
        return """
        (function() {
            document.querySelectorAll('mark.search-result').forEach(function(m) {
                m.replaceWith(m.textContent);
            });
            if (!\(q)) return '{"count":0}';
            var q = \(q);
            var targetIdx = \(idx);
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
    }

    /// Lightweight navigation: only updates the current-match class and scrolls,
    /// without re-doing the full DOM walk. Called on every next/previous navigation.
    /// query is needed to re-count because some marks may have been destroyed by
    /// incremental body updates between navigations.
    static func navigateTo(index: Int) -> String {
        """
        (function() {
            var marks = document.querySelectorAll('mark.search-result');
            marks.forEach(function(m, i) {
                var isCurrent = (i === \(index));
                m.className = 'search-result' + (isCurrent ? ' current-match' : '');
                m.id = isCurrent ? 'search-current-match' : '';
            });
            if (\(index) >= 0 && \(index) < marks.length) {
                marks[\(index)].scrollIntoView({ behavior: 'instant', block: 'center' });
            }
            return JSON.stringify({count: marks.length, currentIndex: \(index)});
        })();
        """
    }

    static func clearHighlights() -> String {
        """
        document.querySelectorAll('mark.search-result').forEach(function(m) {
            m.replaceWith(m.textContent);
        });
        """
    }
}
