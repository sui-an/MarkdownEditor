import AppKit

/// Standalone view that draws line numbers beside a text view.
/// Replaces LineNumberRulerView to avoid NSScrollView ruler timing issues.
final class LineNumberSideView: NSView {
    weak var textView: NSTextView?

    var isDark: Bool = false {
        didSet { needsDisplay = true }
    }

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let textColor = NSColor.secondaryLabelColor

    // Newline position cache for O(log n) line number lookup
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
        needsDisplay = true
    }

    private func ensureNewlineCache() {
        guard let textView = textView else { return }
        let text = textView.string as NSString
        let currentLength = text.length
        guard cachedTextLength != currentLength else { return }

        var positions: [Int] = []
        var range = NSRange(location: 0, length: 0)
        while range.location < currentLength {
            range = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            if range.location < currentLength {
                positions.append(range.location)
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

        layoutManager.ensureLayout(for: textContainer)
        let visibleRect = textView.visibleRect
        let textContent = textView.string as NSString
        let textLength = textContent.length
        guard textLength > 0 else { return }

        let extendedRect = NSRect(
            x: visibleRect.minX,
            y: max(0, visibleRect.minY - 100),
            width: visibleRect.width,
            height: visibleRect.height + 200
        )
        let extGlyphRange = layoutManager.glyphRange(
            forBoundingRect: extendedRect,
            in: textContainer
        )
        guard extGlyphRange.length > 0 else { return }

        let charRange = layoutManager.characterRange(
            forGlyphRange: extGlyphRange,
            actualGlyphRange: nil
        )
        guard charRange.location != NSNotFound, charRange.location < textLength else { return }

        ensureNewlineCache()
        // Binary search: find how many newline positions are before charRange.location
        let lineNumber: Int
        if charRange.location == 0 {
            lineNumber = 1
        } else {
            var lo = 0, hi = newlinePositions.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if newlinePositions[mid] < charRange.location {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            lineNumber = lo + 1
        }

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .right
        paraStyle.lineBreakMode = .byClipping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paraStyle
        ]

        let viewWidth = bounds.width
        var charIndex = charRange.location
        var lineIndex = lineNumber

        while charIndex < textLength {
            let lineRange = textContent.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            let fragRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )

            if fragRect.minY > visibleRect.maxY { break }

            if fragRect.maxY >= visibleRect.minY && fragRect.minY <= visibleRect.maxY {
                let lineStr = "\(lineIndex)"
                let localY = fragRect.minY - visibleRect.minY
                    + (fragRect.height - font.pointSize) / 2
                let labelRect = NSRect(
                    x: 0, y: localY,
                    width: viewWidth - 4,
                    height: font.pointSize
                )
                lineStr.draw(in: labelRect, withAttributes: attrs)
            }

            charIndex = NSMaxRange(lineRange)
            lineIndex += 1
        }
    }
}


