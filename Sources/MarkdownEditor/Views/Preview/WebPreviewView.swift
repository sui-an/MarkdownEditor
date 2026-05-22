import SwiftUI
import WebKit

enum PreviewWidth: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case middle = "Medium"
    case wide = "Wide"

    var id: Self { self }
}

struct WebPreview: View {
    let text: String
    @Binding var scrollToHeading: String?
    var previewWidth: PreviewWidth = .normal
    @State private var html: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var webViewRef: WKWebView?
    @State private var findVisible: Bool = false
    @State private var searchQuery: String = ""
    @State private var matchCount: Int = 0
    @FocusState private var findFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    private let parser = MarkdownParser()
    private let renderer = HTMLRenderer()

    var body: some View {
        VStack(spacing: 0) {
            if findVisible {
                findBar
            }

            WebViewRepresentable(html: html, webViewRef: $webViewRef)
                .onChange(of: text) { _, newText in
                    debounceTask?.cancel()
                    debounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if !Task.isCancelled {
                            updateHTML(newText)
                        }
                    }
                    // Clear find when content changes
                    if findVisible {
                        matchCount = 0
                    }
                }
                .onChange(of: colorScheme) { _, _ in
                    updateHTML(text)
                }
                .onChange(of: previewWidth) { _, _ in
                    updateHTML(text)
                }
                .onChange(of: scrollToHeading) { _, newValue in
                    guard let hid = newValue, let wv = webViewRef else { return }
                    let escaped = hid.replacingOccurrences(of: "'", with: "\\'")
                    let js = "var el=document.getElementById('\(escaped)');if(el)el.scrollIntoView({behavior:'smooth',block:'start'});"
                    wv.evaluateJavaScript(js)
                    DispatchQueue.main.async {
                        scrollToHeading = nil
                    }
                }
                .onAppear {
                    updateHTML(text)
                }
                .onReceive(NotificationCenter.default.publisher(for: .performFindAction)) { notification in
                    guard let rawValue = notification.userInfo?["action"] as? Int,
                          let action = NSTextFinder.Action(rawValue: rawValue) else { return }
                    handleFindAction(action)
                }
                .onExitCommand {
                    dismissFind()
                }
        }
    }

    // MARK: - Find Bar

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .imageScale(.small)

            TextField("Find in preview", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($findFocused)
                .onChange(of: searchQuery) { _, query in
                    performSearch(query)
                }
                .onSubmit {
                    performSearch(searchQuery, backwards: false)
                }

            if matchCount > 0 {
                Text("\(matchCount) matches")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Button(action: { performSearch(searchQuery, backwards: true) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.isEmpty || matchCount == 0)
            .help("Previous (Cmd+Shift+G)")

            Button(action: { performSearch(searchQuery, backwards: false) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.isEmpty || matchCount == 0)
            .help("Next (Cmd+G)")

            Button(action: dismissFind) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    private func handleFindAction(_ action: NSTextFinder.Action) {
        switch action {
        case NSTextFinder.Action.showFindInterface:
            findVisible = true
            // Focus the search field next runloop
            DispatchQueue.main.async {
                findFocused = true
            }
        case NSTextFinder.Action.nextMatch:
            guard findVisible else { return }
            performSearch(searchQuery, backwards: false)
        case NSTextFinder.Action.previousMatch:
            guard findVisible else { return }
            performSearch(searchQuery, backwards: true)
        case NSTextFinder.Action.hideFindInterface:
            dismissFind()
        default:
            break
        }
    }

    private func performSearch(_ query: String, backwards: Bool = false) {
        guard let wv = webViewRef, !query.isEmpty else {
            matchCount = 0
            return
        }
        // Count all matches first
        let countJS = "(function(q){var n=0,s=window.getSelection();s.removeAllRanges();while(window.find(q,false,false,true)){n++;}s.removeAllRanges();return n;})('\(query.replacingOccurrences(of: "'", with: "\\'"))')"
        wv.evaluateJavaScript(countJS) { result, _ in
            if let count = result as? Int {
                self.matchCount = count
            }
        }
        // Navigate to the match in the given direction
        let navJS = "window.find('\(query.replacingOccurrences(of: "'", with: "\\'"))', false, \(backwards), true)"
        wv.evaluateJavaScript(navJS)
    }

    private func dismissFind() {
        findVisible = false
        searchQuery = ""
        matchCount = 0
        webViewRef?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    private func updateHTML(_ source: String) {
        let ast = parser.parse(source)
        let isDark = colorScheme == .dark
        let body = renderer.renderBody(blocks: ast.blocks)
        html = Self.fullHTML(body: body, isDark: isDark, previewWidth: previewWidth)
    }

    private static let katexVersion = "0.16.11"
    private static let mermaidVersion = "10.9.0"
    private static let prismVersion = "1.29.0"

    private static func fullHTML(body: String, isDark: Bool, previewWidth: PreviewWidth = .normal) -> String {
        let maxWidth: String
        switch previewWidth {
        case .normal: maxWidth = "780px"
        case .middle: maxWidth = "960px"
        case .wide:  maxWidth = "1280px"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/katex.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/prismjs@\(prismVersion)/themes/prism\(isDark ? "-okaidia" : ".min").css">
        <style>
          :root {
            --text: \(isDark ? "#e5e5e7" : "#1d1d1f");
            --bg: \(isDark ? "#2b2b2b" : "#ffffff");
            --code-bg: \(isDark ? "#3a3a3c" : "#f5f5f7");
            --block-bg: \(isDark ? "#1a1a1c" : "#f5f5f7");
            --border: \(isDark ? "#444" : "#d2d2d7");
            --quote: \(isDark ? "#a1a1a6" : "#6e6e73");
            --link: \(isDark ? "#64b5f6" : "#0071e3");
            --heading: \(isDark ? "#f5f5f7" : "#1d1d1f");
            --meta: \(isDark ? "#888" : "#6e6e73");
          }
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Helvetica Neue", sans-serif;
            font-size: 15px; line-height: 1.7;
            color: var(--text); background: var(--bg);
            padding: 24px 28px; max-width: \(maxWidth); margin: 0 auto;
            -webkit-font-smoothing: antialiased;
            word-wrap: break-word; overflow-wrap: break-word;
          }
          h1 { font-size: 2em; font-weight: 700; margin: 1em 0 0.35em; letter-spacing: -0.02em; color: var(--heading); }
          h2 { font-size: 1.5em; font-weight: 650; margin: 0.9em 0 0.3em; letter-spacing: -0.01em; color: var(--heading); }
          h3 { font-size: 1.25em; font-weight: 600; margin: 0.8em 0 0.25em; color: var(--heading); }
          h4 { font-size: 1.1em; font-weight: 600; margin: 0.7em 0 0.2em; }
          h5, h6 { font-size: 1em; font-weight: 600; margin: 0.6em 0 0.15em; }
          p { margin: 0.6em 0; }
          a { color: var(--link); text-decoration: none; }
          a:hover { text-decoration: underline; }
          code {
            font-family: "SF Mono", "JetBrains Mono", Menlo, monospace;
            font-size: 0.88em;
            background: var(--code-bg);
            padding: 0.15em 0.4em;
            border-radius: 4px;
          }
          pre {
            background: var(--block-bg);
            padding: 16px 20px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 0.8em 0;
            border: 1px solid var(--border);
          }
          pre code { background: none; padding: 0; border-radius: 0; }
          blockquote {
            border-left: 3px solid var(--border);
            padding: 0.2em 0 0.2em 18px;
            margin: 0.8em 0;
            color: var(--quote);
          }
          blockquote p { margin: 0.3em 0; }
          ul, ol { margin: 0.5em 0; padding-left: 26px; }
          li { margin: 0.25em 0; }
          li > p { margin: 0.2em 0; }
          hr {
            border: none;
            border-top: 1px solid var(--border);
            margin: 1.5em 0;
          }
          table {
            border-collapse: collapse;
            width: 100%;
            margin: 0.8em 0;
            font-size: 0.95em;
          }
          th, td {
            border: 1px solid var(--border);
            padding: 7px 11px;
            text-align: left;
          }
          th {
            background: var(--code-bg);
            font-weight: 600;
          }
          img { max-width: 100%; border-radius: 6px; margin: 0.5em 0; }
          mark { background: #fde68a; color: #1d1d1f; padding: 0.1em 0.2em; border-radius: 2px; }
          .task-list { list-style: none; padding-left: 0; }
          .task-list li { display: flex; align-items: flex-start; gap: 6px; }
          .task-list input[type="checkbox"] { margin-top: 0.35em; }
          .footnote { margin: 0.4em 0; font-size: 0.9em; color: var(--meta); }
          .footnote sup { margin-right: 4px; }
          nav.toc { background: var(--code-bg); border-radius: 8px; padding: 16px 20px; margin: 0.8em 0; }
          nav.toc ul { list-style: none; padding-left: 16px; }
          nav.toc > ul { padding-left: 0; }
          nav.toc a { color: var(--link); }
          .math-inline, .math-display { overflow-x: auto; }
          .math-display { margin: 0.8em 0; text-align: center; }
          .mermaid { background: \(isDark ? "#1d1d1f" : "#fff"); border-radius: 8px; padding: 16px; margin: 0.8em 0; text-align: center; }
          ::selection { background: \(isDark ? "#3a5f8a" : "#b3d4fc"); }
          @media print {
            body { padding: 0; max-width: none; }
            pre { break-inside: avoid; }
          }
        </style>
        </head>
        <body>
        <div id="content">
        \(body)
        </div>
        <script src="https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/katex.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@\(mermaidVersion)/dist/mermaid.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/prismjs@\(prismVersion)/prism.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/prismjs@\(prismVersion)/plugins/autoloader/prism-autoloader.min.js"></script>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
          try {
            document.querySelectorAll('.math-inline').forEach(function(el) {
              katex.render(el.textContent, el, { displayMode: false, throwOnError: false });
            });
            document.querySelectorAll('.math-display').forEach(function(el) {
              katex.render(el.textContent, el, { displayMode: true, throwOnError: false });
            });
          } catch(e) { console.warn('KaTeX error:', e); }
          try {
            mermaid.initialize({ startOnLoad: true, theme: '\(isDark ? "dark" : "default")' });
          } catch(e) { console.warn('Mermaid error:', e); }
        });
        </script>
        </body>
        </html>
        """
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let html: String
    @Binding var webViewRef: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            webView.loadHTMLString(html, baseURL: URL(string: "https://app.local"))
            context.coordinator.lastHTML = html
        }
        DispatchQueue.main.async {
            self.webViewRef = webView
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastHTML: String = ""
    }
}
