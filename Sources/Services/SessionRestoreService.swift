import Foundation

// MARK: - Session Restore (opened documents)

enum SessionRestoreService {

    private static let userDefaultsKey = "openedFilesPaths"

    /// Save the given URLs (all currently open files) to UserDefaults.
    static func saveOpenedFiles(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// Clear all saved file paths.
    static func clearOpenedFiles() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.synchronize()
    }

    /// Read previously saved file paths and return URLs for files that still
    /// exist on disk.
    static func restoreOpenedFiles() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }
}
