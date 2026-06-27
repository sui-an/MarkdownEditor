import SwiftUI
import UniformTypeIdentifiers

// MARK: - Focused Value Key

struct CurrentAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var currentAppState: AppState? {
        get { self[CurrentAppStateKey.self] }
        set { self[CurrentAppStateKey.self] = newValue }
    }
}

// MARK: - Window Creation

/// Creates all app windows via NSWindow + NSHostingController, bypassing
/// SwiftUI openWindow (which has a known double-window bug on macOS 14.0-14.3).
/// All windows share a single Dock icon and each gets an independent SwiftUI
/// rendering context, so @Observable AppState is properly isolated.
final class WindowManager: NSObject {
    static let shared = WindowManager()
    /// The set of windows managed by WindowManager (exposed for cleanup).
    private(set) var windows: Set<NSWindow> = []
    /// Strong references to per-window AppStates.  Without this, AppState has
    /// no strong reference outside SwiftUI's internal observation system, so
    /// AppDelegate.focusedAppState (weak var) can silently become nil, causing
    /// menu commands and performKeyEquivalent handlers to do nothing.
    private var appStates: [NSWindow: AppState] = [:]
    private let mainWindowFrameKey = "mainWindowFrame"

    func createWindow() {
        // Create a dedicated AppState for this window to guarantee isolation.
        // SwiftUI @State + @Observable can share storage across NSHostingController
        // instances on macOS 14; passing the instance explicitly avoids that.
        let appState = AppState()
        let contentView = ContentView(appState: appState)
        let controller = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: controller)
        window.title = "MarkdownEditor"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Restore saved frame, or center on screen if none exists
        if let savedFrame = UserDefaults.standard.string(forKey: mainWindowFrameKey) {
            let frame = NSRectFromString(savedFrame)
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            if screenFrame.intersects(frame) {
                window.setFrame(frame, display: false)
            } else {
                centerWindowOnScreen(window)
            }
        } else {
            centerWindowOnScreen(window)
        }

        // Strongly associate AppState with window so windowDidBecomeKey can
        // find it safely and focusedAppState (weak) stays non-nil.
        objc_setAssociatedObject(window, &AppDelegate.focusedStateHandle, appState, .OBJC_ASSOCIATION_RETAIN)
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.focusedAppState = appState
        }
        windows.insert(window)
        appStates[window] = appState
        window.makeKeyAndOrderFront(nil)
    }

    func saveMainWindowFrame() {
        guard let window = windows.first else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: mainWindowFrameKey)
    }

    private func centerWindowOnScreen(_ window: NSWindow) {
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Save window frame before closing
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: mainWindowFrameKey)
        // Save dirty file before closing (since selectFile no longer saves
        // on each file switch, this ensures no edit is lost when quitting).
        appStates[window]?.saveCurrentFileIfDirty()
        appStates.removeValue(forKey: window)
        windows.remove(window)
    }
}

// MARK: - File Coordination

private let sessionWindowCreationDelay: TimeInterval = 0.15

/// Holds pending URLs from Finder "Open With" until a window claims them.
/// Uses a batch counter to prevent duplicate window creation when macOS
/// delivers application(_:open:) multiple times for the same event, while
/// still allowing a new window for a genuinely new open event.
final class FileOpenCoordinator {
    static let shared = FileOpenCoordinator()
    private var pendingURLs: [URL] = []
    private var currentBatch = 0
    private let lock = NSLock()

    func addFiles(_ urls: [URL]) -> Bool {
        lock.withLock {
            pendingURLs.append(contentsOf: urls)
            if currentBatch != 0 { return false }
            currentBatch = 1
            return true
        }
    }

    func claimFiles() -> [URL] {
        lock.withLock {
            let files = pendingURLs
            pendingURLs.removeAll()
            currentBatch = 0
            return files
        }
    }
}

/// Distributes session-restore file groups across newly created windows.
final class SessionRestoreCoordinator {
    static let shared = SessionRestoreCoordinator()
    private var windowFileGroups: [[URL]] = []
    private var nextIndex = 0

    func setWindows(_ groups: [[URL]]) {
        windowFileGroups = groups
        nextIndex = 0
    }

    func claimNextFiles() -> [URL] {
        guard nextIndex < windowFileGroups.count else { return [] }
        let files = windowFileGroups[nextIndex]
        nextIndex += 1
        return files
    }

