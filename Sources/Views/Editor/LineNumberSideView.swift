import AppKit

/// Standalone view that draws line numbers beside a text view.
/// Replaces LineNumberRulerView to avoid NSScrollView ruler timing issues.
final class LineNumberSideView: NSView {
    weak var textView: NSTextView?

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let textColor = NSColor.secondaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let textContent = textView.string as NSString
        let textLength = textContent.length
        guard textLength > 0 else { return }

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }

        let extendedRect = NSRect(
            x: visibleRect.minX,
            y: max(0, visibleRect.minY - 100),
            width: visibleRect.width,
            height: visibleRect.height + 200
        )
        let extGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: extendedRect,
            in: textContainer
        )
        guard extGlyphRange.length > 0 else { return }

        let charRange = layoutManager.characterRange(
            forGlyphRange: extGlyphRange,
            actualGlyphRange: nil
        )
        guard charRange.location != NSNotFound, charRange.location < textLength else { return }

        var lineNumber = 1
        let scanEnd = min(charRange.location, textLength)
        for i in 0..<scanEnd {
            if textContent.character(at: i) == 0x0A {
                lineNumber += 1
            }
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
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            if glyphRect.minY > visibleRect.maxY { break }

            if glyphRect.maxY >= visibleRect.minY && glyphRect.minY <= visibleRect.maxY {
                let lineStr = "\(lineIndex)"
                let localY = glyphRect.minY - visibleRect.minY
                    + (glyphRect.height - font.pointSize) / 2
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
