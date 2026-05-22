import SwiftUI

var lastEditorText: String = ""

struct MainSplitView: View {
    @ObservedObject var document: DocumentController
    @State private var text: String
    @State private var editorVisible: Bool = true
    @State private var showOutline: Bool = false
    @State private var isLocked: Bool = false
    @State private var scrollTarget: NSRange? = nil
    @State private var previewScrollTarget: String? = nil
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var lockHovered: Bool = false
    @State private var previewWidth: PreviewWidth = .normal

    init(document: DocumentController) {
        self.document = document

        if document.pendingClear {
            _text = State(initialValue: "")
            document.pendingClear = false
            return
        }

        if let content = document.pendingContent {
            _text = State(initialValue: content)
            document.pendingContent = nil
            return
        }

        // Direct read from UserDefaults — completely avoids @Published / property
        // wrapper timing issues that can occur during SwiftUI view creation.
        if let filePath = UserDefaults.standard.string(forKey: "lastOpenedFilePath"),
           let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            _text = State(initialValue: content)
            return
        }

        _text = State(initialValue: defaultMarkdown)
    }

    private var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
    private var charCount: Int { text.count }
    private var lineCount: Int { max(1, text.components(separatedBy: "\n").count) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HSplitView {
                    if showOutline {
                        OutlinePanel(text: text, scrollTarget: $scrollTarget, previewScrollTo: $previewScrollTarget)
                            .frame(minWidth: 180, idealWidth: 220)
                    }

                    if !document.workspaceFiles.isEmpty {
                        workspaceSidebar
                            .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                    }

                    if editorVisible {
                        MarkdownEditorView(text: $text, scrollTarget: $scrollTarget, isLocked: isLocked)
                            .frame(minWidth: 200, idealWidth: geometry.size.width * 0.3)
                            .layoutPriority(1)
                    }

                    WebPreview(text: text, scrollToHeading: $previewScrollTarget, previewWidth: previewWidth)
                        .frame(minWidth: 200)
                        .layoutPriority(1)
                        .background(SplitViewArranger(
                            showOutline: showOutline,
                            editorVisible: editorVisible
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                statusBar
            }
            .toolbar { toolbarContent }
            .background(WindowTitleUpdater(title: document.fileName))
            .onChange(of: text) { _, newText in
                lastEditorText = newText
                guard document.currentFile != nil else { return }
                autoSaveTask?.cancel()
                autoSaveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    document.saveFile(text: newText)
                }
            }
            .onChange(of: document.pendingContent) { _, content in
                if let content {
                    text = content
                    document.pendingContent = nil
                }
            }
            .onChange(of: document.pendingClear) { _, clear in
                if clear {
                    text = ""
                    document.pendingClear = false
                }
            }
            .onChange(of: document.currentFile) { _, newFile in
                // When a file is first loaded (session restore or open), load its content.
                // This catches the case where currentFile was set in DocumentController.init
                // before the view mounted — onAppear below handles the synchronous case,
                // and this onChange catches any subsequent reassignment.
                if newFile != nil, let content = document.pendingContent {
                    text = content
                    document.pendingContent = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleEditor)) { _ in
                editorVisible.toggle()
            }
        }
    }

    // MARK: - Workspace Sidebar

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(document.workspaceURL?.lastPathComponent ?? "")
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(document.workspaceFiles, id: \.path, selection: $document.workspaceSelectedFile) { file in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text(file.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            // Lock toggle
            Button(action: { isLocked.toggle() }) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.caption2)
                    .foregroundColor(isLocked ? .orange : .secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .help(isLocked ? "Unlock editing" : "Lock editing")
            .onHover { over in lockHovered = over }

            Divider()
                .padding(.horizontal, 6)

            // Word count
            Image(systemName: "text.word.count")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(wordCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(minWidth: 30, alignment: .leading)

            // Character count
            Text("\(charCount)")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
                .frame(minWidth: 30, alignment: .leading)

            // Line count
            Text("\(lineCount) lines")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
                .frame(minWidth: 30, alignment: .leading)

            Spacer()

            // Lock indicator (when locked)
            if isLocked {
                Text("LOCKED")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.orange)
            }

            // Editor visibility
            if !editorVisible {
                Text("PREVIEW ONLY")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            // Preview width picker
            Picker("Width", selection: $previewWidth) {
                Text("Narrow").tag(PreviewWidth.normal)
                Text("Medium").tag(PreviewWidth.middle)
                Text("Wide").tag(PreviewWidth.wide)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigation) {
                Button(action: { editorVisible.toggle() }) {
                    Image(systemName: editorVisible ? "doc.richtext" : "doc.text.magnifyingglass")
                }
                .help(editorVisible ? "Hide editor" : "Show editor")
            }

            ToolbarItem(placement: .navigation) {
                Button(action: { showOutline.toggle() }) {
                    Image(systemName: showOutline ? "sidebar.left" : "sidebar.left")
                        .foregroundColor(showOutline ? .accentColor : .secondary)
                }
                .help(showOutline ? "Hide outline" : "Show outline")
            }

            ToolbarItem(placement: .automatic) {
                Spacer()
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { performFindAction(.showFind) }) {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find in preview (⌘F)")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: newDocument) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New document")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: openDocument) {
                    Image(systemName: "folder")
                }
                .help("Open file")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: saveDocument) {
                    Image(systemName: "arrow.down.doc")
                }
                .help("Save")
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }

    // MARK: - Actions

    private enum FindAction: Int {
        case showFind = 1  // NSTextFinder.Action.showFindInterface
    }

    private func performFindAction(_ action: FindAction) {
        NotificationCenter.default.post(
            name: .performFindAction,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
    }

    private func newDocument() {
        document.newFile()
    }

    private func openDocument() {
        document.openFile()
    }

    private func saveDocument() {
        document.saveFile(text: text)
    }
}

