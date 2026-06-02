import Foundation

extension String {
    static func jsLiteral(_ value: String) -> String {
        (try? JSONEncoder().encode(value))
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

    static func clearHighlights() -> String {
        """
        document.querySelectorAll('mark.search-result').forEach(function(m) {
            m.replaceWith(m.textContent);
        });
        """
    }
}
