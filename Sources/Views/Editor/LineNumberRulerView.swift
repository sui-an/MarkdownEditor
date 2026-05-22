import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let textColor = NSColor.secondaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 36
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        let textContent = textView.string as NSString

        let lineCount = textContent.length > 0
            ? textContent.lineRange(for: charRange).length
            : 1

        let firstLine = textContent.length > 0
            ? textContent.lineRange(for: NSRange(location: 0, length: 1)).length
            : 1

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .right
        paraStyle.lineBreakMode = .byClipping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paraStyle
        ]

        var lineIndex = 1
        var charIndex = 0

        while charIndex < textContent.length && lineIndex <= charRange.location + charRange.length + 1 {
            let lineRange = textContent.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            if glyphRect.maxY >= visibleRect.minY && glyphRect.minY <= visibleRect.maxY {
                let lineStr = "\(lineIndex)"
                let y = glyphRect.minY + (glyphRect.height - font.pointSize) / 2
                let labelRect = NSRect(x: 0, y: y, width: ruleThickness - 4, height: font.pointSize)
                lineStr.draw(in: labelRect, withAttributes: attrs)
            }

            charIndex = NSMaxRange(lineRange)
            lineIndex += 1
        }
    }
}
