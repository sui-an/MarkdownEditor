import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()

    /// Set to true during image-attachment replacement to avoid
    /// cascading regex highlighting on every NSTextStorage mutation.
    var suppressHighlighting = false

    // MARK: - Pre-compiled regex (compiled once, reused on every keystroke)

    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(#{1,6})(?=\s)"#, options: .anchorsMatchLines
    )
    private static let blockquoteRegex = try! NSRegularExpression(
        pattern: #"^>\s.*$"#, options: .anchorsMatchLines
    )
    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: #"(?m)^```[\s\S]*?^```"#, options: []
    )
    private static let boldRegex = try! NSRegularExpression(
        pattern: #"\*\*(.+?)\*\*"#, options: []
    )
    private static let italicStarRegex = try! NSRegularExpression(
        pattern: #"\*(.+?)\*"#, options: []
    )
    private static let italicUnderscoreRegex = try! NSRegularExpression(
        pattern: #"\b_(.+?)_\b"#, options: []
    )
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"\[(.+?)\]\((.+?)\)"#, options: []
    )
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"!\[(.+?)\]\((.+?)\)"#, options: []
    )
    private static let strikeRegex = try! NSRegularExpression(
        pattern: #"~~(.+?)~~"#, options: []
    )

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
        guard !suppressHighlighting else { return }

        // Only re-highlight if something actually changed
        guard editedRange.length > 0 else { return }

        // For large files, limit highlighting to the changed area to avoid
        // O(n) regex matching on the entire document. Expand the range to
        // cover a few lines before and after the edit.
        let text = backingStore.string as NSString
        let lineRange = text.lineRange(for: editedRange)
        let expandedRange = text.paragraphRange(for: lineRange)
        // Limit expansion to avoid infinite loops
        let highlightRange = NSRange(
            location: max(0, expandedRange.location - 100),
            length: min(text.length - expandedRange.location, expandedRange.length + 200)
        )

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyHighlighting), object: nil)
        perform(#selector(applyHighlighting), with: highlightRange, afterDelay: 0.1)
    }

    @objc private func applyHighlighting(_ range: NSRange) {
        let length = backingStore.length
        guard length > 0, range.location < length else { return }
        let safeRange = NSRange(location: range.location, length: min(range.length, length - range.location))
        guard safeRange.length > 0 else { return }

        backingStore.addAttribute(.foregroundColor, value: NSColor.textColor, range: safeRange)

        let text = backingStore.string as NSString
        let textLength = text.length

        guard textLength < 200_000 else { return }

        let isDark = NSApp.effectiveAppearance.name == .darkAqua
        highlightHeaders(in: text, length: textLength, range: safeRange, isDark: isDark)
        highlightBlockquotes(in: text, length: textLength, range: safeRange, isDark: isDark)
        highlightCodeBlocks(in: text, length: textLength, range: safeRange, isDark: isDark)
        highlightInlinePatterns(in: text, length: textLength, range: safeRange, isDark: isDark)

        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: safeRange, actualCharacterRange: nil)
        }
    }

    func rehighlightAll(isDark: Bool) {
        let length = backingStore.length
        guard length > 0 else { return }

        let fullRange = NSRange(location: 0, length: length)
        backingStore.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        let text = backingStore.string as NSString
        let textLength = text.length
        highlightHeaders(in: text, length: textLength, isDark: isDark)
        highlightBlockquotes(in: text, length: textLength, isDark: isDark)
        highlightCodeBlocks(in: text, length: textLength, isDark: isDark)
        highlightInlinePatterns(in: text, length: textLength, isDark: isDark)

        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        }
    }

    // MARK: - Semantic highlight colors

    private enum HighlightColors {
        static func header(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1)
                : NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        }
        static func quote(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 0.65, green: 0.70, blue: 0.75, alpha: 1)
                : NSColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 1)
        }
        static func code(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 0.20, green: 0.80, blue: 0.50, alpha: 1)
                : NSColor(red: 0.00, green: 0.62, blue: 0.35, alpha: 1)
        }
        static func link(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 0.80, green: 0.55, blue: 1.00, alpha: 1)
                : NSColor(red: 0.65, green: 0.35, blue: 0.85, alpha: 1)
        }
        static func image(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
                : NSColor(red: 0.90, green: 0.30, blue: 0.55, alpha: 1)
        }
        static func bold(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 1.00, green: 0.60, blue: 0.20, alpha: 1)
                : NSColor(red: 1.00, green: 0.45, blue: 0.00, alpha: 1)
        }
        static func italic(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1)
                : NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
        }
        static func strike(_ isDark: Bool) -> NSColor {
            isDark
                ? NSColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1)
                : NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1)
        }
    }

    // MARK: - Headers

    private func highlightHeaders(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let searchRange = range ?? NSRange(location: 0, length: length)
        for match in Self.headerRegex.matches(in: text as String, range: searchRange) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.header(isDark), range: match.range)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let searchRange = range ?? NSRange(location: 0, length: length)
        for match in Self.blockquoteRegex.matches(in: text as String, range: searchRange) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.quote(isDark), range: match.range)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let searchRange = range ?? NSRange(location: 0, length: length)
        for match in Self.codeBlockRegex.matches(in: text as String, range: searchRange) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.code(isDark), range: match.range)
        }
    }

    // MARK: - Inline Patterns

    private func highlightInlinePatterns(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let searchRange = range ?? NSRange(location: 0, length: length)

        for match in Self.boldRegex.matches(in: text as String, range: searchRange) {
            if match.range(at: 1).location != NSNotFound {
                backingStore.addAttribute(.foregroundColor, value: HighlightColors.bold(isDark), range: match.range(at: 1))
            }
        }
        for match in Self.italicStarRegex.matches(in: text as String, range: searchRange) {
            if match.range(at: 1).location != NSNotFound {
                backingStore.addAttribute(.foregroundColor, value: HighlightColors.italic(isDark), range: match.range(at: 1))
            }
        }
        for match in Self.italicUnderscoreRegex.matches(in: text as String, range: searchRange) {
            if match.range(at: 1).location != NSNotFound {
                backingStore.addAttribute(.foregroundColor, value: HighlightColors.italic(isDark), range: match.range(at: 1))
            }
        }
        for match in Self.linkRegex.matches(in: text as String, range: searchRange) {
            if match.range(at: 1).location != NSNotFound {
                backingStore.addAttribute(.foregroundColor, value: HighlightColors.link(isDark), range: match.range(at: 1))
            }
        }
        for match in Self.imageRegex.matches(in: text as String, range: searchRange) {
            if match.range(at: 1).location != NSNotFound {
                backingStore.addAttribute(.foregroundColor, value: HighlightColors.image(isDark), range: match.range(at: 1))
            }
        }
        for match in Self.strikeRegex.matches(in: text as String, range: searchRange) {
            if match.range(at: 1).location != NSNotFound {
                backingStore.addAttribute(.foregroundColor, value: HighlightColors.strike(isDark), range: match.range(at: 1))
            }
        }
    }
}
