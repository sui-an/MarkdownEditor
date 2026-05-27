import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Image Attachment for inline base64 display

final class MarkdownImageAttachment: NSTextAttachment {
    var markdownSource: String = ""
}

// MARK: - NSTextView subclass with image drop/paste

final class ImageDropTextView: NSTextView {
    var onImageDrop: ((URL) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let placeholder = "请开始你的创作之旅吧～ ^.^"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: NSFont.systemFont(ofSize: 13)
        ]
        let inset = textContainerInset
        let point = NSPoint(x: inset.width + 4, y: inset.height)
        (placeholder as NSString).draw(at: point, withAttributes: attrs)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ImageHandler.supportedImageExtensions.contains(ext) {
                    onImageDrop?(url)
                    return true
                }
            }
        }

        if let image = NSImage(pasteboard: pasteboard) {
            onImagePaste?(image)
            return true
        }

        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.apple.icns"),
        ]

        for type in imageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                onImagePaste?(image)
                return
            }
        }

        if let image = NSImage(pasteboard: pasteboard) {
            onImagePaste?(image)
            return
        }

        super.paste(sender)
    }
}

// MARK: - Scroll View that preserves horizontal scroll position across collapse/expand

final class EditorScrollView: NSScrollView {
    /// Last non-zero horizontal offset, updated on every user scroll.
    private var lastNonZeroHorizontalOffset: CGFloat = 0
    private var pendingRestoreOffset: CGFloat = 0

    func clearPendingRestoreOffset() {
        pendingRestoreOffset = 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        let x = contentView.bounds.origin.x
        if x > 0 {
            lastNonZeroHorizontalOffset = x
            pendingRestoreOffset = 0
        } else if pendingRestoreOffset > 0 {
            var bounds = contentView.bounds
            bounds.origin.x = pendingRestoreOffset
            contentView.bounds = bounds
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width

        // When collapsing to near-zero width, detach width tracking so the text
        // container keeps its previous width — text never reflows to 0, which
        // prevents NSTextView from resetting the horizontal scroll position.
        if newSize.width < 200, oldWidth >= 200 {
            if let textView = documentView as? NSTextView, let container = textView.textContainer {
                container.widthTracksTextView = false
                container.containerSize.width = oldWidth
            }
        }

        let savedOffset = lastNonZeroHorizontalOffset
        super.setFrameSize(newSize)

        if oldWidth < 200, newSize.width >= 200 {
            if let textView = documentView as? NSTextView, let container = textView.textContainer {
                container.widthTracksTextView = true
            }
            // Safety net: if the text system re-layout still reset the offset,
            // re-apply it. The boundsDidChange handler will catch any further
            // resets via pendingRestoreOffset.
            if savedOffset > 0 {
                if contentView.bounds.origin.x == 0 {
                    var bounds = contentView.bounds
                    bounds.origin.x = savedOffset
                    contentView.bounds = bounds
                }
                pendingRestoreOffset = savedOffset
            }
        }
    }
}

// MARK: - Wrapper view: line numbers (left) + scroll view (right)

final class EditorWrapperView: NSView {
    let lineNumberView: LineNumberSideView
    let scrollView: NSScrollView
    let textView: NSTextView
    private var scrollObserver: Any?
    private var textChangeObserver: Any?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        self.lineNumberView = LineNumberSideView(textView: textView)
        super.init(frame: .zero)

        addSubview(lineNumberView)
        addSubview(scrollView)

        // Redraw line numbers on scroll
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.lineNumberView.needsDisplay = true
        }

        // Redraw line numbers on text change
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.lineNumberView.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
        if let o = textChangeObserver { NotificationCenter.default.removeObserver(o) }
    }

    override func layout() {
        super.layout()
        let lineNumberWidth: CGFloat = 30
        lineNumberView.frame = NSRect(x: 0, y: 0, width: lineNumberWidth, height: bounds.height)
        scrollView.frame = NSRect(x: lineNumberWidth, y: 0,
                                  width: bounds.width - lineNumberWidth, height: bounds.height)
    }
}

