import AppKit
import Foundation
import UniformTypeIdentifiers

enum ImageHandler {

    struct InsertResult {
        let markdownSyntax: String
        let success: Bool
        let errorMessage: String?
    }

    /// Embed dragged-in image file as base64 data URI in markdown.
    /// No external assets folder needed — the .md file is self-contained.
    static func handleDroppedFile(_ fileURL: URL, relativeTo mdFileURL: URL) -> InsertResult {
        guard let utType = UTType(filenameExtension: fileURL.pathExtension.lowercased()),
              utType.conforms(to: .image) else {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Unsupported file type.")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let base64 = data.base64EncodedString()
            let mimeType = utType.preferredMIMEType ?? "image/\(fileURL.pathExtension.lowercased())"
            let alt = fileURL.deletingPathExtension().lastPathComponent
            return InsertResult(
                markdownSyntax: "![\(alt)](data:\(mimeType);base64,\(base64))",
                success: true, errorMessage: nil)
        } catch {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Failed to read image: \(error.localizedDescription)")
        }
    }

    /// Convert pasted NSImage to base64 PNG data URI.
    /// No external assets folder needed — the .md file is self-contained.
    static func handlePastedImage(_ image: NSImage, relativeTo mdFileURL: URL) -> InsertResult {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Failed to convert image to PNG.")
        }

        let base64 = pngData.base64EncodedString()
        return InsertResult(
            markdownSyntax: "![image](data:image/png;base64,\(base64))",
            success: true, errorMessage: nil)
    }

    static let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic"]
}
