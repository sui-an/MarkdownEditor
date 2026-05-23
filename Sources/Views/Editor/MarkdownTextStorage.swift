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
        // Reset foreground to dynamic NSColor.textColor which adapts to
        // light/dark mode automatically. Only .foregroundColor is touched —
        // .font is never set globally, preserving CJK font cascading.
        backingStore.addAttribute(.foregroundColor, value: NSColor.textColor,
                                  range: NSRange(location: 0, length: backingStore.length))

        let text = backingStore.string as NSString
        let length = text.length

        guard length < 200_000 else { return }

        highlightHeaders(in: text, length: length)
        highlightBlockquotes(in: text, length: length)
        highlightCodeBlocks(in: text, length: length)
        highlightInlinePatterns(in: text, length: length)

        let fullRange = NSRange(location: 0, length: backingStore.length)
        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        }
    }

    // MARK: - Semantic highlight colors

    private enum HighlightColors {
        static let header   = NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1) // #007AFF blue
        static let quote    = NSColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 1) // gray
        static let code     = NSColor(red: 0.00, green: 0.62, blue: 0.35, alpha: 1) // #009E59 green
        static let link     = NSColor(red: 0.65, green: 0.35, blue: 0.85, alpha: 1) // #A659D9 purple
        static let image    = NSColor(red: 0.90, green: 0.30, blue: 0.55, alpha: 1) // #E64D8C magenta
        static let bold     = NSColor(red: 1.00, green: 0.45, blue: 0.00, alpha: 1) // #FF7300 orange
        static let strike   = NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1) // subdued
    }

    // MARK: - Headers

    private func highlightHeaders(in text: NSString, length: Int) {
        // Only color the # prefix — leave the heading text (which may contain
        // CJK/Unicode) with its default NSTextView attributes intact.
        let pattern = #"^(#{1,6})(?=\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }

        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.header, range: match.range)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(in text: NSString, length: Int) {
        let pattern = #"^>\s.*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.quote, range: match.range)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(in text: NSString, length: Int) {
        let pattern = #"```[\s\S]*?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.code, range: match.range)
        }
    }

    // MARK: - Inline Patterns

    private func highlightInlinePatterns(in text: NSString, length: Int) {
        let patterns: [(String, [NSAttributedString.Key: Any])] = [
            (#"`([^`]+)`"#, [.foregroundColor: HighlightColors.code]),
            (#"!\[([^\]]*)\]\(([^)]+)\)"#, [.foregroundColor: HighlightColors.image]),
            (#"\[([^\]]+)\]\(([^)]+)\)"#, [.foregroundColor: HighlightColors.link]),
            (#"~~(.+?)~~"#, [.foregroundColor: HighlightColors.strike,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue]),
        ]

        for (pattern, attrs) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
                guard match.range.length < 2000 else { continue }
                var existing = backingStore.attributes(at: match.range.location, effectiveRange: nil)
                for (key, value) in attrs { existing[key] = value }
                backingStore.setAttributes(existing, range: match.range)
            }
        }

        let boldPattern = #"(\*\*|__)(.+?)\1"#
        let italicPattern = #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#
        highlightInlineOnShortLines(pattern: boldPattern, attrs: [.foregroundColor: HighlightColors.bold])
        highlightInlineOnShortLines(pattern: italicPattern, attrs: [.foregroundColor: HighlightColors.bold])
    }

    private func highlightInlineOnShortLines(pattern: String, attrs: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = backingStore.string as NSString
        let length = text.length
        var pos = 0
        while pos < length {
            let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
            if lineRange.length < 500 {
                for match in regex.matches(in: text as String, range: lineRange) {
                    guard match.range.length < 2000 else { continue }
                    var existing = backingStore.attributes(at: match.range.location, effectiveRange: nil)
                    for (key, value) in attrs { existing[key] = value }
                    backingStore.setAttributes(existing, range: match.range)
                }
            }
            pos = NSMaxRange(lineRange)
        }
    }
}
