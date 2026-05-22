import SwiftUI
import WebKit

struct PreviewWebView: NSViewRepresentable {
    @Environment(AppState.self) private var appState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        if let mermaidPath = Bundle.main.path(forResource: "mermaid.min", ofType: "js"),
           let mermaidJS = try? String(contentsOfFile: mermaidPath) {
            let userScript = WKUserScript(
                source: mermaidJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(userScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = appState.renderedHTML
        guard html != context.coordinator.lastLoadedHTML, !html.isEmpty else { return }
        context.coordinator.lastLoadedHTML = html

        if context.coordinator.pageLoaded {
            // Fast path: inject body content via JS — avoids full DOM rebuild
            if let body = extractBody(from: html) {
                let escaped = escapeForJS(body)
                webView.evaluateJavaScript("window._replaceBody(`\(escaped)`)")
            }
        } else {
            // First load: full page load to establish CSS + JS context
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func extractBody(from html: String) -> String? {
        guard let start = html.range(of: "<body>"),
              let end = html.range(of: "</body>", range: start.upperBound..<html.endIndex) else {
            return nil
        }
        return String(html[start.upperBound..<end.lowerBound])
    }

    private func escapeForJS(_ str: String) -> String {
        var result = ""
        result.reserveCapacity(str.utf8.count)
        for char in str {
            switch char {
            case "\\": result += "\\\\"
            case "`":  result += "\\`"
            case "$":  result += "\\$"
            default:   result.append(char)
            }
        }
        return result
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String = ""
        var pageLoaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            // Define a JS function for incremental body updates.
            // Kept alive across file switches — no CSS/JS redownload.
            let js = """
            window._replaceBody = function(html) {
                document.body.innerHTML = html;
                if (typeof mermaid !== 'undefined' && mermaid.run) {
                    setTimeout(function() {
                        try { mermaid.run({ nodes: document.querySelectorAll('.mermaid') }); } catch(e) { }
                    }, 50);
                }
            };
            """
            webView.evaluateJavaScript(js)
        }
    }
}
