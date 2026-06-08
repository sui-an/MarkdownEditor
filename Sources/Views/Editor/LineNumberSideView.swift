import AppKit

/// Standalone view that draws line numbers beside a text view.
/// Replaces LineNumberRulerView to avoid NSScrollView ruler timing issues.
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

        var positions: [Int] = [0]
        positions.reserveCapacity(currentLength / 40)
        for i in 0..<currentLength {
            if text.character(at: i) == 10 { // \n
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

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: labelParagraphStyle
        ]

        let viewWidth = bounds.width
        var lineIndex = lineNumber

        while lineIndex - 1 < newlinePositions.count {
            let lineStart = newlinePositions[lineIndex - 1]
            let lineLength: Int
            if lineIndex < newlinePositions.count {
                lineLength = newlinePositions[lineIndex] - lineStart
            } else {
                lineLength = textLength - lineStart
            }
            guard lineLength > 0 else { lineIndex += 1; continue }
            let lineRange = NSRange(location: lineStart, length: lineLength)

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else {
                lineIndex += 1; continue
            }
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

            lineIndex += 1
        }
    }
}


