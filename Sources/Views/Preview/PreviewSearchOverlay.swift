import SwiftUI
import AppKit
import WebKit

// MARK: - Unified Search Overlay

struct SearchOverlay: View {
    var webView: (() -> WKWebView?)?
    var textView: (() -> NSTextView?)?
    var viewRefs: ViewRefs?
    var replaceExpanded: Bool = false
    var commandId: Int
    var onClose: (() -> Void)?

    // MARK: Search state
    @State private var query = ""
    @State private var replacement = ""
    @State private var currentMatchIndex = 0
    @State private var totalMatches = 0
    @State private var searchDebounceWork: DispatchWorkItem?
    @State private var isReplaceExpanded = false

    // MARK: Drag state
    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero
    @State private var dragStartLocation = CGPoint.zero
    @State private var dragOffsetOnMouseDown = CGSize.zero
    @State private var eventMonitor: Any?

    private var isEditMode: Bool { textView != nil }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            searchPill
            if isReplaceExpanded { replacePill }
        }
        .frame(width: 420)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .offset(dragOffset)
        .onAppear {
            isReplaceExpanded = replaceExpanded
            dragOffset = .zero
            startDragMonitor()
        }
        .onDisappear { stopDragMonitor() }
        .onChange(of: replaceExpanded) { _, newValue in
            isReplaceExpanded = newValue
        }
        .onExitCommand { close() }
    }

    // MARK: - Pill Views

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .pillIconStyle()

            NativeSearchField(
                text: $query,
                placeholder: isEditMode ? "Search" : "Search preview",
                commandId: commandId,
                onSubmit: {
                    searchDebounceWork?.cancel()
                    totalMatches == 0 ? performSearch() : findNext()
                },
                onChange: { newValue in
                    searchDebounceWork?.cancel()
                    if newValue.isEmpty { performSearch(); return }
                    let work = DispatchWorkItem { [performSearch] in performSearch() }
                    searchDebounceWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
                }
            )
            .frame(height: 18)

            if !query.isEmpty { matchControls }

            PillCloseButton(query: $query, isEmpty: query.isEmpty, onClose: onClose, onSearch: performSearch)
        }
        .pillBackground()
    }

    private var matchControls: some View {
        Group {
            Text(matchLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)

            PillIconButton(
                systemName: "chevron.up",
                size: 10,
                help: nil,
                disabled: totalMatches == 0,
                action: findPrevious
            )

            PillIconButton(
                systemName: "chevron.down",
                size: 10,
                help: nil,
                disabled: totalMatches == 0,
                action: findNext
            )

            PillIconButton(
                systemName: isReplaceExpanded ? "chevron.up" : "chevron.down",
                size: 8,
                help: isReplaceExpanded ? "Hide Replace" : "Show Replace (⌘⌥F)",
                disabled: false,
                action: { withAnimation(.easeInOut(duration: 0.12)) { isReplaceExpanded.toggle() } }
            )
        }
    }

    private var replacePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle")
                .pillIconStyle()

            TextField("Replacement", text: $replacement)
                .textFieldStyle(.plain)
                .font(.system(size: 15))

            Button("Replace") { replaceCurrent() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(totalMatches == 0 || replacement.isEmpty)

            Button("All") { replaceAll() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(totalMatches == 0 || replacement.isEmpty)
        }
        .pillBackground()
    }

    // MARK: - Drag handling

    private func startDragMonitor() {
        stopDragMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [self] event in
            self.handleDragEvent(event)
            return event
        }
    }

    private func stopDragMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let location = event.locationInWindow
        let hitView = contentView.hitTest(location)

        switch event.type {
        case .leftMouseDown:
            if let hitView, isInteractiveView(hitView) { return }
            isDragging = true
            dragStartLocation = location
            dragOffsetOnMouseDown = dragOffset
        case .leftMouseDragged:
            guard isDragging else { return }
            dragOffset = CGSize(
                width: dragOffsetOnMouseDown.width + location.x - dragStartLocation.x,
                height: dragOffsetOnMouseDown.height - (location.y - dragStartLocation.y)
            )
        case .leftMouseUp:
            isDragging = false
        default: break
        }
    }

    private func isInteractiveView(_ view: NSView) -> Bool {
        if view is NSButton || view is NSTextField || view is NSSecureTextField { return true }
        var current = view.superview
        for _ in 0..<6 {
            guard let v = current else { break }
            if v is NSButton || v is NSTextField || v is NSSecureTextField { return true }
            current = v.superview
        }
        return false
    }

    // MARK: - Helpers

    private var matchLabel: String {
        totalMatches > 0 ? "\(currentMatchIndex + 1)/\(totalMatches)" : "0/0"
    }

    // MARK: - Actions

    private func close() {
        viewRefs?.lastSearchQuery = ""
        if isEditMode {
            clearEditorHighlights()
        }
        webView?()?.evaluateJavaScript(SearchJS.clearHighlights())
        onClose?()
    }

    private func performSearch() {
        if isEditMode { performEditorSearch() }
        performPreviewSearch()
    }

    private func findNext() {
        guard totalMatches > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % totalMatches
        if isEditMode { navigateEditorMatch() }
        navigatePreviewIndex()
    }

    private func findPrevious() {
        guard totalMatches > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + totalMatches) % totalMatches
        if isEditMode { navigateEditorMatch() }
        navigatePreviewIndex()
    }

    // MARK: - Editor Search

    private func performEditorSearch() {
        guard let tv = textView?() else { return }
        clearEditorHighlights()
        guard !query.isEmpty else { totalMatches = 0; currentMatchIndex = 0; return }
        let ranges = findEditorMatches(in: tv.string)
        totalMatches = ranges.count
        currentMatchIndex = 0
        applyEditorHighlights(ranges: ranges)
        if let storage = tv.textStorage {
            for lm in storage.layoutManagers { lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length)) }
        }
        if let first = ranges.first { tv.scrollRangeToVisible(first); tv.setSelectedRange(NSRange(location: first.location, length: 0)) }
    }

    private func navigateEditorMatch() {
        guard let tv = textView?(), let storage = tv.textStorage else { return }
        let ranges = findEditorMatches(in: tv.string)
        guard currentMatchIndex < ranges.count else { return }
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
        applyEditorHighlights(ranges: ranges)
        for lm in storage.layoutManagers { lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length)) }
        let range = ranges[currentMatchIndex]
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    private func findEditorMatches(in text: String) -> [NSRange] {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let found = nsText.range(of: query, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            searchRange = NSRange(location: found.location + found.length, length: nsText.length - found.location - found.length)
        }
        return ranges
    }

    private func applyEditorHighlights(ranges: [NSRange]) {
        guard let tv = textView?(), let storage = tv.textStorage else { return }
        for (index, range) in ranges.enumerated() {
            let color = index == currentMatchIndex
                ? NSColor(red: 1.0, green: 0.59, blue: 0.0, alpha: 0.7)
                : NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 0.45)
            storage.addAttribute(.backgroundColor, value: color, range: range)
        }
    }

    private func clearEditorHighlights() {
        guard let tv = textView?(), let storage = tv.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        for lm in storage.layoutManagers { lm.invalidateDisplay(forCharacterRange: fullRange) }
    }

    // MARK: - Editor Replace

    private func replaceCurrent() {
        guard let tv = textView?(), !query.isEmpty else { return }
        let ranges = findEditorMatches(in: tv.string)
        guard currentMatchIndex < ranges.count else { return }
        tv.insertText(replacement as NSString, replacementRange: ranges[currentMatchIndex])
        performSearch()
    }

    private func replaceAll() {
        guard let tv = textView?(), !query.isEmpty else { return }
        let ranges = findEditorMatches(in: tv.string)
        guard !ranges.isEmpty else { return }
        tv.undoManager?.beginUndoGrouping()
        for range in ranges.reversed() {
            tv.insertText(replacement as NSString, replacementRange: range)
        }
        tv.undoManager?.endUndoGrouping()
        performSearch()
    }

    // MARK: - Preview Search

    private func performPreviewSearch() {
        guard let wv = webView?() else { return }
        guard !query.isEmpty else {
            wv.evaluateJavaScript(SearchJS.clearHighlights())
            if !isEditMode { totalMatches = 0; currentMatchIndex = 0 }
            return
        }
        viewRefs?.lastSearchQuery = query
        wv.evaluateJavaScript(SearchJS.highlight(query: query, currentIndex: currentMatchIndex)) { result, error in
            guard error == nil, let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = json["count"] as? Int else { return }
            DispatchQueue.main.async { if !self.isEditMode { self.totalMatches = count } }
        }
    }

    private func navigatePreviewIndex() {
        guard let wv = webView?() else { return }
        wv.evaluateJavaScript(SearchJS.navigateTo(index: currentMatchIndex)) { result, _ in
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = json["count"] as? Int else { return }
            DispatchQueue.main.async { if !self.isEditMode { self.totalMatches = count } }
        }
    }
}

