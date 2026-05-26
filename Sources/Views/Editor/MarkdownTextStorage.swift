import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()

    /// Set to true during image-attachment replacement to avoid
    /// cascading regex highlighting on every NSTextStorage mutation.
    var suppressHighlighting = false

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

        // Reset foreground to dynamic NSColor.textColor which adapts to
        // light/dark mode automatically. Only .foregroundColor is touched —
        // .font is never set globally, preserving CJK font cascading.
        // Only reset the highlighted range, not the entire document.
        backingStore.addAttribute(.foregroundColor, value: NSColor.textColor, range: safeRange)

        let text = backingStore.string as NSString
        let textLength = text.length

        guard textLength < 200_000 else { return }

        // Only run regex on the limited range, not the entire document
        highlightHeaders(in: text, length: textLength, range: safeRange)
        highlightBlockquotes(in: text, length: textLength, range: safeRange)
        highlightCodeBlocks(in: text, length: textLength, range: safeRange)
        highlightInlinePatterns(in: text, length: textLength, range: safeRange)

        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: safeRange, actualCharacterRange: nil)
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
        static let italic   = NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1) // gray
        static let strike   = NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1) // subdued
    }

    // MARK: - Headers

    private func highlightHeaders(in text: NSString, length: Int, range: NSRange? = nil) {
        // Only color the # prefix — leave the heading text (which may contain
        // CJK/Unicode) with its default NSTextView attributes intact.
        let pattern = #"^(#{1,6})(?=\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }

        let searchRange = range ?? NSRange(location: 0, length: length)
        for match in regex.matches(in: text as String, range: searchRange) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.header, range: match.range)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(in text: NSString, length: Int, range: NSRange? = nil) {
        let pattern = #"^>\s.*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let searchRange = range ?? NSRange(location: 0, length: length)
        for match in regex.matches(in: text as String, range: searchRange) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.quote, range: match.range)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(in text: NSString, length: Int, range: NSRange? = nil) {
        let pattern = #"```[\s\S]*?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let searchRange = range ?? NSRange(location: 0, length: length)
        for match in regex.matches(in: text as String, range: searchRange) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.code, range: match.range)
        }
    }

    // MARK: - Inline Patterns

    private func highlightInlinePatterns(in text: NSString, length: Int, range: NSRange? = nil) {
        let searchRange = range ?? NSRange(location: 0, length: length)

        // Bold: **text** or __text__
        let boldPattern = #"\*\*(.+?)\*\*"#
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            let boldMatches = boldRegex.matches(in: text as String, range: searchRange)
            for match in boldMatches {
                if match.range(at: 1).location != NSNotFound {
                    backingStore.addAttribute(.foregroundColor, value: HighlightColors.bold, range: match.range(at: 1))
                }
            }
        }

        // Italic: *text* or _text_
        let italicPattern = #"(\*|_)(.+?)\1"#
        if let italicRegex = try? NSRegularExpression(pattern: italicPattern, options: []) {
            let italicMatches = italicRegex.matches(in: text as String, range: searchRange)
            for match in italicMatches {
                if match.range(at: 2).location != NSNotFound {
                    backingStore.addAttribute(.foregroundColor, value: HighlightColors.italic, range: match.range(at: 2))
                }
            }
        }

        // Links: [text](url)
        let linkPattern = #"\[(.+?)\]\((.+?)\)"#
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            let linkMatches = linkRegex.matches(in: text as String, range: searchRange)
            for match in linkMatches {
                if match.range(at: 1).location != NSNotFound {
                    backingStore.addAttribute(.foregroundColor, value: HighlightColors.link, range: match.range(at: 1))
                }
            }
        }

        // Images: ![alt](url)
        let imagePattern = #"!\[(.+?)\]\((.+?)\)"#
        if let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: []) {
            let imageMatches = imageRegex.matches(in: text as String, range: searchRange)
            for match in imageMatches {
                if match.range(at: 1).location != NSNotFound {
                    backingStore.addAttribute(.foregroundColor, value: HighlightColors.image, range: match.range(at: 1))
                }
            }
        }

        // Strikethrough: ~~text~~
        let strikePattern = #"~~(.+?)~~"#
        if let strikeRegex = try? NSRegularExpression(pattern: strikePattern, options: []) {
            let strikeMatches = strikeRegex.matches(in: text as String, range: searchRange)
            for match in strikeMatches {
                if match.range(at: 1).location != NSNotFound {
                    backingStore.addAttribute(.foregroundColor, value: HighlightColors.strike, range: match.range(at: 1))
                }
            }
        }
    }
}
