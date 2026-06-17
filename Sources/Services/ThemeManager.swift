import AppKit
import Observation

/// Posted when the effective appearance changes.  `NSApp.appearance` is already
/// set before this fires, so dynamic `NSColor` resolution (`.textColor`,
/// `.controlBackgroundColor`, etc.) is correct at observation time.
extension Notification.Name {
    static let themeDidChange = Notification.Name("com.MarkdownEditor.themeDidChange")
}

/// Single source of truth for the app's light/dark appearance.
///
/// - Reads the user's preference from ``UserDefaults`` key `"themeMode"`
///   (`"system"`, `"light"`, `"dark"`).
/// - Exposes the computed `isDark` flag so views can adjust without duplicating
///   the "system → AppleInterfaceStyle" fallback logic.
/// - Applies `NSApp.appearance` to the entire app and posts ``themeDidChange``
///   so `NSViewRepresentable` coordinators (and any other observer) can refresh
///   appearance-sensitive state.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    /// `true` when the effective appearance is dark.
    private(set) var isDark: Bool = false

    /// Tracks the last-known theme-mode string so callers outside SwiftUI
    /// (e.g. `NSViewRepresentable.updateNSView`) can cheaply detect changes.
    private(set) var lastThemeMode: String = "system"

    private var systemObserver: Any?

    private init() {
        lastThemeMode = UserDefaults.standard.string(forKey: "themeMode") ?? "system"
        isDark = Self.isDark(for: lastThemeMode)

        // Watch for system-level appearance changes while in "system" mode.
        systemObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let mode = UserDefaults.standard.string(forKey: "themeMode") ?? "system"
            guard mode == "system" else { return }
            self.lastThemeMode = mode
            self.isDark = Self.isDark(for: mode)
            NotificationCenter.default.post(name: .themeDidChange, object: nil, userInfo: ["isDark": self.isDark])
        }
    }

    deinit {
        if let observer = systemObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
        }
    }

    /// Apply the current ``UserDefaults`` preference to the whole app.
    ///
    /// Sets `NSApp.appearance`, propagates the appearance to every open window
    /// (so floating panels follow suit), and posts ``themeDidChange``.
    func applyCurrentTheme() {
        let mode = UserDefaults.standard.string(forKey: "themeMode") ?? "system"
        lastThemeMode = mode
        isDark = Self.isDark(for: mode)

        let appearance: NSAppearance?
        switch mode {
        case "dark":  appearance = NSAppearance(named: .darkAqua)
        case "light": appearance = NSAppearance(named: .aqua)
        default:      appearance = nil
        }
        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
        }

        NotificationCenter.default.post(name: .themeDidChange, object: nil, userInfo: ["isDark": isDark])
    }

    /// Synchronously compute the effective dark state for a given mode string
    /// without going through the instance — useful during SwiftUI body evaluation
    /// when ``isDark`` may not have been updated yet.
    static func isDark(for mode: String) -> Bool {
        switch mode {
        case "dark":  return true
        case "light": return false
        default:      return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }

    static func applyTheme(textView: NSTextView, scrollView: NSScrollView, lineNumberView: LineNumberSideView, isDark: Bool) {
        scrollView.backgroundColor = notesBackgroundColor(isDark: isDark)
        textView.drawsBackground = true
        textView.backgroundColor = notesBackgroundColor(isDark: isDark)
        textView.textColor = isDark
            ? NSColor(calibratedWhite: 0.92, alpha: 1.0)
            : NSColor(calibratedWhite: 0.08, alpha: 1.0)
        textView.insertionPointColor = isDark
            ? NSColor(calibratedWhite: 0.92, alpha: 1.0)
            : NSColor(calibratedWhite: 0.08, alpha: 1.0)
        lineNumberView.isDark = isDark
        lineNumberView.needsDisplay = true
        scrollView.needsDisplay = true
        textView.needsDisplay = true
        if let storage = textView.textStorage as? MarkdownTextStorage {
            storage.rehighlightAll(isDark: isDark)
        }
    }

}
