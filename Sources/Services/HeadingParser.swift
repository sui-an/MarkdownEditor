import Foundation

enum HeadingParser {

    static func parse(_ markdown: String) -> [HeadingItem] {
        let lines = markdown.components(separatedBy: .newlines)
        var flat: [HeadingItem] = []

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let level = trimmed.prefix(while: { $0 == "#" }).count
            guard level >= 1 && level <= 6 else { continue }

            let afterHash = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            guard !afterHash.isEmpty else { continue }

            let slug = slugify(String(afterHash))
            flat.append(HeadingItem(level: level, title: String(afterHash), lineIndex: lineIndex, slug: slug))
        }

        return buildTree(flat)
    }

    /// Convert flat heading list into a hierarchical tree.
    private static func buildTree(_ items: [HeadingItem]) -> [HeadingItem] {
        var root: [HeadingItem] = []
        var stack: [(item: HeadingItem, children: [HeadingItem])] = []

        for item in items {
            while let top = stack.last, top.item.level >= item.level {
                let completed = stack.removeLast()
                if var parent = stack.last {
                    parent.children.append(buildChild(completed))
                    stack[stack.count - 1] = parent
                } else {
                    root.append(buildChild(completed))
                }
            }
            stack.append((item, []))
        }

        while let top = stack.popLast() {
            if let parent = stack.last {
                var p = parent
                p.children.append(buildChild(top))
                stack[stack.count - 1] = p
            } else {
                root.append(buildChild(top))
            }
        }

        return root
    }

    private static func buildChild(_ node: (item: HeadingItem, children: [HeadingItem])) -> HeadingItem {
        var item = node.item
        item.children = node.children
        return item
    }

    static func slugify(_ title: String) -> String {
        // Keep all Unicode characters except HTML/JS-unsafe ones.
        // HTML5 id allows any non-whitespace character, so we only strip
        // characters that would break getElementById or the id attribute.
        let slug = title
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"["'<>&/\\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return slug.isEmpty ? "heading" : slug
    }
}
