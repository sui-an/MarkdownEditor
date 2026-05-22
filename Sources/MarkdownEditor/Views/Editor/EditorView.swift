import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollTarget: NSRange?
    var isLocked: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        textView.isEditable = !isLocked
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 20)
        textView.textContainer?.lineFragmentPadding = 0
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.textColor
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.scrollerKnobStyle = .default
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? EditorTextView else { return }

        textView.isEditable = !isLocked

        let eq = textView.markdownText == text
        if !eq {
            textView.string = text
            textView.convertDataUriImages()
            if let storage = textView.textStorage {
                SyntaxHighlighter.highlight(storage)
            }
        }

            if let target = scrollTarget {
            // Clamp to valid range
            let clamped = NSRange(
                location: min(target.location, text.utf16.count),
                length: min(target.length, text.utf16.count - min(target.location, text.utf16.count))
            )
            if clamped.length > 0 || clamped.location < text.utf16.count {
                textView.scrollRangeToVisible(clamped)
                textView.showFindIndicator(for: clamped)
            }
            DispatchQueue.main.async {
                scrollTarget = nil
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        var highlightTask: DispatchWorkItem?
        weak var textView: NSTextView?

        init(parent: MarkdownEditorView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleFindAction(_:)),
                name: .performFindAction, object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func handleFindAction(_ notification: Notification) {
            guard let rawValue = notification.userInfo?["action"] as? Int,
                  let tv = textView else { return }
            guard let fr = tv.window?.firstResponder, fr === tv else { return }
            let sender = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            sender.tag = rawValue
            tv.performTextFinderAction(sender)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? EditorTextView else { return }
            parent.text = textView.markdownText
            scheduleHighlight(textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSStandardKeyBindingResponding.insertTab(_:)) {
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }

        private func scheduleHighlight(_ textView: NSTextView) {
            highlightTask?.cancel()
            let task = DispatchWorkItem { [weak textView] in
                guard let tv = textView, let storage = tv.textStorage else { return }
                let markedLen = tv.markedRange().length
                guard markedLen == 0 else { return }
                SyntaxHighlighter.highlight(storage)
            }
            highlightTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
    }
}

// MARK: - Inline Image Attachment

/// Renders an image inline in the text view, scaled to fit within display bounds.
class ImageAttachmentCell: NSTextAttachmentCell {
    let markdownString: String
    let imageData: Data

    private static let maxDisplayWidth: CGFloat = 360
    private static let maxDisplayHeight: CGFloat = 300

    init(imageData: Data, markdown: String) {
        self.imageData = imageData
        self.markdownString = markdown
        super.init()
        self.image = NSImage(data: imageData)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        guard let img = image else { return NSSize(width: 20, height: 20) }
        let imageW = img.size.width
        let imageH = img.size.height

        var w = min(imageW, Self.maxDisplayWidth)
        var h = w * (imageH / imageW)

        if h > Self.maxDisplayHeight {
            h = Self.maxDisplayHeight
            w = h * (imageW / imageH)
        }

        return NSSize(width: w, height: h)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let img = image else { return }
        img.draw(in: cellFrame, from: NSZeroRect, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }
}

class EditorTextView: NSTextView {
    /// Tracks whether the document contains any inline image attachments.
    /// When false, `markdownText` can skip the expensive attribute-scan and
    /// return the plain string directly.
    private(set) var hasImageAttachments = false

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let storage = textStorage, storage.length > 0 {
            typingAttributes = storage.attributes(at: min(selectedRange().location, storage.length - 1), effectiveRange: nil)
        }
        return result
    }

    /// Full markdown representation including data URIs for pasted images.
    /// Converts any inline image attachments back to `![...](data:...)` strings.
    var markdownText: String {
        guard hasImageAttachments else { return string }
        guard let storage = textStorage, storage.length > 0 else { return string }
        let fullRange = NSRange(location: 0, length: storage.length)
        var result = ""
        var pos = 0
        while pos < fullRange.length {
            var effectiveRange = NSRange()
            let attrs = storage.attributes(at: pos, effectiveRange: &effectiveRange)
            let end = min(effectiveRange.upperBound, fullRange.length)
            if let attachment = attrs[.attachment] as? NSTextAttachment,
               let cell = attachment.attachmentCell as? ImageAttachmentCell {
                result += cell.markdownString
            } else {
                let substring = (storage.string as NSString).substring(with: NSRange(location: pos, length: end - pos))
                result += substring
            }
            pos = end
        }
        return result
    }

    // MARK: - Drag-and-Drop (Image Files)

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let charIndex = characterIndexForInsertion(at: dropPoint)
        setSelectedRange(NSRange(location: charIndex, length: 0))

        let scrollOrigin = enclosingScrollView?.documentVisibleRect.origin

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"].contains(ext),
                   let markdown = imageFileToDataURI(url) {
                    insertText(markdown, replacementRange: selectedRange())
                    convertDataUriImages()
                    if let origin = scrollOrigin {
                        scroll(NSPoint(x: origin.x, y: origin.y))
                    }
                    return true
                }
            }
        }

        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first,
           let markdown = nsImageToDataURI(first, label: "dragged image") {
            insertText(markdown, replacementRange: selectedRange())
            convertDataUriImages()
            if let origin = scrollOrigin {
                scroll(NSPoint(x: origin.x, y: origin.y))
            }
            return true
        }

        return super.performDragOperation(sender)
    }

    private func imageFileToDataURI(_ url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return nsImageToDataURI(image, label: url.lastPathComponent)
    }

    /// Converts an NSImage to a markdown image string with embedded base64 data URI.
    private func nsImageToDataURI(_ image: NSImage, label: String) -> String? {
        guard let imageData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let base64 = pngData.base64EncodedString()
        return "![\(label)](data:image/png;base64,\(base64))"
    }

    // MARK: - Paste Handling

    override func paste(_ sender: Any?) {
        if let image = extractImageFromPasteboard() {
            insertPastedImage(image)
            return
        }

        super.paste(sender)
    }

    private func extractImageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let first = images.first {
            return first
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"].contains(ext) {
                    if let image = NSImage(contentsOf: url) { return image }
                }
            }
        }
        return nil
    }

    /// Pastes an image by inserting markdown text with embedded base64 data URI.
    /// No NSTextAttachment is created, so the editor shows the markdown syntax
    /// rather than an inline rendered image.  The preview panel renders it
    /// natively via WKWebView's data: URI support.
    private func insertPastedImage(_ image: NSImage) {
        guard let imageData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let base64 = pngData.base64EncodedString()
        let markdown = "![pasted image](data:image/png;base64,\(base64))"
        let scrollOrigin = enclosingScrollView?.documentVisibleRect.origin

        insertText(markdown, replacementRange: selectedRange())
        convertDataUriImages()

        if let origin = scrollOrigin {
            scroll(NSPoint(x: origin.x, y: origin.y))
        }
    }

    // MARK: - Data URI → Inline Image Conversion

    /// Scans the current text storage for `![...](data:image/...;base64,...)` patterns
    /// and replaces each match with an inline NSTextAttachment.
    /// This keeps base64 data out of the text storage so layout and syntax
    /// highlighting stay fast even with large embedded images.
    func convertDataUriImages() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let str = storage.string as NSString

        guard let regex = try? NSRegularExpression(
            pattern: "!\\[([^\\]]*)\\]\\(data:image/([^;]+);base64,([^)]+)\\)",
            options: []
        ) else { return }

        let matches = regex.matches(in: str as String, range: NSRange(location: 0, length: storage.length))
        guard !matches.isEmpty else { return }

        hasImageAttachments = true

        for match in matches.reversed() {
            let fullRange = match.range
            let base64Range = match.range(at: 3)
            guard base64Range.location != NSNotFound else { continue }

            let base64Str = str.substring(with: base64Range)
            let markdown = str.substring(with: fullRange)

            guard let imageData = Data(base64Encoded: base64Str),
                  let _ = NSImage(data: imageData)
            else { continue }

            let attachment = NSTextAttachment()
            let cell = ImageAttachmentCell(imageData: imageData, markdown: markdown)
            attachment.attachmentCell = cell

            storage.replaceCharacters(in: fullRange, with: NSAttributedString(attachment: attachment))
        }
    }
}

