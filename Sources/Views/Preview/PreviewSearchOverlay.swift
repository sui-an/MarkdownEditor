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

    @State private var query = ""
    @State private var replacement = ""
    @State private var currentMatchIndex = 0
    @State private var totalMatches = 0
    @State private var searchDebounceWork: DispatchWorkItem?
    @State private var isReplaceExpanded = false

    private var isEditMode: Bool { textView != nil }

    var body: some View {
        VStack(spacing: 6) {
            // Search pill — all controls inside
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)

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

                if !query.isEmpty {
                    Text(matchLabel)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ZStack {
                        Button { findPrevious() } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 20, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(totalMatches == 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    ZStack {
                        Button { findNext() } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 20, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(totalMatches == 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    ZStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) { isReplaceExpanded.toggle() }
                        } label: {
                            Image(systemName: isReplaceExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .medium))
                                .frame(width: 20, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isReplaceExpanded ? "Hide Replace" : "Show Replace (⌘⌥F)")
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }

                ZStack {
                    Button {
                        if query.isEmpty { onClose?(); return }
                        query = ""
                        searchDebounceWork?.cancel()
                        performSearch()
                    } label: {
                        Image(systemName: query.isEmpty ? "xmark" : "xmark.circle.fill")
                            .font(.system(size: query.isEmpty ? 11 : 13))
                            .frame(width: 20, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
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

            // Replace pill (when expanded)
            if isReplaceExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)

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
            }
        }
        .frame(width: 420)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onAppear {
            isReplaceExpanded = replaceExpanded
        }
        .onChange(of: replaceExpanded) { _, newValue in
            isReplaceExpanded = newValue
        }
        .onExitCommand { close() }
    }

    // MARK: - Helpers

    private var matchLabel: String {
        totalMatches > 0 ? "\(currentMatchIndex + 1)/\(totalMatches)" : "0/0"
    }

    // MARK: - Actions

    private func close() {
        if isEditMode {
            clearEditorHighlights()
            webView?()?.evaluateJavaScript(SearchJS.clearHighlights())
        } else {
            viewRefs?.lastSearchQuery = ""
            webView?()?.evaluateJavaScript(SearchJS.clearHighlights())
        }
        onClose?()
    }

    private func performSearch() {
        isEditMode ? performEditorSearch() : nil
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
        guard let tv = textView?(), let storage = tv.textStorage, !query.isEmpty else { return }
        let ranges = findEditorMatches(in: tv.string)
        guard currentMatchIndex < ranges.count else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: ranges[currentMatchIndex], with: replacement)
        storage.endEditing()
        performSearch()
    }

    private func replaceAll() {
        guard let tv = textView?(), let storage = tv.textStorage, !query.isEmpty else { return }
        let ranges = findEditorMatches(in: tv.string)
        guard !ranges.isEmpty else { return }
        storage.beginEditing()
        var offset = 0
        for range in ranges {
            let adjusted = NSRange(location: range.location + offset, length: range.length)
            storage.replaceCharacters(in: adjusted, with: replacement)
            offset += (replacement as NSString).length - range.length
        }
        storage.endEditing()
        performSearch()
    }

    // MARK: - Preview Search

    private func performPreviewSearch() {
        guard let wv = webView?() else { return }
        guard !query.isEmpty else { wv.evaluateJavaScript(SearchJS.clearHighlights()); if !isEditMode { totalMatches = 0; currentMatchIndex = 0 }; return }
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

// MARK: - Native NSTextField wrapper with reliable focus control

struct NativeSearchField: NSViewRepresentable {
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
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if context.coordinator.lastCommandId != commandId {
            context.coordinator.lastCommandId = commandId
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
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
