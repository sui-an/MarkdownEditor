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
        let textContent = textView.string as NSString

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

        while charIndex < textContent.length {
            let lineRange = textContent.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Stop once we're past the visible area (glyphRect is zero for non-laid-out lines beyond viewport)
            if glyphRect.minY > visibleRect.maxY {
                break
            }

            if glyphRect.maxY >= visibleRect.minY && glyphRect.minY <= visibleRect.maxY {
                let lineStr = "\(lineIndex)"
                // Convert from document Y to ruler-visible Y
                let y = glyphRect.minY - visibleRect.minY + (glyphRect.height - font.pointSize) / 2
                let labelRect = NSRect(x: 0, y: y, width: ruleThickness - 4, height: font.pointSize)
                lineStr.draw(in: labelRect, withAttributes: attrs)
            }

            charIndex = NSMaxRange(lineRange)
            lineIndex += 1
        }
    }
}
