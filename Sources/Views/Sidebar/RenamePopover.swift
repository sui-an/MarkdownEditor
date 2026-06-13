import SwiftUI

struct RenamePopover: View {
    let currentName: String
    let isDirectory: Bool
    let parentDirectoryURL: URL
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var newName: String = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isDirectory ? "Rename Folder" : "Rename File")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { confirm() }
                .onExitCommand { onCancel() }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.isEmpty || newName == currentName)
            }
        }
        .padding(10)
        .frame(width: max(200, min(CGFloat(currentName.count) * 8 + 60, 360)))
        .onAppear {
            newName = currentName
            isFocused = true
        }
    }

    private func confirm() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Name cannot be empty"
            return
        }
        guard !trimmed.contains("/") && !trimmed.contains(":") else {
            errorMessage = "Name contains invalid characters"
            return
        }
        guard trimmed != currentName else { return }

        let newURL = parentDirectoryURL.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: newURL.path) {
            errorMessage = "An item with this name already exists"
            return
        }

        onConfirm(trimmed)
    }
}
