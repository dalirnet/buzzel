import Foundation
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "TransportManager")

// MARK: - Transport Manager

class TransportManager: ObservableObject, BleCentralDelegate, TcpClientDelegate {

    static let shared = TransportManager()

    private static let responseTimeout: TimeInterval = 10
    private static let heartbeatTimeout: TimeInterval = 45
    private static let pingInterval: TimeInterval = 15

    // MARK: Connection State

    enum ConnectionState {
        case disconnected
        case scanning
        case active
    }

    // MARK: Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var isConnected = false
    @Published var isPairing = false
    @Published var pairingError: String?
    @Published var logEntries: [LogEntry] = []

    // MARK: Callbacks

    var onSmsReceived: ((SmsPayload) -> Void)?
    var onQueueFlushed: (([SmsPayload]) -> Void)?
    var onPairingComplete: ((String) -> Void)?
    var onDeviceReady: (() -> Void)?

    // MARK: Private

    let ble = BleCentral()
    private let tcp = TcpClient()
    private let maxLogEntries = 200
    private var pendingPairingCode: String?
    private var recentMessageIds: [String] = []
    private let maxRecentIds = 50
    private var pendingTimeouts: [String: DispatchWorkItem] = [:]
    private var heartbeatTimer: DispatchWorkItem?
    private var pingTimer: DispatchSourceTimer?
    private let deviceName = "Android"

    // MARK: Init

    init() {
        ble.delegate = self
        tcp.delegate = self
    }

    // MARK: - State Machine

    private func transitionTo(_ newState: ConnectionState) {
        let oldState = connectionState
        guard oldState != newState || newState == .active else { return }
        os_log("State: %{public}@ -> %{public}@", log: log, type: .debug, "\(oldState)", "\(newState)")
        connectionState = newState

        switch newState {
        case .disconnected:
            cancelAllTimeouts()
            stopHeartbeat()
            DispatchQueue.main.async { self.isConnected = false }

        case .scanning:
            cancelAllTimeouts()
            stopHeartbeat()
            DispatchQueue.main.async { self.isConnected = false }

        case .active:
            DispatchQueue.main.async { self.isConnected = true }
            resetHeartbeat()
            startPingTimer()
        }
    }

    // MARK: - Heartbeat

