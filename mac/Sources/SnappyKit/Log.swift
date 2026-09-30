import Foundation
import os

public enum Log {
    public static let directory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Snappy", directoryHint: .isDirectory)

    public static let fileURL: URL = directory.appending(path: "snappy.log")

    private static let subsystem = OSLog(subsystem: "com.tobykalkman.snappy", category: "app")
    private static let queue = DispatchQueue(label: "com.tobykalkman.snappy.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static func write(_ message: String) {
        os_log("%{public}@", log: subsystem, type: .info, message)
        append(message)
    }

    public static func error(_ message: String) {
        os_log("%{public}@", log: subsystem, type: .error, message)
        append(message)
    }

    private static func append(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: fileURL.path) {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
                fm.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
