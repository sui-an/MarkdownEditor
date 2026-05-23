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

        // highlight.js — injected once, persists across incremental DOM updates
        if let hljsPath = Bundle.main.path(forResource: "highlight.min", ofType: "js"),
           let hljsJS = try? String(contentsOfFile: hljsPath) {
            let script = WKUserScript(source: hljsJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // mermaid.min.js — injected once (not inlined in every HTML string).
        // This saves ~3.3MB per preview update and is required for incremental
        // DOM updates where inline scripts from loadHTMLString never run.
        if let mmdPath = Bundle.main.path(forResource: "mermaid.min", ofType: "js"),
           let mmdJS = try? String(contentsOfFile: mmdPath) {
            let script = WKUserScript(source: mmdJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // Convert data URI images to Blob URLs — WKWebView may struggle with
        // very long base64 data URIs loaded via loadHTMLString.
        let blobScriptSrc = """
        (function() {
            function fixDataURIs() {
                document.querySelectorAll('img[src^="data:"]').forEach(function(img) {
                    try {
                        var src = img.src;
                        var comma = src.indexOf(',');
                        if (comma === -1) return;
                        var mime = src.substring(5, comma).split(';')[0];
                        var raw = src.substring(comma + 1);
                        var binary = atob(raw);
                        var bytes = new Uint8Array(binary.length);
                        for (var i = 0; i < binary.length; i++) {
                            bytes[i] = binary.charCodeAt(i);
                        }
                        var blob = new Blob([bytes], {type: mime});
                        img.src = URL.createObjectURL(blob);
                    } catch(e) {
                        // keep original src
                    }
                });
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', fixDataURIs);
            } else {
                fixDataURIs();
            }
        })();
        """
        let blobScript = WKUserScript(source: blobScriptSrc, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(blobScript)

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
    /// Full HTML document (template + body) — used for initial loadHTMLString
    /// and on file switches where a fresh page load is required.
    let html: String
    /// Body-only HTML fragment — used for incremental DOM updates via JS
    /// after the template has been loaded once. Avoids full WKWebView page
    /// rebuild (DOM reparse, script re-execution, scroll position loss).
    let bodyHTML: String
    let hasFile: Bool
    /// Non-nil when a file is open — WKWebView loads HTML with the file's
    /// directory as baseURL so data URIs have a non-opaque security origin
    /// (known WebKit issue: data URIs may fail to load with baseURL: nil).
    let baseURL: URL?

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
            if context.coordinator.templateReady {
                context.coordinator.templateReady = false
                context.coordinator.lastBodyHTML = ""
                webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            }
            return
        }

        guard bodyHTML != context.coordinator.lastBodyHTML else { return }
        context.coordinator.lastBodyHTML = bodyHTML

        context.coordinator.debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak webView, bodyHTML, html, baseURL, coordinator = context.coordinator] in
            guard let webView else { return }

            if coordinator.templateReady && coordinator.lastBaseURL == baseURL {
                // Template already cached — update content via JS injection.
                // This avoids full WKWebView page rebuild.
                coordinator.updateBodyViaJS(webView, bodyHTML: bodyHTML)
            } else {
                // First load or file switch — use loadHTMLString to set up
                // the page with content embedded so there is no blank flash.
                coordinator.lastBaseURL = baseURL
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }
        context.coordinator.debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    static func dismantleNSView(_ container: ClipContainer, coordinator: Coordinator) {
        guard let webView = container.subviews.first as? WKWebView else { return }
        webView.removeFromSuperview()
        coordinator.debounceWorkItem?.cancel()
        coordinator.debounceWorkItem = nil
        coordinator.lastBodyHTML = ""
        coordinator.templateReady = false
        coordinator.lastBaseURL = nil
        WebViewPool.shared.enqueue(webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastBodyHTML: String = ""
        var lastBaseURL: URL?
        var templateReady = false
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

        /// Replace content div innerHTML and re-apply highlight.js + mermaid.
        /// JSON-encoding the HTML guarantees safe JavaScript string escaping.
        func updateBodyViaJS(_ webView: WKWebView, bodyHTML: String) {
            guard let encoded = try? JSONEncoder().encode(bodyHTML),
                  let jsonStr = String(data: encoded, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript("""
            document.getElementById('md-content').innerHTML = \(jsonStr);
            if (typeof hljs !== 'undefined') hljs.highlightAll();
            if (typeof mermaid !== 'undefined') mermaid.run({ querySelector: '.mermaid' });
            """)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            templateReady = true
            // Run highlight.js and mermaid on the initial content.
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
