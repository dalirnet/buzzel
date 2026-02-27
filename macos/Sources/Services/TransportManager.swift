import Combine
import Foundation
import Network

private let logCategory = "TransportManager"

class TransportManager: ObservableObject, BleCentralDelegate, TcpServerDelegate {
    static let shared = TransportManager()

    private static let pongTimeout: TimeInterval = 5
    private static let pingInterval: TimeInterval = 10
    private static let failoverTimeout: TimeInterval = 10
    private static let handshakeTimeout: TimeInterval = 30
    private static let maximumReconnectAttempts = 2

    enum ConnectionState { case idle, connecting, handshaking, active }

    enum Transport: String {
        case wifi, ble
        var displayName: String {
            self == .wifi ? "WiFi" : "BLE"
        }
    }

    @Published var connectionState: ConnectionState = .idle
    @Published var hasBeenConnected = false
    @Published var isConnected = false
    @Published var isPairing = false
    @Published var pairingError: String?
    @Published var logEntries: [LogEntry] = []
    @Published var activeTransport: String = ""
    @Published var connectingTransport: String = ""
    @Published var bleAuthorized = false
    @Published var bluetoothPoweredOff = false

    var onPairingComplete: ((String) -> Void)?
    var onDeviceReady: (() -> Void)?

    let ble = BleCentral()
    private let tcpServer = TcpServer()
    private var bluetoothAuthorizationSubscription: AnyCancellable?
    private var bluetoothPoweredOffSubscription: AnyCancellable?
    private let maximumLogEntries = 100
    private let deviceName = "Android"

    private var failoverSteps: [Transport] = []
    private var failoverIndex = 0
    private var failoverWorkItem: DispatchWorkItem?
    private var currentTransport: Transport?

    private var pairingSessionIdentifier: String?
    private var pairingCode: String?

    private var lastPongTime: Date?
    private var lastPingSentTime: Date?
    private var pingTimer: DispatchSourceTimer?

    private var handshakeWorkItem: DispatchWorkItem?

    private var reconnectAttempts = 0

    private var nextSequenceNumber: UInt16 = 0
    private var pendingAcknowledgmentSequenceNumber: UInt16?
    private var pendingRetries = 0
    private var retryPayload: Data?
    private var retryWorkItem: DispatchWorkItem?

    init() {
        ble.delegate = self
        tcpServer.delegate = self
        bluetoothAuthorizationSubscription = ble.$bluetoothAuthorization
            .receive(on: DispatchQueue.main)
            .map { $0 == .allowedAlways }
            .assign(to: \.bleAuthorized, on: self)
        bluetoothPoweredOffSubscription = ble.$bluetoothPoweredOff
            .receive(on: DispatchQueue.main)
            .assign(to: \.bluetoothPoweredOff, on: self)
    }

    // MARK: - Failover

    private func resolvePreferredTransport(_ preference: String) -> Transport {
        if preference == "ble" { return .ble }
        if preference == "wifi" { return .wifi }

        let hasWifi = detectWifiAvailability()
        FileLogger.info(
            "Auto-detect: WiFi \(hasWifi ? "available" : "unavailable")", category: logCategory
        )
        return hasWifi ? .wifi : .ble
    }

    private func detectWifiAvailability() -> Bool {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        let semaphore = DispatchSemaphore(value: 0)
        var hasWifi = false

        monitor.pathUpdateHandler = { path in
            hasWifi = path.status == .satisfied
            semaphore.signal()
        }

        let queue = DispatchQueue(label: "buzzel.wifi-check")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 1)
        monitor.cancel()

