import SwiftUI
import WebKit
import AppKit

// MARK: - Per-WebView state + navigation delegate

final class WebViewState: NSObject, WKNavigationDelegate {
    var needsScrollReset = false
    var lastBodyHTML = ""
    var lastBaseURL: String?
    var lastSearchQuery = ""
    var hasLoadedContent = false
    /// Non-nil when a font-size change arrived before the page finished loading.
    /// Applied in webView(_:didFinish:) so we never evaluate JS on an empty page.
    var pendingFontSize: CGFloat?
    /// True once mermaid.min.js has been injected into this WebView.
    /// Reset to false on page navigation (loadHTMLString).
    var mermaidInjected = false
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
        mermaidInjected = false

        if !lastBodyHTML.isEmpty {
            let base = lastBaseURL
            let query = lastSearchQuery
            lastBaseURL = nil
            lastSearchQuery = ""
            updateBodyViaJS(webView, bodyHTML: lastBodyHTML, baseURL: base, searchQuery: query)
        }
        webView.evaluateJavaScript("""
        if (typeof hljs !== 'undefined') { hljs.highlightAll(); }
        """)
        if let size = pendingFontSize {
            injectFontSize(webView, fontSize: size)
            pendingFontSize = nil
        }
        if needsScrollReset {
            needsScrollReset = false
            webView.evaluateJavaScript("window.scrollTo(0, 0)")
        }
        // Check if mermaid is needed (tiny evaluateJavaScript, no 3.2MB payload).
        // If the page has .mermaid elements, inject mermaid.min.js.
        tryInjectMermaidInitial(webView)
    }

    /// Initial page load path — checks for `.mermaid` via native evaluateJavaScript
    /// (tiny payload, <1ms) before deciding to inject 3.2MB mermaid.min.js.
    private func tryInjectMermaidInitial(_ webView: WKWebView) {
        guard !mermaidInjected, let mmdJS = WebViewCache.cachedMermaidJS else { return }
        webView.evaluateJavaScript("document.querySelector('.mermaid') !== null") { [weak self] result, _ in
            guard let self, let needsMermaid = result as? Bool, needsMermaid,
                  !self.mermaidInjected else { return }
            self.mermaidInjected = true
            self.doInjectMermaid(webView, mmdJS: mmdJS)
        }
    }

    /// Incremental body update path — uses cached bodyHTML for a cheap
    /// contains() check on the Swift side before injecting 3.2MB.
    /// If mermaid is already injected, just re-run for new content.
    private func tryInjectMermaidIncremental(_ webView: WKWebView) {
        guard let mmdJS = WebViewCache.cachedMermaidJS,
              lastBodyHTML.contains("mermaid") else { return }
        if mermaidInjected {
            webView.evaluateJavaScript("mermaid.run({ querySelector: '.mermaid' })")
            return
        }
        mermaidInjected = true
        doInjectMermaid(webView, mmdJS: mmdJS)
    }

    private func doInjectMermaid(_ webView: WKWebView, mmdJS: String) {
        let literal = String.jsLiteral(mmdJS)
        webView.evaluateJavaScript("""
        (function() {
            if (typeof mermaid !== 'undefined') return;
            var s = document.createElement('script');
            s.textContent = \(literal);
            document.head.appendChild(s);
            mermaid.run({ querySelector: '.mermaid' });
        })();
        """)
    }

    func updateBodyViaJS(_ webView: WKWebView, bodyHTML: String, baseURL: String? = nil, searchQuery: String = "") {
        let jsonStr = String.jsLiteral(bodyHTML)
        let baseJSCode: String
        if let url = baseURL {
            let literal = String.jsLiteral(url)
            baseJSCode = """
            var b = document.querySelector('base');
            if (!b) { b = document.createElement('base'); document.head.appendChild(b); }
            b.href = \(literal);
            """
        } else {
            baseJSCode = ""
        }
        webView.evaluateJavaScript("""
        \(baseJSCode)
        document.getElementById('md-content').innerHTML = \(jsonStr);
        if (typeof hljs !== 'undefined') hljs.highlightAll();
        \(SearchJS.highlight(query: searchQuery))
        """)
        tryInjectMermaidIncremental(webView)
    }

}

