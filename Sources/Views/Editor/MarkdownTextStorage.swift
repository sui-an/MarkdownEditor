import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    var suppressHighlighting = false
    var baseFontSize: CGFloat = 13
    private var editingNeedsHighlight = false
    private var insideHighlight = false

    // MARK: - Pre-compiled regex

    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(#{1,6}\s+.+)$"#, options: .anchorsMatchLines
    )
    private static let blockquoteRegex = try! NSRegularExpression(
        pattern: #"^>\s.*$"#, options: .anchorsMatchLines
    )
    private static let boldRegex = try! NSRegularExpression(
        pattern: #"\*\*(.+?)\*\*"#, options: []
    )
    private static let boldUnderlineRegex = try! NSRegularExpression(
        pattern: #"__(.+?)__"#, options: []
    )
    private static let italicStarRegex = try! NSRegularExpression(
        pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, options: []
    )
    private static let italicUnderscoreRegex = try! NSRegularExpression(
        pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, options: []
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
    private static let inlineCodeRegex = try! NSRegularExpression(
        pattern: #"`([^`\n]+)`"#, options: []
    )
    private static let taskListRegex = try! NSRegularExpression(
        pattern: #"^(\s*[-*+]\s)\[([ xX])\]"#, options: .anchorsMatchLines
    )
    private static let unorderedListRegex = try! NSRegularExpression(
        pattern: #"^(\s*[-*+]\s)"#, options: .anchorsMatchLines
    )
    private static let orderedListRegex = try! NSRegularExpression(
        pattern: #"^(\s*\d+\.\s)"#, options: .anchorsMatchLines
    )
    private static let horizontalRuleRegex = try! NSRegularExpression(
        pattern: #"^(\s*[-*_]{3,}\s*)$"#, options: .anchorsMatchLines
    )
    private static let htmlTagRegex = try! NSRegularExpression(
        pattern: #"</?[a-zA-Z][^>]*>"#, options: []
    )
    private static let autolinkRegex = try! NSRegularExpression(
        pattern: #"<(https?://[^>]+)>"#, options: []
    )

    override var string: String { backingStore.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        let newLength = (str as NSString).length
        backingStore.replaceCharacters(in: range, with: str)
        if newLength > 0 {
            backingStore.addAttributes([
                .foregroundColor: NSColor.textColor,
                .font: NSFont.systemFont(ofSize: baseFontSize),
                .strikethroughStyle: 0
            ], range: NSRange(location: range.location, length: newLength))
        }
        edited(.editedCharacters, range: range, changeInLength: newLength - range.length)
        editingNeedsHighlight = true
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        editingNeedsHighlight = true
        endEditing()
    }

    func replaceAllPrepared(_ text: String, isDark: Bool) {
        let oldLength = backingStore.length
        let newLength = (text as NSString).length
        beginEditing()
        backingStore.replaceCharacters(in: NSRange(location: 0, length: oldLength), with: text)
        if newLength > 0 {
            let fullRange = NSRange(location: 0, length: newLength)
            backingStore.addAttributes([
                .foregroundColor: NSColor.textColor,
                .font: NSFont.systemFont(ofSize: baseFontSize),
                .strikethroughStyle: 0
            ], range: fullRange)
            applyHighlightAttributes(in: fullRange, isDark: isDark)
        }
        edited([.editedCharacters, .editedAttributes], range: NSRange(location: 0, length: oldLength), changeInLength: newLength - oldLength)
        editingNeedsHighlight = false
        endEditing()
    }

    // MARK: - Highlight before display

    /// Apply syntax attributes BEFORE `super.endEditing()` triggers the
    /// text‑system display notification. This ensures the display pass
    /// sees both content and colors in a single frame — no flicker.
    override func endEditing() {
        if editingNeedsHighlight && !suppressHighlighting && !insideHighlight {
            editingNeedsHighlight = false
            insideHighlight = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.autoHighlight()
                self.insideHighlight = false
            }
        }
        super.endEditing()
    }

    override func processEditing() {
        super.processEditing()
    }

    private func autoHighlight() {
        let len = backingStore.length
        guard len > 0, len < 200_000 else { return }

        let isDark = NSApp.effectiveAppearance.name == .darkAqua

        // Clamp editedRange to valid bounds
        let safeRange = NSRange(location: 0, length: len)
        let er: NSRange
        if editedRange.location == NSNotFound || editedRange.location + editedRange.length > len || editedRange.length == 0 {
            er = safeRange
        } else {
            er = NSIntersectionRange(editedRange, safeRange)
        }

        // Compute range: expanded ≈ visible region
        let lineR = (backingStore.string as NSString).lineRange(for: er)
        let paraR = (backingStore.string as NSString).paragraphRange(for: lineR)
        let loc: Int = max(0, paraR.location - 100)
        let e = min(len, paraR.location + paraR.length + 200)
        let syncRange = NSRange(location: loc, length: e - loc)
        guard syncRange.length > 0 else { return }

        beginEditing()
        backingStore.addAttributes([
            .foregroundColor: NSColor.textColor,
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .strikethroughStyle: 0
        ], range: syncRange)
        applyHighlightAttributes(in: syncRange, isDark: isDark, includeCodeBlocks: er.length > 100 || isInsideCodeBlock(backingStore.string as NSString, range: er))
        edited(.editedAttributes, range: syncRange, changeInLength: 0)
        endEditing()
    }

    // MARK: - Full re-highlight (for theme switch)

    func rehighlightAll(isDark: Bool) {
        let len = backingStore.length
        guard len > 0 else { return }

        let fullRange = NSRange(location: 0, length: len)
        beginEditing()
        backingStore.addAttributes([
            .foregroundColor: NSColor.textColor,
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .strikethroughStyle: 0
        ], range: fullRange)
        applyHighlightAttributes(in: fullRange, isDark: isDark)
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        endEditing()

        for lm in layoutManagers {
            lm.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            lm.invalidateDisplay(forCharacterRange: fullRange)
        }
    }

    private func applyHighlightAttributes(in range: NSRange, isDark: Bool, includeCodeBlocks: Bool = true) {
        let text = backingStore.string as NSString
        let textLen = text.length
        highlightHeaders(in: text, length: textLen, range: range, isDark: isDark)
        highlightBlockquotes(in: text, length: textLen, range: range, isDark: isDark)
        if includeCodeBlocks {
            highlightCodeBlocks(in: text, length: textLen, range: range, isDark: isDark)
        }
        highlightInlinePatterns(in: text, length: textLen, range: range, isDark: isDark)
        highlightLists(in: text, length: textLen, range: range, isDark: isDark)
        highlightHorizontalRules(in: text, length: textLen, range: range, isDark: isDark)
        highlightTables(in: text, length: textLen, range: range, isDark: isDark)
        highlightHTML(in: text, length: textLen, range: range, isDark: isDark)
    }
}

