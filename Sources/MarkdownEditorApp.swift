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

// MARK: - Dock Drop Support

extension Notification.Name {
    static let openFileURL = Notification.Name("com.MarkdownEditor.openFile")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Pending URL set during cold launch before the SwiftUI scene is ready.
    private(set) var pendingFileURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI's internal delegate intercepts application(_:open:urls:)
        // and crashes during toolbar layout. We remove that handler and
        // install our own for the 'odoc' Apple Event so file-open never
        // reaches SwiftUI's crashy path.
        let coreEventClass = FourCharCode(0x61657674) // 'aevt'
        let aeOpenDocs    = FourCharCode(0x6f646f63) // 'odoc'
        NSAppleEventManager.shared().removeEventHandler(forEventClass: coreEventClass, andEventID: aeOpenDocs)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleODocEvent(_:withReplyEvent:)),
            forEventClass: coreEventClass,
            andEventID: aeOpenDocs
        )
    }

    @objc
    private func handleODocEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let descriptor = event.paramDescriptor(forKeyword: keyDirectObject) else { return }

        var urls: [URL] = []
        if descriptor.descriptorType == typeAEList {
            for i in 1 ... descriptor.numberOfItems {
                if let str = descriptor.atIndex(i)?.stringValue, let url = URL(string: str) {
                    urls.append(url)
                }
            }
        } else if let str = descriptor.stringValue, let url = URL(string: str) {
            urls.append(url)
        }

        for url in urls {
            openAndNotify(url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openAndNotify(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for fname in filenames {
            _ = openAndNotify(URL(fileURLWithPath: fname))
        }
        sender.reply(toOpenOrPrint: .success)
    }

    /// Store the URL and post a notification so any active ContentView can pick it up.
    @discardableResult
    private func openAndNotify(_ url: URL) -> Bool {
        pendingFileURL = url
        // For hot launch: post notification so ContentView.onReceive picks it up.
        // For cold launch: ContentView.onAppear will call consumePendingFileURL().
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openFileURL, object: url)
            // Ensure the app is frontmost – the user expects to see the window.
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// Called by ContentView.onAppear to consume a cold-launch pending URL.
    func consumePendingFileURL() -> URL? {
        let url = pendingFileURL
        pendingFileURL = nil
        return url
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
    @AppStorage("previewOnly") private var previewOnly = false

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
