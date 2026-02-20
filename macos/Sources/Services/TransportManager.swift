import Combine
import Foundation
import Network

private let cat = "TransportManager"

class TransportManager: ObservableObject, BleCentralDelegate, TcpServerDelegate {

  static let shared = TransportManager()

  private static let pongTimeout: TimeInterval = 5
  private static let pingInterval: TimeInterval = 10
  private static let failoverTimeout: TimeInterval = 10
  private static let handshakeTimeout: TimeInterval = 30
  private static let maxReconnectAttempts = 2

  enum ConnectionState { case idle, connecting, handshaking, active }

  enum Transport: String {
    case wifi, ble
    var displayName: String { self == .wifi ? "WiFi" : "BLE" }
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
  private var bleSub: AnyCancellable?
  private var blePoweredOffSub: AnyCancellable?
  private let maxLogEntries = 100
  private let deviceName = "Android"

  private var failoverSteps: [Transport] = []
  private var failoverIndex = 0
  private var failoverWork: DispatchWorkItem?
  private var currentTransport: Transport?

  private var pairingSessionId: String?
  private var pairingCode: String?

  // Keepalive
  private var lastPongTime: Date?
  private var lastPingSentTime: Date?
  private var pingTimer: DispatchSourceTimer?

  // Handshake timeout
  private var handshakeWork: DispatchWorkItem?

  // Reconnect tracking
  private var reconnectAttempts = 0

  // Reliable delivery
  private var nextSeq: UInt16 = 0
  private var pendingAckSeq: UInt16?
  private var pendingRetries = 0
  private var retryPayload: Data?
  private var retryWork: DispatchWorkItem?

  init() {
    ble.delegate = self
    tcpServer.delegate = self
    bleSub = ble.$bluetoothAuthorization
      .receive(on: DispatchQueue.main)
      .map { $0 == .allowedAlways }
      .assign(to: \.bleAuthorized, on: self)
    blePoweredOffSub = ble.$bluetoothPoweredOff
      .receive(on: DispatchQueue.main)
      .assign(to: \.bluetoothPoweredOff, on: self)
  }

  // MARK: - Failover

  private func resolvePreferredTransport(_ prefer: String) -> Transport {
    if prefer == "ble" { return .ble }
    if prefer == "wifi" { return .wifi }
    // "auto": detect WiFi availability
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
    FileLogger.info("Auto-detect: WiFi \(hasWifi ? "available" : "unavailable")", category: cat)
    return hasWifi ? .wifi : .ble
  }

  private func buildFailoverSteps(prefer: String) {
    let primary = resolvePreferredTransport(prefer)
    let secondary: Transport = primary == .wifi ? .ble : .wifi
    failoverSteps = [primary, secondary]
    FileLogger.debug(
      "Failover steps: \(failoverSteps.map { $0.rawValue }.joined(separator: ", "))",
      category: cat)
  }

  private func startFailover(prefer: String) {
    FileLogger.info("Starting failover, prefer=\(prefer)", category: cat)
    buildFailoverSteps(prefer: prefer)
    failoverIndex = 0
    tryNextFailoverStep()
  }