// MARK: - Semantic highlight colors

private enum HighlightColors {
    static let headerLight   = NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
    static let headerDark    = NSColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1)
    static let quoteLight    = NSColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 1)
    static let quoteDark     = NSColor(red: 0.65, green: 0.70, blue: 0.75, alpha: 1)
    static let codeLight     = NSColor(red: 0.00, green: 0.62, blue: 0.35, alpha: 1)
    static let codeDark      = NSColor(red: 0.20, green: 0.80, blue: 0.50, alpha: 1)
    static let inlineCodeLight = NSColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1)
    static let inlineCodeDark   = NSColor(red: 0.90, green: 0.45, blue: 0.45, alpha: 1)
    static let linkLight     = NSColor(red: 0.65, green: 0.35, blue: 0.85, alpha: 1)
    static let linkDark      = NSColor(red: 0.80, green: 0.55, blue: 1.00, alpha: 1)
    static let imageLight    = NSColor(red: 0.90, green: 0.30, blue: 0.55, alpha: 1)
    static let imageDark     = NSColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
    static let boldLight     = NSColor(red: 0.85, green: 0.35, blue: 0.10, alpha: 1)
    static let boldDark      = NSColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1)
    static let italicLight   = NSColor(red: 0.55, green: 0.40, blue: 0.65, alpha: 1)
    static let italicDark    = NSColor(red: 0.70, green: 0.55, blue: 0.80, alpha: 1)
    static let strikeLight   = NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1)
    static let strikeDark    = NSColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1)
    static let listBulletLight = NSColor(red: 0.40, green: 0.50, blue: 0.65, alpha: 1)
    static let listBulletDark  = NSColor(red: 0.55, green: 0.65, blue: 0.80, alpha: 1)
    static let taskCheckedLight = NSColor(red: 0.20, green: 0.60, blue: 0.30, alpha: 1)
    static let taskCheckedDark  = NSColor(red: 0.30, green: 0.75, blue: 0.40, alpha: 1)
    static let taskUncheckedLight = NSColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
    static let taskUncheckedDark  = NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1)
    static let hrLight       = NSColor(red: 0.75, green: 0.78, blue: 0.82, alpha: 1)
    static let hrDark        = NSColor(red: 0.40, green: 0.42, blue: 0.45, alpha: 1)
    static let tableSepLight = NSColor(red: 0.70, green: 0.73, blue: 0.78, alpha: 1)
    static let tableSepDark  = NSColor(red: 0.45, green: 0.48, blue: 0.52, alpha: 1)
    static let htmlTagLight  = NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1)
    static let htmlTagDark   = NSColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)
    static let autolinkLight = NSColor(red: 0.10, green: 0.45, blue: 0.80, alpha: 1)
    static let autolinkDark  = NSColor(red: 0.30, green: 0.65, blue: 1.00, alpha: 1)

    static func header(_ d: Bool) -> NSColor { d ? headerDark : headerLight }
    static func quote(_ d: Bool) -> NSColor { d ? quoteDark : quoteLight }
    static func code(_ d: Bool) -> NSColor { d ? codeDark : codeLight }
    static func inlineCode(_ d: Bool) -> NSColor { d ? inlineCodeDark : inlineCodeLight }
    static func link(_ d: Bool) -> NSColor { d ? linkDark : linkLight }
    static func image(_ d: Bool) -> NSColor { d ? imageDark : imageLight }
    static func bold(_ d: Bool) -> NSColor { d ? boldDark : boldLight }
    static func italic(_ d: Bool) -> NSColor { d ? italicDark : italicLight }
    static func strike(_ d: Bool) -> NSColor { d ? strikeDark : strikeLight }
    static func listBullet(_ d: Bool) -> NSColor { d ? listBulletDark : listBulletLight }
    static func taskChecked(_ d: Bool) -> NSColor { d ? taskCheckedDark : taskCheckedLight }
    static func taskUnchecked(_ d: Bool) -> NSColor { d ? taskUncheckedDark : taskUncheckedLight }
    static func hr(_ d: Bool) -> NSColor { d ? hrDark : hrLight }
    static func tableSep(_ d: Bool) -> NSColor { d ? tableSepDark : tableSepLight }
    static func htmlTag(_ d: Bool) -> NSColor { d ? htmlTagDark : htmlTagLight }
    static func autolink(_ d: Bool) -> NSColor { d ? autolinkDark : autolinkLight }
}

