import Foundation

enum MarkdownParser {

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
        let pattern = #"```mermaid\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

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
        if let match = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)"#)
            .firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
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

        if let match = try? NSRegularExpression(pattern: #"^[\s]*[-*+]\s+(.+)"#)
            .firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
            let content = String(line[Range(match.range(at: 1), in: line)!])
            return "<ul>\n<li>\(inlineFormatting(content))</li>\n</ul>"
        }

        if let match = try? NSRegularExpression(pattern: #"^[\s]*(\d+)\.\s+(.+)"#)
            .firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
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
        var result = text

        // Images ![alt](url)
        let imgPattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<img src=\"$2\" alt=\"$1\" loading=\"lazy\">")
        }

        // Bold **text** or __text__
        let boldPattern = #"(\*\*|__)(.+?)\1"#
        if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<strong>$2</strong>")
        }

        // Italic *text* or _text_
        let italicPattern = #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#
        if let regex = try? NSRegularExpression(pattern: italicPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<em>$1</em>")
        }

        // Inline code `text`
        let codePattern = #"`([^`]+)`"#
        if let regex = try? NSRegularExpression(pattern: codePattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<code>$1</code>")
        }

        // Links [text](url)
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<a href=\"$2\">$1</a>")
        }

        // Strikethrough ~~text~~
        let strikePattern = #"~~(.+?)~~"#
        if let regex = try? NSRegularExpression(pattern: strikePattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "<del>$1</del>")
        }

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
