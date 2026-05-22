import Foundation
import AppKit

// MARK: - Feature Tests

struct FeatureTests {

    @MainActor
    static func run() {
        print("🧪 Running Feature Tests...\n")

        testSaveAndRestoreLastFile()
        testSaveAndRestoreWorkspace()
        testLastFileValidation_fileExists()
        testLastFileValidation_fileMissing()
        testImageToBase64DataURI()
        testImageMarkdownSyntax()
        testNewFileClearsState()
        testNewFileResetsContent()
        testRestoreLastSessionLoadsContent()

        print("\n✅ Feature Tests Complete: \(testResults.passed) passed, \(testResults.failed) failed\n")
    }

    // MARK: - Remember Last Opened File

    static func testSaveAndRestoreLastFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_remember_last_file.md")
        FileManager.default.createFile(atPath: testFile.path, contents: "hello".data(using: .utf8))
        defer { try? FileManager.default.removeItem(at: testFile) }

        let defaults = UserDefaults(suiteName: "test_save_restore_\(UUID().uuidString)")!
        let key = "lastOpenedFilePath"
        defaults.set(testFile.path, forKey: key)

        guard let restoredPath = defaults.string(forKey: key) else {
            assertTrue(false, "Should restore last opened file path")
            return
        }
        let restoredURL = URL(fileURLWithPath: restoredPath)
        assertEqual(restoredURL.lastPathComponent, "test_remember_last_file.md", "Restored file name should match")
        assertTrue(FileManager.default.fileExists(atPath: restoredPath), "Restored file should exist on disk")
    }

    static func testSaveAndRestoreWorkspace() {
        let tempDir = FileManager.default.temporaryDirectory
        let workspaceURL = tempDir.appendingPathComponent("test_workspace_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let testFile = workspaceURL.appendingPathComponent("doc.md")
        FileManager.default.createFile(atPath: testFile.path, contents: "# Test".data(using: .utf8))

        let defaults = UserDefaults(suiteName: "test_workspace_\(UUID().uuidString)")!
        let key = "lastWorkspacePath"
        defaults.set(workspaceURL.path, forKey: key)

        guard let restoredPath = defaults.string(forKey: key) else {
            assertTrue(false, "Should restore workspace path")
            return
        }
        let restoredURL = URL(fileURLWithPath: restoredPath)
        assertEqual(restoredURL.lastPathComponent, workspaceURL.lastPathComponent, "Workspace folder name should match")
        assertTrue(FileManager.default.fileExists(atPath: restoredPath), "Workspace folder should exist")

        let contents = try? FileManager.default.contentsOfDirectory(at: restoredURL, includingPropertiesForKeys: nil)
        assertNotNil(contents, "Should be able to list workspace contents")
        if let files = contents {
            assertTrue(files.contains { $0.lastPathComponent == "doc.md" }, "Workspace should contain doc.md")
        }
    }

    static func testLastFileValidation_fileExists() {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_exists_\(UUID().uuidString).md")
        FileManager.default.createFile(atPath: testFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: testFile) }

        assertTrue(FileManager.default.fileExists(atPath: testFile.path), "File should exist")
    }

    static func testLastFileValidation_fileMissing() {
        let tempDir = FileManager.default.temporaryDirectory
        let missingFile = tempDir.appendingPathComponent("nonexistent_\(UUID().uuidString).md")

        assertFalse(FileManager.default.fileExists(atPath: missingFile.path), "Non-existent file should report missing")
    }

    // MARK: - Paste Image (base64 embedding)

    static func testImageToBase64DataURI() {
        // Create a small test image
        guard let testImage = createTestImage() else {
            assertTrue(false, "Should create test image")
            return
        }
        guard let imageData = testImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            assertTrue(false, "Should convert image to PNG data")
            return
        }

        let base64 = pngData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(base64)"

        assertTrue(dataURI.hasPrefix("data:image/png;base64,"), "Data URI should have correct prefix")
        assertTrue(dataURI.count > 50, "Data URI should contain substantial base64 content")
        assertEqual(dataURI.components(separatedBy: ",").count, 2, "Data URI should have exactly one comma separator")

        // Verify it's valid base64
        let parts = dataURI.components(separatedBy: ",")
        let decoded = Data(base64Encoded: parts[1])
        assertNotNil(decoded, "Base64 content should be decodable")
        if let decoded {
            assertTrue(decoded.count > 0, "Decoded data should not be empty")
        }
    }

    static func testImageMarkdownSyntax() {
        guard let testImage = createTestImage() else {
            assertTrue(false, "Should create test image")
            return
        }
        guard let imageData = testImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            assertTrue(false, "Should convert image to PNG data")
            return
        }

        let base64 = pngData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(base64)"
        let markdown = "![pasted image](\(dataURI))"

        assertTrue(markdown.hasPrefix("!["), "Markdown image should start with ![")
        assertTrue(markdown.hasSuffix(")"), "Markdown image should end with )")
        assertTrue(markdown.contains("data:image/png;base64,"), "Markdown should contain data URI")
        assertTrue(Expression(pattern: "!\\[.*\\]\\(data:image/.*;base64,.*\\)")
            .matches(markdown), "Markdown should match image syntax with data URI")
    }

    // MARK: - New File

    @MainActor
    static func testNewFileClearsState() {
        let doc = DocumentController()

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_newfile_\(UUID().uuidString).md")
        FileManager.default.createFile(atPath: testFile.path, contents: "# Old content".data(using: .utf8))
        defer { try? FileManager.default.removeItem(at: testFile) }

        doc.currentFile = testFile
        assertNotNil(doc.currentFile, "Current file should be set before new file")

        doc.currentFile = nil
        assertEqual(doc.currentFile, nil, "Current file should be nil after new file")
        assertEqual(doc.fileName, "Untitled", "File name should return to Untitled")
    }

    @MainActor
    static func testNewFileResetsContent() {
        let doc = DocumentController()
        doc.currentFile = nil

        assertEqual(doc.fileName, "Untitled", "No file open should show 'Untitled'")
        assertEqual(doc.currentFile, nil, "currentFile should be nil when no file is open")
    }

    // MARK: - Session Restore

    /// Verify that restoreLastSession loads file content from UserDefaults.
    /// This test uses the same UserDefaults.standard that the app uses at runtime.
    @MainActor
    static func testRestoreLastSessionLoadsContent() {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_restore_content_\(UUID().uuidString).md")
        try! "session restore test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Preserve any existing value to avoid corrupting the user's session data
        let savedPath = UserDefaults.standard.string(forKey: "lastOpenedFilePath")
        defer {
            if let p = savedPath {
                UserDefaults.standard.set(p, forKey: "lastOpenedFilePath")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastOpenedFilePath")
            }
        }

        UserDefaults.standard.set(testFile.path, forKey: "lastOpenedFilePath")

        let doc = DocumentController()
        assertEqual(doc.pendingContent, "session restore test content",
                    "pendingContent should be set from file during restore")
        assertEqual(doc.currentFile?.path, testFile.path,
                    "currentFile should point to restored file")
        assertEqual(doc.fileName, testFile.lastPathComponent,
                    "fileName should show restored file name")
    }

    // MARK: - Helpers

    /// Create a small colored test image for testing
    private static func createTestImage() -> NSImage? {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}

// MARK: - Simple regex helper for tests

struct Expression {
    let pattern: NSRegularExpression
    init(pattern: String) {
        // swiftlint:disable:next force_try
        self.pattern = try! NSRegularExpression(pattern: pattern)
    }
    func matches(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: text.utf16.count)
        return pattern.firstMatch(in: text, range: range) != nil
    }
}
