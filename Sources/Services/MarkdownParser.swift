import Foundation

enum MarkdownParser {

    private static let headerRegex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)"#)
    private static let ulRegex = try! NSRegularExpression(pattern: #"^[\s]*[-*+]\s+(.+)"#)
    private static let olRegex = try! NSRegularExpression(pattern: #"^[\s]*(\d+)\.\s+(.+)"#)
    private static let mermaidBlockRegex = try! NSRegularExpression(pattern: #"```mermaid\s*\n([\s\S]*?)```"#, options: [.caseInsensitive])
    private static let imgRegex = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
    private static let boldRegex = try! NSRegularExpression(pattern: #"(\*\*|__)(.+?)\1"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
    private static let strikeRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)

    static func parseToHTML(_ markdown: String) -> String {
        let bodyHTML = convertMarkdownToHTMLBody(markdown)
        let css = Self.previewCSS
        let mermaidScript = hasMermaidBlocks(in: markdown) ? """
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            if (typeof mermaid !== 'undefined') {
                mermaid.initialize({ startOnLoad: true, theme: 'default' });
            }
        });
        </script>
        """ : ""

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head><body>\(bodyHTML)\(mermaidScript)</body></html>
        """
    }

    private static func hasMermaidBlocks(in markdown: String) -> Bool {
        let pattern = #"```mermaid\b"#
        return markdown.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func convertMarkdownToHTMLBody(_ markdown: String) -> String {
        let processed = processMermaidBlocks(in: markdown)
        return renderMarkdownToHTML(processed)
    }

    private static func processMermaidBlocks(in text: String) -> String {
        let nsText = text as NSString
        let matches = mermaidBlockRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var result = ""
        var lastEnd = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)

            result += nsText.substring(with: NSRange(location: lastEnd, length: fullRange.location - lastEnd))

            let mermaidContent = nsText.substring(with: contentRange)
            let escaped = mermaidContent
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            result += "<div class=\"mermaid\">\n\(escaped)\n</div>"

            lastEnd = fullRange.location + fullRange.length
        }

        if lastEnd < nsText.length {
            result += nsText.substring(with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
        }

        return result
    }

    private static func renderMarkdownToHTML(_ text: String) -> String {
        var html = ""
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLang = ""

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") && !inCodeBlock {
                inCodeBlock = true
                codeBlockLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeBlockContent = ""
                continue
            }

            if line.hasPrefix("```") && inCodeBlock {
                inCodeBlock = false
                let langClass = codeBlockLang.isEmpty ? "" : " class=\"language-\(escapeHTML(codeBlockLang))\""
                html += "<pre><code\(langClass)>\(escapeHTML(codeBlockContent))\n</code></pre>\n"
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty { codeBlockContent += "\n" }
                codeBlockContent += line
                continue
            }

            html += renderLine(line) + "\n"
        }

        if inCodeBlock {
            html += "<pre><code>\(escapeHTML(codeBlockContent))\n</code></pre>\n"
        }

        return html
    }

    private static func renderLine(_ line: String) -> String {
        if let match = headerRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
            let level = line[Range(match.range(at: 1), in: line)!].count
            let text = String(line[Range(match.range(at: 2), in: line)!])
            let id = text.lowercased()
                .replacingOccurrences(of: #"[^\w\s-]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            return "<h\(level) id=\"\(id)\">\(inlineFormatting(text))</h\(level)>"
        }

        if line.hasPrefix("> ") {
            let content = String(line.dropFirst(2))
            return "<blockquote><p>\(inlineFormatting(content))</p></blockquote>"
        }

        if let match = ulRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
            let content = String(line[Range(match.range(at: 1), in: line)!])
            return "<ul>\n<li>\(inlineFormatting(content))</li>\n</ul>"
        }

        if let match = olRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
            let content = String(line[Range(match.range(at: 2), in: line)!])
            return "<ol>\n<li>\(inlineFormatting(content))</li>\n</ol>"
        }

        if line.hasPrefix("---") || line.hasPrefix("***") || line.hasPrefix("___") {
            return "<hr>"
        }

        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return ""
        }

        if line.hasPrefix("|") && line.hasSuffix("|") {
            return renderTable(line)
        }

        return "<p>\(inlineFormatting(line))</p>"
    }

    private static func renderTable(_ firstLine: String) -> String {
        return "<p>\(inlineFormatting(firstLine))</p>"
    }

    private static func inlineFormatting(_ text: String) -> String {
        // Fast path: lines without markdown syntax chars just get HTML-escaped.
        // For 1.1MB of markdown this skips ~70,000 unnecessary regex calls.
        let hasMarkdownChars = text.contains(where: { char in
            char == "*" || char == "_" || char == "`" || char == "[" || char == "!" || char == "~"
        })
        if !hasMarkdownChars || text.utf16.count >= 500 {
            return escapeHTML(text)
        }

        var result = text

        // Images ![alt](url) — replace base64 data URIs with a placeholder
        if imgRegex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count)) != nil {
            let nsResult = result as NSString
            let matches = imgRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
            var offset = 0
            for match in matches {
                let urlRange = match.range(at: 2)
                let url = nsResult.substring(with: urlRange)
                if url.hasPrefix("data:") || url.count > 2000 {
                    let alt = nsResult.substring(with: match.range(at: 1))
                    let placeholder = "<div style=\"padding:16px;background:rgba(128,128,128,0.08);border-radius:8px;text-align:center;color:var(--blockquote-color);font-size:13px;margin:12px 0;\">🖼️ \(escapeHTML(alt))<br><span style=\"font-size:11px;\">(base64 image — not displayed in preview)</span></div>"
                    result = (result as NSString).replacingCharacters(in: NSRange(location: match.range.location + offset, length: match.range.length), with: placeholder)
                    offset += placeholder.utf16.count - match.range.length
                } else {
                    let imgTag = "<img src=\"\(escapeHTML(url))\" alt=\"\(escapeHTML(nsResult.substring(with: match.range(at: 1))))\" loading=\"lazy\">"
                    result = (result as NSString).replacingCharacters(in: NSRange(location: match.range.location + offset, length: match.range.length), with: imgTag)
                    offset += imgTag.utf16.count - match.range.length
                }
            }
        }

        // Bold **text** or __text__
        result = boldRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<strong>$2</strong>")

        // Italic *text* or _text_
        result = italicRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<em>$1</em>")

        // Inline code `text`
        result = codeRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<code>$1</code>")

        // Links [text](url)
        result = linkRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<a href=\"$2\">$1</a>")

        // Strikethrough ~~text~~
        result = strikeRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<del>$1</del>")

        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

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
        .mermaid {
            text-align: center;
            margin: 20px 0;
            overflow-x: auto;
            background: transparent;
        }
        .mermaid svg { max-width: 100%; }
        """
    }()
}
