import Foundation

struct FileTreeItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let isDirectory: Bool
    let parentID: String?

    var children: [FileTreeItem]? = nil

    var allMarkdownFiles: [FileTreeItem] {
        guard isDirectory else { return [self] }
        return children?.flatMap { $0.allMarkdownFiles } ?? []
    }

    static func == (lhs: FileTreeItem, rhs: FileTreeItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
