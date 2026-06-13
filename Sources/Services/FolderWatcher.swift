import Foundation

final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var paths: [String]
    private let callback: ([URL]) -> Void

    init(paths: [String], callback: @escaping ([URL]) -> Void) {
        self.paths = paths
        self.callback = callback
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<FolderWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, numEvents, rawPaths, _, _) in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let pathList = rawPaths.assumingMemoryBound(to: UnsafeRawPointer.self)
                let urls = (0..<numEvents).compactMap { i -> URL? in
                    let pathStr = String(cString: pathList[i].assumingMemoryBound(to: CChar.self))
                    return URL(fileURLWithPath: pathStr)
                }
                DispatchQueue.main.async {
                    watcher.callback(urls)
                }
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            flags
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .background))
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
