import Foundation
import os.log

enum FileLogger {
    enum Level: String {
        case debug = "D"
        case info = "I"
        case error = "E"
    }

    private static let subsystem = "com.buzzel"
    private static let maximumFileSizeInBytes: UInt64 = 5 * 1024 * 1024

    private static let queue = DispatchQueue(label: "com.buzzel.filelogger", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static var fileURL: URL? = {
        guard
            let libraryDirectory = FileManager.default.urls(
                for: .libraryDirectory, in: .userDomainMask
            ).first
        else { return nil }
        let logsDirectory = libraryDirectory.appendingPathComponent(
            "Logs/Buzzel", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true)
        return logsDirectory.appendingPathComponent("buzzel.log")
    }()

    private static var operatingSystemLogs: [String: OSLog] = [:]
    private static func operatingSystemLog(for category: String) -> OSLog {
        if let existing = operatingSystemLogs[category] { return existing }
        let log = OSLog(subsystem: subsystem, category: category)
        operatingSystemLogs[category] = log
        return log
    }

    static func debug(_ message: String, category: String) {
        write(message, level: .debug, category: category)
    }

    static func info(_ message: String, category: String) {
        write(message, level: .info, category: category)
    }

    static func error(_ message: String, category: String) {
        write(message, level: .error, category: category)
    }

    private static func write(_ message: String, level: Level, category: String) {
        let log = operatingSystemLog(for: category)
        switch level {
        case .debug: os_log("%{public}@", log: log, type: .debug, message)
        case .info: os_log("%{public}@", log: log, type: .info, message)
        case .error: os_log("%{public}@", log: log, type: .error, message)
        }

        let line =
            "\(dateFormatter.string(from: Date())) \(level.rawValue)/\(category): \(message)\n"
        queue.async { appendToFile(line) }
    }

    private static func appendToFile(_ line: String) {
        guard let url = fileURL else { return }

        if shouldRotateLogFile(at: url) {
            let backupURL = url.deletingLastPathComponent().appendingPathComponent("buzzel.log.1")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: url, to: backupURL)
        }

        guard let data = line.data(using: .utf8) else { return }

        guard FileManager.default.fileExists(atPath: url.path) else {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let fileHandle = try? FileHandle(forWritingTo: url) else { return }
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        try? fileHandle.close()
    }

    private static func shouldRotateLogFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? UInt64
        else { return false }
        return fileSize > maximumFileSizeInBytes
    }

    static func logPath() -> String {
        fileURL?.path ?? "unavailable"
    }
}
