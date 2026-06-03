import Foundation

// MARK: - Session Restore (opened documents per window)

enum SessionRestoreService {

    private static let userDefaultsKey = "openedFileGroups"

    /// Save the given groups of URLs (each group = one window's files) to UserDefaults.
    static func saveWindows(_ groups: [[URL]]) {
        let paths = groups.map { $0.map { $0.path } }
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// Clear all saved file groups.
    static func clearOpenedFiles() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.synchronize()
    }

    /// Read previously saved file groups and return URL groups for files that
    /// still exist on disk.
    static func restoreWindows() -> [[URL]] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let pathGroups = try? JSONDecoder().decode([[String]].self, from: data) else {
            return []
        }
        return pathGroups.map { group in
            group.compactMap { path in
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url
            }
        }.filter { !$0.isEmpty }
    }
}
