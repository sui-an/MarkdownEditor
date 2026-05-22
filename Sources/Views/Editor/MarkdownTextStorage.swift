import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()

    override var string: String {
        backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        super.processEditing()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyHighlighting), object: nil)
        perform(#selector(applyHighlighting), with: nil, afterDelay: 0.1)
    }

    @objc private func applyHighlighting() {
        let baseFont = NSFont.systemFont(ofSize: 13)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor
        ]

        beginEditing()
        backingStore.setAttributes(baseAttrs, range: NSRange(location: 0, length: backingStore.length))

        let text = backingStore.string as NSString
        let length = text.length

        // Skip highlighting for huge documents (> 200KB) to avoid beachball
        guard length < 200_000 else {
            endEditing()
            return
        }

        // Headers (must run first — whole-line styling)
        highlightHeaders(in: text, length: length)

        // Blockquotes
        highlightBlockquotes(in: text, length: length)

        // Code blocks (multi-line) — find ``` ... ``` spans
        highlightCodeBlocks(in: text, length: length)

        // Bold + Italic + Strikethrough + Inline Code + Links + Images (inline)
        highlightInlinePatterns(in: text, length: length)

        endEditing()
    }

    // MARK: - Headers

    private func highlightHeaders(in text: NSString, length: Int) {
        let pattern = #"^(#{1,6})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }

        let matches = regex.matches(in: text as String, options: [], range: NSRange(location: 0, length: length))
        let boldFont = NSFont.systemFont(ofSize: 13, weight: .bold)

        for match in matches {
            let fullRange = match.range(at: 0)
            backingStore.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: fullRange)
            backingStore.addAttribute(.font, value: boldFont, range: fullRange)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(in text: NSString, length: Int) {
        let pattern = #"^>\s.*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }

        for match in regex.matches(in: text as String, options: [], range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(in text: NSString, length: Int) {
        let pattern = #"```[\s\S]*?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }

        for match in regex.matches(in: text as String, options: [], range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
        }
    }

    // MARK: - Inline Patterns

    private func highlightInlinePatterns(in text: NSString, length: Int) {
        let patterns: [(String, [NSAttributedString.Key: Any])] = [
            (#"`([^`]+)`"#, [.foregroundColor: NSColor.systemGreen]),
            (#"!\[([^\]]*)\]\(([^)]+)\)"#, [.foregroundColor: NSColor.systemPurple]),
            (#"\[([^\]]+)\]\(([^)]+)\)"#, [.foregroundColor: NSColor.systemBlue]),
            (#"~~(.+?)~~"#, [.foregroundColor: NSColor.tertiaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]),
        ]

        for (pattern, attrs) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            for match in regex.matches(in: text as String, options: [], range: NSRange(location: 0, length: length)) {
                // Skip matches across extremely long spans (base64, data URIs)
                guard match.range.length < 2000 else { continue }
                var existing = backingStore.attributes(at: match.range.location, effectiveRange: nil)
                for (key, value) in attrs {
                    existing[key] = value
                }
                backingStore.setAttributes(existing, range: match.range)
            }
        }

        // Bold/Italic — only on lines < 500 chars to avoid base64 backtracking
        let boldPattern = #"(\*\*|__)(.+?)\1"#
        let italicPattern = #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#
        highlightInlineOnShortLines(pattern: boldPattern, attrs: [.font: NSFont.systemFont(ofSize: 14, weight: .bold)])
        highlightInlineOnShortLines(pattern: italicPattern, attrs: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask)])
    }

    /// Apply regex only to lines shorter than 500 characters to avoid catastrophic backtracking on base64 / data URIs.
    private func highlightInlineOnShortLines(pattern: String, attrs: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = backingStore.string as NSString
        let length = text.length
        var pos = 0
        while pos < length {
            let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
            if lineRange.length < 500 {
                for match in regex.matches(in: text as String, options: [], range: lineRange) {
                    guard match.range.length < 2000 else { continue }
                    var existing = backingStore.attributes(at: match.range.location, effectiveRange: nil)
                    for (key, value) in attrs {
                        existing[key] = value
                    }
                    backingStore.setAttributes(existing, range: match.range)
                }
            }
            pos = NSMaxRange(lineRange)
        }
    }
}