    /// Called after all session windows have been created to prevent stale
    /// file groups from being claimed by user-initiated windows.
    func clear() {
        windowFileGroups = []
        nextIndex = 0
    }
}

/// Tracks all open windows' file lists for session persistence.
final class WindowSessionCoordinator {
    static let shared = WindowSessionCoordinator()
    private var windows: [UUID: [URL]] = [:]

    func register(files: [URL]) -> UUID {
        let id = UUID()
        windows[id] = files
        return id
    }

    func update(id: UUID, files: [URL]) {
        windows[id] = files
    }

    func unregister(_ id: UUID) {
        windows.removeValue(forKey: id)
        persist()
    }

    private func persist() {
        SessionRestoreService.saveWindows(Array(windows.values))
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var didFinishLaunching = false
    /// Tracks the focused window's AppState for menu commands (replaces
    /// @FocusedValue which doesn't work with NSWindow-created views).
    weak var focusedAppState: AppState?
    private var sessionRestoreWork: [DispatchWorkItem] = []
    static var focusedStateHandle: UInt8 = 0

    func application(_ application: NSApplication, open urls: [URL]) {
        cancelSessionRestore()
        SessionRestoreCoordinator.shared.clear()

        if didFinishLaunching {
            let shouldCreate = FileOpenCoordinator.shared.addFiles(urls)
            if shouldCreate {
                WindowManager.shared.createWindow()
            }
            NSApp.activate(ignoringOtherApps: true)
        } else {
            _ = FileOpenCoordinator.shared.addFiles(urls)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Track which window is key so menu commands always target the
        // focused AppState.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        didFinishLaunching = true
        DispatchQueue.global(qos: .utility).async {
            WebViewCache.preloadScripts()
        }

        // Close the WindowGroup ghost window (invisible bootstrap).
        for w in NSApp.windows {
            if !WindowManager.shared.windows.contains(w) {
                w.close()
            }
        }

        // Create all real windows through WindowManager.
        let sessionWindows = SessionRestoreService.restoreWindows()
        if !sessionWindows.isEmpty {
            SessionRestoreCoordinator.shared.setWindows(sessionWindows)
            sessionRestoreWork = []
            for i in 0..<sessionWindows.count {
                let work = DispatchWorkItem {
                    WindowManager.shared.createWindow()
                }
                sessionRestoreWork.append(work)
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Double(i) * sessionWindowCreationDelay,
                    execute: work
                )
            }
        } else {
            WindowManager.shared.createWindow()
        }

        // Remove the system "Show Tab Bar" menu item from View menu.
        // The item may be added asynchronously by SwiftUI, so observe
        // NSMenu.didAddItemNotification to catch it whenever it appears.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
        // Also try once immediately for the common case.
        DispatchQueue.main.async {
            self.removeTabBarMenuItems()
        }
    }

    @objc private func menuDidAddItem(_ notification: Notification) {
        removeTabBarMenuItems()
    }

    private func removeTabBarMenuItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for menuItem in mainMenu.items {
            if menuItem.title == "View" || menuItem.submenu?.title == "View" {
                guard let viewMenu = menuItem.submenu else { continue }
                for (index, item) in viewMenu.items.enumerated().reversed() {
                    if item.title == "Show Tab Bar" || item.title == "Hide Tab Bar" || item.title == "Show All Tabs" {
                        viewMenu.removeItem(at: index)
                    }
                }
                break
            }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let state = objc_getAssociatedObject(window, &AppDelegate.focusedStateHandle) as? AppState {
            focusedAppState = state
        }
    }

    private func cancelSessionRestore() {
        for work in sessionRestoreWork { work.cancel() }
        sessionRestoreWork.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.saveMainWindowFrame()
        SessionRestoreService.clearOpenedFiles()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Dock")
        let item = NSMenuItem(title: "New Window", action: #selector(newWindowFromDock), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func newWindowFromDock() {
        WindowManager.shared.createWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 先尝试恢复已最小化的窗口，符合 Dock 图标点击的常规预期
            if let minimizedWindow = sender.windows.first(where: { $0.isMiniaturized }) {
                minimizedWindow.deminiaturize(nil)
                return true
            }
            let windows = SessionRestoreService.restoreWindows()
            if !windows.isEmpty {
                SessionRestoreCoordinator.shared.setWindows(windows)
                sessionRestoreWork = []
                for i in 0..<windows.count {
                    let work = DispatchWorkItem {
                        WindowManager.shared.createWindow()
                    }
                    sessionRestoreWork.append(work)
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + Double(i) * sessionWindowCreationDelay,
                        execute: work
                    )
                }
            } else {
                // No session — open a single fresh window
                WindowManager.shared.createWindow()
            }
        }
        return true
    }
}

