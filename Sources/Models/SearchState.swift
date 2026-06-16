import Foundation
import Observation
import AppKit

@Observable
final class SearchState {
    var query = ""
    var replacement = ""
    var matches: [NSRange] = []
    var currentMatchIndex = 0
    var isVisible = false {
        didSet {
            if !isVisible, let tv = trackedTextView {
                clearHighlights(textView: tv)
                trackedTextView = nil
            }
        }
    }

    /// Weak reference to the text view being searched, used to clear highlights
    /// when the search panel closes through paths that don't pass a textView.
    private weak var trackedTextView: NSTextView?

    private var content: () -> String

    init(content: @escaping () -> String) {
        self.content = content
    }

    /// Replace the content source closure after init (needed when @Observable
    /// prevents accessing self before stored properties are initialized).
    func setContent(_ newContent: @escaping () -> String) {
        content = newContent
    }

    var currentMatchRange: NSRange? {
        guard !matches.isEmpty, currentMatchIndex < matches.count else { return nil }
        return matches[currentMatchIndex]
    }

    var matchLabel: String {
        guard !matches.isEmpty else { return "0/0" }
        return "\(currentMatchIndex + 1)/\(matches.count)"
    }

    /// Used by refreshHighlights to only update the two affected match ranges
    /// instead of clearing and re-adding all highlights.
    private var previousMatchIndex = -1

    private static let matchNormalColor = NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 0.45)
    private static let matchCurrentColor = NSColor(red: 1.0, green: 0.59, blue: 0.0, alpha: 0.7)

    func findNext(textView: NSTextView?) {
        guard !matches.isEmpty else { return }
        previousMatchIndex = currentMatchIndex
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        refreshHighlights(textView: textView)
    }

    func findPrevious(textView: NSTextView?) {
        guard !matches.isEmpty else { return }
        previousMatchIndex = currentMatchIndex
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        refreshHighlights(textView: textView)
    }

    /// Refresh highlights to reflect the new current match index without
    /// re-running the full search.
    private func refreshHighlights(textView: NSTextView?) {
        guard let storage = textView?.textStorage, !matches.isEmpty else { return }
        if previousMatchIndex >= 0, previousMatchIndex < matches.count {
            let range = matches[previousMatchIndex]
            if range.location + range.length <= storage.length {
                storage.addAttribute(.backgroundColor, value: Self.matchNormalColor, range: range)
                for lm in storage.layoutManagers {
                    lm.invalidateDisplay(forCharacterRange: range)
                }
            }
        }
        if currentMatchIndex >= 0, currentMatchIndex < matches.count {
            let range = matches[currentMatchIndex]
            if range.location + range.length <= storage.length {
                storage.addAttribute(.backgroundColor, value: Self.matchCurrentColor, range: range)
                for lm in storage.layoutManagers {
                    lm.invalidateDisplay(forCharacterRange: range)
                }
            }
        }
    }

    func replace(textView: NSTextView?) {
        guard let range = currentMatchRange, let textView else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        matches = findMatches(in: textView.string, for: query)
        currentMatchIndex = matches.isEmpty ? 0 : min(currentMatchIndex, matches.count - 1)
    }

    func replaceAll(textView: NSTextView?) {
        guard let textView, let storage = textView.textStorage, !query.isEmpty else { return }
        let full = textView.string
        let ranges = findMatches(in: full, for: query)
        storage.beginEditing()
        var offset = 0
        for range in ranges {
            let adjusted = NSRange(location: range.location + offset, length: range.length)
            storage.replaceCharacters(in: adjusted, with: replacement)
            offset += (replacement as NSString).length - range.length
        }
        storage.endEditing()
        // Recalculate matches from final text and apply highlights inline
        // (avoid calling queryDidChange → performSearch which could trigger
        // nested text storage editing notifications)
        matches = findMatches(in: textView.string, for: query)
        currentMatchIndex = matches.isEmpty ? 0 : 0
        previousMatchIndex = -1
        applyHighlights(textView: textView)
    }

    func queryDidChange(textView: NSTextView?) {
        performSearch(textView: textView)
    }

    // MARK: - Search Highlighting

    func clearHighlights(textView: NSTextView?) {
        guard let storage = textView?.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: range)
        for lm in storage.layoutManagers {
            lm.invalidateDisplay(forCharacterRange: range)
        }
    }

    private func applyHighlights(textView: NSTextView?) {
        guard let storage = textView?.textStorage, !matches.isEmpty else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        for (index, range) in matches.enumerated() {
            guard range.location + range.length <= storage.length else { continue }
            storage.addAttribute(.backgroundColor, value: index == currentMatchIndex ? Self.matchCurrentColor : Self.matchNormalColor, range: range)
        }
        for lm in storage.layoutManagers {
            lm.invalidateDisplay(forCharacterRange: fullRange)
        }
    }

    // MARK: - Internal

    private func performSearch(textView: NSTextView?) {
        // Use the provided textView, or fall back to the tracked one.
        // This ensures we always search on the NSTextView's display string
        // (which includes \u{FFFC} image placeholders), NOT on the clean
        // markdown source that may differ in length.
        let effectiveTV = textView ?? trackedTextView
        if let effectiveTV { trackedTextView = effectiveTV }
        let text: String
        if let effectiveTV {
            text = effectiveTV.string
        } else {
            text = content()
        }
        // Clear old highlights before computing new matches
        clearHighlights(textView: effectiveTV)
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
        matches = findMatches(in: text, for: query)
        currentMatchIndex = matches.isEmpty ? 0 : min(currentMatchIndex, matches.count - 1)
        previousMatchIndex = -1
        applyHighlights(textView: effectiveTV)
    }

    private func findMatches(in text: String, for pattern: String) -> [NSRange] {
        guard !pattern.isEmpty else { return [] }
        let nsText = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let found = nsText.range(of: pattern, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: nsText.length - next)
        }
        return ranges
    }
}
