import Foundation
import os.log

/// Single logger that writes to both os_log (Console.app) and a file.
///
/// File location: ~/Library/Containers/net.dalir.buzzel/Data/Library/Logs/buzzel.log
/// Rotates at 5 MB, keeps one backup (buzzel.log.1).
///
/// Usage — replace:
///   os_log("msg", log: log, type: .debug)
/// with:
///   FileLogger.shared.debug("msg", category: "MyCategory")
///
enum FileLogger {

  enum Level: String {
    case debug = "D"
    case info = "I"
    case error = "E"
  }

  private static let subsystem = "com.buzzel"
  private static let maxBytes: UInt64 = 5 * 1024 * 1024

  private static let queue = DispatchQueue(label: "com.buzzel.filelogger", qos: .utility)
  private static let fmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
  }()

  private static var fileURL: URL? = {
    guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    else { return nil }
    let dir = lib.appendingPathComponent("Logs/Buzzel", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("buzzel.log")
  }()

  // One OSLog per category, cached.
  private static var osLogs: [String: OSLog] = [:]
  private static func osLog(for category: String) -> OSLog {
    if let existing = osLogs[category] { return existing }
    let l = OSLog(subsystem: subsystem, category: category)
    osLogs[category] = l
    return l
  }

  static func debug(_ msg: String, category: String) {
    write(msg, level: .debug, category: category)
  }

  static func info(_ msg: String, category: String) {
    write(msg, level: .info, category: category)
  }

  static func error(_ msg: String, category: String) {
    write(msg, level: .error, category: category)
  }

  private static func write(_ msg: String, level: Level, category: String) {
    // os_log on calling thread
    let log = osLog(for: category)
    switch level {
    case .debug: os_log("%{public}@", log: log, type: .debug, msg)
    case .info: os_log("%{public}@", log: log, type: .info, msg)
    case .error: os_log("%{public}@", log: log, type: .error, msg)
    }

    // file write on background queue
    let line = "\(fmt.string(from: Date())) \(level.rawValue)/\(category): \(msg)\n"
    queue.async { appendToFile(line) }
  }

  private static func appendToFile(_ line: String) {
    guard let url = fileURL else { return }
    // Rotate if over limit
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? UInt64, size > maxBytes
    {
      let backup = url.deletingLastPathComponent().appendingPathComponent("buzzel.log.1")
      try? FileManager.default.removeItem(at: backup)
      try? FileManager.default.moveItem(at: url, to: backup)
    }
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: url.path) {
      if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
      }
    } else {
      try? data.write(to: url, options: .atomic)
    }
  }

  static func logPath() -> String { fileURL?.path ?? "unavailable" }
}