// MARK: - Window Bootstrap

/// Placeholder for the WindowGroup scene.  Invisible and immediately
/// closes itself so the real first window (created by WindowManager)
/// becomes the only visible window.
private struct WindowBootstrapView: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .hidden()
    }
}

// MARK: - App Entry

@main
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WindowBootstrapView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    focusedAppState()?.openNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Window") {
                    WindowManager.shared.createWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                OpenFileCommand()
                OpenFolderCommand()
            }

            CommandGroup(replacing: .saveItem) {
                SaveCommand()
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                FindCommand()
                FindAndReplaceCommand()
            }

            SidebarCommands()

            CommandGroup(before: .toolbar) {
                TogglePreviewCommand()

                Divider()

                FontSizeCommands()

                Divider()

                ThemePickerCommand()
            }
        }
    }
}

// MARK: - Menu Commands

private func focusedAppState() -> AppState? {
    if let window = NSApp.keyWindow,
       let state = objc_getAssociatedObject(window, &AppDelegate.focusedStateHandle) as? AppState {
        return state
    }
    return (NSApp.delegate as? AppDelegate)?.focusedAppState
}

struct OpenFileCommand: View {
    var body: some View {
        Button("Open File...") {
            openFileDialog()
        }
        .keyboardShortcut("o", modifiers: .command)
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        let htmlType = UTType.html
        panel.allowedContentTypes = [mdType, htmlType, UTType.plainText, UTType.text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open File"
        panel.message = "Select a .md or .html file to edit"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let state = focusedAppState()
        DispatchQueue.main.async {
            state?.openFile(url: url)
        }
    }
}

struct OpenFolderCommand: View {
    var body: some View {
        Button("Open Folder...") {
            openFolderDialog()
        }
    }

    private func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Open Folder"
        panel.message = "Select a folder to browse its Markdown files"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let state = focusedAppState()
        DispatchQueue.main.async {
            state?.openFolder(url: url)
        }
    }
}

struct SaveCommand: View {
    var body: some View {
        Button("Save") {
            guard let window = NSApp.keyWindow,
                  let state = objc_getAssociatedObject(window, &AppDelegate.focusedStateHandle) as? AppState
            else { return }
            state.saveCurrentFile()
        }
        .keyboardShortcut("s", modifiers: .command)
    }
}

struct TogglePreviewCommand: View {
    var body: some View {
        let state = focusedAppState()
        Button((state?.previewOnly ?? true) ? "Show Editor" : "Preview Only") {
            focusedAppState()?.previewOnly.toggle()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}

// MARK: - Theme

struct FontSizeCommands: View {
    var body: some View {
        Button("Larger Text") {
            focusedAppState()?.changeFontSize(by: 1)
        }
        .keyboardShortcut("=", modifiers: .command)

        Button("Smaller Text") {
            focusedAppState()?.changeFontSize(by: -1)
        }
        .keyboardShortcut("-", modifiers: .command)

        Button("Reset Text Size") {
            focusedAppState()?.resetFontSize()
        }
    }
}

struct ThemePickerCommand: View {
    @AppStorage("themeMode") private var themeMode: String = "system"

    var body: some View {
        Picker("Appearance", selection: $themeMode) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
    }
}

// MARK: - Find / Replace Commands

struct FindCommand: View {
    var body: some View {
        Button("Find...") {
            focusedAppState()?.openSearch(replaceExpanded: false)
        }
        .keyboardShortcut("f", modifiers: .command)
    }
}

struct FindAndReplaceCommand: View {
    var body: some View {
        Button("Find and Replace...") {
            focusedAppState()?.openSearch(replaceExpanded: true)
        }
        .keyboardShortcut("f", modifiers: [.command, .option])
    }
}