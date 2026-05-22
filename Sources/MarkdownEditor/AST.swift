import Foundation

// MARK: - Diagram Types
public enum DiagramType: String {
    case flowchart, sequenceDiagram, classDiagram, stateDiagram, gantt, pie, erDiagram
}

// MARK: - Inline Elements
public enum InlineElement: Equatable {
    case text(String)
    case bold(TextContent)
    case italic(TextContent)
    case code(String)
    case link(text: TextContent, url: String, title: String?)
    case image(url: String, alt: String?)
    case math(String)
    case strikethrough(TextContent)
    case highlight(TextContent)

    public typealias TextContent = [InlineElement]
}

// MARK: - List Items
public struct ListItem: Identifiable {
    public let id: UUID
    public var inlines: [InlineElement]
    public var childBlocks: [Block]

    public init(id: UUID = UUID(), inlines: [InlineElement], childBlocks: [Block] = []) {
        self.id = id
        self.inlines = inlines
        self.childBlocks = childBlocks
    }
}

public struct TaskListItem: Identifiable {
    public let id: UUID
    public var checked: Bool
    public var inlines: [InlineElement]

    public init(id: UUID = UUID(), checked: Bool = false, inlines: [InlineElement]) {
        self.id = id
        self.checked = checked
        self.inlines = inlines
    }
}

// MARK: - Heading Tree
public struct HeadingNode {
    public let title: String
    public let level: Int
    public let range: NSRange
    public var children: [HeadingNode]

    public init(title: String, level: Int, range: NSRange, children: [HeadingNode] = []) {
        self.title = title
        self.level = level
        self.range = range
        self.children = children
    }
}

// MARK: - Block-level Elements
public enum Block: Identifiable {
    case heading(level: Int, text: [InlineElement], range: NSRange)
    case paragraph(inlines: [InlineElement])
    case codeBlock(language: String?, code: String)
    case blockquote(blocks: [Block])
    case unorderedList(items: [ListItem])
    case orderedList(start: Int, items: [ListItem])
    case table(headers: [String], rows: [[String]])
    case taskList(items: [TaskListItem])
    case image(url: String, alt: String?)
    case thematicBreak
    case footnote(identifier: String, content: [Block])
    case mathBlock(formula: String)
    case diagramBlock(type: DiagramType, code: String)
    case tableOfContents(headings: [HeadingNode])
    case htmlBlock(html: String)

    public var id: String {
        switch self {
        case .heading(let level, let text, _):
            let h = text.reduce(0) { $0 &* 31 &+ $1.id.hashValue }
            return "h\(level)-\(h)"
        case .paragraph(let inlines):
            return "p-\(inlinesHash(inlines))"
        case .codeBlock(let lang, let code):
            return "code-\(lang ?? "")-\(code.hashValue)"
        case .blockquote(let blocks):
            return "bq-\(blocks.count)"
        case .unorderedList(let items):
            return "ul-\(items.count)-\(items.first?.inlinesHash ?? 0)"
        case .orderedList(let s, let items):
            return "ol-\(s)-\(items.count)"
        case .table(let headers, _):
            return "tbl-\(headers.joined().hashValue)"
        case .taskList(let items):
            return "tl-\(items.count)"
        case .image(let url, _):
            return "img-\(url.hashValue)"
        case .thematicBreak:
            return "hr"
        case .footnote(let id, _):
            return "fn-\(id)"
        case .mathBlock(let formula):
            return "math-\(formula.hashValue)"
        case .diagramBlock:
            return "diag"
        case .tableOfContents:
            return "toc"
        case .htmlBlock(let html):
            return "html-\(html.hashValue)"
        }
    }

    public var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

private func inlinesHash(_ inlines: [InlineElement]) -> Int {
    inlines.reduce(0) { $0 &* 31 &+ $1.id.hashValue }
}

extension InlineElement {
    var id: String {
        switch self {
        case .text(let t): return "t\(t.hashValue)"
        case .bold(let c): return "b\(inlinesHash(c))"
        case .italic(let c): return "i\(inlinesHash(c))"
        case .code(let t): return "c\(t.hashValue)"
        case .link(let t, let u, _): return "l\(inlinesHash(t))-\(u.hashValue)"
        case .image(let u, _): return "im\(u.hashValue)"
        case .math(let f): return "m\(f.hashValue)"
        case .strikethrough(let c): return "s\(inlinesHash(c))"
        case .highlight(let c): return "h\(inlinesHash(c))"
        }
    }
}

extension ListItem {
    var inlinesHash: Int { self.inlines.reduce(0) { $0 &* 31 &+ $1.id.hashValue } }
}

// MARK: - Document AST
public struct DocumentAST {
    public let blocks: [Block]
    public let hasMath: Bool
    public let hasDiagram: Bool
    public let headingTree: [HeadingNode]

    public init(blocks: [Block], hasMath: Bool, hasDiagram: Bool, headingTree: [HeadingNode]) {
        self.blocks = blocks
        self.hasMath = hasMath
        self.hasDiagram = hasDiagram
        self.headingTree = headingTree
    }
}
