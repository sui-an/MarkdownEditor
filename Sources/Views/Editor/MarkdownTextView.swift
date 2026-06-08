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
    /// Retrieves the AppState associated with this text view's window (set via
    /// objc_setAssociatedObject in WindowManager / ContentView).  More reliable
    /// than AppDelegate.focusedAppState because it doesn't depend on global
    /// weak-reference state.
    private var appState: AppState? {
        guard let window else { return nil }
        return objc_getAssociatedObject(window, &AppDelegate.focusedStateHandle) as? AppState
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        if chars == "f" {
            return false
        }
        if chars == "s" {
            appState?.saveCurrentFile()
            return true
        }
        if chars == "=" {
            appState?.changeFontSize(by: 1)
            return true
        }
        if chars == "-" {
            appState?.changeFontSize(by: -1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Handle File → Save (system menu item).  The system Save at .saveItem
    /// sends saveDocument: to the first responder; our override makes it save
    /// the current file instead of being a no-op (since we don't use NSDocument).
    @objc func saveDocument(_ sender: Any?) {
        appState?.saveCurrentFile()
    }

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
            pendingRestoreOffset = 0
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width

        guard newSize.width > 0 else {
            super.setFrameSize(newSize)
            return
        }

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

// MARK: - Notes-style background color

func notesBackgroundColor(isDark: Bool) -> NSColor {
    isDark
        ? NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        : NSColor(calibratedWhite: 1.0, alpha: 1.0)
}

// MARK: - Wrapper view: line numbers (left) + scroll view (right)

final class EditorWrapperView: NSView {
    let lineNumberView: LineNumberSideView
    let scrollView: NSScrollView
    let textView: NSTextView
    private var scrollObserver: Any?
    private var textChangeObserver: Any?
    private var lastLayoutTime: TimeInterval = 0

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
        let scrollWidth = max(0, bounds.width - lineNumberWidth)
        lineNumberView.frame = NSRect(x: 0, y: 0, width: lineNumberWidth, height: bounds.height)
        scrollView.frame = NSRect(x: lineNumberWidth, y: 0,
                                  width: scrollWidth, height: bounds.height)
        guard scrollWidth > 0 else { return }

        let now = CACurrentMediaTime()
        let interval = now - lastLayoutTime
        lastLayoutTime = now
        if let tc = textView.textContainer, interval > 0, interval < 0.08 {
            tc.widthTracksTextView = false
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(restoreTrack), object: nil)
            perform(#selector(restoreTrack), with: nil, afterDelay: 0.25)
        }
    }

    @objc private func restoreTrack() {
        textView.textContainer?.widthTracksTextView = true
        needsLayout = true
    }
}

// MARK: - NSViewRepresentable

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var currentFileURL: URL?
    var viewRefs: ViewRefs?
    var themeMode: String = "system"
    var fontSize: CGFloat = 13
    var onFontSizeChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func dismantleNSView(_ wrapper: EditorWrapperView, coordinator: Coordinator) {
        coordinator.editorWrapper = nil
    }

    func makeNSView(context: Context) -> EditorWrapperView {
        let scrollView = EditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = notesBackgroundColor(isDark: ThemeManager.isDark(for: themeMode))
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
        textView.drawsBackground = true
        textView.backgroundColor = notesBackgroundColor(isDark: ThemeManager.isDark(for: themeMode))
        textView.isEditable = true
        textView.isSelectable = true
        textView.enabledTextCheckingTypes = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.defaultTabInterval = 28
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
        context.coordinator.setupScrollMonitor()
        scrollView.documentView = textView

        textView.textContainerInset = NSSize(width: 0, height: 12)

        let wrapper = EditorWrapperView(textView: textView, scrollView: scrollView)
        context.coordinator.editorWrapper = wrapper
        return wrapper
    }

    func updateNSView(_ wrapper: EditorWrapperView, context: Context) {
        let textView = wrapper.textView
        let scrollView = wrapper.scrollView
        let coordinator = context.coordinator
        coordinator.parent = self

        let isDark = ThemeManager.isDark(for: themeMode)

        if coordinator.lastAppliedIsDark != isDark {
            coordinator.lastAppliedIsDark = isDark
            ThemeManager.applyTheme(textView: textView, scrollView: scrollView, lineNumberView: wrapper.lineNumberView, isDark: isDark)
        } else {
            textView.textColor = isDark
                ? NSColor(calibratedWhite: 0.92, alpha: 1.0)
                : NSColor(calibratedWhite: 0.08, alpha: 1.0)
        }

        if fontSize != coordinator.lastAppliedFontSize {
            coordinator.lastAppliedFontSize = fontSize
            wrapper.lineNumberView.fontSize = max(8, fontSize - 3)
            textView.font = NSFont.systemFont(ofSize: fontSize)
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: NSRange(location: 0, length: storage.length))
            }
        }

        let isFileSwitch = coordinator.lastFileURL != currentFileURL

        if !isFileSwitch {
            if textView.string == text {
                coordinator.scheduleImageProcessing()
                return
            }
            if let storage = textView.textStorage {
                let cleanCurrent = Coordinator.buildCleanMarkdown(from: storage)
                if cleanCurrent == text {
                    coordinator.scheduleImageProcessing()
                    return
                }
            }
        } else if textView.string == text {
            // Cache hit on file switch — content identical, no replacement needed.
            coordinator.lastFileURL = currentFileURL
            coordinator.scheduleImageProcessing()
            wrapper.lineNumberView.needsDisplay = true
            return
        }

        coordinator.hasInlineImages = text.contains("![")
        coordinator.suppressTextDidChange = true
        let selectedRange = textView.selectedRange()
        textView.string = text
        let safeLocation = min(selectedRange.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        coordinator.suppressTextDidChange = false
        coordinator.scheduleImageProcessing()
        if text.isEmpty {
            textView.window?.makeFirstResponder(textView)
        }
        if isFileSwitch {
            textView.undoManager?.removeAllActions()
            if !text.isEmpty {
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        coordinator.lastFileURL = currentFileURL
        wrapper.lineNumberView.needsDisplay = true
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        weak var editorWrapper: EditorWrapperView?
        var suppressTextDidChange = false
        /// Tracks the last opened file URL so we can detect document switches.
        var lastFileURL: URL?
        /// Cached flag: does the current file contain `![` (inline image syntax)?
        /// Avoids O(n) string scan on every keystroke for files without images.
        var hasInlineImages = false
        /// Tracks the last applied isDark value to deduplicate theme application.
        var lastAppliedIsDark: Bool?
        private var scrollMonitor: Any?
        private var accumulatedScrollDelta: CGFloat = 0
        /// Tracks the last applied font size to avoid redundant updateNSView re-application.
        var lastAppliedFontSize: CGFloat = 0
        private var themeObserver: Any?
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
            super.init()
            themeObserver = NotificationCenter.default.addObserver(
                forName: .themeDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                 guard let self,
                      let textView = self.textView,
                       let wrapper = self.editorWrapper else { return }
                let scrollView = wrapper.scrollView
                let isDark = (notification.userInfo?["isDark"] as? Bool) ?? false
                guard lastAppliedIsDark != isDark else { return }
                lastAppliedIsDark = isDark
                ThemeManager.applyTheme(textView: textView, scrollView: scrollView, lineNumberView: wrapper.lineNumberView, isDark: isDark)
            }
        }

        func setupScrollMonitor() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                if !event.modifierFlags.contains(.command) {
                    accumulatedScrollDelta = 0
                    return event
                }
                // Normalize scroll direction: trackpad (hasPreciseScrollingDeltas)
                // and mouse wheel report opposite deltaY signs for "scroll up".
                let delta = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY
                    : -event.scrollingDeltaY
                accumulatedScrollDelta += delta
                if abs(accumulatedScrollDelta) >= 0.5 {
                    parent.onFontSizeChange?(accumulatedScrollDelta < 0 ? 1 : -1)
                    accumulatedScrollDelta = 0
                }
                return nil
            }
        }

        deinit {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let observer = themeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }


        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !suppressTextDidChange,
                  let textView = notification.object as? NSTextView else { return }

            // Build clean markdown from attachment attributes WITHOUT mutating
            // the text storage. This avoids the \u{FFFC} → base64 expansion
            // on every keystroke that caused layout reflow and scroll-to-end.
            if let storage = textView.textStorage {
                let cleanText = Self.buildCleanMarkdown(from: storage)
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

        static func buildCleanMarkdown(from storage: NSTextStorage) -> String {
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
            guard hasInlineImages else { return }
            // Capture the current file URL so processInlineImages can verify
            // it hasn't changed when the delayed callback fires.
            pendingImageProcessingURL = parent.currentFileURL
            perform(#selector(processInlineImages), with: nil, afterDelay: 0.2)
        }

        private var pendingImageProcessingURL: URL?

        @objc private func processInlineImages() {
            guard let textView = textView,
                  let textStorage = textView.textStorage as? MarkdownTextStorage,
                  parent.currentFileURL == pendingImageProcessingURL else { return }

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

                let displayImage = NSImage(size: size, flipped: false) { _ in
                    image.draw(in: NSRect(origin: .zero, size: size),
                               from: NSRect(origin: .zero, size: image.size),
                               operation: .copy, fraction: 1.0)
                    return true
                }

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
            let clean = Self.buildCleanMarkdown(from: storage)
            let storageCursor = textView.selectedRange().location
            let current = clean as NSString

            // Map cursor from storage coordinates to clean-markdown coordinates.
            // Each \u{FFFC} attachment char (1 byte) expands to a full
            // markdown string in `clean`, so we add the expansion delta for
            // every attachment that lies before the cursor.
            var cleanCursor = storageCursor
            if storageCursor > 0, storage.length > 0 {
                let enumerateRange = NSRange(location: 0, length: min(storageCursor, storage.length))
                storage.enumerateAttribute(.attachment, in: enumerateRange, options: []) { value, range, _ in
                    if let att = value as? MarkdownImageAttachment {
                        let expansion = (att.markdownSource as NSString).length - range.length
                        if expansion > 0 { cleanCursor += expansion }
                    }
                }
            }

            var insertion = result.markdownSyntax
            if cleanCursor > 0 && current.length > 0 {
                let prevChar = current.substring(with: NSRange(location: cleanCursor - 1, length: 1))
                if prevChar != "\n" {
                    insertion = "\n" + insertion
                }
            }
            if cleanCursor < current.length {
                let nextChar = current.substring(with: NSRange(location: cleanCursor, length: 1))
                if nextChar != "\n" {
                    insertion = insertion + "\n"
                }
            } else {
                insertion = insertion + "\n"
            }

            let newText = current.replacingCharacters(in: NSRange(location: cleanCursor, length: 0), with: insertion)

            // Register undo so Cmd+Z can revert the paste.
            let oldText = clean
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.suppressTextDidChange = true
                target.textView?.string = oldText
                target.suppressTextDidChange = false
                DispatchQueue.main.async {
                    target.parent.text = oldText
                }
            }

            suppressTextDidChange = true
            textView.string = newText
            // Process immediately so images appear in the same frame.
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.processInlineImages), object: nil)
            processInlineImages()
            // After processing, images are \u{FFFC} — set cursor to end of storage.
            if let storage = textView.textStorage {
                textView.setSelectedRange(NSRange(location: storage.length, length: 0))
            }
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
