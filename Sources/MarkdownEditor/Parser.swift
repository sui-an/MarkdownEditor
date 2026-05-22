import Foundation

// MARK: - Markdown Parser
public struct MarkdownParser {
    public init() {}

    public func parse(_ text: String) -> DocumentAST {
        let lines = text.components(separatedBy: .newlines)
        let hasMath = text.contains("$$") || text.contains("$")
        let hasDiagram = text.contains("```mermaid")

        let blocks = parseBlocks(lines, source: text)
        let headingTree = buildHeadingTree(blocks)

        return DocumentAST(
            blocks: blocks,
            hasMath: hasMath,
            hasDiagram: hasDiagram,
            headingTree: headingTree
        )
    }

    // MARK: - Block-level parsing
    func parseBlocks(_ lines: [String], source: String) -> [Block] {
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Thematic break
            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // ATX heading
            if let heading = parseHeading(line, source: source, lineIndex: i) {
                blocks.append(heading)
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let (codeBlock, consumed) = parseFencedCode(lines, start: i)
                blocks.append(codeBlock)
                i += consumed
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                let (quoteBlock, consumed) = parseBlockquote(lines, start: i, source: source)
                blocks.append(quoteBlock)
                i += consumed
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                let (list, consumed) = parseUnorderedList(lines, start: i, source: source)
                blocks.append(list)
                i += consumed
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                let (list, consumed) = parseOrderedList(lines, start: i, source: source)
                blocks.append(list)
                i += consumed
                continue
            }

            // Table
            if isTableRow(trimmed) && (i + 1 < lines.count) && isTableSeparator(lines[i + 1]) {
                let (table, consumed) = parseTable(lines, start: i)
                blocks.append(table)
                i += consumed
                continue
            }

            // Task list
            if isTaskListItem(trimmed) {
                let (taskList, consumed) = parseTaskList(lines, start: i, source: source)
                blocks.append(taskList)
                i += consumed
                continue
            }

            // Footnote
            if let footnote = parseFootnote(line, lines: lines, index: i, source: source) {
                blocks.append(footnote)
                i += 1
                continue
            }

            // Paragraph (collect contiguous text lines)
            let (paragraph, consumed) = collectParagraph(lines, start: i, source: source)
            blocks.append(paragraph)
            i += consumed
        }