// MARK: - Syntax Highlighting

enum SyntaxHighlighter {
    private static let rules: [Rule] = {
        let palette: [(String, NSColor)] = [
            ("^#{1,6}\\s+.*$", NSColor(red: 0.91, green: 0.38, blue: 0.38, alpha: 1)),
            ("(\\*\\*|__)(.+?)\\1", NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)),
            ("(?<!\\*)(\\*|_)(?!\\*)(.+?)\\1(?!\\*)", NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)),
            ("`[^`]+`", NSColor(red: 0.80, green: 0.50, blue: 0.20, alpha: 1)),
            ("\\[([^\\]]+)\\]\\(([^)]+)\\)", NSColor(red: 0.60, green: 0.40, blue: 0.80, alpha: 1)),
            ("!\\[([^\\]]*)\\]\\(([^)]+)\\)", NSColor(red: 0.60, green: 0.40, blue: 0.80, alpha: 1)),
            ("^(\\s*)[\\-\\*\\+]\\s", NSColor(red: 0.45, green: 0.70, blue: 0.35, alpha: 1)),
            ("^(\\s*)\\d+\\.\\s", NSColor(red: 0.45, green: 0.70, blue: 0.35, alpha: 1)),
            ("^>\\s?", NSColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)),
            ("^-{3,}$|^\\*{3,}$", NSColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)),
        ]
        return palette.compactMap { (p, c) in
            guard let r = try? NSRegularExpression(pattern: p, options: [.anchorsMatchLines]) else { return nil }
            return Rule(pattern: r, color: c)
        }
    }()

    struct Rule {
        let pattern: NSRegularExpression
        let color: NSColor
    }

    static func highlight(_ storage: NSTextStorage) {
        guard storage.length > 0 else { return }

        let currentText = storage.string
        storage.beginEditing()

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ], range: fullRange)

        for rule in rules {
            rule.pattern.enumerateMatches(in: currentText, range: fullRange) { match, _, _ in
                guard let m = match else { return }
                storage.addAttributes([.foregroundColor: rule.color], range: m.range(at: 0))
            }
        }

        storage.endEditing()
    }
}
