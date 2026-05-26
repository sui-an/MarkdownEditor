import Foundation

struct HeadingItem: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let title: String
    let lineIndex: Int
    let slug: String
    var children: [HeadingItem] = []

    static func == (lhs: HeadingItem, rhs: HeadingItem) -> Bool {
        lhs.id == rhs.id
    }
}