// MARK: - WebView cache (shared single WebView)

final class WebViewCache {
    // Pre-cached JS scripts — read from disk once, avoids blocking the main
    // thread on every first-time WKWebView creation (mermaid.min.js is 3.2MB).
    private static let cachedHighlightJS: String? = {
        guard let path = Bundle.main.path(forResource: "highlight.min", ofType: "js"),
              let content = try? String(contentsOfFile: path) else { return nil }
        return content
    }()

    static let cachedMermaidJS: String? = {
        guard let path = Bundle.main.path(forResource: "mermaid.min", ofType: "js"),
              let content = try? String(contentsOfFile: path) else { return nil }
        return content
    }()

    /// Warm up the JS cache on a background queue during app launch.
    /// Does nothing if the cache has already been populated.
    static func preloadScripts() {
        _ = cachedHighlightJS
        _ = cachedMermaidJS
    }

    private var sharedWebView: WKWebView?
    private var sharedState: WebViewState?

    /// Returns the shared WebView (and its state). Creates on first access
    /// with a preloaded CSS template so all content goes via `updateBodyViaJS`.
    func webView(for fileID: String, url: URL) -> (WKWebView, WebViewState) {
        if let wv = sharedWebView, let state = sharedState {
            return (wv, state)
        }
        let webView = createWebView()
        let state = WebViewState()
        webView.navigationDelegate = state
        sharedWebView = webView
        sharedState = state

        state.hasLoadedContent = true
        let css = MarkdownParser.previewCSS
        webView.loadHTMLString("""
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style></head><body><div id="md-content"></div></body></html>
        """, baseURL: nil)

        return (webView, state)
    }

    /// No-op: shared WebView stays alive for all files.
    func remove(for fileID: String) {}

    /// No-op: shared WebView stays alive for all files.
    func removeWebView(for url: URL) {}

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()

