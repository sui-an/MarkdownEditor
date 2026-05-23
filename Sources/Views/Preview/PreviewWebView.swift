import SwiftUI
import WebKit
import AppKit

// MARK: - Shared WebView pool

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
        findScrollView(in: webView)?.scrollerStyle = .overlay
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
        webView.wantsLayer = true
        findScrollView(in: webView)?.scrollerStyle = .overlay

        return webView
    }

    func handleMemoryPressure() { preWarmedView = nil }
}

private func findScrollView(in view: NSView) -> NSScrollView? {
    if let sv = view as? NSScrollView { return sv }
    for sub in view.subviews {
        if let found = findScrollView(in: sub) { return found }
    }
    return nil
}

// MARK: - PreviewWebView

struct PreviewWebView: NSViewRepresentable {
    let html: String
    let hasFile: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ClipContainer {
        let container = ClipContainer()
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let webView = WebViewPool.shared.dequeue()
        webView.navigationDelegate = context.coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.configureScrollView(webView)
        return container
    }

    func updateNSView(_ container: ClipContainer, context: Context) {
        guard let webView = container.subviews.first as? WKWebView else { return }
        context.coordinator.configureScrollView(webView)
        guard hasFile else {
            if context.coordinator.lastLoadedHTML != "" {
                context.coordinator.lastLoadedHTML = ""
                webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            }
            return
        }
        guard html != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = html

        context.coordinator.debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak webView, html] in
            webView?.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    static func dismantleNSView(_ container: ClipContainer, coordinator: Coordinator) {
        guard let webView = container.subviews.first as? WKWebView else { return }
        webView.removeFromSuperview()
        coordinator.debounceWorkItem?.cancel()
        coordinator.debounceWorkItem = nil
        coordinator.lastLoadedHTML = ""
        WebViewPool.shared.enqueue(webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String = ""
        var debounceWorkItem: DispatchWorkItem?
        var scrollerConfigured = false

        func configureScrollView(_ webView: WKWebView) {
            guard !scrollerConfigured else { return }
            scrollerConfigured = true
            if let sv = findScrollView(in: webView) {
                sv.scrollerStyle = .overlay
                sv.verticalScrollElasticity = .none
                sv.horizontalScrollElasticity = .none
            }
        }

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

// MARK: - Clip container

final class ClipContainer: NSView {
}