        return hasWifi
    }

    private func buildFailoverSteps(preference: String) {
        let primary = resolvePreferredTransport(preference)
        let secondary: Transport = primary == .wifi ? .ble : .wifi
        failoverSteps = [primary, secondary]
        FileLogger.debug(
            "Failover steps: \(failoverSteps.map { $0.rawValue }.joined(separator: ", "))",
            category: logCategory
        )
    }

    private func startFailover(preference: String) {
        FileLogger.info("Starting failover, prefer=\(preference)", category: logCategory)
        buildFailoverSteps(preference: preference)
        failoverIndex = 0
        tryNextFailoverStep()
    }

    private func tryNextFailoverStep() {
        failoverWorkItem?.cancel()
        guard !failoverSteps.isEmpty else {
            FileLogger.error("Failover: no steps configured", category: logCategory)
            return
        }
        let transport = failoverSteps[failoverIndex % failoverSteps.count]

        FileLogger.info(
            "Failover step \(failoverIndex): trying \(transport.rawValue) (timeout=\(Self.failoverTimeout)s)",
            category: logCategory
        )
        stopCurrentTransport()
        transitionTo(.connecting)

        switch transport {
        case .wifi:
            currentTransport = .wifi
            tcpServer.start(port: BuzzelProtocol.tcpPort)
        case .ble:
            currentTransport = .ble
            ble.start()
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            FileLogger.info(
                "Failover timeout: \(transport.rawValue) did not connect in \(Self.failoverTimeout)s, advancing",
                category: logCategory
            )
            self.failoverIndex += 1
            self.tryNextFailoverStep()
        }
        failoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.failoverTimeout, execute: workItem)
    }

    private func stopCurrentTransport() {
        FileLogger.debug("Stopping current transport", category: logCategory)
        tcpServer.stop()
        ble.stop()
        currentTransport = nil
    }

    private func cancelFailover() {
        FileLogger.debug("Failover cancelled", category: logCategory)
        failoverWorkItem?.cancel()
        failoverWorkItem = nil
    }

    // MARK: - State Machine

    private func transitionTo(_ newState: ConnectionState) {
        let oldState = connectionState
        guard oldState != newState || newState == .active else { return }
        FileLogger.info("State: \(oldState) → \(newState)", category: logCategory)
        connectionState = newState

        switch newState {
        case .idle:
            stopKeepalive()
            cancelHandshakeTimeout()
            cancelRetry()
        case .connecting:
            connectingTransport = currentTransport?.displayName ?? ""
        case .handshaking:
            startHandshakeTimeout()
        case .active:
            cancelFailover()
            cancelHandshakeTimeout()
            lastPongTime = Date()
            lastPingSentTime = nil
            reconnectAttempts = 0
            hasBeenConnected = true
            isConnected = true
            activeTransport = currentTransport?.displayName ?? ""
            startKeepalive()
        }

        if newState != .active {
            isConnected = false
            activeTransport = ""
        }
        if newState != .connecting {
            connectingTransport = ""
        }
    }

    // MARK: - Handshake Timeout

    private func startHandshakeTimeout() {
        cancelHandshakeTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .handshaking else { return }
            FileLogger.error("Handshake timeout", category: logCategory)
            self.appendEntry(
                .deviceDisconnected, "Handshake timeout",
                status: .failed, error: "No response"
            )
            self.handleDisconnect()
        }
        handshakeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handshakeTimeout, execute: workItem)
    }

    private func cancelHandshakeTimeout() {
        handshakeWorkItem?.cancel()
        handshakeWorkItem = nil
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        stopKeepalive()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.connectionState == .active else { return }

            let isPongTimedOut: Bool = {
                guard let sentTime = self.lastPingSentTime,
                    let pongTime = self.lastPongTime,
                    pongTime < sentTime
                else { return false }
                return Date().timeIntervalSince(sentTime) > Self.pongTimeout
            }()

            if isPongTimedOut {
                FileLogger.error("Pong timeout", category: logCategory)
                self.appendEntry(
                    .deviceDisconnected, "Pong timeout",
                    status: .failed, error: "No pong for \(Int(Self.pongTimeout))s"
                )
                self.handleDisconnect()
                return
            }

            FileLogger.debug("Sending ping", category: logCategory)
            self.lastPingSentTime = Date()
            self.send(BuzzelProtocol.createPing())
        }
        pingTimer = timer
        timer.resume()
    }

    private func stopKeepalive() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    // MARK: - Reliable Delivery

    func sendCommand(commandIdentifier: UInt8, tagLengthValueData: Data = Data()) {
        let sequenceNumber = nextSequenceNumber
        nextSequenceNumber &+= 1
        let payload = BuzzelProtocol.createCommand(
            commandIdentifier: commandIdentifier, sequenceNumber: sequenceNumber,
            tagLengthValueData: tagLengthValueData
        )
        retryPayload = payload
        pendingAcknowledgmentSequenceNumber = sequenceNumber
        pendingRetries = 0
        send(payload)
        startRetryTimer()
    }

    private func startRetryTimer() {
        cancelRetry()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingAcknowledgmentSequenceNumber != nil else { return }

            if self.pendingRetries >= 3 {
                FileLogger.error("Command failed after 3 retries", category: logCategory)
                self.handleDisconnect()
                return
            }

            self.pendingRetries += 1
            FileLogger.info(
                "Retry command seq=\(self.pendingAcknowledgmentSequenceNumber ?? 0), attempt=\(self.pendingRetries)",
                category: logCategory
            )
            if let payload = self.retryPayload { self.send(payload) }
            self.startRetryTimer()
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func cancelRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    // MARK: - Activity Log

    func appendEntry(
        _ type: LogEventType, _ message: String,
        direction: LogDirection = .local, status: LogStatus = .success, error: String? = nil
    ) {
        let entry = LogEntry(
            type: type, message: message, direction: direction, status: status, error: error
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.logEntries.append(entry)
            if self.logEntries.count > self.maximumLogEntries { self.logEntries.removeFirst() }
        }
    }

    // MARK: - Connection

    func start() {
        FileLogger.info("TransportManager started", category: logCategory)
        let preference = AppStore.shared.transportMethod
        startFailover(preference: preference)
    }

    func disconnect() {
        FileLogger.info("TransportManager disconnecting (soft)", category: logCategory)
        let wasActive = connectionState == .active || connectionState == .handshaking
        if wasActive {
            send(BuzzelProtocol.createGoodbye())
        }
        transitionTo(.idle)
        cancelFailover()
        if wasActive {
            waitForBleQueueThenStop()
        } else {
            stopCurrentTransport()
        }
    }

    func stop() {
        FileLogger.info("TransportManager stopping (unpair)", category: logCategory)
        let wasActive = connectionState == .active || connectionState == .handshaking
        if wasActive {
            send(BuzzelProtocol.createUnpair())
        }
        hasBeenConnected = false
        transitionTo(.idle)
        cancelFailover()
        AppStore.shared.pairedDevice = nil
        AppStore.shared.save()
        if wasActive {
            waitForBleQueueThenStop()
        } else {
            stopCurrentTransport()
            FileLogger.info("TransportManager stopped", category: logCategory)
        }
    }

    private func waitForBleQueueThenStop(elapsedMilliseconds: Int = 0) {
        let maximumWaitMilliseconds = 2000
        let pollIntervalMilliseconds = 100
        if !ble.hasQueuedWrites || elapsedMilliseconds >= maximumWaitMilliseconds {
            stopCurrentTransport()
            FileLogger.info("TransportManager stopped", category: logCategory)
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(pollIntervalMilliseconds)
        ) { [weak self] in
            self?.waitForBleQueueThenStop(
                elapsedMilliseconds: elapsedMilliseconds + pollIntervalMilliseconds
            )
        }
    }

    func unpair() {
        FileLogger.info("Unpair requested (state=\(connectionState))", category: logCategory)
        let hasLink = connectionState == .active || connectionState == .handshaking
        if hasLink { send(BuzzelProtocol.createUnpair()) }
        hasBeenConnected = false
        reconnectAttempts = 0
        transitionTo(.idle)
        cancelFailover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.stopCurrentTransport()
        }
    }

    private func handleRemoteTermination() {
        hasBeenConnected = false
        transitionTo(.idle)
        cancelFailover()
        stopCurrentTransport()
        AppStore.shared.pairedDevice = nil
        AppStore.shared.save()
    }

    private func handleRemoteSoftDisconnect() {
        transitionTo(.idle)
        stopCurrentTransport()
        startFailover(preference: AppStore.shared.transportMethod)
    }

    private func handleDisconnect() {
        transitionTo(.idle)
        stopCurrentTransport()

        let hasPairingContext =
            pairingSessionIdentifier != nil || AppStore.shared.pairedDevice != nil
        guard hasPairingContext else {
            FileLogger.info("No pairing context — not reconnecting", category: logCategory)
            return
        }

        if hasBeenConnected {
            reconnectAttempts += 1
            if reconnectAttempts > Self.maximumReconnectAttempts {
                FileLogger.info(
                    "Max reconnect attempts reached (\(reconnectAttempts)), stopping",
                    category: logCategory
                )
                reconnectAttempts = 0
                return
            }
            FileLogger.info(
                "Reconnect attempt \(reconnectAttempts)/\(Self.maximumReconnectAttempts)",
                category: logCategory
            )
        }
        startFailover(preference: AppStore.shared.transportMethod)
    }

    // MARK: - Pairing Mode

    func startPairingMode(sessionIdentifier: String, code: String) {
        FileLogger.info("Entering pairing mode", category: logCategory)
        pairingSessionIdentifier = sessionIdentifier
        pairingCode = code
        isPairing = false
        pairingError = nil
        startBothTransports()
    }

    private func startBothTransports() {
        cancelFailover()
        stopCurrentTransport()
        FileLogger.info("Starting both transports for pairing", category: logCategory)
        currentTransport = nil
        transitionTo(.connecting)
        connectingTransport = "BLE + WiFi"
        tcpServer.start(port: BuzzelProtocol.tcpPort)
        ble.start()
    }

    func stopPairingMode() {
        FileLogger.info("Exiting pairing mode", category: logCategory)
        pairingSessionIdentifier = nil
        pairingCode = nil
        isPairing = false
        guard connectionState != .active else { return }
        cancelFailover()
        stopCurrentTransport()
        transitionTo(.idle)
    }

    // MARK: - Pairing

    private func clearPairingContext() {
        pairingCode = nil
        pairingSessionIdentifier = nil
    }

    private func handleIncomingPairingRequest(_ payload: Data) {
        guard let code = BuzzelProtocol.parsePairRequestCode(payload) else {
            FileLogger.error("Pairing request: failed to parse code", category: logCategory)
            return
        }
        FileLogger.info(
            "Pairing request received (code match=\(code == pairingCode))", category: logCategory
        )

        if code == pairingCode {
            send(BuzzelProtocol.createPairResponse(accepted: true))
            appendEntry(.pairingComplete, "Paired with \(deviceName)", direction: .incoming)
            clearPairingContext()
            transitionTo(.active)
            onPairingComplete?(deviceName)
            isPairing = false
            onDeviceReady?()
        } else {
            send(BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01))
            clearPairingContext()
            pairingError = "Invalid pairing code"
            appendEntry(
                .pairingFailed, "Invalid pairing code", direction: .incoming, status: .failed
            )
        }
    }

    // MARK: - Message Handling

    private func send(_ data: Data) {
        guard let transport = currentTransport else {
            FileLogger.debug("Send failed: no active transport", category: logCategory)
            return
        }
        FileLogger.debug(
            "Send \(data.count) bytes via \(transport.rawValue)", category: logCategory)

        switch transport {
        case .ble:
            guard ble.isConnected else {
                FileLogger.debug("BLE send failed: not connected", category: logCategory)
                return
            }
            _ = ble.send(data)
        case .wifi:
            guard tcpServer.isConnected else {
                FileLogger.debug("WiFi send failed: not connected", category: logCategory)
                return
            }
            _ = tcpServer.send(data)
        }
    }

    private func handleIncoming(_ payload: Data) {
        guard let signalIdentifier = BuzzelProtocol.parseSignalIdentifier(payload) else { return }
        FileLogger.debug(
            "Received signal 0x\(String(format: "%02x", signalIdentifier)) (\(payload.count) bytes)",
            category: logCategory
        )

        if connectionState == .active { lastPongTime = Date() }

        switch signalIdentifier {
        case Signal.pairRequest:
            handleIncomingPairingRequest(payload)

        case Signal.pairResponse:
            handleIncomingPairResponse(payload)

        case Signal.ready:
            handleIncomingReady()

        case Signal.ping:
            send(BuzzelProtocol.createPong())

        case Signal.pong:
            lastPongTime = Date()

        case Signal.acknowledgment:
            handleIncomingAcknowledgment(payload)

        case Signal.goodbye:
            appendEntry(.deviceDisconnected, "\(deviceName) disconnected", direction: .incoming)
            handleRemoteSoftDisconnect()

        case Signal.unpair:
            appendEntry(.deviceDisconnected, "\(deviceName) unpaired", direction: .incoming)
            handleRemoteTermination()

        case Signal.command:
            handleIncomingCommand(payload)

        default:
            FileLogger.error(
                "Unknown signal 0x\(String(format: "%02x", signalIdentifier))",
                category: logCategory
            )
        }
    }

    private func handleIncomingPairResponse(_ payload: Data) {
        guard let result = BuzzelProtocol.parsePairResponse(payload) else { return }

        if result.accepted {
            appendEntry(.pairingComplete, "Paired with \(deviceName)", direction: .incoming)
            transitionTo(.active)
            onDeviceReady?()
        } else {
            clearPairingContext()
            appendEntry(.pairingFailed, "Pairing rejected", direction: .incoming, status: .failed)
            handleDisconnect()
        }
    }

    private func handleIncomingReady() {
        appendEntry(.deviceConnected, "\(deviceName) is ready", direction: .incoming)
        guard connectionState == .handshaking else {
            FileLogger.info(
                "Ignoring ready signal in state \(connectionState)", category: logCategory
            )
            return
        }
        transitionTo(.active)
        onDeviceReady?()
    }

    private func handleIncomingAcknowledgment(_ payload: Data) {
        guard let sequenceNumber = BuzzelProtocol.parseAcknowledgmentSequenceNumber(payload),
            sequenceNumber == pendingAcknowledgmentSequenceNumber
        else { return }

        FileLogger.debug("Ack received for seq=\(sequenceNumber)", category: logCategory)
        pendingAcknowledgmentSequenceNumber = nil
        retryPayload = nil
        cancelRetry()
    }

    private func handleIncomingCommand(_ payload: Data) {
        guard let command = BuzzelProtocol.parseCommand(payload) else { return }

        send(BuzzelProtocol.createAcknowledgment(sequenceNumber: command.sequenceNumber))
        handleCommand(command)
    }

    private func handleCommand(_ command: BuzzelProtocol.Command) {
        FileLogger.debug(
            "Command 0x\(String(format: "%02x", command.commandIdentifier)) seq=\(command.sequenceNumber)",
            category: logCategory
        )
    }

    // MARK: - Transport Delegate Helpers

    private func transportDidConnect(_ transport: Transport) {
        let label = transport.displayName
        let isPairingInProgress = pairingSessionIdentifier != nil
        FileLogger.info(
            "\(label) connected (pairing=\(isPairingInProgress))", category: logCategory
        )
        appendEntry(.deviceConnected, "Connected to \(deviceName) via \(label)")
        currentTransport = transport
        transport == .ble ? tcpServer.stop() : ble.stop()
        transitionTo(.handshaking)

        if isPairingInProgress {
            FileLogger.debug("Waiting for pair request from \(deviceName)", category: logCategory)
            isPairing = true
        } else {
            FileLogger.debug("Sending ready signal", category: logCategory)
            send(BuzzelProtocol.createReady())
        }
    }

    private func transportDidDisconnect(_ transport: Transport) {
        let label = transport.displayName
        FileLogger.info(
            "\(label) disconnected (state=\(connectionState), current=\(currentTransport?.rawValue ?? "none"))",
            category: logCategory
        )
        appendEntry(.deviceDisconnected, "\(label) disconnected from \(deviceName)")
        guard currentTransport == transport else { return }
        switch connectionState {
        case .connecting:
            FileLogger.info("Transport connect failed, advancing failover", category: logCategory)
            failoverIndex += 1
            tryNextFailoverStep()
        case .handshaking, .active:
            handleDisconnect()
        case .idle:
            break
        }
    }

    private func transportDidReceiveData(_ data: Data, via transport: Transport) {
        FileLogger.debug(
            "Received \(data.count) bytes via \(transport.rawValue)", category: logCategory
        )
        handleIncoming(data)
    }

    // MARK: - BleCentralDelegate

    func bleDidStartConnecting() {
        DispatchQueue.main.async {
            FileLogger.info(
                "BLE connecting to peripheral — cancelling failover timer", category: logCategory
            )
            self.cancelFailover()
        }
    }

    func bleDidConnect() {
        DispatchQueue.main.async { self.transportDidConnect(.ble) }
    }

    func bleDidDisconnect() {
        DispatchQueue.main.async { self.transportDidDisconnect(.ble) }
    }

    func bleDidReceiveData(_ data: Data) {
        DispatchQueue.main.async { self.transportDidReceiveData(data, via: .ble) }
    }

    // MARK: - TcpServerDelegate

    func tcpServerDidAcceptNewConnection() {
        DispatchQueue.main.async {
            FileLogger.info(
                "TCP new connection accepted — cancelling failover timer", category: logCategory
            )
            self.cancelFailover()
        }
    }

    func tcpServerDidAcceptClient() {
        DispatchQueue.main.async { self.transportDidConnect(.wifi) }
    }

    func tcpServerDidDisconnect() {
        DispatchQueue.main.async { self.transportDidDisconnect(.wifi) }
    }

    func tcpServerDidReceiveData(_ data: Data) {
        DispatchQueue.main.async { self.transportDidReceiveData(data, via: .wifi) }
    }
}
