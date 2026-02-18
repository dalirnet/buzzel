import Foundation

enum LogEventType: String {
  case deviceConnected
  case deviceDisconnected
  case pairingComplete
  case pairingFailed
}

enum LogDirection {
  case incoming
  case outgoing
  case local
}

enum LogStatus {
  case success
  case failed
}

struct LogEntry: Identifiable {
  private static let timeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm"
    return fmt
  }()

  let id = UUID()
  let timestamp: Date
  let type: LogEventType
  let message: String
  let direction: LogDirection
  let status: LogStatus
  let error: String?

  init(
    timestamp: Date = Date(), type: LogEventType, message: String,
    direction: LogDirection = .local, status: LogStatus = .success, error: String? = nil
  ) {
    self.timestamp = timestamp
    self.type = type
    self.message = message
    self.direction = direction
    self.status = status
    self.error = error
  }

  var timeString: String { Self.timeFormatter.string(from: timestamp) }
}
