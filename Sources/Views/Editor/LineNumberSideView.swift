import AppKit

/// Standalone view that draws line numbers beside a text view.
final class LineNumberSideView: NSView {
    weak var textView: NSTextView?

    var isDark: Bool = false {
        didSet { needsDisplay = true }
    }

    var fontSize: CGFloat = 10 {
        didSet { needsDisplay = true }
    }

    private var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
    }
    private let textColor = NSColor.secondaryLabelColor

    private let labelParagraphStyle: NSParagraphStyle = {
        let s = NSMutableParagraphStyle()
        s.alignment = .right
        s.lineBreakMode = .byClipping
        return s
    }()

    // Newline positions cache
    private var newlinePositions: [Int] = []
    private var cachedTextLength: Int = 0
    private var textChangeObserver: Any?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateNewlineCache()
        }
    }

    deinit {
        if let o = textChangeObserver { NotificationCenter.default.removeObserver(o) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func invalidateNewlineCache() {
        cachedTextLength = 0
        newlinePositions.removeAll()
    }

    private func ensureNewlineCache() {
        guard let textView = textView else { return }
        let text = textView.string as NSString
        let currentLength = text.length
        guard cachedTextLength != currentLength else { return }

        var positions: [Int] = [0]
        positions.reserveCapacity(currentLength / 40)
        for i in 0..<currentLength {
            if text.character(at: i) == 10 {
                positions.append(i + 1)
            }
        }
        newlinePositions = positions
        cachedTextLength = currentLength
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        notesBackgroundColor(isDark: isDark).setFill()
        bounds.fill()

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let containerOrigin = textView.textContainerOrigin
        let textContent = textView.string as NSString
        let textLength = textContent.length
        guard textLength > 0 else { return }

        ensureNewlineCache()
        guard !newlinePositions.isEmpty else { return }

        // Find visible character range from the layout manager
        let visibleContainerRect = NSRect(
            x: visibleRect.minX - containerOrigin.x,
            y: visibleRect.minY - containerOrigin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let visGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        guard visGlyphRange.length > 0 else { return }

        let visCharRange = layoutManager.characterRange(
            forGlyphRange: visGlyphRange,
            actualGlyphRange: nil
        )
        guard visCharRange.location != NSNotFound, visCharRange.location < textLength else { return }

        // Binary search: find the line number for the first visible character
        let firstLine: Int
        if visCharRange.location == 0 {
            firstLine = 0
        } else {
            var lo = 0, hi = newlinePositions.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if newlinePositions[mid] <= visCharRange.location {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            firstLine = max(0, lo - 1)
        }

        let labelHeight = font.ascender + abs(font.descender)
        let padding: CGFloat = 6

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: labelParagraphStyle
        ]

        // Calculate right-aligned label width based on total line count
        let totalLines = newlinePositions.count
        let digits = "\(totalLines)".count
        let charWidth = ("0" as NSString).size(withAttributes: attrs).width
        let labelWidth = charWidth * CGFloat(digits) + padding

        // Draw line numbers for each visible line
        for lineIdx in firstLine..<newlinePositions.count {
            let lineStart = newlinePositions[lineIdx]
            let lineEnd = lineIdx + 1 < newlinePositions.count ? newlinePositions[lineIdx + 1] : textLength
            let lineLength = lineEnd - lineStart
            guard lineLength > 0 else { continue }

            let lineRange = NSRange(location: lineStart, length: lineLength)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { continue }

            let fragRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )

            // Convert from textContainer coords to view coords
            let lineY = fragRect.minY + containerOrigin.y - visibleRect.minY

            // Skip lines fully above or below visible area
            if lineY + fragRect.height < -labelHeight { continue }
            if lineY > visibleRect.height + labelHeight { break }

            let localY = lineY + (fragRect.height - labelHeight) / 2
            let lineStr = "\(lineIdx + 1)"
            let labelRect = NSRect(
                x: bounds.width - labelWidth - 2,
                y: localY,
                width: labelWidth,
                height: labelHeight
            )
            lineStr.draw(in: labelRect, withAttributes: attrs)
        }
    }
}