// MARK: - Reusable Pill Components

private extension View {
    func pillBackground() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .overlay(CursorArrowView().allowsHitTesting(false))
    }

    func pillIconStyle() -> some View {
        self
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Pill Icon Button

private struct PillIconButton: View {
    let systemName: String
    let size: CGFloat
    let help: String?
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: size, weight: .medium))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
        .contentShape(Rectangle())
        .iflet(help) { view, text in view.help(text) }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Pill Close Button

private struct PillCloseButton: View {
    @Binding var query: String
    let isEmpty: Bool
    let onClose: (() -> Void)?
    let onSearch: () -> Void

    var body: some View {
        ZStack {
            Button {
                if isEmpty { onClose?(); return }
                query = ""
                onSearch()
            } label: {
                Image(systemName: isEmpty ? "xmark" : "xmark.circle.fill")
                    .font(.system(size: isEmpty ? 11 : 13))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Optional Help Modifier

extension View {
    @ViewBuilder
    fileprivate func iflet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Cursor-tracking overlay that forces arrow cursor

private struct CursorArrowView: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorArrowNSView { CursorArrowNSView() }
    func updateNSView(_ nsView: CursorArrowNSView, context: Context) {}
}

private class CursorArrowNSView: NSView {
    private var cursorPushed = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.options.contains(.cursorUpdate) {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let contentView = window?.contentView else { return }
        let hitView = contentView.hitTest(event.locationInWindow)
        if let hitView, isInteractiveView(hitView) { return }
        if !cursorPushed {
            NSCursor.arrow.push()
            cursorPushed = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    private func isInteractiveView(_ view: NSView) -> Bool {
        if view is NSTextField || view is NSButton { return true }
        var current = view.superview
        for _ in 0..<8 {
            guard let v = current else { break }
            if v is NSTextField || v is NSButton { return true }
            current = v.superview
        }
        return false
    }
}

// MARK: - Native NSTextField wrapper

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let commandId: Int
    let onSubmit: () -> Void
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.placeholderString = placeholder
        tf.font = .systemFont(ofSize: 15, weight: .regular)
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        context.coordinator.field = tf
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        if context.coordinator.lastCommandId != commandId {
            context.coordinator.lastCommandId = commandId
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onChange: onChange)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        let onChange: (String) -> Void
        weak var field: NSTextField?
        var lastCommandId = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onChange: @escaping (String) -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            let newText = (obj.object as? NSTextField)?.stringValue ?? ""
            text = newText
            onChange(newText)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}
