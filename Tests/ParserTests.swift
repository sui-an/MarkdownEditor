import Foundation

// MARK: - Parser Tests
struct ParserTests {

    static func run() {
        print("🧪 Running Parser Tests...\n")

        testParseEmptyString()
        testParseHeading()
        testParseBoldAndItalic()
        testParseInlineCode()
        testParseCodeBlock()
        testParseUnorderedList()
        testParseOrderedList()
        testParseTable()
        testParseTaskList()
        testParseBlockquote()
        testParseThematicBreak()
        testParseLink()
        testParseImage()
        testParseMathFormula()
        testParseMermaidDiagram()
        testParseFootnote()
        testDetectMath()
        testDetectDiagram()
        testLargeDocument()
        testBuildHeadingTree()

        print("\n✅ Parser Tests Complete: \(testResults.passed) passed, \(testResults.failed) failed\n")
    }

    // MARK: - Empty string
    static func testParseEmptyString() {
        let parser = MarkdownParser()
        let ast = parser.parse("")
        assertEqual(ast.blocks.count, 0, "Empty string should produce no blocks")
        assertFalse(ast.hasMath, "Empty string has no math")
        assertFalse(ast.hasDiagram, "Empty string has no diagram")
    }

    // MARK: - Headings
    static func testParseHeading() {
        let parser = MarkdownParser()
        let ast = parser.parse("# Hello")
        assertEqual(ast.blocks.count, 1, "Single heading should produce 1 block")
        if case .heading(let level, let text, _) = ast.blocks.first! {
            assertEqual(level, 1, "Heading level should be 1")
            assertEqual(text.count, 1, "Heading should have 1 text element")
            if case .text(let content) = text[0] {
                assertEqual(content, "Hello", "Heading text should be 'Hello'")
            } else {
                assertTrue(false, "Heading text should be .text")
            }
        } else {
            assertTrue(false, "First block should be .heading")
        }
    }

