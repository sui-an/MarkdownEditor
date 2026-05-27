import Foundation
#if canImport(CCmarkGfm)
import CCmarkGfm
#endif

enum MarkdownParser {

    #if canImport(CCmarkGfm)
    private static var gfmExtensionsRegistered = false

    private static func ensureGFMExtensions() {
        guard !gfmExtensionsRegistered else { return }
        cmark_gfm_core_extensions_ensure_registered()
        gfmExtensionsRegistered = true
    }
    #endif

    // MARK: - Public API

    /// cmark-gfm imposes a 4096-byte URL limit, easily exceeded by base64
    /// data URIs. Convert `![alt](data:image/...;base64,...)` to raw `<img>`
    /// HTML so cmark-gfm passes it through unchanged.
    private static let base64ImageRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"!\[([^\]]*)\]\((data:image/[^;]+;base64,[A-Za-z0-9+/=]+)\)"#,
            options: []
        )
    }()

    private static func preprocessBase64Images(_ markdown: String) -> String {
        let nsString = markdown as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var result = ""
        var lastEnd = 0

        for match in base64ImageRegex.matches(in: markdown, range: range) {
            let fullRange = match.range(at: 0)
            let altRange = match.range(at: 1)
            let urlRange = match.range(at: 2)

            result += nsString.substring(with: NSRange(location: lastEnd, length: fullRange.location - lastEnd))

            let alt = nsString.substring(with: altRange)
            let url = nsString.substring(with: urlRange)
            // HTML-escape alt text
            let escapedAlt = alt
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            result += "<img src=\"\(url)\" alt=\"\(escapedAlt)\">"

            lastEnd = fullRange.location + fullRange.length
        }

        if lastEnd < nsString.length {
            result += nsString.substring(with: NSRange(location: lastEnd, length: nsString.length - lastEnd))
        }

        return result
    }

    /// Parse markdown to full HTML document. Thread-safe.
    /// Returns both the body-only HTML (for incremental JS injection) and the
    /// full document (for initial loadHTMLString).
    static func parseToHTML(_ markdown: String) -> (body: String, full: String) {
        #if canImport(CCmarkGfm)
        ensureGFMExtensions()
        #endif

        let mermaidResult = extractMermaidBlocks(markdown)
        // Pre-process base64 data URIs before cmark-gfm (avoids 4096-byte URL limit)
        let preprocessed = preprocessBase64Images(mermaidResult.text)
        let bodyHTML = renderBody(preprocessed)
        let finalBody = injectHeadingIDs(reinsertMermaidBlocks(bodyHTML, mermaidResult))

        let css = Self.previewCSS
        let mermaidScript = mermaidResult.blocks.isEmpty ? "" : mermaidHTML()

        let full = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        \(mermaidScript)
        </head><body><div id="md-content">\(finalBody)</div></body></html>
        """
        return (finalBody, full)
    }

    /// Parse markdown to HTML body fragment only (no wrapper, no CSS).
    static func parseToHTMLBody(_ markdown: String) -> String {
        #if canImport(CCmarkGfm)
        ensureGFMExtensions()
        #endif

        let mermaidResult = extractMermaidBlocks(markdown)
        // Pre-process base64 data URIs before cmark-gfm (avoids 4096-byte URL limit)
        let preprocessed = preprocessBase64Images(mermaidResult.text)
        let bodyHTML = renderBody(preprocessed)
        return injectHeadingIDs(reinsertMermaidBlocks(bodyHTML, mermaidResult))
    }

    // MARK: - cmark-gfm rendering (with regex fallback)

    #if canImport(CCmarkGfm)
    private static func renderBody(_ markdown: String) -> String {
        guard let cstr = markdown.cString(using: .utf8) else { return fallbackRenderBody(markdown) }
        let len = strlen(cstr)
        // CMARK_OPT_UNSAFE prevents cmark-gfm from filtering/escaping raw HTML
        // (needed for our pre-processed <img src="data:..."> tags).
        let options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE

        guard let parser = cmark_parser_new(options) else {
            return fallbackRenderBody(markdown)
        }

        // Attach GFM extensions registered by ensureGFMExtensions()
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, cstr, len)

        guard let doc = cmark_parser_finish(parser) else {
            cmark_parser_free(parser)
            return fallbackRenderBody(markdown)
        }
        defer { cmark_node_free(doc) }
        cmark_parser_free(parser)

        guard let htmlCStr = cmark_render_html(doc, options, nil) else {
            return fallbackRenderBody(markdown)
        }
        defer { free(htmlCStr) }

        return String(cString: htmlCStr)
    }
    #else
    private static func renderBody(_ markdown: String) -> String {
        return fallbackRenderBody(markdown)
    }
    #endif

    // MARK: - Mermaid extraction

    private struct MermaidExtractResult {
        let text: String
        let blocks: [String]
    }

    private static func extractMermaidBlocks(_ markdown: String) -> MermaidExtractResult {
        var text = ""
        var blocks: [String] = []
        var lastEnd = 0
        let nsText = markdown as NSString

        let pattern = try! NSRegularExpression(
            pattern: #"```mermaid\s*\n([\s\S]*?)```"#,
            options: .caseInsensitive
        )

        for match in pattern.matches(in: markdown, range: NSRange(location: 0, length: nsText.length)) {
            let full = match.range(at: 0)
            let content = match.range(at: 1)

            text += nsText.substring(with: NSRange(location: lastEnd, length: full.location - lastEnd))
            text += "%%MERMAID_\(blocks.count)%%"
            blocks.append(nsText.substring(with: content))
            lastEnd = full.location + full.length
        }

        if lastEnd < nsText.length {
            text += nsText.substring(with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
        }

        return MermaidExtractResult(text: text, blocks: blocks)
    }

    private static func reinsertMermaidBlocks(_ html: String, _ result: MermaidExtractResult) -> String {
        var out = html
        for (i, block) in result.blocks.enumerated() {
            // Do NOT HTML-escape mermaid content — angle brackets are valid
            // diagram syntax (e.g. A-->B, A-->|text|B).
            let div = "<div class=\"mermaid\">\n\(block)\n</div>"
            out = out.replacingOccurrences(of: "%%MERMAID_\(i)%%", with: div)
        }
        return out
    }

    /// Inject id="heading-{slug}" into <h1>-<h6> tags for outline scroll sync.
    private static func injectHeadingIDs(_ html: String) -> String {
        let nsHTML = html as NSString
        guard let regex = try? NSRegularExpression(
            pattern: #"<h([1-6])([^>]*)>(.*?)</h\1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return html }

        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let full = match.range(at: 0)
            let levelRange = match.range(at: 1)
            let attrsRange = match.range(at: 2)
            let contentRange = match.range(at: 3)

            result += nsHTML.substring(with: NSRange(location: lastEnd, length: full.location - lastEnd))

            let level = nsHTML.substring(with: levelRange)
            let existingAttrs = nsHTML.substring(with: attrsRange)
            let content = nsHTML.substring(with: contentRange)

            // Strip any inline HTML tags from content for clean slug
            let plainText = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let slug = HeadingParser.slugify(plainText)
            let idAttr = " id=\"heading-\(slug)\""

            result += "<h\(level)\(existingAttrs)\(idAttr)>\(content)</h\(level)>"
            lastEnd = full.location + full.length
        }
        if lastEnd < nsHTML.length {
            result += nsHTML.substring(with: NSRange(location: lastEnd, length: nsHTML.length - lastEnd))
        }
        return result
    }

    /// Returns the shell of the preview HTML template — everything except
    /// the body content. The caller fills <div id="md-content">BODY</div>.
    /// Used by PreviewWebView to load a valid template before content is ready.
    /// Includes the mermaid runner script — it's harmless when no mermaid
    /// blocks exist (typeof check skips execution), but avoids needing a
    /// full page reload when switching to a file that has mermaid diagrams.
    static func previewTemplateShell() -> String {
        let css = previewCSS
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        \(mermaidHTML())
        </head><body><div id="md-content"></div></body></html>
        """
    }

    /// Returns the runner script. mermaid.min.js itself is loaded via
    /// WKUserScript (WebViewPool) so it persists across incremental
    /// DOM updates without re-injecting 3.3MB of JS on every change.
    private static func mermaidHTML() -> String {
        """
        <script>
        setTimeout(function() {
            if (typeof mermaid !== 'undefined') {
                mermaid.run({ querySelector: '.mermaid' });
            }
        }, 10);
        </script>
        """
    }

    /// Fallback parser when cmark-gfm is unavailable. Wraps lines in <p> tags
    /// and escapes HTML. Kept minimal to avoid the old regex performance issues.
    private static func fallbackRenderBody(_ markdown: String) -> String {
        var html = ""
        var inCodeBlock = false
        var codeLang = ""

        markdown.enumerateSubstrings(in: markdown.startIndex..., options: .byLines) { line, _, _, _ in
            guard let line else { return }
            if line.hasPrefix("```") && !inCodeBlock {
                inCodeBlock = true
                codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                html += "<pre><code class=\"language-\(escapeHTML(codeLang))\">"
                return
            }
            if line.hasPrefix("```") && inCodeBlock {
                inCodeBlock = false
                html += "</code></pre>\n"
                return
            }
            if inCodeBlock {
                html += escapeHTML(line) + "\n"
                return
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "<br>\n"
                return
            }
            html += "<p>\(escapeHTML(line))</p>\n"
        }
        if inCodeBlock {
            html += "</code></pre>\n"
        }
        return html
    }

    // MARK: - Helpers

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Preview CSS

    static let previewCSS: String = {
        """
        :root {
            --text-color: #1d1d1f;
            --bg-color: transparent;
            --code-bg: rgba(0,0,0,0.05);
            --pre-bg: rgba(0,0,0,0.04);
            --blockquote-border: #ccc;
            --blockquote-color: #888;
            --th-bg: #f5f5f7;
            --table-border: #ddd;
            --link-color: #007aff;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --text-color: #f5f5f7;
                --bg-color: transparent;
                --code-bg: rgba(255,255,255,0.1);
                --pre-bg: rgba(255,255,255,0.06);
                --blockquote-border: #555;
                --blockquote-color: #aaa;
                --th-bg: #333;
                --table-border: #444;
                --link-color: #6ea8fe;
            }
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
            font-size: 15px;
            line-height: 1.6;
            color: var(--text-color);
            background: var(--bg-color);
            max-width: 720px;
            margin: 0 auto;
            padding: 24px 20px 32px;
            word-wrap: break-word;
            overflow-x: hidden;
        }
        h1 { font-size: 30px; font-weight: 700; margin: 32px 0 12px; }
        h2 { font-size: 24px; font-weight: 600; margin: 28px 0 10px; }
        h3 { font-size: 20px; font-weight: 600; margin: 24px 0 8px; }
        h4 { font-size: 17px; font-weight: 600; margin: 20px 0 8px; }
        h5, h6 { font-size: 15px; font-weight: 600; margin: 16px 0 8px; }
        h1:first-child { margin-top: 0; }
        p { margin: 0 0 12px; }
        code {
            font-family: 'SF Mono', Menlo, Monaco, monospace;
            font-size: 13px;
            background: var(--code-bg);
            border-radius: 4px;
            padding: 2px 6px;
        }
        pre {
            background: var(--pre-bg);
            border-radius: 8px;
            padding: 16px;
            overflow-x: auto;
            margin: 12px 0;
        }
        pre code {
            background: none;
            padding: 0;
            font-size: 13px;
            line-height: 1.5;
        }
        blockquote {
            border-left: 3px solid var(--blockquote-border);
            padding-left: 16px;
            color: var(--blockquote-color);
            margin: 8px 0;
        }
        blockquote p { margin: 0; }
        ul, ol {
            margin: 8px 0;
            padding-left: 24px;
        }
        ul ul, ol ol, ul ol, ol ul { margin: 0; }
        li { margin: 2px 0; }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 12px 0;
        }
        th, td {
            border: 1px solid var(--table-border);
            padding: 8px 12px;
            text-align: left;
        }
        th { background: var(--th-bg); font-weight: 600; }
        a { color: var(--link-color); text-decoration: none; }
        a:hover { text-decoration: underline; }
        hr {
            border: none;
            border-top: 1px solid var(--blockquote-border);
            margin: 24px 0;
        }
        img { max-width: 100%; height: auto; border-radius: 6px; margin: 8px 0; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        del { text-decoration: line-through; opacity: 0.6; }
        mark.search-result { background: rgba(255, 200, 0, 0.45); border-radius: 2px; }
        mark.search-result.current-match { background: rgba(255, 150, 0, 0.7); border-radius: 2px; outline: 2px solid rgba(255, 150, 0, 0.8); }
        @media (prefers-color-scheme: dark) {
            mark.search-result { background: rgba(255, 200, 0, 0.3); }
            mark.search-result.current-match { background: rgba(255, 180, 0, 0.55); outline: 2px solid rgba(255, 180, 0, 0.7); }
        }
        .mermaid {
            text-align: center;
            margin: 20px 0;
            overflow-x: auto;
            background: transparent;
        }
        .mermaid svg { max-width: 100%; }

        /* highlight.js theme — GitHub-inspired light/dark */
        .hljs-keyword, .hljs-selector-tag, .hljs-type { color: #d73a49; }
        .hljs-string { color: #032f62; }
        .hljs-comment, .hljs-quote { color: #6a737d; font-style: italic; }
        .hljs-number, .hljs-literal { color: #005cc5; }
        .hljs-title, .hljs-section { color: #6f42c1; }
        .hljs-built_in, .hljs-builtin-name { color: #005cc5; }
        .hljs-attr { color: #005cc5; }
        .hljs-params { color: #24292e; }
        .hljs-meta { color: #e36209; }
        .hljs-name { color: #22863a; }
        .hljs-tag { color: #22863a; }
        .hljs-regexp { color: #032f62; }
        @media (prefers-color-scheme: dark) {
            .hljs-keyword, .hljs-selector-tag, .hljs-type { color: #ff7b72; }
            .hljs-string { color: #a5d6ff; }
            .hljs-comment, .hljs-quote { color: #8b949e; }
            .hljs-number, .hljs-literal { color: #79c0ff; }
            .hljs-title, .hljs-section { color: #d2a8ff; }
            .hljs-built_in, .hljs-builtin-name { color: #79c0ff; }
            .hljs-attr { color: #79c0ff; }
            .hljs-params { color: #e6edf3; }
            .hljs-meta { color: #ffa657; }
            .hljs-name { color: #7ee787; }
            .hljs-tag { color: #7ee787; }
            .hljs-regexp { color: #a5d6ff; }
        }
        """
    }()
}
