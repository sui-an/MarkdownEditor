import SwiftUI
import WebKit
import AppKit

// MARK: - Per-WebView state + navigation delegate

final class WebViewState: NSObject, WKNavigationDelegate {
    var templateReady = false
    var needsScrollReset = false
    var lastBodyHTML = ""
    var hasLoadedContent = false
    private var scrollerConfigured = false

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
        templateReady = true
        // If body content was already saved before the template finished loading
        // (e.g. re-attaching a cached WebView where content had been generated),
        // inject it now so the preview isn't blank.
        if !lastBodyHTML.isEmpty {
            updateBodyViaJS(webView, bodyHTML: lastBodyHTML)
        }
        webView.evaluateJavaScript("""
        if (typeof mermaid !== 'undefined') { mermaid.run({ querySelector: '.mermaid' }); }
        if (typeof hljs !== 'undefined') { hljs.highlightAll(); }
        """)
        if needsScrollReset {
            needsScrollReset = false
            webView.evaluateJavaScript("window.scrollTo(0, 0)")
        }
    }

    func updateBodyViaJS(_ webView: WKWebView, bodyHTML: String) {
        guard let encoded = try? JSONEncoder().encode(bodyHTML),
              let jsonStr = String(data: encoded, encoding: .utf8) else { return }
        webView.evaluateJavaScript("""
        document.getElementById('md-content').innerHTML = \(jsonStr);
        if (typeof hljs !== 'undefined') hljs.highlightAll();
        if (typeof mermaid !== 'undefined') mermaid.run({ querySelector: '.mermaid' });
        """)
    }

    func updateBaseURL(_ webView: WKWebView, baseURL: URL?) {
        guard let baseURLStr = baseURL?.absoluteString else { return }
        let escaped = (try? JSONEncoder().encode(baseURLStr))
            .flatMap { String(data: $0, encoding: .utf8) } ?? baseURLStr
        webView.evaluateJavaScript("""
        var oldBase = document.querySelector('base');
        if (oldBase) oldBase.remove();
        var base = document.createElement('base');
        base.href = \(escaped);
        document.head.appendChild(base);
        """)
    }
}

// MARK: - WebView cache (per-fileID)

final class WebViewCache {
    static let shared = WebViewCache()

    private var cache: [UUID: WKWebView] = [:]
    private var states: [ObjectIdentifier: WebViewState] = [:]
    private var urlToFileID: [URL: UUID] = [:]
    private var accessOrder: [UUID] = []
    private let maxEntries = 10

    /// Returns the WebView (and its state) for the given fileID.
    /// Creates a new WebView on first access. LRU evicts when over limit.
    func webView(for fileID: UUID, url: URL) -> (WKWebView, WebViewState) {
        urlToFileID[url] = fileID

        if let existing = cache[fileID] {
            touch(fileID)
            return (existing, state(for: existing))
        }

        let webView = createWebView()
        let state = WebViewState()
        webView.navigationDelegate = state

        cache[fileID] = webView
        states[ObjectIdentifier(webView)] = state
        accessOrder.append(fileID)

        if accessOrder.count > maxEntries {
            evictOldest()
        }

        return (webView, state)
    }

    /// Remove cached WebView by fileID (file closed).
    func remove(for fileID: UUID) {
        guard let webView = cache.removeValue(forKey: fileID) else { return }
        states.removeValue(forKey: ObjectIdentifier(webView))
        accessOrder.removeAll { $0 == fileID }
        urlToFileID = urlToFileID.filter { $0.value != fileID }
    }

    /// Remove cached WebView by file URL.
    func removeWebView(for url: URL) {
        guard let fileID = urlToFileID[url] else { return }
        remove(for: fileID)
    }

    private func touch(_ fileID: UUID) {
        accessOrder.removeAll { $0 == fileID }
        accessOrder.append(fileID)
    }

    private func evictOldest() {
        guard accessOrder.count > maxEntries else { return }
        let oldest = accessOrder.removeFirst()
        remove(for: oldest)
    }

    private func state(for webView: WKWebView) -> WebViewState {
        states[ObjectIdentifier(webView)]!
    }

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()

        // highlight.js — injected once, persists across incremental DOM updates
        if let hljsPath = Bundle.main.path(forResource: "highlight.min", ofType: "js"),
           let hljsJS = try? String(contentsOfFile: hljsPath) {
            let script = WKUserScript(source: hljsJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // mermaid.min.js — injected once, persists across incremental DOM updates.
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
                        var binary = atob(src.substring(comma + 1));
                        var bytes = new Uint8Array(binary.length);
                        for (var i = 0; i < binary.length; i++) {
                            bytes[i] = binary.charCodeAt(i);
                        }
                        var blob = new Blob([bytes], {type: mime});
                        img.src = URL.createObjectURL(blob);
                    } catch(e) {}
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
        if let sv = findScrollView(in: webView) {
            sv.scrollerStyle = .overlay
        }

        return webView
    }
}

// MARK: - PreviewWebView

struct PreviewWebView: NSViewRepresentable {
    /// Full HTML document (template + body) — used for first load.
    let html: String
    /// Body-only HTML fragment — used for incremental DOM updates via JS.
    let bodyHTML: String
    let hasFile: Bool
    /// The file's parent directory — WKWebView baseURL for resolving relative resources.
    let baseURL: URL?
    /// The actual file URL — used as cache key for per-document WebView lookup.
    let fileURL: URL?
    let fileID: UUID?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard hasFile, let fileID, let fileURL else {
            if !container.subviews.isEmpty {
                container.subviews.forEach { $0.removeFromSuperview() }
            }
            context.coordinator.currentWebView = nil
            return
        }

        let (webView, state) = WebViewCache.shared.webView(for: fileID, url: fileURL)

        if context.coordinator.currentWebView !== webView {
            // Add new WebView FIRST, then remove old ones — avoids a blank
            // container flash while the old subview is missing.
            context.coordinator.currentWebView = webView

            state.configureScrollView(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            container.subviews.filter { $0 !== webView }.forEach { $0.removeFromSuperview() }

            if state.hasLoadedContent {
                // WebView already has the template loaded — avoid loadHTMLString
                // (which causes a WKWebView page-reload flash). Just inject the body.
                if !bodyHTML.isEmpty {
                    state.lastBodyHTML = bodyHTML
                    state.updateBodyViaJS(webView, bodyHTML: bodyHTML)
                }
            } else if !html.isEmpty {
                state.hasLoadedContent = true
                state.needsScrollReset = true
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        } else {
            if state.hasLoadedContent {
                if !bodyHTML.isEmpty && bodyHTML != state.lastBodyHTML {
                    state.lastBodyHTML = bodyHTML
                    state.updateBodyViaJS(webView, bodyHTML: bodyHTML)
                }
            } else if !html.isEmpty {
                state.hasLoadedContent = true
                state.needsScrollReset = true
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        // WebView lifecycle is managed by WebViewCache.
        // Just detach from the container — the WebView stays alive for
        // later re-use when the user switches back to this file.
        container.subviews.forEach { $0.removeFromSuperview() }
        coordinator.currentWebView = nil
    }

    final class Coordinator {
        var currentWebView: WKWebView?
    }
}

private func findScrollView(in view: NSView) -> NSScrollView? {
    if let sv = view as? NSScrollView { return sv }
    for sub in view.subviews {
        if let found = findScrollView(in: sub) { return found }
    }
    return nil
}
