import Foundation

// MARK: - Log Event Type

enum LogEventType: String {
    case smsReceived
    case smsForwarded
    case smsQueued
    case smsFiltered
    case queueFlushed
    case deviceConnected
    case deviceDisconnected
    case pairingStarted
    case pairingComplete
    case pairingFailed
    case filterUpdated
    case configSynced
}

// MARK: - Log Direction

enum LogDirection {
    case incoming
    case outgoing
    case local
}

// MARK: - Log Status

enum LogStatus {
    case success
    case failed
}

// MARK: - Log Entry

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

    init(timestamp: Date = Date(), type: LogEventType, message: String,
         direction: LogDirection = .local, status: LogStatus = .success, error: String? = nil) {
        self.timestamp = timestamp
        self.type = type
        self.message = message
        self.direction = direction
        self.status = status
        self.error = error
    }

    var timeString: String { Self.timeFormatter.string(from: timestamp) }
}
