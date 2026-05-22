import AppKit
import Foundation
import UniformTypeIdentifiers

enum ImageHandler {

    struct InsertResult {
        let markdownSyntax: String
        let success: Bool
        let errorMessage: String?
    }

    static func handleDroppedFile(_ fileURL: URL, relativeTo mdFileURL: URL) -> InsertResult {
        guard let utType = UTType(filenameExtension: fileURL.pathExtension.lowercased()),
              utType.conforms(to: .image) else {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Unsupported file type.")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let ext = preferredExtension(for: fileURL.pathExtension)
            let savedURL = try FileService.saveImage(data, extension: ext, relativeTo: mdFileURL)
            let relPath = FileService.relativePath(from: mdFileURL, to: savedURL)
            let alt = fileURL.deletingPathExtension().lastPathComponent
            return InsertResult(markdownSyntax: "![\(alt)](\(relPath))", success: true, errorMessage: nil)
        } catch {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Failed to save image: \(error.localizedDescription)")
        }
    }

    static func handlePastedImage(_ image: NSImage, relativeTo mdFileURL: URL) -> InsertResult {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Failed to convert image to PNG.")
        }

        do {
            let savedURL = try FileService.saveImage(pngData, extension: "png", relativeTo: mdFileURL)
            let relPath = FileService.relativePath(from: mdFileURL, to: savedURL)
            return InsertResult(markdownSyntax: "![image](\(relPath))", success: true, errorMessage: nil)
        } catch {
            return InsertResult(markdownSyntax: "", success: false,
                                errorMessage: "Failed to save image: \(error.localizedDescription)")
        }
    }

    static let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic"]

    private static func preferredExtension(for ext: String) -> String {
        let lower = ext.lowercased()
        switch lower {
        case "jpeg": return "jpg"
        case "tiff": return "png"
        case "heic": return "png"
        default: return lower
        }
    }
}