    private func resetHeartbeat() {
        heartbeatTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.heartbeatTimer = nil
            os_log("Heartbeat timeout", log: log, type: .error)
            self.appendEntry(.deviceDisconnected,
                             "No heartbeat from \(self.deviceName)",
                             status: .failed,
                             error: "No data for \(Int(Self.heartbeatTimeout))s")
            self.transitionTo(.scanning)
            self.ble.disconnect()
        }
        heartbeatTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartbeatTimeout, execute: work)
    }

    private func startPingTimer() {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .active else { return }
            self.sendPing()
        }
        pingTimer = timer
        timer.resume()
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        stopPingTimer()
    }

    // MARK: - Activity Log

    func appendEntry(_ type: LogEventType, _ message: String,
                     direction: LogDirection = .local, status: LogStatus = .success, error: String? = nil) {
        let entry = LogEntry(type: type, message: message, direction: direction, status: status, error: error)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logEntries.append(entry)
            if self.logEntries.count > self.maxLogEntries {
                self.logEntries.removeFirst()
            }
        }
    }

    // MARK: - Response Timeout

    private func expectResponse(_ responseType: String, label: String, logType: LogEventType) {
        cancelTimeout(responseType)
        let work = DispatchWorkItem { [weak self] in
            self?.pendingTimeouts.removeValue(forKey: responseType)
            self?.appendEntry(logType, "\(label) timed out", direction: .outgoing, status: .failed, error: "No response after \(Int(Self.responseTimeout))s")
        }
        pendingTimeouts[responseType] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.responseTimeout, execute: work)
    }

    private func fulfillTimeout(_ responseType: String) {
        if let work = pendingTimeouts.removeValue(forKey: responseType) {
            work.cancel()
        }
    }

    private func cancelTimeout(_ responseType: String) {
        if let work = pendingTimeouts.removeValue(forKey: responseType) {
            work.cancel()
        }
    }

    private func cancelAllTimeouts() {
        for (_, work) in pendingTimeouts { work.cancel() }
        pendingTimeouts.removeAll()
    }

    private func notifyDeviceReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.onDeviceReady?()
        }
    }

    // MARK: - Connection

    func start() {
        os_log("start", log: log, type: .debug)
        transitionTo(.scanning)
        ble.start()
    }

    func connectTcp(host: String, port: UInt16) {
        tcp.connect(host: host, port: port)
    }

    func stop() {
        sendGoodbye()
        transitionTo(.disconnected)
        ble.stop()
        tcp.disconnect()
    }

    func unpair() {
        transitionTo(.disconnected)
        tcp.disconnect()

        if ble.isConnected {
            sendUnpair()
            // Delay disconnect so the unpair write has time to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.ble.stop()
            }
        } else {
            ble.stop()
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        ble.startDiscovery()
    }

    func stopDiscovery() {
        ble.stopDiscovery()
    }

    // MARK: - Pairing

    func connectAndPair(device: DiscoveredDevice, code: String) {
        appendEntry(.pairingStarted, "Pairing with \(device.name)...", direction: .outgoing)
        isPairing = true
        pairingError = nil
        pendingPairingCode = code

        if ble.isConnected && ble.peripheralIdentifier == device.id {
            sendPairingRequest()
        } else {
            ble.connect(to: device)
        }
    }

    func cancelPairing() {
        isPairing = false
        pendingPairingCode = nil
        cancelTimeout(MessageType.pairingResponse)
    }

    private func sendPairingRequest() {
        guard let code = pendingPairingCode else { return }

        guard let data = BuzzelProtocol.createPairingRequest(code: code) else {
            pairingError = "Failed to create pairing request"
            isPairing = false
            appendEntry(.pairingFailed, "Pairing failed", direction: .outgoing, status: .failed, error: "Failed to create pairing request")
            return
        }
        if ble.isConnected {
            _ = ble.send(data)
            expectResponse(MessageType.pairingResponse, label: "Pairing", logType: .pairingFailed)
        }
    }

    private func handlePairingResponse() {
        fulfillTimeout(MessageType.pairingResponse)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appendEntry(.pairingComplete, "Paired with \(self.deviceName)", direction: .incoming)
            self.pendingPairingCode = nil
            self.transitionTo(.active)
            self.onPairingComplete?(self.deviceName)
            self.isPairing = false
            self.sendReady()
            self.notifyDeviceReady()
        }
    }

    // MARK: - Messages

    func sendReady() {
        guard let data = BuzzelProtocol.createReady() else { return }
        send(data)
    }

    func sendGoodbye() {
        guard let data = BuzzelProtocol.createGoodbye() else { return }
        send(data)
    }

    func sendUnpair() {
        guard let data = BuzzelProtocol.createUnpair() else { return }
        send(data)
    }

    func sendPing() {
        guard let data = BuzzelProtocol.createMessage(type: MessageType.ping) else { return }
        send(data)
    }

    func sendPong() {
        guard let data = BuzzelProtocol.createPong() else { return }
        send(data)
    }

    func sendConfig(transport: String, wifiHost: String?, wifiPort: Int, filters: [FilterRule]) {
        guard let data = BuzzelProtocol.createConfigSync(
            transport: transport, wifiHost: wifiHost, wifiPort: wifiPort, filters: filters
        ) else { return }
        appendEntry(.configSynced, "Syncing \(filters.count) filters to \(deviceName)", direction: .outgoing)
        send(data)
        expectResponse(MessageType.configAck, label: "Config sync", logType: .configSynced)
    }

    func syncConfig(store: AppStore) {
        sendConfig(
            transport: store.transportMethod,
            wifiHost: store.wifiHost.isEmpty ? nil : store.wifiHost,
            wifiPort: store.wifiPort,
            filters: store.filters
        )
    }

    private func send(_ data: Data) {
        let type = BuzzelProtocol.parseType(data) ?? "?"
        guard ble.isConnected || tcp.isConnected else {
            os_log("send(%{public}@) — no transport connected", log: log, type: .error, type)
            appendEntry(.deviceDisconnected, "Failed to send: not connected", status: .failed, error: "No transport connected")
            return
        }
        os_log("send(%{public}@)", log: log, type: .debug, type)
        if ble.isConnected {
            _ = ble.send(data)
        }
        if tcp.isConnected {
            _ = tcp.send(data)
        }
    }

    private func isDuplicate(_ raw: Data) -> Bool {
        guard let dict = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let id = dict["id"] as? String else { return false }
        if recentMessageIds.contains(id) { return true }
        recentMessageIds.append(id)
        if recentMessageIds.count > maxRecentIds {
            recentMessageIds.removeFirst()
        }
        return false
    }

    private func handleIncoming(_ raw: Data) {
        guard let type = BuzzelProtocol.parseType(raw) else {
            os_log("handleIncoming — failed to parse type", log: log, type: .error)
            return
        }
        os_log("recv: %{public}@", log: log, type: .debug, type)

        // Reset heartbeat on any incoming message
        if connectionState == .active {
            resetHeartbeat()
        }

        if isDuplicate(raw) { return }

        if type == MessageType.pairingResponse {
            handlePairingResponse()
            return
        }

        DispatchQueue.main.async { [weak self] in
            switch type {
            case MessageType.sms:
                if let sms = BuzzelProtocol.parseSms(raw) {
                    self?.appendEntry(.smsReceived, "Received SMS from \(sms.contactName ?? sms.sender)", direction: .incoming)
                    self?.onSmsReceived?(sms)
                }
            case MessageType.queueFlush:
                let messages = BuzzelProtocol.parseQueueFlush(raw)
                self?.appendEntry(.queueFlushed, "Delivered \(messages.count) queued messages", direction: .incoming)
                self?.onQueueFlushed?(messages)
            case MessageType.ping:
                self?.sendPong()
            case MessageType.pong:
                break // heartbeat already reset above
            case MessageType.goodbye:
                self?.appendEntry(.deviceDisconnected, "\(self?.deviceName ?? "Android") said goodbye", direction: .incoming)
                self?.transitionTo(.scanning)
                self?.ble.disconnect()
            case MessageType.configAck:
                self?.fulfillTimeout(MessageType.configAck)
                self?.appendEntry(.configSynced, "\(self?.deviceName ?? "Android") confirmed settings", direction: .incoming)
            default:
                break
            }
        }
    }

    // MARK: - BleCentralDelegate

    func bleDidConnect() {
        os_log("bleDidConnect", log: log, type: .debug)
        appendEntry(.deviceConnected, "Connected to \(deviceName)")
        transitionTo(.active)
        if isPairing {
            sendPairingRequest()
        } else {
            sendReady()
            notifyDeviceReady()
        }
    }

    func bleDidDisconnect() {
        os_log("bleDidDisconnect", log: log, type: .debug)
        appendEntry(.deviceDisconnected, "Disconnected from \(deviceName)")
        transitionTo(.scanning)
    }

    func bleDidReceiveData(_ data: Data) {
        handleIncoming(data)
    }

    // MARK: - TcpClientDelegate

    func tcpDidConnect() {
        appendEntry(.deviceConnected, "Connected via TCP")
        transitionTo(.active)
        sendReady()
        notifyDeviceReady()
    }

    func tcpDidDisconnect() {
        appendEntry(.deviceDisconnected, "TCP disconnected")
        if !ble.isConnected {
            transitionTo(.scanning)
        }
    }

    func tcpDidReceiveData(_ data: Data) {
        handleIncoming(data)
    }
}
