import Foundation

private var _handle: FileHandle? = {
    let path = "/tmp/mded_trace.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

private let queue = DispatchQueue(label: "trace")

func trace(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    if let d = line.data(using: .utf8) {
        queue.async { _handle?.write(d) }
    }
}


