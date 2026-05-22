import SwiftUI
import AppKit

extension Notification.Name {
    static let toggleEditor = Notification.Name("toggleEditor")
    static let performFindAction = Notification.Name("performFindAction")
}

private func findAction(_ action: NSTextFinder.Action) {
    NotificationCenter.default.post(name: .performFindAction,
                                     object: nil,
                                     userInfo: ["action": action.rawValue])
}

@main
struct MarkdownEditorApp: App {
    @StateObject private var document = DocumentController()

    var body: some Scene {
        WindowGroup {
            MainSplitView(document: document)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    document.newFile()
                }
                .keyboardShortcut("n")

                Divider()

                Button("Open File...") {
                    document.openFile()
                }
                .keyboardShortcut("o")

                Button("Open Folder...") {
                    document.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    document.saveFile(text: lastEditorText)
                }
                .keyboardShortcut("s")

                Button("Save As...") {
                    document.saveFileAs(text: lastEditorText)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Toggle Editor") {
                    NotificationCenter.default.post(name: .toggleEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()
                Button("Find...") {
                    findAction(.showFindInterface)
                }
                .keyboardShortcut("f")

                Button("Find Next") {
                    findAction(.nextMatch)
                }
                .keyboardShortcut("g")

                Button("Find Previous") {
                    findAction(.previousMatch)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}