// MARK: - NSViewRepresentable

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var currentFileURL: URL?
    var viewRefs: ViewRefs?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditorWrapperView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let bg = NSColor.controlBackgroundColor.withAlphaComponent(1.0)
        scrollView.drawsBackground = true
        scrollView.backgroundColor = bg
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        // Build text system
        let textStorage = MarkdownTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = ImageDropTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = CGSize(width: 0, height: 0)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        viewRefs?.textView = textView
        textView.allowsUndo = true
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.textColor = NSColor.textColor
        textView.backgroundColor = bg
        textView.isEditable = true
        textView.isSelectable = true
        textView.enabledTextCheckingTypes = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: 13)
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        var stops: [NSTextTab] = []
        for i in 1..<20 {
            stops.append(NSTextTab(type: .leftTabStopType, location: CGFloat(i * 28)))
        }
        paragraphStyle.tabStops = stops
        textView.defaultParagraphStyle = paragraphStyle

        textView.registerForDraggedTypes([
            .fileURL, .tiff, .png,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.file-url"),
        ])

        textView.onImageDrop = { url in
            context.coordinator.handleImageDrop(url: url)
        }
        textView.onImagePaste = { image in
            context.coordinator.handleImagePaste(image: image)
        }

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        scrollView.documentView = textView

        textView.textContainerInset = NSSize(width: 4, height: 12)

        return EditorWrapperView(textView: textView, scrollView: scrollView)
    }

    func updateNSView(_ wrapper: EditorWrapperView, context: Context) {
        let textView = wrapper.textView
        let scrollView = wrapper.scrollView

        if let storage = textView.textStorage {
            let cleanCurrent = context.coordinator.buildCleanMarkdown(from: storage)
            if cleanCurrent == text {
                context.coordinator.scheduleImageProcessing()
                return
            }
        } else if textView.string == text {
            context.coordinator.scheduleImageProcessing()
            return
        }

        context.coordinator.suppressTextDidChange = true
        let selectedRange = textView.selectedRange()
        textView.string = text
        let safeLocation = min(selectedRange.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        context.coordinator.suppressTextDidChange = false
        context.coordinator.scheduleImageProcessing()
        if text.isEmpty {
            textView.window?.makeFirstResponder(textView)
        }
        // Scroll to top-left when switching documents.
        if context.coordinator.lastFileURL != currentFileURL, !text.isEmpty {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        context.coordinator.lastFileURL = currentFileURL
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        var suppressTextDidChange = false
        /// Tracks the last opened file URL so we can detect document switches.
        var lastFileURL: URL?
        /// Cache of decoded NSImages keyed by URL string. Avoids re-decoding
        /// base64 images on every processInlineImages call (the biggest bottleneck
        /// for files with embedded base64 images).
        private static let imageCache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 50
            cache.totalCostLimit = 100 * 1024 * 1024  // 100 MB
            return cache
        }()

        private static let imageRegex: NSRegularExpression = {
            try! NSRegularExpression(
                pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#,
                options: []
            )
        }()

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }


        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !suppressTextDidChange,
                  let textView = notification.object as? NSTextView else { return }

            // Build clean markdown from attachment attributes WITHOUT mutating
            // the text storage. This avoids the \u{FFFC} → base64 expansion
            // on every keystroke that caused layout reflow and scroll-to-end.
            if let storage = textView.textStorage {
                let cleanText = buildCleanMarkdown(from: storage)
                DispatchQueue.main.async {
                    self.parent.text = cleanText
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.text = textView.string
                }
            }

            scheduleImageProcessing()
        }

        /// Enumerate \u{FFFC} attachment chars and replace them with their
        /// markdown source strings WITHOUT modifying text storage. This is the
        /// non-mutating counterpart of restoreImageAttachmentsToMarkdown.
        func buildCleanMarkdown(from storage: NSTextStorage) -> String {
            let fullRange = NSRange(location: 0, length: storage.length)
            let result = NSMutableString(string: storage.string)
            // Walk in reverse so ranges stay valid after string replacements
            storage.enumerateAttribute(.attachment, in: fullRange, options: .reverse) { value, range, _ in
                if let attachment = value as? MarkdownImageAttachment, !attachment.markdownSource.isEmpty {
                    result.replaceCharacters(in: range, with: attachment.markdownSource)
                }
            }
            return result as String
        }

        // MARK: - Inline Image Processing

        func scheduleImageProcessing() {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processInlineImages), object: nil)
            perform(#selector(processInlineImages), with: nil, afterDelay: 0.2)
        }

        func restoreImageAttachmentsToMarkdown(in textStorage: NSTextStorage) {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: .reverse) { value, range, _ in
                if let attachment = value as? MarkdownImageAttachment, !attachment.markdownSource.isEmpty {
                    textStorage.replaceCharacters(in: range, with: attachment.markdownSource)
                }
            }
        }

        @objc private func processInlineImages() {
            guard let textView = textView,
                  let textStorage = textView.textStorage as? MarkdownTextStorage else { return }

            let text = textStorage.string
            let nsString = text as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)

            let matches = Self.imageRegex.matches(in: text, options: [], range: fullRange)
            guard !matches.isEmpty else { return }

            suppressTextDidChange = true

            // Suppress syntax highlighting during attachment replacements to avoid
            // cascading regex re-highlight on every textStorage mutation.
            textStorage.suppressHighlighting = true

            // Batch all replacements into a single layout pass to prevent the
            // content "jump" caused by sequential text storage mutations.
            textStorage.beginEditing()

            var didReplace = false

            for match in matches.reversed() {
                let fullMatchRange = match.range(at: 0)
                let urlRange = match.range(at: 2)

                guard fullMatchRange.location != NSNotFound,
                      urlRange.location != NSNotFound,
                      urlRange.length > 0 else { continue }

                let urlStr = nsString.substring(with: urlRange)
                let cacheKey = urlStr as NSString

                // Check cache first — avoids re-decoding base64 every time
                if let cached = Self.imageCache.object(forKey: cacheKey) {
                    let attachment = MarkdownImageAttachment()
                    attachment.markdownSource = nsString.substring(with: fullMatchRange)
                    attachment.image = cached
                    attachment.bounds = NSRect(x: 0, y: 0, width: cached.size.width, height: cached.size.height)
                    let attrString = NSAttributedString(attachment: attachment)
                    textStorage.replaceCharacters(in: fullMatchRange, with: attrString)
                    didReplace = true
                    continue
                }

                guard let image = loadImage(from: urlStr) else { continue }

                // Resize for display
                let maxWidth: CGFloat = 400
                let maxHeight: CGFloat = 300
                var size = image.size
                if size.width > maxWidth || size.height > maxHeight {
                    let scale = min(maxWidth / size.width, maxHeight / size.height)
                    size = NSSize(width: size.width * scale, height: size.height * scale)
                }
                if size.width < 20 { size.width = 20 }
                if size.height < 20 { size.height = 20 }

                let displayImage = NSImage(size: size)
                displayImage.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: size),
                           from: NSRect(origin: .zero, size: image.size),
                           operation: .copy, fraction: 1.0)
                displayImage.unlockFocus()

                // Store in cache for next time
                Self.imageCache.setObject(displayImage, forKey: cacheKey, cost: Int(size.width * size.height * 4))

                let attachment = MarkdownImageAttachment()
                attachment.markdownSource = nsString.substring(with: fullMatchRange)
                attachment.image = displayImage
                attachment.bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)

                let attrString = NSAttributedString(attachment: attachment)
                textStorage.replaceCharacters(in: fullMatchRange, with: attrString)
                didReplace = true
            }

            textStorage.endEditing()
            textStorage.suppressHighlighting = false

            if didReplace {
                let updatedRange = NSRange(location: 0, length: textStorage.length)
                for layoutManager in textStorage.layoutManagers {
                    layoutManager.invalidateLayout(forCharacterRange: updatedRange, actualCharacterRange: nil)
                }
            }

            self.suppressTextDidChange = false
        }

        // MARK: - Image Loading

        private func loadImage(from urlStr: String) -> NSImage? {
            if urlStr.hasPrefix("data:image/") {
                guard let commaIdx = urlStr.firstIndex(of: ",") else { return nil }
                let base64Data = String(urlStr[urlStr.index(after: commaIdx)...])
                guard !base64Data.isEmpty,
                      let data = Data(base64Encoded: base64Data, options: .ignoreUnknownCharacters),
                      let image = NSImage(data: data) else { return nil }
                return image
            } else {
                guard let mdURL = parent.currentFileURL else { return nil }
                let resolvedURL: URL
                if urlStr.hasPrefix("/") {
                    resolvedURL = URL(fileURLWithPath: urlStr)
                } else {
                    resolvedURL = mdURL.deletingLastPathComponent().appendingPathComponent(urlStr)
                }
                return NSImage(contentsOf: resolvedURL)
            }
        }

        // Image handling

        func handleImageDrop(url: URL) {
            guard let mdURL = parent.currentFileURL else {
                showMissingFileAlert()
                return
            }
            let result = ImageHandler.handleDroppedFile(url, relativeTo: mdURL)
            insertAtCursor(result)
        }

        func handleImagePaste(image: NSImage) {
            guard let mdURL = parent.currentFileURL else {
                showMissingFileAlert()
                return
            }
            let result = ImageHandler.handlePastedImage(image, relativeTo: mdURL)
            insertAtCursor(result)
        }

        private func insertAtCursor(_ result: ImageHandler.InsertResult) {
            guard result.success else {
                let alert = NSAlert()
                alert.messageText = "Image Insert Failed"
                alert.informativeText = result.errorMessage ?? "Unknown error"
                alert.alertStyle = .warning
                alert.runModal()
                return
            }

            guard let textView = self.textView,
                  let storage = textView.textStorage else { return }

            // Use clean markdown from attachments (not textView.string which
            // has \u{FFFC} after processInlineImages ran) so that subsequent
            // pastes correctly include previous images' markdown syntax.
            let clean = buildCleanMarkdown(from: storage)
            let cursor = textView.selectedRange().location
            let current = clean as NSString

            var insertion = result.markdownSyntax
            if cursor > 0 && current.length > 0 {
                let prevChar = current.substring(with: NSRange(location: cursor - 1, length: 1))
                if prevChar != "\n" {
                    insertion = "\n" + insertion
                }
            }
            if cursor < current.length {
                let nextChar = current.substring(with: NSRange(location: cursor, length: 1))
                if nextChar != "\n" {
                    insertion = insertion + "\n"
                }
            } else {
                insertion = insertion + "\n"
            }

            let newText = (clean as NSString).replacingCharacters(in: NSRange(location: cursor, length: 0), with: insertion)
            let insertEnd = cursor + (insertion as NSString).length

            suppressTextDidChange = true
            textView.string = newText
            // Process immediately so images appear in the same frame.
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.processInlineImages), object: nil)
            processInlineImages()
            textView.setSelectedRange(NSRange(location: insertEnd, length: 0))
            suppressTextDidChange = false

            DispatchQueue.main.async {
                self.parent.text = newText
            }
        }

        private func showMissingFileAlert() {
            let alert = NSAlert()
            alert.messageText = "Cannot Insert Image"
            alert.informativeText = "Please save the current file first (Cmd+S) before inserting images."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