        // highlight.js — injected once, persists across incremental DOM updates.
        if let hljsJS = Self.cachedHighlightJS {
            let script = WKUserScript(source: hljsJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // mermaid.min.js is NOT added unconditionally (it's 3.2MB and most
        // files don't have mermaid blocks).  It's injected dynamically via
        // injectMermaidIfNeeded() only when the rendered content actually
        // contains `.mermaid` elements.

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
    let html: String
    let bodyHTML: String
    let hasFile: Bool
    let baseURL: URL?
    let fileURL: URL?
    let fileID: String?
    var viewRefs: ViewRefs?
    let previewContentWidth: Int
    var themeMode: String = "system"
    var fontSize: CGFloat = 15
    let webViewCache: WebViewCache

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

        let (webView, state) = webViewCache.webView(for: fileID, url: fileURL)

        // Theme change — @AppStorage triggers updateNSView directly
        let isDark = ThemeManager.isDark(for: themeMode)
        if context.coordinator.lastAppliedIsDark != isDark {
            context.coordinator.lastAppliedIsDark = isDark
            injectTheme(webView, isDark: isDark)
        }

        // Font size sync — scale preview body font proportionally to editor font
        if context.coordinator.lastAppliedFontSize != fontSize {
            context.coordinator.lastAppliedFontSize = fontSize
            if state.hasLoadedContent {
                injectFontSize(webView, fontSize: fontSize)
            } else {
                // Defer injection until the page actually finishes loading,
                // avoiding evaluateJavaScript on an empty WKWebView.
                state.pendingFontSize = fontSize
            }
        }

        if context.coordinator.currentWebView !== webView {
            context.coordinator.currentWebView = webView
            context.coordinator.lastPreviewContentWidth = nil
            viewRefs?.webView = webView

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
                    state.lastBaseURL = fileURL.deletingLastPathComponent().absoluteString
                    state.lastSearchQuery = viewRefs?.lastSearchQuery ?? ""
                    state.updateBodyViaJS(webView, bodyHTML: bodyHTML, baseURL: state.lastBaseURL, searchQuery: state.lastSearchQuery)
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
                    state.lastBaseURL = fileURL.deletingLastPathComponent().absoluteString
                    state.lastSearchQuery = viewRefs?.lastSearchQuery ?? ""
                    state.updateBodyViaJS(webView, bodyHTML: bodyHTML, baseURL: state.lastBaseURL, searchQuery: state.lastSearchQuery)
                }
                // Toggle content width based on previewContentWidth setting
                if context.coordinator.lastPreviewContentWidth != previewContentWidth {
                    context.coordinator.lastPreviewContentWidth = previewContentWidth
                    let (maxWidth, margin) = widthValues(previewContentWidth)
                    webView.evaluateJavaScript("""
                        document.body.style.maxWidth = "\(maxWidth)";
                        document.body.style.margin = "\(margin)";
                        """)
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
        // Just detach from the container — the shared WebView stays alive.
        container.subviews.forEach { $0.removeFromSuperview() }
        coordinator.currentWebView = nil
    }

    final class Coordinator {
        var currentWebView: WKWebView?
        var lastPreviewContentWidth: Int?
        var lastAppliedIsDark: Bool?
        var lastAppliedFontSize: CGFloat?
        private var themeObserver: Any?

        init() {
            themeObserver = NotificationCenter.default.addObserver(
                forName: .themeDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let webView = self.currentWebView else { return }
                let isDark = (notification.userInfo?["isDark"] as? Bool) ?? false
                guard lastAppliedIsDark != isDark else { return }
                lastAppliedIsDark = isDark
                injectTheme(webView, isDark: isDark)
            }
        }

        deinit {
            if let observer = themeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

private func findScrollView(in view: NSView) -> NSScrollView? {
    if let sv = view as? NSScrollView { return sv }
    for sub in view.subviews {
        if let found = findScrollView(in: sub) {
            return found
        }
    }
    return nil
}

// MARK: - Helpers

private func widthValues(_ mode: Int) -> (maxWidth: String, margin: String) {
    switch mode {
    case 1: return ("960px", "0 auto")
    case 2: return ("none", "0 auto")
    default: return ("720px", "0 auto")
    }
}

// MARK: - Theme injection

/// Injects a `<style>` element into the preview WebView that overrides all
/// CSS custom properties with the values for the requested appearance.  Uses
/// `!important` to beat the `@media (prefers-color-scheme)` selectors in the
/// base CSS so manual theme switching works regardless of `NSApp.appearance`.
private func injectTheme(_ webView: WKWebView, isDark: Bool) {
    let vars: [(String, String)] = isDark ? [
        ("--text-color",         "#f5f5f7"),
        ("--code-bg",            "rgba(255,255,255,0.1)"),
        ("--pre-bg",             "rgba(255,255,255,0.06)"),
        ("--blockquote-border",  "#555"),
        ("--blockquote-color",   "#aaa"),
        ("--th-bg",              "#333"),
        ("--table-border",       "#444"),
        ("--link-color",         "#6ea8fe"),
    ] : [
        ("--text-color",         "#1d1d1f"),
        ("--code-bg",            "rgba(0,0,0,0.05)"),
        ("--pre-bg",             "rgba(0,0,0,0.04)"),
        ("--blockquote-border",  "#ccc"),
        ("--blockquote-color",   "#888"),
        ("--th-bg",              "#f5f5f7"),
        ("--table-border",       "#ddd"),
        ("--link-color",         "#007aff"),
    ]

    let css = vars.map { "\($0.0): \($0.1) !important;" }.joined(separator: " ")
    webView.evaluateJavaScript("""
    (function() {
        var id = 'md-theme-override';
        var el = document.getElementById(id);
        if (!el) {
            el = document.createElement('style');
            el.id = id;
            document.head.appendChild(el);
        }
        el.textContent = ':root { ' + \(String.jsLiteral(css)) + ' }';
    })();
    """)
}

/// Injects a CSS `font-size` rule into the preview body, scaled proportionally
/// from the editor's default (13pt → 15px CSS base).
private func injectFontSize(_ webView: WKWebView, fontSize: CGFloat) {
    let scale = fontSize / 13.0
    let previewSize = Int(15.0 * scale)
    webView.evaluateJavaScript("""
        document.body.style.setProperty('font-size', '\(previewSize)px', 'important');
        """)
}