// MARK: - Split View Arranger

struct SplitViewArranger: NSViewRepresentable {
    let showOutline: Bool
    let editorVisible: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        let outlineChanged = coord.lastShowOutline != showOutline
        let editorChanged = coord.lastEditorVisible != editorVisible
        guard outlineChanged || editorChanged || !coord.didInitialLayout else {
            return
        }
        coord.lastShowOutline = showOutline
        coord.lastEditorVisible = editorVisible
        coord.didInitialLayout = true

        // CRASH ROOT CAUSE: Never call split.setPosition() synchronously in
        // updateNSView. SwiftUI may be mid-NSSplitView-subview-array mutation
        // (adding/removing views for `if` conditionals), and setPosition in that
        // window corrupts internal split view state → EXC_BAD_ACCESS.
        // Instead: defer ALL NSSplitView manipulation to the next run loop,
        // after SwiftUI has finished its update pass and the subview array is stable.
        DispatchQueue.main.async { [showOutline, editorVisible, weak nsView] in
            guard let nsView = nsView else { return }
            // Find NSSplitView fresh each time — window may not be ready at
            // updateNSView time, and the SplitViewArranger view moves in the
            // hierarchy during SwiftUI's update pass.
            guard let split = self.findSplitView(from: nsView) else { return }
            let count = split.subviews.count
            guard count >= 2 else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.adjustDividers(split: split, count: count, showOutline: showOutline, editorVisible: editorVisible, animated: true)
            }
        }
    }

    /// Position NSSplitView dividers so visible panels get their target widths.
    /// Uses the explicit `showOutline`/`editorVisible` rather than self properties,
    /// because this function may be called from an async closure where self is stale.
    private func adjustDividers(split: NSSplitView, count: Int, showOutline: Bool, editorVisible: Bool, animated: Bool) {
        let t = split.dividerThickness
        let total = split.bounds.width
        let available = total - t * CGFloat(count - 1)
        guard available > 10, count >= 2 else { return }

        let hasWorkspace = count - (showOutline ? 1 : 0) - (editorVisible ? 1 : 0) - 1
        guard hasWorkspace == 0 || hasWorkspace == 1 else { return }

        // Build target widths for each visible subview.
        var widths: [CGFloat] = []
        if showOutline { widths.append(220) }
        if hasWorkspace == 1 { widths.append(220) }
        if editorVisible { widths.append(max(200, available * 0.35)) }
        let used = widths.reduce(0, +)
        widths.append(max(100, available - used))

        let totalW = widths.reduce(0, +)
        if totalW > available {
            widths = widths.map { $0 * available / totalW }
        }

        let dividerCount = count - 1
        let loopEnd = min(dividerCount, widths.count)
        var x: CGFloat = 0
        for i in 0..<loopEnd {
            x += widths[i]
            let pos = x + t * CGFloat(i)
            if animated {
                split.animator().setPosition(pos, ofDividerAt: i)
            }
        }
    }

    /// Find the NSSplitView that contains the given NSView.
    /// Since SplitViewArranger is placed as a .background() on a view inside
    /// HSplitView, the superview chain should reach NSSplitView.
    /// Falls back to searching the window's contentView recursively.
    private func findSplitView(from view: NSView) -> NSSplitView? {
        var current: NSView? = view.superview
        while current != nil {
            if let split = current as? NSSplitView { return split }
            current = current?.superview
        }
        guard let window = view.window, let contentView = window.contentView else { return nil }
        return findNSSplitView(in: contentView)
    }

    private func findNSSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for subview in view.subviews {
            if let found = findNSSplitView(in: subview) { return found }
        }
        return nil
    }

    class Coordinator {
        var lastShowOutline: Bool = false
        var lastEditorVisible: Bool = true
        var didInitialLayout: Bool = false
    }
}

// MARK: - Window Title Updater

/// Sets the window title via the NSView's `.window` property,
/// which is only available after the view is added to a window.
/// Uses `view.window?.title` which is safe and callback-free.
struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.title = title
    }
}

// MARK: - Outline Panel

struct OutlinePanel: View {
    let text: String
    @Binding var scrollTarget: NSRange?
    @Binding var previewScrollTo: String?

    @State private var headings: [(level: Int, title: String, range: NSRange)] = []
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.secondary)
                Text("Outline")
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Text("\(headings.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if headings.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No headings")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(headings.enumerated()), id: \.offset) { idx, h in
                            Button(action: {
                                scrollTarget = h.range
                                previewScrollTo = slugify(h.title)
                            }) {
                                HStack(spacing: 4) {
                                    Text(h.title)
                                        .font(.system(size: max(12 - CGFloat(h.level - 1), 10)))
                                        .fontWeight(h.level <= 2 ? .semibold : .regular)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, CGFloat(h.level - 1) * 16 + 8)
                                .padding(.trailing, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onChange(of: text) { _, _ in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if !Task.isCancelled {
                    headings = parseHeadings(text)
                }
            }
        }
        .onAppear {
            headings = parseHeadings(text)
        }
    }
}

private func slugify(_ title: String) -> String {
    title.lowercased()
        .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fff]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func parseHeadings(_ text: String) -> [(level: Int, title: String, range: NSRange)] {
    var result: [(level: Int, title: String, range: NSRange)] = []
    let nsText = text as NSString
    let lines = text.components(separatedBy: "\n")
    var location = 0
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            let range = NSRange(location: location, length: line.count)
            result.append((level: level, title: title, range: range))
        }
        location += line.count + 1
    }
    return result
}
