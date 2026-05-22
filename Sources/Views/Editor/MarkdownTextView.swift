import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        let textStorage = NSTextStorage()
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
        textView.isRichText = false
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

        if textView.string != text {
            context.coordinator.suppressTextDidChange = true
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            context.coordinator.suppressTextDidChange = false
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        var suppressTextDidChange = false
        var scrollObserver: Any?
        var textChangeObserver: Any?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        deinit {
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = textChangeObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func textDidChange(_ notification: Notification) {
            guard !suppressTextDidChange,
                  let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
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

            textView.string = newText
            textView.setSelectedRange(NSRange(location: insertEnd, length: 0))
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
