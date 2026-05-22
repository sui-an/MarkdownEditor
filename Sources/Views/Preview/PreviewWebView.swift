import SwiftUI
import WebKit
import AppKit

// MARK: - Shared WebView pool for pre-warming

final class WebViewPool {
    static let shared = WebViewPool()

    private var preWarmedView: WKWebView?

    func dequeue() -> WKWebView {
        if let view = preWarmedView {
            preWarmedView = nil
            return view
        }
        return createWebView()
    }

    func enqueue(_ webView: WKWebView?) {
        guard let webView else { return }
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        webView.navigationDelegate = nil

        preWarmedView?.loadHTMLString("<html><body></body></html>", baseURL: nil)
        preWarmedView = webView
    }

    func preWarm() {
        guard preWarmedView == nil else { return }
        let view = createWebView()
        view.loadHTMLString("<html><body></body></html>", baseURL: nil)
        preWarmedView = view
    }

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()

        if let hljsPath = Bundle.main.path(forResource: "highlight.min", ofType: "js"),
           let hljsJS = try? String(contentsOfFile: hljsPath) {
            let script = WKUserScript(source: hljsJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        for subview in webView.subviews {
            if let scrollView = subview as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                break
            }
        }

        return webView
    }

    func handleMemoryPressure() {
        preWarmedView = nil
    }
}

// MARK: - PreviewWebView

struct PreviewWebView: NSViewRepresentable {
    @Environment(AppState.self) private var appState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WebViewPool.shared.dequeue()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if appState.currentFileURL == nil {
            if context.coordinator.lastLoadedHTML != "" {
                context.coordinator.lastLoadedHTML = ""
                webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            }
            return
        }
        let html = appState.renderedHTML
        guard html != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.lastLoadedHTML = ""
        WebViewPool.shared.enqueue(nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("""
            if (typeof mermaid !== 'undefined') {
                mermaid.run({ querySelector: '.mermaid' });
            }
            if (typeof hljs !== 'undefined') {
                hljs.highlightAll();
            }
            """)
        }
    }
}
