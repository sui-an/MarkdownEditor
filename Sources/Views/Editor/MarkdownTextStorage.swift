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
        // Only reset foreground color — do NOT override .font on the full text range.
        // Forcing .font explicitly on every character breaks NSTextView's native
        // font cascading for CJK/Unicode glyphs (Chinese, Japanese, Korean, emoji).
        // NSTextView.font already provides the correct default font for all scripts.
        backingStore.addAttribute(.foregroundColor, value: NSColor.textColor,
                                  range: NSRange(location: 0, length: backingStore.length))

        let text = backingStore.string as NSString
        let length = text.length

        // Skip highlighting for huge documents (> 200KB)
        guard length < 200_000 else { return }

        highlightHeaders(in: text, length: length)
        highlightBlockquotes(in: text, length: length)
        highlightCodeBlocks(in: text, length: length)
        highlightInlinePatterns(in: text, length: length)

        // Invalidate layout so the text view re-renders with updated attributes
        let fullRange = NSRange(location: 0, length: backingStore.length)
        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        }
    }

    // MARK: - Headers

    private func highlightHeaders(in text: NSString, length: Int) {
        let pattern = #"^(#{1,6})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let boldFont = NSFont.systemFont(ofSize: 13, weight: .bold)

        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            backingStore.addAttribute(.font, value: boldFont, range: match.range)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(in text: NSString, length: Int) {
        let pattern = #"^>\s.*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
            backingStore.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(in text: NSString, length: Int) {
        let pattern = #"```[\s\S]*?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: length)) {
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
        highlightInlineOnShortLines(pattern: boldPattern, attrs: [.font: NSFont.systemFont(ofSize: 14, weight: .bold)])
        highlightInlineOnShortLines(pattern: italicPattern, attrs: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask)])
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