  private func tryNextFailoverStep() {
    failoverWork?.cancel()
    guard !failoverSteps.isEmpty else {
      FileLogger.error("Failover: no steps configured", category: cat)
      return
    }
    let transport = failoverSteps[failoverIndex % failoverSteps.count]

    FileLogger.info(
      "Failover step \(failoverIndex): trying \(transport.rawValue) (timeout=\(Self.failoverTimeout)s)",
      category: cat)
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

    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.connectionState == .connecting else { return }
      FileLogger.info(
        "Failover timeout: \(transport.rawValue) did not connect in \(Self.failoverTimeout)s, advancing",
        category: cat)
      self.failoverIndex += 1
      self.tryNextFailoverStep()
    }
    failoverWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.failoverTimeout, execute: work)
  }

  private func stopCurrentTransport() {
    FileLogger.debug("Stopping current transport", category: cat)
    tcpServer.stop()
    ble.stop()
    currentTransport = nil
  }

  private func cancelFailover() {
    FileLogger.debug("Failover cancelled", category: cat)
    failoverWork?.cancel()
    failoverWork = nil
  }

  // MARK: - State Machine

  private func transitionTo(_ newState: ConnectionState) {
    let oldState = connectionState
    guard oldState != newState || newState == .active else { return }
    FileLogger.info("State: \(oldState) → \(newState)", category: cat)
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
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.connectionState == .handshaking else { return }
      FileLogger.error("Handshake timeout", category: cat)
      self.appendEntry(
        .deviceDisconnected, "Handshake timeout",
        status: .failed, error: "No response")
      self.handleDisconnect()
    }
    handshakeWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.handshakeTimeout, execute: work)
  }

  private func cancelHandshakeTimeout() {
    handshakeWork?.cancel()
    handshakeWork = nil
  }

  // MARK: - Keepalive

  private func startKeepalive() {
    stopKeepalive()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
    timer.setEventHandler { [weak self] in
      guard let self = self, self.connectionState == .active else { return }
      // Only timeout if we sent a ping and got no pong back within pongTimeout.
      if let sent = self.lastPingSentTime,
        let pong = self.lastPongTime, pong < sent,
        Date().timeIntervalSince(sent) > Self.pongTimeout
      {
        FileLogger.error("Pong timeout", category: cat)
        self.appendEntry(
          .deviceDisconnected, "Pong timeout",
          status: .failed, error: "No pong for \(Int(Self.pongTimeout))s")
        self.handleDisconnect()
        return
      }
      FileLogger.debug("Sending ping", category: cat)
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

  func sendCommand(cmd: UInt8, tlvData: Data = Data()) {
    let seq = nextSeq
    nextSeq &+= 1
    let payload = BuzzelProtocol.createCommand(cmd: cmd, seq: seq, tlvData: tlvData)
    retryPayload = payload
    pendingAckSeq = seq
    pendingRetries = 0
    send(payload)
    startRetryTimer()
  }

  private func startRetryTimer() {
    cancelRetry()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      if self.pendingAckSeq != nil && self.pendingRetries < 3 {
        self.pendingRetries += 1
        FileLogger.info(
          "Retry command seq=\(self.pendingAckSeq ?? 0), attempt=\(self.pendingRetries)",
          category: cat)
        if let payload = self.retryPayload { self.send(payload) }
        self.startRetryTimer()
      } else if self.pendingRetries >= 3 {
        FileLogger.error("Command failed after 3 retries", category: cat)
        self.handleDisconnect()
      }
    }
    retryWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
  }

  private func cancelRetry() {
    retryWork?.cancel()
    retryWork = nil
  }

  // MARK: - Activity Log

  func appendEntry(
    _ type: LogEventType, _ message: String,
    direction: LogDirection = .local, status: LogStatus = .success, error: String? = nil
  ) {
    let entry = LogEntry(
      type: type, message: message, direction: direction, status: status, error: error)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.logEntries.append(entry)
      if self.logEntries.count > self.maxLogEntries { self.logEntries.removeFirst() }
    }
  }

  // MARK: - Connection

  func start() {
    FileLogger.info("TransportManager started", category: cat)
    let prefer = AppStore.shared.transportMethod
    startFailover(prefer: prefer)
  }

  func stop() {
    FileLogger.info("TransportManager stopping", category: cat)
    let wasActive = connectionState == .active || connectionState == .handshaking
    if wasActive {
      send(BuzzelProtocol.createGoodbye())
    }
    hasBeenConnected = false
    transitionTo(.idle)
    cancelFailover()
    AppStore.shared.pairedDevice = nil
    AppStore.shared.save()
    if wasActive {
      // Delay teardown so goodbye has time to be delivered
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.stopCurrentTransport()
        FileLogger.info("TransportManager stopped", category: cat)
      }
    } else {
      stopCurrentTransport()
      FileLogger.info("TransportManager stopped", category: cat)
    }
  }

  func unpair() {
    FileLogger.info("Unpair requested (state=\(connectionState))", category: cat)
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

  private func handleDisconnect() {
    transitionTo(.idle)
    stopCurrentTransport()

    // Only reconnect when we have an active session (pairing in progress or paired device exists)
    let hasPairingContext = pairingSessionId != nil || AppStore.shared.pairedDevice != nil
    guard hasPairingContext else {
      FileLogger.info("No pairing context — not reconnecting", category: cat)
      return
    }

    if hasBeenConnected {
      reconnectAttempts += 1
      if reconnectAttempts > Self.maxReconnectAttempts {
        FileLogger.info(
          "Max reconnect attempts reached (\(reconnectAttempts)), stopping",
          category: cat)
        reconnectAttempts = 0
        return
      }
      FileLogger.info(
        "Reconnect attempt \(reconnectAttempts)/\(Self.maxReconnectAttempts)",
        category: cat)
    }
    startFailover(prefer: AppStore.shared.transportMethod)
  }

  // MARK: - Pairing Mode

  func startPairingMode(sessionId: String, code: String) {
    FileLogger.info("Entering pairing mode", category: cat)
    pairingSessionId = sessionId
    pairingCode = code
    isPairing = false
    pairingError = nil
    startBothTransports()
  }

  /// During pairing, run BLE scanning and TCP server simultaneously so
  /// whichever transport the Android device uses connects immediately.
  private func startBothTransports() {
    cancelFailover()
    stopCurrentTransport()
    FileLogger.info("Starting both transports for pairing", category: cat)
    transitionTo(.connecting)
    currentTransport = nil
    tcpServer.start(port: BuzzelProtocol.tcpPort)
    ble.start()
  }

  func stopPairingMode() {
    FileLogger.info("Exiting pairing mode", category: cat)
    pairingSessionId = nil
    pairingCode = nil
    isPairing = false
    // If pairing succeeded the state is already .active — don't tear down the live connection.
    if connectionState != .active {
      cancelFailover()
      stopCurrentTransport()
      transitionTo(.idle)
    }
  }

  // MARK: - Pairing

  private func handleIncomingPairingRequest(_ payload: Data) {
    guard let code = BuzzelProtocol.parsePairRequestCode(payload) else {
      FileLogger.error("Pairing request: failed to parse code", category: cat)
      return
    }
    FileLogger.info("Pairing request received (code match=\(code == pairingCode))", category: cat)

    if code == pairingCode {
      send(BuzzelProtocol.createPairResponse(accepted: true))
      appendEntry(.pairingComplete, "Paired with \(deviceName)", direction: .incoming)
      pairingCode = nil
      pairingSessionId = nil
      transitionTo(.active)
      onPairingComplete?(deviceName)
      isPairing = false
      onDeviceReady?()
    } else {
      send(BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01))
      pairingError = "Invalid pairing code"
      appendEntry(
        .pairingFailed, "Invalid pairing code", direction: .incoming, status: .failed)
    }
  }

  // MARK: - Message Handling

  private func send(_ data: Data) {
    guard let transport = currentTransport else {
      FileLogger.debug("Send failed: no active transport", category: cat)
      return
    }
    FileLogger.debug("Send \(data.count) bytes via \(transport.rawValue)", category: cat)

    switch transport {
    case .ble:
      guard ble.isConnected else {
        FileLogger.debug("BLE send failed: not connected", category: cat)
        return
      }
      _ = ble.send(data)
    case .wifi:
      guard tcpServer.isConnected else {
        FileLogger.debug("WiFi send failed: not connected", category: cat)
        return
      }
      _ = tcpServer.send(data)
    }
  }

  private func handleIncoming(_ payload: Data) {
    guard let signalId = BuzzelProtocol.parseSignalId(payload) else { return }
    FileLogger.debug(
      "Received signal 0x\(String(format: "%02x", signalId)) (\(payload.count) bytes)",
      category: cat)

    if connectionState == .active { lastPongTime = Date() }

    switch signalId {
    case Signal.pairRequest:
      handleIncomingPairingRequest(payload)

    case Signal.pairResponse:
      if let result = BuzzelProtocol.parsePairResponse(payload) {
        if result.accepted {
          appendEntry(.pairingComplete, "Paired with \(deviceName)", direction: .incoming)
          transitionTo(.active)
          onDeviceReady?()
        } else {
          appendEntry(.pairingFailed, "Pairing rejected", direction: .incoming, status: .failed)
          handleDisconnect()
        }
      }

    case Signal.ready:
      appendEntry(.deviceConnected, "\(deviceName) is ready", direction: .incoming)
      if connectionState == .handshaking {
        transitionTo(.active)
        onDeviceReady?()
      } else {
        FileLogger.info(
          "Ignoring ready signal in state \(connectionState)", category: cat)
      }

    case Signal.ping:
      send(BuzzelProtocol.createPong())

    case Signal.pong:
      lastPongTime = Date()

    case Signal.ack:
      if let seq = BuzzelProtocol.parseAckSeq(payload), seq == pendingAckSeq {
        FileLogger.debug("Ack received for seq=\(seq)", category: cat)
        pendingAckSeq = nil
        retryPayload = nil
        cancelRetry()
      }

    case Signal.goodbye:
      appendEntry(.deviceDisconnected, "\(deviceName) said goodbye", direction: .incoming)
      handleRemoteTermination()

    case Signal.unpair:
      appendEntry(.deviceDisconnected, "\(deviceName) unpaired", direction: .incoming)
      handleRemoteTermination()

    case Signal.command:
      if let cmd = BuzzelProtocol.parseCommand(payload) {
        send(BuzzelProtocol.createAck(seq: cmd.seq))
        handleCommand(cmd)
      }

    default:
      FileLogger.error("Unknown signal 0x\(String(format: "%02x", signalId))", category: cat)
    }
  }

  private func handleCommand(_ cmd: BuzzelProtocol.Command) {
    FileLogger.debug(
      "Command 0x\(String(format: "%02x", cmd.cmd)) seq=\(cmd.seq)", category: cat)
    // All command IDs reserved — dispatch as features are added
  }

  // MARK: - Transport Delegate Helpers

  private func transportDidConnect(_ transport: Transport) {
    let label = transport == .ble ? "BLE" : "WiFi"
    let isPairing = pairingSessionId != nil
    FileLogger.info(
      "\(label) connected (pairing=\(isPairing))", category: cat)
    appendEntry(.deviceConnected, "Connected to \(deviceName) via \(label)")
    currentTransport = transport
    // Stop the other transport now that we have a connection
    switch transport {
    case .ble: tcpServer.stop()
    case .wifi: ble.stop()
    }
    transitionTo(.handshaking)
    if !isPairing {
      FileLogger.debug("Sending ready signal", category: cat)
      send(BuzzelProtocol.createReady())
    } else {
      FileLogger.debug("Waiting for pair request from \(deviceName)", category: cat)
      self.isPairing = true
    }
  }

  private func transportDidDisconnect(_ transport: Transport) {
    let label = transport == .ble ? "BLE" : "WiFi"
    FileLogger.info(
      "\(label) disconnected (state=\(connectionState), current=\(currentTransport?.rawValue ?? "none"))",
      category: cat)
    appendEntry(.deviceDisconnected, "\(label) disconnected from \(deviceName)")
    guard currentTransport == transport else { return }
    switch connectionState {
    case .connecting:
      // Transport failed to connect — advance to next failover step
      FileLogger.info("Transport connect failed, advancing failover", category: cat)
      failoverIndex += 1
      tryNextFailoverStep()
    case .handshaking, .active:
      handleDisconnect()
    case .idle:
      break
    }
  }

  private func transportDidReceiveData(_ data: Data, via transport: Transport) {
    FileLogger.debug("Received \(data.count) bytes via \(transport.rawValue)", category: cat)
    handleIncoming(data)
  }

  // MARK: - BleCentralDelegate

  func bleDidStartConnecting() {
    DispatchQueue.main.async {
      FileLogger.info("BLE connecting to peripheral — cancelling failover timer", category: cat)
      self.cancelFailover()
    }
  }
  func bleDidConnect() { DispatchQueue.main.async { self.transportDidConnect(.ble) } }
  func bleDidDisconnect() { DispatchQueue.main.async { self.transportDidDisconnect(.ble) } }
  func bleDidReceiveData(_ data: Data) { DispatchQueue.main.async { self.transportDidReceiveData(data, via: .ble) } }

  // MARK: - TcpServerDelegate

  func tcpServerDidAcceptNewConnection() {
    // Cancel failover as soon as a TCP client connects (before NWConnection reaches .ready).
    // The connection will transition to .ready shortly and fire tcpServerDidAcceptClient.
    DispatchQueue.main.async {
      FileLogger.info("TCP new connection accepted — cancelling failover timer", category: cat)
      self.cancelFailover()
    }
  }
  func tcpServerDidAcceptClient() { DispatchQueue.main.async { self.transportDidConnect(.wifi) } }
  func tcpServerDidDisconnect() { DispatchQueue.main.async { self.transportDidDisconnect(.wifi) } }
  func tcpServerDidReceiveData(_ data: Data) { DispatchQueue.main.async { self.transportDidReceiveData(data, via: .wifi) } }
}
