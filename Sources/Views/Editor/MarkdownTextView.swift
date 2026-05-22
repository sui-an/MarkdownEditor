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

// MARK: - NSViewRepresentable

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var currentFileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
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
        textView.allowsUndo = true
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.controlBackgroundColor
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

        // Line number ruler
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true

        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { _ in
            ruler.needsDisplay = true
        }

        context.coordinator.textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { _ in
            ruler.needsDisplay = true
        }

        // Text inset — only horizontal padding, no top gap
        textView.textContainerInset = NSSize(width: 8, height: 0)

        // Disable automatic content insets so text exits cleanly at top
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Restore any image attachments to markdown before comparing text.
        // Otherwise textView.string (with attachment placeholder chars) will
        // never match the binding's clean markdown, causing attachment loss
        // every time SwiftUI re-renders the view.
        context.coordinator.suppressTextDidChange = true
        if let storage = textView.textStorage {
            context.coordinator.restoreBase64AttachmentsToMarkdown(in: storage)
        }
        let currentRaw = textView.string
        context.coordinator.suppressTextDidChange = false

        if currentRaw != text {
            context.coordinator.suppressTextDidChange = true
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            context.coordinator.suppressTextDidChange = false
            context.coordinator.scheduleBase64Processing()
        } else {
            // Text matches — just make sure base64 images are rendered
            // (may have been cleared by a previous updateNSView pass)
            context.coordinator.scheduleBase64Processing()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        var suppressTextDidChange = false
        var scrollObserver: Any?
        var textChangeObserver: Any?

        private static let base64ImageRegex: NSRegularExpression = {
            try! NSRegularExpression(
                pattern: #"!\[([^\]]*)\]\(data:image\/[^;]+;base64,([^)\s]+)\)"#,
                options: []
            )
        }()

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        deinit {
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = textChangeObserver { NotificationCenter.default.removeObserver(obs) }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !suppressTextDidChange,
                  let textView = notification.object as? NSTextView else { return }

            // Restore any image attachments back to markdown source so
            // the SwiftUI binding receives clean text (not attachment placeholder chars)
            if let storage = textView.textStorage {
                suppressTextDidChange = true
                restoreBase64AttachmentsToMarkdown(in: storage)
                suppressTextDidChange = false
            }

            DispatchQueue.main.async {
                self.parent.text = textView.string
            }

            scheduleBase64Processing()
        }

        // MARK: - Base64 Image Processing

        func scheduleBase64Processing() {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processBase64Images), object: nil)
            perform(#selector(processBase64Images), with: nil, afterDelay: 0.2)
        }

        func restoreBase64AttachmentsToMarkdown(in textStorage: NSTextStorage) {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: .reverse) { value, range, _ in
                if let attachment = value as? MarkdownImageAttachment, !attachment.markdownSource.isEmpty {
                    textStorage.replaceCharacters(in: range, with: attachment.markdownSource)
                }
            }
        }

        @objc private func processBase64Images() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let text = textStorage.string
            let nsString = text as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)

            let matches = Self.base64ImageRegex.matches(in: text, options: [], range: fullRange)
            guard !matches.isEmpty else { return }

            suppressTextDidChange = true
            defer {
                DispatchQueue.main.async {
                    self.suppressTextDidChange = false
                }
            }

            for match in matches.reversed() {
                let fullMatchRange = match.range(at: 0)
                let base64Range = match.range(at: 2)

                guard fullMatchRange.location != NSNotFound,
                      base64Range.location != NSNotFound,
                      base64Range.length > 0 else { continue }

                let base64String = nsString.substring(with: base64Range)
                guard let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
                      let image = NSImage(data: imageData) else { continue }

                let attachment = MarkdownImageAttachment()
                attachment.markdownSource = nsString.substring(with: fullMatchRange)

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

                attachment.image = displayImage
                attachment.bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)

                let attrString = NSAttributedString(attachment: attachment)
                textStorage.replaceCharacters(in: fullMatchRange, with: attrString)
            }

            // Invalidate layout so attachments appear
            let updatedRange = NSRange(location: 0, length: textStorage.length)
            for layoutManager in textStorage.layoutManagers {
                layoutManager.invalidateLayout(forCharacterRange: updatedRange, actualCharacterRange: nil)
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

            guard let textView = self.textView else { return }

            let cursor = textView.selectedRange().location
            let current = textView.string as NSString

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

            let updated = current as String
            let newText = (updated as NSString).replacingCharacters(in: NSRange(location: cursor, length: 0), with: insertion)
            let insertEnd = cursor + (insertion as NSString).length

            suppressTextDidChange = true
            textView.string = newText
            textView.setSelectedRange(NSRange(location: insertEnd, length: 0))
            suppressTextDidChange = false
            DispatchQueue.main.async {
                self.parent.text = newText
                self.scheduleBase64Processing()
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
