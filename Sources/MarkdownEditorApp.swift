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

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Called by NSApplication when files are opened via Finder (Open With,
    /// drag to dock icon, double-click file, etc.).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppState.shared.openFile(url: url)
        }
        // Wait for the SwiftUI window to be created before activating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-cache JS resources on background queue so first WKWebView
        // creation doesn't read 3.2MB mermaid.min.js on the main thread.
        DispatchQueue.global(qos: .utility).async {
            WebViewCache.preloadScripts()
        }

        let urls = SessionRestoreService.restoreOpenedFiles()
        if !urls.isEmpty {
            DispatchQueue.main.async {
                for url in urls {
                    AppState.shared.openFile(url: url)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Dock → Quit: the app truly terminates, so clear all saved files.
        // The user wants a fresh start next time.
        SessionRestoreService.clearOpenedFiles()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let urls = SessionRestoreService.restoreOpenedFiles()
            for url in urls {
                AppState.shared.openFile(url: url)
            }
        }
        return true
    }
}

// MARK: - App Entry

@main
struct MarkdownEditorApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
    }

    var body: some Scene {
        WindowGroup(id: "Main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Window") {
                    openWindow(id: "Main")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                OpenFileCommand()
                OpenFolderCommand()
            }

            CommandGroup(after: .saveItem) {
                SaveCommand()
            }

            SidebarCommands()

            // View menu
            CommandGroup(before: .toolbar) {
                TogglePreviewCommand()

                Divider()

                ThemePickerCommand()
            }
        }
    }
}

// MARK: - Menu Commands

struct OpenFileCommand: View {
    @FocusedValue(\.currentAppState) var appState

    var body: some View {
        Button("Open File...") {
            openFileDialog()
        }
        .keyboardShortcut("o", modifiers: .command)
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText, UTType.text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Markdown File"
        panel.message = "Select a .md file to edit"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let state = appState
        DispatchQueue.main.async {
            state?.openFile(url: url)
        }
    }
}

struct OpenFolderCommand: View {
    @FocusedValue(\.currentAppState) var appState

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
        let state = appState
        DispatchQueue.main.async {
            state?.openFolder(url: url)
        }
    }
}

struct SaveCommand: View {
    @FocusedValue(\.currentAppState) var appState

    var body: some View {
        Button("Save") {
            appState?.saveCurrentFile()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(appState?.currentFileURL == nil)
    }
}

struct TogglePreviewCommand: View {
    @AppStorage("previewOnly") private var previewOnly = true

    var body: some View {
        Button("Preview Only") {
            previewOnly.toggle()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}

// MARK: - Theme

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