        return blocks
    }

    // MARK: - Heading
    func parseHeading(_ line: String, source: String, lineIndex: Int) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        guard trimmed.count > level else { return nil }
        let afterHash = trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)]
        guard afterHash == " " else { return nil }

        let content = String(trimmed.dropFirst(level + 1))
        let inlines = parseInlines(content)
        let range = NSRange(location: lineIndex * 80, length: line.count)

        return .heading(level: level, text: inlines, range: range)
    }

    // MARK: - Thematic Break
    func isThematicBreak(_ trimmed: String) -> Bool {
        let patterns = ["---", "***", "___"]
        for p in patterns {
            if trimmed.count >= 3 && trimmed.allSatisfy({ p.contains($0) }) {
                return true
            }
        }
        return false
    }

    // MARK: - Fenced Code Block
    func parseFencedCode(_ lines: [String], start: Int) -> (Block, Int) {
        let firstLine = lines[start].trimmingCharacters(in: .whitespaces)
        var fence = ""
        for ch in firstLine {
            if ch == "`" { fence.append(ch) } else { break }
        }
        let language = String(firstLine.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)

        var codeLines: [String] = []
        var i = start + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(String(repeating: "`", count: fence.count)) {
                i += 1
                break
            }
            codeLines.append(lines[i])
            i += 1
        }

        let code = codeLines.joined(separator: "\n")

        // Check for Mermaid
        if language.lowercased() == "mermaid" {
            let diagramType = detectMermaidType(code)
            return (.diagramBlock(type: diagramType, code: code), i - start)
        }

        return (.codeBlock(language: language.isEmpty ? nil : language, code: code), i - start)
    }

    func detectMermaidType(_ code: String) -> DiagramType {
        let firstLine = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if firstLine.hasPrefix("flowchart") || firstLine.hasPrefix("graph") { return .flowchart }
        if firstLine.hasPrefix("sequencediagram") { return .sequenceDiagram }
        if firstLine.hasPrefix("classdiagram") { return .classDiagram }
        if firstLine.hasPrefix("statediagram") { return .stateDiagram }
        if firstLine.hasPrefix("gantt") { return .gantt }
        if firstLine.hasPrefix("pie") { return .pie }
        if firstLine.hasPrefix("er") || firstLine.hasPrefix("erDiagram") { return .erDiagram }
        return .flowchart
    }

    // MARK: - Blockquote
    func parseBlockquote(_ lines: [String], start: Int, source: String) -> (Block, Int) {
        var quoteLines: [String] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                quoteLines.append(content)
                i += 1
            } else if trimmed.isEmpty {
                i += 1
                break
            } else {
                break
            }
        }

        let childBlocks = parseBlocks(quoteLines, source: source)
        return (.blockquote(blocks: childBlocks), i - start)
    }

    // MARK: - Unordered List
    func isUnorderedListItem(_ trimmed: String) -> Bool {
        let markers = ["- ", "* ", "+ "]
        return markers.contains(where: { trimmed.hasPrefix($0) })
    }

    func parseUnorderedList(_ lines: [String], start: Int, source: String) -> (Block, Int) {
        var items: [ListItem] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if isUnorderedListItem(trimmed) {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let inlines = parseInlines(content)
                items.append(ListItem(inlines: inlines))
                i += 1
            } else if trimmed.isEmpty {
                i += 1
                break
            } else {
                break
            }
        }
        return (.unorderedList(items: items), i - start)
    }

    // MARK: - Ordered List
    func isOrderedListItem(_ trimmed: String) -> Bool {
        let pattern = #/^\d+\.\s/#
        return (try? pattern.prefixMatch(in: trimmed)) != nil
    }

    func parseOrderedList(_ lines: [String], start: Int, source: String) -> (Block, Int) {
        var items: [ListItem] = []
        var i = start
        var startNumber = 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if isOrderedListItem(trimmed) {
                if let dotIndex = trimmed.firstIndex(of: ".") {
                    let numStr = trimmed[trimmed.startIndex..<dotIndex]
                    if let num = Int(numStr), i == start { startNumber = num }
                    let content = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                    let inlines = parseInlines(content)
                    items.append(ListItem(inlines: inlines))
                }
                i += 1
            } else if trimmed.isEmpty {
                i += 1
                break
            } else {
                break
            }
        }
        return (.orderedList(start: startNumber, items: items), i - start)
    }

    // MARK: - Table
    func isTableRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|")
    }

    func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.contains("-")
    }

    func parseTable(_ lines: [String], start: Int) -> (Block, Int) {
        let headerLine = lines[start].trimmingCharacters(in: .whitespaces)
        let headers = headerLine.split(separator: "|", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        var rows: [[String]] = []
        var i = start + 2 // skip header and separator
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") {
                let cells = trimmed.split(separator: "|", omittingEmptySubsequences: true).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                rows.append(cells)
                i += 1
            } else {
                break
            }
        }
        return (.table(headers: headers, rows: rows), i - start)
    }

    // MARK: - Task List
    func isTaskListItem(_ trimmed: String) -> Bool {
        let pattern = #/^-\s\[[ x]\]\s/#
        return (try? pattern.prefixMatch(in: trimmed)) != nil
    }

    func parseTaskList(_ lines: [String], start: Int, source: String) -> (Block, Int) {
        var items: [TaskListItem] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if let match = try? #/^-\s\[([ x])\]\s(.+)/#.wholeMatch(in: trimmed) {
                let checked = String(match.1) == "x"
                let content = String(match.2)
                let inlines = parseInlines(content)
                items.append(TaskListItem(checked: checked, inlines: inlines))
                i += 1
            } else {
                break
            }
        }
        return (.taskList(items: items), i - start)
    }

    // MARK: - Footnote
    func parseFootnote(_ line: String, lines: [String], index: Int, source: String) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #/^\[(\^\w+)\]:\s(.+)/#
        guard let match = try? pattern.wholeMatch(in: trimmed) else { return nil }
        let identifier = String(match.1)
        let content = String(match.2)
        let contentBlocks = parseBlocks([content], source: source)
        return .footnote(identifier: identifier, content: contentBlocks)
    }

    // MARK: - Paragraph
    func collectParagraph(_ lines: [String], start: Int, source: String) -> (Block, Int) {
        var paraLines: [String] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("```") || trimmed.hasPrefix(">")
                || isUnorderedListItem(trimmed) || isOrderedListItem(trimmed)
                || isThematicBreak(trimmed) || isTaskListItem(trimmed) { break }
            paraLines.append(lines[i])
            i += 1
        }
        let text = paraLines.joined(separator: " ")
        let inlines = parseInlines(text)
        return (.paragraph(inlines: inlines), i - start)
    }

    // MARK: - Inline Parsing
    func parseInlines(_ text: String) -> [InlineElement] {
        var result: [InlineElement] = []
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            // Math inline $$
            if ch == "$" && i + 1 < chars.count && chars[i + 1] == "$" {
                var j = i + 2
                while j < chars.count - 1 {
                    if chars[j] == "$" && chars[j + 1] == "$" {
                        let formula = String(chars[(i + 2)..<j])
                        result.append(.math(formula))
                        i = j + 2
                        break
                    }
                    j += 1
                }
                if i < j { i += 1; continue } // fallback if $$ not closed
                continue
            }

            // Math inline $
            if ch == "$" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "$" {
                        let formula = String(chars[(i + 1)..<j])
                        if !formula.isEmpty {
                            result.append(.math(formula))
                            i = j + 1
                        } else {
                            i += 1
                        }
                        break
                    }
                    j += 1
                }
                if j >= chars.count { i += 1 } // unclosed $, treat as text
                continue
            }

            // Image ![]()
            if ch == "!" && i + 1 < chars.count && chars[i + 1] == "[" {
                if let closeBracket = findNext(chars, start: i + 2, target: "]"),
                   closeBracket + 1 < chars.count && chars[closeBracket + 1] == "(",
                   let urlEnd = findNext(chars, start: closeBracket + 2, target: ")") {
                    let alt = String(chars[(i + 2)..<closeBracket])
                    let url = String(chars[(closeBracket + 2)..<urlEnd])
                    result.append(.image(url: url, alt: alt))
                    i = urlEnd + 1
                    continue
                }
            }

            // Link [text](url)
            if ch == "[" {
                if let closeBracket = findNext(chars, start: i + 1, target: "]"),
                   closeBracket + 1 < chars.count && chars[closeBracket + 1] == "(",
                   let urlEnd = findNext(chars, start: closeBracket + 2, target: ")") {
                    let linkText = String(chars[(i + 1)..<closeBracket])
                    let url = String(chars[(closeBracket + 2)..<urlEnd])
                    result.append(.link(text: parseInlines(linkText), url: url, title: nil))
                    i = urlEnd + 1
                    continue
                }
            }

            // Inline code `code`
            if ch == "`" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "`" {
                        let code = String(chars[(i + 1)..<j])
                        result.append(.code(code))
                        i = j + 1
                        break
                    }
                    j += 1
                }
                if j >= chars.count { i += 1 }
                continue
            }

            // Strikethrough ~~text~~
            if ch == "~" && i + 1 < chars.count && chars[i + 1] == "~" {
                var j = i + 2
                while j < chars.count - 1 {
                    if chars[j] == "~" && chars[j + 1] == "~" {
                        let inner = String(chars[(i + 2)..<j])
                        result.append(.strikethrough(parseInlines(inner)))
                        i = j + 2
                        break
                    }
                    j += 1
                }
                if i < j { i += 1 }
                continue
            }

            // Bold **text**
            if ch == "*" && i + 1 < chars.count && chars[i + 1] == "*" {
                var j = i + 2
                while j < chars.count - 1 {
                    if chars[j] == "*" && chars[j + 1] == "*" {
                        let inner = String(chars[(i + 2)..<j])
                        result.append(.bold(parseInlines(inner)))
                        i = j + 2
                        break
                    }
                    j += 1
                }
                if i < j { i += 1 }
                continue
            }

            // Italic *text*
            if ch == "*" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "*" {
                        let inner = String(chars[(i + 1)..<j])
                        if !inner.isEmpty {
                            result.append(.italic(parseInlines(inner)))
                            i = j + 1
                        } else {
                            i += 1
                        }
                        break
                    }
                    j += 1
                }
                if j >= chars.count { i += 1 }
                continue
            }

            // Collect consecutive regular text
            var textStr = String(ch)
            i += 1
            while i < chars.count {
                let next = chars[i]
                if next == "$" || next == "!" || next == "[" || next == "`" || next == "~" || next == "*" {
                    break
                }
                textStr.append(next)
                i += 1
            }
            result.append(.text(textStr))
        }

        return result
    }

    private func findNext(_ chars: [Character], start: Int, target: Character) -> Int? {
        for j in start..<chars.count {
            if chars[j] == target { return j }
        }
        return nil
    }

    // MARK: - Heading Tree
    func buildHeadingTree(_ blocks: [Block]) -> [HeadingNode] {
        var tree: [HeadingNode] = []
        var stack: [HeadingNode] = []

        for block in blocks {
            guard case .heading(let level, let inlines, let range) = block else { continue }
            let title = inlines.compactMap { el -> String? in
                if case .text(let t) = el { return t }
                return nil
            }.joined()

            let node = HeadingNode(title: title, level: level, range: range)

            while let last = stack.last, last.level >= level {
                stack.removeLast()
            }
            if let parent = stack.last {
                // Find the parent node in the tree and add child
                func findAndAdd(in nodes: inout [HeadingNode], parentTitle: String, parentLevel: Int, newNode: HeadingNode) {
                    for i in nodes.indices {
                        if nodes[i].title == parentTitle && nodes[i].level == parentLevel {
                            nodes[i].children.append(newNode)
                            return
                        }
                        findAndAdd(in: &nodes[i].children, parentTitle: parentTitle, parentLevel: parentLevel, newNode: newNode)
                    }
                }
                findAndAdd(in: &tree, parentTitle: parent.title, parentLevel: parent.level, newNode: node)
            } else {
                tree.append(node)
            }
            stack.append(node)
        }

        return tree
    }
}

// MARK: - String helpers
extension StringProtocol {
    func firstMatch(of pattern: String) -> Range<String.Index>? {
        range(of: pattern)
    }
}