    static func testParseHeadingLevels() {
        let parser = MarkdownParser()
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            let ast = parser.parse("\(prefix) Level \(level)")
            if case .heading(let l, _, _) = ast.blocks.first! {
                assertEqual(l, level, "Heading level \(level) should be parsed correctly")
            }
        }
    }

    // MARK: - Inline formatting
    static func testParseBoldAndItalic() {
        let parser = MarkdownParser()
        let ast = parser.parse("**bold** and *italic*")
        assertEqual(ast.blocks.count, 1, "Should be 1 paragraph")
        if case .paragraph(let inlines) = ast.blocks.first! {
            var foundBold = false
            var foundItalic = false
            for inline in inlines {
                if case .bold = inline { foundBold = true }
                if case .italic = inline { foundItalic = true }
            }
            assertTrue(foundBold, "Should find bold element")
            assertTrue(foundItalic, "Should find italic element")
        } else {
            assertTrue(false, "First block should be .paragraph")
        }
    }

    static func testParseInlineCode() {
        let parser = MarkdownParser()
        let ast = parser.parse("Use `code` here")
        if case .paragraph(let inlines) = ast.blocks.first! {
            var foundCode = false
            for inline in inlines {
                if case .code(let c) = inline {
                    foundCode = true
                    assertEqual(c, "code", "Code content should match")
                }
            }
            assertTrue(foundCode, "Should find inline code element")
        }
    }

    // MARK: - Code Block
    static func testParseCodeBlock() {
        let parser = MarkdownParser()
        let ast = parser.parse("```swift\nlet x = 1\nprint(x)\n```")
        assertEqual(ast.blocks.count, 1, "Should be 1 code block")
        if case .codeBlock(let lang, let code) = ast.blocks.first! {
            assertEqual(lang, "swift", "Language should be 'swift'")
            assertEqual(code, "let x = 1\nprint(x)", "Code content should match")
        } else {
            assertTrue(false, "Block should be .codeBlock")
        }
    }

    // MARK: - Lists
    static func testParseUnorderedList() {
        let parser = MarkdownParser()
        let ast = parser.parse("- Item 1\n- Item 2\n- Item 3")
        assertEqual(ast.blocks.count, 1, "Should be 1 list block")
        if case .unorderedList(let items) = ast.blocks.first! {
            assertEqual(items.count, 3, "Should have 3 items")
        } else {
            assertTrue(false, "Block should be .unorderedList")
        }
    }

    static func testParseOrderedList() {
        let parser = MarkdownParser()
        let ast = parser.parse("1. First\n2. Second\n3. Third")
        assertEqual(ast.blocks.count, 1, "Should be 1 ordered list")
        if case .orderedList(let start, let items) = ast.blocks.first! {
            assertEqual(start, 1, "Start should be 1")
            assertEqual(items.count, 3, "Should have 3 items")
        }
    }

    // MARK: - Table
    static func testParseTable() {
        let parser = MarkdownParser()
        let ast = parser.parse("| H1 | H2 |\n|----|----|\n| A  | B  |\n| C  | D  |")
        assertTrue(ast.blocks.count >= 1, "Should have a table block")
        // Check that at least one block exists and is a table
        let hasTable = ast.blocks.contains { block in
            if case .table = block { return true }
            return false
        }
        assertTrue(hasTable, "Should contain a table block")
    }

    // MARK: - Task List
    static func testParseTaskList() {
        let parser = MarkdownParser()
        let ast = parser.parse("- [x] Done\n- [ ] Not done")
        assertEqual(ast.blocks.count, 1, "Should be 1 task list")
        if case .taskList(let items) = ast.blocks.first! {
            assertEqual(items.count, 2, "Should have 2 items")
            assertTrue(items[0].checked, "First item should be checked")
            assertFalse(items[1].checked, "Second item should not be checked")
        }
    }

    // MARK: - Blockquote
    static func testParseBlockquote() {
        let parser = MarkdownParser()
        let ast = parser.parse("> This is a quote")
        assertEqual(ast.blocks.count, 1, "Should be 1 blockquote")
        if case .blockquote(let blocks) = ast.blocks.first! {
            assertTrue(blocks.count >= 1, "Blockquote should have content")
        }
    }

    // MARK: - Thematic Break
    static func testParseThematicBreak() {
        let parser = MarkdownParser()
        let ast = parser.parse("---")
        assertEqual(ast.blocks.count, 1, "Should be 1 break")
        if case .thematicBreak = ast.blocks.first! {
            assertTrue(true, "Should be thematicBreak")
        } else {
            assertTrue(false, "Should be thematicBreak")
        }
    }

    // MARK: - Link & Image
    static func testParseLink() {
        let parser = MarkdownParser()
        let ast = parser.parse("[Click here](https://example.com)")
        if case .paragraph(let inlines) = ast.blocks.first! {
            var foundLink = false
            for inline in inlines {
                if case .link(let text, let url, _) = inline {
                    foundLink = true
                    assertEqual(url, "https://example.com", "URL should match")
                    assertEqual(text.count, 1, "Link text should have 1 element")
                }
            }
            assertTrue(foundLink, "Should find a link element")
        }
    }

    static func testParseImage() {
        let parser = MarkdownParser()
        let ast = parser.parse("![Alt](image.png)")
        if case .paragraph(let inlines) = ast.blocks.first! {
            var foundImage = false
            for inline in inlines {
                if case .image(let url, let alt) = inline {
                    foundImage = true
                    assertEqual(url, "image.png", "Image URL should match")
                    assertEqual(alt, "Alt", "Alt text should match")
                }
            }
            assertTrue(foundImage, "Should find an image element")
        }
    }

    // MARK: - Math
    static func testParseMathFormula() {
        let parser = MarkdownParser()
        let ast = parser.parse("Formula: $$E = mc^2$$")
        assertTrue(ast.hasMath, "Should detect math formula")
    }

    // MARK: - Mermaid
    static func testParseMermaidDiagram() {
        let parser = MarkdownParser()
        let ast = parser.parse("```mermaid\nflowchart LR\nA-->B\n```")
        assertTrue(ast.hasDiagram, "Should detect mermaid diagram")
        if case .diagramBlock(let type, _) = ast.blocks.first! {
            assertEqual(type, DiagramType.flowchart, "Diagram type should be flowchart")
        }
    }

    // MARK: - Footnote
    static func testParseFootnote() {
        let parser = MarkdownParser()
        let ast = parser.parse("Text[^1]\n\n[^1]: Footnote content")
        assertTrue(ast.blocks.count >= 1, "Should have blocks")
    }

    // MARK: - Detection
    static func testDetectMath() {
        let parser = MarkdownParser()
        let ast1 = parser.parse("No math here")
        assertFalse(ast1.hasMath, "Plain text no math")
        let ast2 = parser.parse("With $$math$$")
        assertTrue(ast2.hasMath, "Should detect $$")
        let ast3 = parser.parse("With $inline$ math")
        assertTrue(ast3.hasMath, "Should detect inline math $")
    }

    static func testDetectDiagram() {
        let parser = MarkdownParser()
        let ast1 = parser.parse("No diagram")
        assertFalse(ast1.hasDiagram, "Plain text no diagram")
        let ast2 = parser.parse("```mermaid\nflowchart LR\nA-->B\n```")
        assertTrue(ast2.hasDiagram, "Should detect mermaid")
    }

    // MARK: - Large Document
    static func testLargeDocument() {
        let parser = MarkdownParser()
        var lines: [String] = []
        for i in 1...100 {
            lines.append("## Heading \(i)")
            lines.append("Paragraph text for section \(i).")
        }
        let text = lines.joined(separator: "\n")
        let ast = parser.parse(text)
        assertTrue(ast.blocks.count > 50, "Large document should produce many blocks")
    }

    // MARK: - Heading Tree
    static func testBuildHeadingTree() {
        let parser = MarkdownParser()
        let text = "# Title\n## Section\n### Sub\n## Section2"
        let ast = parser.parse(text)
        assertEqual(ast.headingTree.count, 1, "Should have 1 root heading (H1)")
        if !ast.headingTree.isEmpty {
            let root = ast.headingTree[0]
            assertEqual(root.title, "Title", "Root title should be 'Title'")
            assertEqual(root.children.count, 2, "Should have 2 children (H2s)")
        }
    }
}