// MARK: - Highlight implementations

private extension MarkdownTextStorage {
    func highlightHeaders(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let sr = range ?? NSRange(location: 0, length: length)
        let sizes: [CGFloat] = [baseFontSize + 11, baseFontSize + 7, baseFontSize + 5, baseFontSize + 3, baseFontSize + 1, baseFontSize]
        for m in Self.headerRegex.matches(in: text as String, range: sr) {
            let headerText = text.substring(with: m.range)
            var level = 0
            for ch in headerText { if ch == "#" { level += 1 } else { break } }
            let hSize = sizes[max(0, min(level, sizes.count) - 1)]
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.header(isDark), range: m.range)
            backingStore.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: hSize), range: m.range)
        }
    }

    func highlightBlockquotes(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let sr = range ?? NSRange(location: 0, length: length)
        for m in Self.blockquoteRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.quote(isDark), range: m.range)
        }
    }

    func highlightCodeBlocks(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        // Scan from the very beginning of the file so that ``` open/close
        // pairing is always correct regardless of syncRange position.
        let end = length
        var pos = 0
        var inCode = false
        var blockStart = 0

        while pos < end {
            if end - pos >= 3,
               text.character(at: pos) == 96,
               text.character(at: pos + 1) == 96,
               text.character(at: pos + 2) == 96 {
                if !inCode {
                    inCode = true; blockStart = pos; pos += 3
                    while pos < end, text.character(at: pos) != 10 { pos += 1 }
                    if pos < end { pos += 1 }
                } else {
                    let blockEnd = pos + 3
                    backingStore.addAttribute(.foregroundColor, value: HighlightColors.code(isDark), range: NSRange(location: blockStart, length: blockEnd - blockStart))
                    inCode = false; pos += 3
                }
                continue
            }
            while pos < end, text.character(at: pos) != 10 { pos += 1 }
            if pos < end { pos += 1 }
        }
        _ = inCode
    }

    func highlightInlinePatterns(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let sr = range ?? NSRange(location: 0, length: length)

        for m in Self.inlineCodeRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.inlineCode(isDark), range: m.range(at: 1))
        }
        for m in Self.boldRegex.matches(in: text as String, range: sr) {
            let r = m.range(at: 1)
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.bold(isDark), range: r)
        }
        for m in Self.boldUnderlineRegex.matches(in: text as String, range: sr) {
            let r = m.range(at: 1)
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.bold(isDark), range: r)
        }
        for m in Self.italicStarRegex.matches(in: text as String, range: sr) {
            let r = m.range(at: 1)
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.italic(isDark), range: r)
        }
        for m in Self.italicUnderscoreRegex.matches(in: text as String, range: sr) {
            let r = m.range(at: 1)
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.italic(isDark), range: r)
        }
        for m in Self.linkRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.link(isDark), range: m.range(at: 1))
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.link(isDark), range: m.range(at: 2))
        }
        for m in Self.imageRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.image(isDark), range: m.range(at: 1))
        }
        for m in Self.strikeRegex.matches(in: text as String, range: sr) {
            let r = m.range(at: 1)
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.strike(isDark), range: r)
            backingStore.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        for m in Self.autolinkRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.autolink(isDark), range: m.range(at: 1))
        }
    }

    func highlightLists(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let sr = range ?? NSRange(location: 0, length: length)
        for m in Self.taskListRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.listBullet(isDark), range: m.range(at: 1))
            let ch = text.substring(with: m.range(at: 2))
            let checked = ch == "x" || ch == "X"
            backingStore.addAttribute(.foregroundColor, value: checked ? HighlightColors.taskChecked(isDark) : HighlightColors.taskUnchecked(isDark), range: m.range(at: 2))
        }
        for m in Self.unorderedListRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.listBullet(isDark), range: m.range(at: 1))
        }
        for m in Self.orderedListRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.listBullet(isDark), range: m.range(at: 1))
        }
    }

    func highlightHorizontalRules(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let sr = range ?? NSRange(location: 0, length: length)
        for m in Self.horizontalRuleRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.hr(isDark), range: m.range(at: 1))
        }
    }

    func highlightTables(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        // Table highlighting not implemented yet
    }

    func highlightHTML(in text: NSString, length: Int, range: NSRange? = nil, isDark: Bool) {
        let sr = range ?? NSRange(location: 0, length: length)
        for m in Self.htmlTagRegex.matches(in: text as String, range: sr) {
            backingStore.addAttribute(.foregroundColor, value: HighlightColors.htmlTag(isDark), range: m.range)
        }
    }

    // MARK: - Helper

    /// Returns true when the edit range is inside a fenced code block
    /// (between a pair of ``` markers). Uses a backward scan to find the
    /// opening fence and a forward scan to verify the closing fence.
    func isInsideCodeBlock(_ text: NSString, range: NSRange) -> Bool {
        let len = text.length
        // Scan backward up to 200 chars for opening ```
        let backStart = max(0, range.location - 200)
        var openPos: Int? = nil
        var i = range.location - 1
        while i >= backStart {
            if i + 2 < len,
               text.character(at: i) == 96,
               text.character(at: i + 1) == 96,
               text.character(at: i + 2) == 96 {
                openPos = i
                break
            }
            i -= 1
        }
        guard let open = openPos else { return false }

        // Scan forward from after the opening fence for a closing ```
        let fwdEnd = min(len, open + 200)
        var j = open + 3
        // Skip the language tag line
        while j < fwdEnd, text.character(at: j) != 10 { j += 1 }
        if j < fwdEnd { j += 1 }
        // Look for closing ```
        while j < fwdEnd - 2 {
            if text.character(at: j) == 96,
               text.character(at: j + 1) == 96,
               text.character(at: j + 2) == 96 {
                return true  // found matching close, we're inside a code block
            }
            j += 1
        }
        return false
    }
}
