import Foundation

// MARK: - Session Restore (last opened document)

enum SessionRestoreService {

    private static let bookmarkKey = "lastOpenedFileBookmark"

    /// Save a security-scoped bookmark for the given URL to UserDefaults.
    static func saveLastOpened(_ url: URL) {
        // For non-sandboxed apps, store URL bookmark so the file can be
        // resolved even if it moves. Security-scoped bookmark is not needed
        // when the app has full file system access.
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            // Non-fatal: just won't restore on next launch
            print("Failed to create bookmark for \(url): \(error)")
        }
    }

    /// Clear the saved bookmark (e.g. when closing the last file).
    static func clearLastOpened() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Resolve the bookmark saved from a previous session.
    /// Returns `nil` if the bookmark is invalid or the file no longer exists.
    static func restoreLastOpened() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Re-save if stale (file may have been moved)
            if isStale {
                do {
                    let newBookmark = try url.bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    UserDefaults.standard.set(newBookmark, forKey: bookmarkKey)
                } catch {
                    // Ignore re-save failure
                }
            }

            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        } catch {
            return nil
        }
    }
}
