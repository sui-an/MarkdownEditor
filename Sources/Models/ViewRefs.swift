import AppKit
import Observation
import WebKit

/// Holds weak references to the active editor and preview views.
/// Used by the search panel and other tools that need to access
/// NSTextView/WKWebView directly from SwiftUI.
@Observable
final class ViewRefs {
    weak var textView: NSTextView?
    weak var webView: WKWebView?
}
