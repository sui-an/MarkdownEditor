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

// MARK: - App Entry

@main
struct MarkdownEditorApp: App {
    @Environment(\.openWindow) private var openWindow

    init() {
        // Pre-warm WKWebView process on app launch to reduce first-preview latency
        DispatchQueue.main.async {
            WebViewPool.shared.preWarm()
        }
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

            // View menu
            CommandGroup(before: .toolbar) {
                TogglePreviewCommand()
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
