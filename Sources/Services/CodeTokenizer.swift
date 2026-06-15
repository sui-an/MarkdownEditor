import AppKit

enum CodeTokenizer {

    // MARK: - Helpers

    private static func charAt(_ text: NSString, _ pos: Int) -> Character {
        Character(UnicodeScalar(text.character(at: pos))!)
    }

    enum TokenType {
        case keyword
        case string
        case comment
        case number
        case function
        case type
        case operatorToken
        case plain
    }

    struct Token {
        let range: NSRange
        let type: TokenType
    }

    struct LanguageRules {
        let keywords: Set<String>
        let types: Set<String>
        let lineComment: String?
        let blockCommentStart: String?
        let blockCommentEnd: String?
        let stringDelimiters: [Character]
    }

    // MARK: - Language Definitions

    static let languages: [String: LanguageRules] = [
        "swift": LanguageRules(
            keywords: ["associatedtype", "class", "deinit", "enum", "extension", "func", "import", "init", "inout", "internal", "let", "operator", "private", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch", "dynamicType", "false", "is", "nil", "super", "self", "Self", "true", "try", "__COLUMN__", "__FILE__", "__FUNCTION__", "__LINE__", "#available", "#colorLiteral", "#column", "#file", "#function", "#imageLiteral", "#line", "#selector", "#sourceLocation"],
            types: ["String", "Int", "Double", "Float", "Bool", "Character", "Array", "Dictionary", "Set", "Optional", "Any", "AnyObject", "Void", "Error", "Result", "URL", "Data", "Date", "Range", "ClosedRange", "UIColor", "NSColor", "UIImage", "NSImage"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"]
        ),
        "javascript": LanguageRules(
            keywords: ["abstract", "arguments", "async", "await", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "debugger", "default", "delete", "do", "double", "else", "enum", "export", "extends", "final", "finally", "float", "for", "function", "goto", "if", "implements", "import", "in", "instanceof", "int", "interface", "let", "long", "native", "new", "null", "package", "private", "protected", "public", "return", "short", "static", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "typeof", "var", "void", "volatile", "while", "with", "yield", "true", "false", "undefined", "NaN", "Infinity"],
            types: ["Array", "Boolean", "Date", "Error", "Function", "JSON", "Math", "Number", "Object", "Promise", "RegExp", "String", "Map", "Set", "WeakMap", "WeakSet", "Symbol"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'", "`"]
        ),
        "typescript": LanguageRules(
            keywords: ["abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "constructor", "continue", "debugger", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "is", "keyof", "let", "module", "namespace", "new", "of", "package", "private", "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this", "throw", "try", "type", "typeof", "var", "void", "while", "with", "yield", "true", "false", "null", "undefined", "any", "boolean", "never", "number", "string", "symbol", "unknown", "object"],
            types: ["Array", "Boolean", "Date", "Error", "Function", "JSON", "Math", "Number", "Object", "Promise", "RegExp", "String", "Map", "Set", "WeakMap", "WeakSet", "Symbol", "Record", "Partial", "Required", "Readonly", "Pick", "Omit", "Exclude", "Extract", "NonNullable", "ReturnType", "Parameters"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'", "`"]
        ),
        "python": LanguageRules(
            keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "True", "False", "None"],
            types: ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes", "type", "object", "Exception", "ValueError", "TypeError", "KeyError", "IndexError", "RuntimeError", "StopIteration", "print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "open", "input", "super", "self", "cls"],
            lineComment: "#",
            blockCommentStart: nil,
            blockCommentEnd: nil,
            stringDelimiters: ["\"", "'"]
        ),
        "go": LanguageRules(
            keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "true", "false", "iota", "nil"],
            types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any", "comparable"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "`"]
        ),
        "rust": LanguageRules(
            keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"],
            types: ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16", "u32", "u64", "u128", "usize", "String", "Vec", "Box", "Rc", "Arc", "Option", "Result", "HashMap", "HashSet", "Iterator", "Option", "Result"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"]
        ),
        "java": LanguageRules(
            keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long", "native", "new", "package", "private", "protected", "public", "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false", "null", "var", "record", "sealed", "permits", "yield"],
            types: ["Boolean", "Byte", "Character", "Double", "Float", "Integer", "Long", "Short", "String", "Object", "Void", "Class", "System", "Math", "Object", "Exception", "RuntimeException", "Error", "List", "ArrayList", "Map", "HashMap", "Set", "HashSet", "Collection", "Iterator"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"]
        ),
        "c": LanguageRules(
            keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Bool", "_Complex", "_Imaginary", "NULL", "true", "false"],
            types: ["int", "char", "float", "double", "long", "short", "unsigned", "signed", "void", "size_t", "ssize_t", "ptrdiff_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "FILE", "DIR"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\""]
        ),
        "cpp": LanguageRules(
            keywords: ["alignas", "alignof", "and", "asm", "auto", "bool", "break", "case", "catch", "char", "char8_t", "char16_t", "char32_t", "class", "concept", "const", "consteval", "constexpr", "constinit", "const_cast", "continue", "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float", "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not", "nullptr", "operator", "or", "private", "protected", "public", "register", "reinterpret_cast", "requires", "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while"],
            types: ["bool", "char", "char8_t", "char16_t", "char32_t", "double", "float", "int", "long", "short", "unsigned", "wchar_t", "void", "size_t", "string", "vector", "map", "set", "pair", "tuple", "array", "list", "deque", "queue", "stack", "unordered_map", "unordered_set"],
            lineComment: "//",
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"]
        ),
        "html": LanguageRules(
            keywords: ["DOCTYPE", "html", "head", "body", "div", "span", "p", "a", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button", "select", "option", "textarea", "script", "style", "link", "meta", "title", "img", "video", "audio", "canvas", "svg"],
            types: ["class", "id", "style", "href", "src", "alt", "width", "height", "type", "name", "value", "placeholder", "disabled", "checked", "selected", "required", "readonly", "multiple", "autofocus", "autocomplete"],
            lineComment: nil,
            blockCommentStart: "<!--",
            blockCommentEnd: "-->",
            stringDelimiters: ["\"", "'"]
        ),
        "css": LanguageRules(
            keywords: ["!important", "and", "not", "only", "or", "from", "to", "keyframes", "media", "font-face", "page", "supports", "charset", "namespace"],
            types: ["color", "background", "margin", "padding", "border", "width", "height", "font", "display", "position", "top", "right", "bottom", "left", "float", "clear", "overflow", "z-index", "opacity", "transition", "animation", "transform", "flex", "grid", "content", "items", "self", "justify", "align", "gap", "order", "flex-grow", "flex-shrink", "flex-basis"],
            lineComment: nil,
            blockCommentStart: "/*",
            blockCommentEnd: "*/",
            stringDelimiters: ["\"", "'"]
        ),
        "json": LanguageRules(
            keywords: ["true", "false", "null"],
            types: [],
            lineComment: nil,
            blockCommentStart: nil,
            blockCommentEnd: nil,
            stringDelimiters: ["\""]
        ),
        "yaml": LanguageRules(
            keywords: ["true", "false", "null", "yes", "no", "on", "off"],
            types: [],
            lineComment: "#",
            blockCommentStart: nil,
            blockCommentEnd: nil,
            stringDelimiters: ["\"", "'"]
        ),
        "markdown": LanguageRules(
            keywords: [],
            types: [],
            lineComment: nil,
            blockCommentStart: nil,
            blockCommentEnd: nil,
            stringDelimiters: []
        ),
        "bash": LanguageRules(
            keywords: ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "do", "done", "in", "function", "return", "exit", "export", "source", "alias", "unalias", "set", "unset", "readonly", "local", "declare", "typeset", "eval", "exec", "trap", "wait", "kill", "cd", "pwd", "echo", "printf", "read", "test", "shift", "getopts", "select", "time", "coproc"],
            types: [],
            lineComment: "#",
            blockCommentStart: nil,
            blockCommentEnd: nil,
            stringDelimiters: ["\"", "'"]
        ),
    ]

    // MARK: - Tokenization

    static func tokenize(_ text: String, language: String) -> [Token] {
        let nsString = text as NSString
        let length = nsString.length
        guard length > 0 else { return [] }

        guard let rules = languages[language.lowercased()] else {
            return []
        }

        var tokens: [Token] = []
        var pos = 0

        while pos < length {
            let remaining = length - pos
            let range = NSRange(location: pos, length: remaining)

            // Check for line comment
            if let lineComment = rules.lineComment {
                if nsString.range(of: lineComment, options: [], range: range).location == pos {
                    let lineEnd = nsString.range(of: "\n", options: [], range: range)
                    let commentEnd = lineEnd.location != NSNotFound ? lineEnd.location : length
                    tokens.append(Token(range: NSRange(location: pos, length: commentEnd - pos), type: .comment))
                    pos = commentEnd
                    continue
                }
            }

            // Check for block comment
            if let blockStart = rules.blockCommentStart, let blockEnd = rules.blockCommentEnd {
                if nsString.range(of: blockStart, options: [], range: range).location == pos {
                    let searchRange = NSRange(location: pos + blockStart.count, length: length - pos - blockStart.count)
                    let endRange = nsString.range(of: blockEnd, options: [], range: searchRange)
                    if endRange.location != NSNotFound {
                        let blockLength = endRange.location + endRange.length - pos
                        tokens.append(Token(range: NSRange(location: pos, length: blockLength), type: .comment))
                        pos += blockLength
                        continue
                    } else {
                        tokens.append(Token(range: NSRange(location: pos, length: length - pos), type: .comment))
                        pos = length
                        continue
                    }
                }
            }

            // Check for string
            if !rules.stringDelimiters.isEmpty {
                let char = charAt(nsString, pos)
                if rules.stringDelimiters.contains(char) {
                    pos += 1
                    var escaped = false
                    while pos < length {
                        let c = charAt(nsString, pos)
                        if escaped {
                            escaped = false
                        } else if c == "\\" {
                            escaped = true
                        } else if c == char {
                            pos += 1
                            break
                        }
                        pos += 1
                    }
                    let stringStart = pos - (pos - (pos - 1))
                    tokens.append(Token(range: NSRange(location: stringStart, length: pos - stringStart), type: .string))
                    continue
                }
            }

            // Check for number
            if pos < length {
                let char = charAt(nsString, pos)
                if char.isNumber || (char == "." && pos + 1 < length && charAt(nsString, pos + 1).isNumber) {
                    let numStart = pos
                    if char == "0" && pos + 1 < length {
                        let next = charAt(nsString, pos + 1)
                        if next == "x" || next == "X" {
                            pos += 2
                            while pos < length && charAt(nsString, pos).isHexDigit {
                                pos += 1
                            }
                        } else if next == "b" || next == "B" {
                            pos += 2
                            while pos < length && (charAt(nsString, pos) == "0" || charAt(nsString, pos) == "1") {
                                pos += 1
                            }
                        } else {
                            while pos < length && (charAt(nsString, pos).isNumber || charAt(nsString, pos) == ".") {
                                pos += 1
                            }
                        }
                    } else {
                        while pos < length && (charAt(nsString, pos).isNumber || charAt(nsString, pos) == ".") {
                            pos += 1
                        }
                        if pos < length && (charAt(nsString, pos) == "e" || charAt(nsString, pos) == "E") {
                            pos += 1
                            if pos < length && (charAt(nsString, pos) == "+" || charAt(nsString, pos) == "-") {
                                pos += 1
                            }
                            while pos < length && charAt(nsString, pos).isNumber {
                                pos += 1
                            }
                        }
                    }
                    tokens.append(Token(range: NSRange(location: numStart, length: pos - numStart), type: .number))
                    continue
                }
            }

            // Check for word (identifier/keyword)
            if pos < length {
                let char = charAt(nsString, pos)
                if char.isLetter || char == "_" {
                    let wordStart = pos
                    while pos < length && (charAt(nsString, pos).isLetter || charAt(nsString, pos).isNumber || charAt(nsString, pos) == "_") {
                        pos += 1
                    }
                    let word = nsString.substring(with: NSRange(location: wordStart, length: pos - wordStart))

                    // Check if it's followed by ( to detect function calls
                    var isFunction = false
                    if pos < length {
                        var lookAhead = pos
                        while lookAhead < length && charAt(nsString, lookAhead) == " " {
                            lookAhead += 1
                        }
                        if lookAhead < length && charAt(nsString, lookAhead) == "(" {
                            isFunction = true
                        }
                    }

                    if rules.keywords.contains(word) {
                        tokens.append(Token(range: NSRange(location: wordStart, length: pos - wordStart), type: .keyword))
                    } else if rules.types.contains(word) {
                        tokens.append(Token(range: NSRange(location: wordStart, length: pos - wordStart), type: .type))
                    } else if isFunction {
                        tokens.append(Token(range: NSRange(location: wordStart, length: pos - wordStart), type: .function))
                    } else {
                        tokens.append(Token(range: NSRange(location: wordStart, length: pos - wordStart), type: .plain))
                    }
                    continue
                }
            }

            // Check for operator
            if pos < length {
                let char = charAt(nsString, pos)
                if "+-*/%=<>!&|^~?".contains(char) {
                    let opStart = pos
                    pos += 1
                    while pos < length {
                        let next = charAt(nsString, pos)
                        if "+-*/%=<>!&|^~?".contains(next) {
                            pos += 1
                        } else {
                            break
                        }
                    }
                    tokens.append(Token(range: NSRange(location: opStart, length: pos - opStart), type: .operatorToken))
                    continue
                }
            }

            // Default: advance one character
            pos += 1
        }

        return tokens
    }

    // MARK: - Apply Highlighting

    static func applyHighlighting(to storage: NSTextStorage, in range: NSRange, language: String, isDark: Bool) {
        let text = storage.string as NSString
        let textRange = NSRange(location: range.location, length: min(range.length, text.length - range.location))
        guard textRange.length > 0 else { return }

        let tokens = tokenize(text.substring(with: textRange), language: language)
        let theme = isDark ? darkTheme : lightTheme

        for token in tokens {
            let adjustedRange = NSRange(location: textRange.location + token.range.location, length: token.range.length)
            guard adjustedRange.location >= 0,
                  adjustedRange.location + adjustedRange.length <= storage.length else { continue }

            let color: NSColor
            switch token.type {
            case .keyword:
                color = theme.keywordColor
            case .string:
                color = theme.stringColor
            case .comment:
                color = theme.commentColor
            case .number:
                color = theme.numberColor
            case .function:
                color = theme.functionColor
            case .type:
                color = theme.typeColor
            case .operatorToken:
                color = theme.operatorColor
            case .plain:
                color = theme.plainColor
            }

            storage.addAttribute(.foregroundColor, value: color, range: adjustedRange)
        }
    }

    // MARK: - Themes

    struct TokenTheme {
        let keywordColor: NSColor
        let stringColor: NSColor
        let commentColor: NSColor
        let numberColor: NSColor
        let functionColor: NSColor
        let typeColor: NSColor
        let operatorColor: NSColor
        let plainColor: NSColor
    }

    static let darkTheme = TokenTheme(
        keywordColor: NSColor(red: 0.68, green: 0.50, blue: 0.85, alpha: 1),      // Purple
        stringColor: NSColor(red: 0.60, green: 0.80, blue: 0.50, alpha: 1),      // Green
        commentColor: NSColor(red: 0.45, green: 0.48, blue: 0.52, alpha: 1),     // Gray
        numberColor: NSColor(red: 0.85, green: 0.60, blue: 0.40, alpha: 1),      // Orange
        functionColor: NSColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1),    // Blue
        typeColor: NSColor(red: 1.00, green: 0.80, blue: 0.30, alpha: 1),        // Yellow
        operatorColor: NSColor(red: 0.90, green: 0.35, blue: 0.40, alpha: 1),    // Red
        plainColor: NSColor(calibratedWhite: 0.92, alpha: 1.0)                     // Light
    )

    static let lightTheme = TokenTheme(
        keywordColor: NSColor(red: 0.55, green: 0.20, blue: 0.65, alpha: 1),      // Purple
        stringColor: NSColor(red: 0.15, green: 0.55, blue: 0.15, alpha: 1),      // Green
        commentColor: NSColor(red: 0.45, green: 0.48, blue: 0.52, alpha: 1),     // Gray
        numberColor: NSColor(red: 0.70, green: 0.35, blue: 0.15, alpha: 1),      // Orange
        functionColor: NSColor(red: 0.10, green: 0.40, blue: 0.80, alpha: 1),    // Blue
        typeColor: NSColor(red: 0.75, green: 0.50, blue: 0.10, alpha: 1),        // Yellow/Brown
        operatorColor: NSColor(red: 0.80, green: 0.15, blue: 0.20, alpha: 1),    // Red
        plainColor: NSColor(calibratedWhite: 0.08, alpha: 1.0)                     // Dark
    )

    // MARK: - Language Detection

    static func detectLanguage(from codeBlock: String) -> String? {
        let trimmed = codeBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }

        let firstLine = String(trimmed.prefix(while: { $0 != "\n" }))
        let langTag = firstLine.dropFirst(3).trimmingCharacters(in: .whitespaces)

        if langTag.isEmpty { return nil }

        let normalized = langTag.lowercased()
        if languages.keys.contains(normalized) {
            return normalized
        }

        // Handle aliases
        let aliases: [String: String] = [
            "js": "javascript",
            "ts": "typescript",
            "py": "python",
            "rb": "ruby",
            "rs": "rust",
            "kt": "kotlin",
            "sh": "bash",
            "shell": "bash",
            "zsh": "bash",
            "yml": "yaml",
            "htm": "html",
            "c++": "cpp",
            "objc": "c",
            "golang": "go",
        ]

        return aliases[normalized]
    }
}
