import Foundation

public class HTMLRenderer {
    public init() {}

    public func renderBody(blocks: [Block]) -> String {
        blocks.map { renderBlock($0) }.joined(separator: "\n")
    }

    func renderBlock(_ block: Block) -> String {
        switch block {
        case .heading(let level, let text, _):
            let tag = "h\(min(max(level, 1), 6))"
            let anchor = headingAnchor(text)
            return "<\(tag) id=\"\(anchor)\">\(renderInlines(text))</\(tag)>"

        case .paragraph(let inlines):
            return "<p>\(renderInlines(inlines))</p>"

        case .codeBlock(let language, let code):
            let escaped = escapeHTML(code)
            let langAttr = language.map { " class=\"language-\($0)\"" } ?? " class=\"language-none\""
            return "<pre><code\(langAttr)>\(escaped)</code></pre>"

        case .blockquote(let blocks):
            let inner = blocks.map { renderBlock($0) }.joined(separator: "\n")
            return "<blockquote>\(inner)</blockquote>"

        case .unorderedList(let items):
            let inner = items.map { "<li>\(renderInlines($0.inlines))</li>" }.joined(separator: "\n")
            return "<ul>\(inner)</ul>"

        case .orderedList(let start, let items):
            let inner = items.map { "<li>\(renderInlines($0.inlines))</li>" }.joined(separator: "\n")
            return "<ol start=\"\(start)\">\(inner)</ol>"

        case .table(let headers, let rows):
            let headerRow = "<tr>" + headers.map { "<th>\(escapeHTML($0))</th>" }.joined() + "</tr>"
            let bodyRows = rows.map { row in
                "<tr>" + row.map { "<td>\(escapeHTML($0))</td>" }.joined() + "</tr>"
            }.joined(separator: "\n")
            return "<table><thead>\(headerRow)</thead><tbody>\(bodyRows)</tbody></table>"

        case .taskList(let items):
            let inner = items.map { item in
                let checked = item.checked ? "checked" : ""
                return "<li><input type=\"checkbox\" \(checked) disabled> \(renderInlines(item.inlines))</li>"
            }.joined(separator: "\n")
            return "<ul class=\"task-list\">\(inner)</ul>"

        case .image(let url, let alt):
            return "<img src=\"\(escapeHTML(url))\" alt=\"\(escapeHTML(alt ?? ""))\">"

        case .thematicBreak:
            return "<hr>"

        case .footnote(let identifier, let content):
            let inner = content.map { renderBlock($0) }.joined(separator: "\n")
            return "<div class=\"footnote\" id=\"fn-\(identifier)\"><sup>\(identifier)</sup> \(inner)</div>"

        case .mathBlock(let formula):
            return "<div class=\"math-display\">\(escapeHTML(formula))</div>"

        case .diagramBlock(_, let code):
            return "<pre class=\"mermaid\">\(escapeHTML(code))</pre>"

        case .tableOfContents(let headings):
            return renderTOC(headings)

        case .htmlBlock(let html):
            return html
        }
    }

    func renderInlines(_ inlines: [InlineElement]) -> String {
        inlines.map { renderInline($0) }.joined()
    }

    func renderInline(_ inline: InlineElement) -> String {
        switch inline {
        case .text(let t): return escapeHTML(t)
        case .bold(let children): return "<strong>\(renderInlines(children))</strong>"
        case .italic(let children): return "<em>\(renderInlines(children))</em>"
        case .code(let t): return "<code>\(escapeHTML(t))</code>"
        case .link(let text, let url, _):
            return "<a href=\"\(escapeHTML(url))\">\(renderInlines(text))</a>"
        case .image(let url, let alt):
            return "<img src=\"\(escapeHTML(url))\" alt=\"\(escapeHTML(alt ?? ""))\">"
        case .math(let formula): return "<span class=\"math-inline\">\(escapeHTML(formula))</span>"
        case .strikethrough(let children): return "<del>\(renderInlines(children))</del>"
        case .highlight(let children): return "<mark>\(renderInlines(children))</mark>"
        }
    }

    func renderTOC(_ headings: [HeadingNode]) -> String {
        func renderNodes(_ nodes: [HeadingNode]) -> String {
            guard !nodes.isEmpty else { return "" }
            let items = nodes.map { node -> String in
                let children = renderNodes(node.children)
                let anchor = node.title.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
                return "<li><a href=\"#\(escapeHTML(anchor))\">\(escapeHTML(node.title))</a>"
                    + (children.isEmpty ? "" : "<ul>\(children)</ul>") + "</li>"
            }.joined(separator: "\n")
            return items
        }
        return "<nav class=\"toc\"><ul>\(renderNodes(headings))</ul></nav>"
    }

    func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Heading Anchors

    func plainText(_ inlines: [InlineElement]) -> String {
        inlines.map { node in
            switch node {
            case .text(let t): return t
            case .bold(let c): return plainText(c)
            case .italic(let c): return plainText(c)
            case .code(let t): return t
            case .link(let c, _, _): return plainText(c)
            case .image: return ""
            case .math: return ""
            case .strikethrough(let c): return plainText(c)
            case .highlight(let c): return plainText(c)
            }
        }.joined()
    }

    func headingAnchor(_ inlines: [InlineElement]) -> String {
        let text = plainText(inlines)
        return text.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
    }
}
