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

        // Fast-path: skip expensive regex pre-processing when not needed.
        // contains() is O(n) with early exit — much cheaper than NSRegularExpression
        // scanning the entire text for patterns that don't exist.
        let hasMermaid = markdown.contains("```mermaid")
        let hasBase64 = markdown.contains("data:image/")

        var mermaidResult: MermaidExtractResult?
        var codeBlocks: [(String, String)] = []
        let processedForBase64: String

        if hasMermaid {
            let result = extractMermaidBlocks(markdown)
            mermaidResult = result
            processedForBase64 = result.text
        } else {
            processedForBase64 = markdown
        }

        // Extract all fenced code blocks so base64 preprocessing doesn't
        // corrupt code examples that happen to contain image syntax.
        let preprocessed: String
        if hasBase64 {
            let extracted = extractCodeBlocks(processedForBase64)
            codeBlocks = extracted.blocks
            preprocessed = preprocessBase64Images(extracted.text)
        } else {
            preprocessed = processedForBase64
        }

        let bodyHTML = renderBody(reinsertCodeBlocks(preprocessed, codeBlocks))

        let finalBody: String
        if let result = mermaidResult {
            finalBody = wrapTables(injectHeadingIDs(reinsertMermaidBlocks(bodyHTML, result)))
        } else {
            finalBody = wrapTables(injectHeadingIDs(bodyHTML))
        }

        let css = Self.previewCSS
        let mermaidScript = (mermaidResult?.blocks.isEmpty ?? true) ? "" : mermaidHTML()

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
        for name in ["table", "strikethrough", "tasklist", "autolink", "footnotes"] {
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

    /// Extract all fenced code blocks (``` or ~~~ ... ``` or ~~~) so base64 preprocessing
    /// doesn't corrupt code examples containing `![alt](data:...)` syntax.
    private static let codeBlockExtractRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(```|~~~)(\w*)\s*\n([\s\S]*?)\1"#,
            options: .caseInsensitive
        )
    }()

    private static func extractCodeBlocks(_ markdown: String) -> (text: String, blocks: [(String, String)]) {
        var text = ""
        var blocks: [(String, String)] = []
        var lastEnd = 0
        let nsText = markdown as NSString

        let pattern = Self.codeBlockExtractRegex

        for match in pattern.matches(in: markdown, range: NSRange(location: 0, length: nsText.length)) {
            let full = match.range(at: 0)
            let lang = match.range(at: 2)
            let content = match.range(at: 3)

            text += nsText.substring(with: NSRange(location: lastEnd, length: full.location - lastEnd))
            let idx = blocks.count
            text += "%%CODEBLOCK_\(idx)%%"
            blocks.append((
                nsText.substring(with: lang),
                nsText.substring(with: content)
            ))
            lastEnd = full.location + full.length
        }

        if lastEnd < nsText.length {
            text += nsText.substring(with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
        }

        return (text, blocks)
    }

    private static func reinsertCodeBlocks(_ text: String, _ blocks: [(String, String)]) -> String {
        guard !blocks.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var remaining = text[...]
        for (i, (lang, content)) in blocks.enumerated() {
            let placeholder = "%%CODEBLOCK_\(i)%%"
            guard let range = remaining.range(of: placeholder) else { continue }
            result += remaining[..<range.lowerBound]
            result += "```"
            result += lang
            result += "\n"
            result += content
            result += "```"
            remaining = remaining[range.upperBound...]
        }
        result += remaining
        return result
    }

    // MARK: - Mermaid extraction

    private struct MermaidExtractResult {
        let text: String
        let blocks: [String]
    }

    private static let mermaidExtractRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"```mermaid\s*\n([\s\S]*?)```"#,
            options: .caseInsensitive
        )
    }()

    private static func extractMermaidBlocks(_ markdown: String) -> MermaidExtractResult {
        var text = ""
        var blocks: [String] = []
        var lastEnd = 0
        let nsText = markdown as NSString

        let pattern = Self.mermaidExtractRegex

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
            // HTML-escape mermaid content to prevent HTML injection (e.g. </div>, <script>, etc.)
            // that would break the WebView's DOM structure.
            // Mermaid.js reads the diagram via element.textContent which decodes HTML entities,
            // so angle brackets used in mermaid syntax (e.g. A-->B, A-->|text|B) are preserved.
            let escaped = escapeHTML(block)
            let div = "<div class=\"mermaid\">\n\(escaped)\n</div>"
            out = out.replacingOccurrences(of: "%%MERMAID_\(i)%%", with: div)
        }
        return out
    }

    /// Wrap <table> in <div class="table-wrapper"> for horizontal scrolling.
    private static func wrapTables(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<table", with: "<div class=\"table-wrapper\"><table")
            .replacingOccurrences(of: "</table>", with: "</table></div>")
    }

    /// Regex for heading tag matching (compiled once).
    private static let headingTagRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<h([1-6])([^>]*)>(.*?)</h\1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    /// Inject id="heading-{slug}" into <h1>-<h6> tags for outline scroll sync.
    private static func injectHeadingIDs(_ html: String) -> String {
        // Fast-path: no heading tags → return unchanged.
        // Avoids NSRegularExpression scanning 10MB+ of HTML for nothing.
        guard hasHeadingTags(html) else { return html }

        let nsHTML = html as NSString
        let regex = Self.headingTagRegex

        var result = ""
        var lastEnd = 0
        var slugCount: [String: Int] = [:]
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
            let count = slugCount[slug, default: 0]
            slugCount[slug] = count + 1
            let suffix = count > 0 ? "-\(count)" : ""
            let idAttr = " id=\"heading-\(slug)\(suffix)\""

            result += "<h\(level)\(existingAttrs)\(idAttr)>\(content)</h\(level)>"
            lastEnd = full.location + full.length
        }
        if lastEnd < nsHTML.length {
            result += nsHTML.substring(with: NSRange(location: lastEnd, length: nsHTML.length - lastEnd))
        }
        return result
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
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for char in text {
            switch char {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default:  result.append(char)
            }
        }
        return result
    }

    /// Returns true if the HTML contains any `<h1>`–`<h6>` tags.
    /// Uses character-by-character scanning (not regex) so it can exit early.
    /// Avoids NSRegularExpression's overhead on large HTML bodies with no headings.
    private static func hasHeadingTags(_ html: String) -> Bool {
        var i = html.startIndex
        let end = html.endIndex
        while i < end {
            if html[i] == "<" {
                i = html.index(after: i)
                guard i < end else { break }
                let c = html[i]
                if c == "h" || c == "H" {
                    i = html.index(after: i)
                    guard i < end else { break }
                    let d = html[i]
                    if d >= "1" && d <= "6" { return true }
                    continue
                }
            }
            html.formIndex(after: &i)
        }
        return false
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
            --search-bg: rgba(255, 200, 0, 0.45);
            --search-current-bg: rgba(255, 150, 0, 0.7);
            --search-current-outline: rgba(255, 150, 0, 0.8);
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
                --search-bg: rgba(255, 200, 0, 0.3);
                --search-current-bg: rgba(255, 180, 0, 0.55);
                --search-current-outline: rgba(255, 180, 0, 0.7);
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
        mark.search-result { background: var(--search-bg); border-radius: 2px; }
        mark.search-result.current-match { background: var(--search-current-bg); border-radius: 2px; outline: 2px solid var(--search-current-outline); }
        .mermaid {
            text-align: center;
            margin: 20px 0;
            overflow-x: auto;
            background: transparent;
        }
        .mermaid svg { max-width: 100%; }
        .table-wrapper { overflow-x: auto; margin: 12px 0; }
        .table-wrapper table { margin: 0; }
        .task-list-item { list-style: none; margin-left: -20px; }
        .task-list-item input[type="checkbox"] {
            appearance: none; width: 16px; height: 16px;
            border: 1.5px solid var(--text-color); border-radius: 3px;
            vertical-align: middle; margin-right: 6px;
            background: transparent; cursor: default;
        }
        .task-list-item input[type="checkbox"]:checked {
            background: var(--link-color); border-color: var(--link-color);
        }
        .task-list-item input[type="checkbox"]:checked::after {
            content: "✓"; color: white; display: block;
            text-align: center; font-size: 11px; line-height: 16px;
        }
        .footnotes { font-size: 0.85em; color: var(--blockquote-color); margin-top: 24px; padding-top: 12px; border-top: 1px solid var(--table-border); }
        .footnote-ref { font-size: 0.75em; vertical-align: super; }
        kbd {
            display: inline-block; padding: 2px 6px; font-size: 0.85em;
            font-family: 'SF Mono', Menlo, monospace;
            border: 1px solid var(--table-border); border-radius: 4px;
            background: var(--code-bg);
        }
        details { margin: 8px 0; padding: 8px 12px; border: 1px solid var(--table-border); border-radius: 6px; }
        summary { font-weight: 600; cursor: pointer; }
        sup { font-size: 0.75em; vertical-align: super; }
        sub { font-size: 0.75em; vertical-align: sub; }

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
