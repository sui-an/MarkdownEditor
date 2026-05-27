import AppKit
import WebKit

/// Holds weak references to the active editor and preview views.
/// Used by the search panel and other tools that need to access
/// NSTextView/WKWebView directly from SwiftUI.
/// Not @Observable — this is a pure passive holder and never drives UI updates.
final class ViewRefs {
    weak var textView: NSTextView?
    weak var webView: WKWebView?
}
