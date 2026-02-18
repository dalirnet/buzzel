import Combine
import Foundation
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "TransportManager")

class TransportManager: ObservableObject, BleCentralDelegate, TcpServerDelegate {

  static let shared = TransportManager()

  private static let pongTimeout: TimeInterval = 10
  private static let pingInterval: TimeInterval = 30
  private static let failoverTimeout: TimeInterval = 10
  private static let handshakeTimeout: TimeInterval = 30

  enum ConnectionState { case idle, connecting, handshaking, active }

  enum Transport: String { case wifi, ble }

  private struct FailoverStep {
    let transport: Transport
  }

  @Published var connectionState: ConnectionState = .idle
  @Published var hasBeenConnected = false
  @Published var isConnected = false
  @Published var isPairing = false
  @Published var pairingError: String?
  @Published var logEntries: [LogEntry] = []
  @Published var activeTransport: String = ""
  @Published var bleAuthorized = false

  var onPairingComplete: ((String) -> Void)?
  var onDeviceReady: (() -> Void)?

  let ble = BleCentral()
  private let tcpServer = TcpServer()
  private var bleSub: AnyCancellable?
  private let maxLogEntries = 100
  private let deviceName = "Android"

  private var failoverSteps: [FailoverStep] = []
  private var failoverIndex = 0
  private var failoverWork: DispatchWorkItem?
  private var currentTransport: Transport?

  private var pairingSessionId: String?
  private var pairingCode: String?

  // Keepalive
  private var lastPongTime: Date?
  private var pingTimer: DispatchSourceTimer?
  private var pongTimeoutWork: DispatchWorkItem?

  // Handshake timeout
  private var handshakeWork: DispatchWorkItem?

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
  }

  // MARK: - Failover

  private func buildFailoverSteps(prefer: String) {
    let primary: Transport = prefer == "ble" ? .ble : .wifi
    let secondary: Transport = primary == .wifi ? .ble : .wifi
    failoverSteps = [FailoverStep(transport: primary), FailoverStep(transport: secondary)]
    os_log(
      "Failover steps: %{public}@", log: log, type: .debug,
      failoverSteps.map { $0.transport.rawValue }.joined(separator: ", "))
  }

  private func startFailover(prefer: String) {
    os_log("Starting failover, prefer=%{public}@", log: log, type: .info, prefer)
    buildFailoverSteps(prefer: prefer)
    failoverIndex = 0
    tryNextFailoverStep()
  }

  private func tryNextFailoverStep() {
    failoverWork?.cancel()
    guard !failoverSteps.isEmpty else { return }
    let step = failoverSteps[failoverIndex % failoverSteps.count]

    os_log("Failover: trying %{public}@", log: log, type: .debug, step.transport.rawValue)
    stopCurrentTransport()
    transitionTo(.connecting)

    switch step.transport {
    case .wifi:
      currentTransport = .wifi
      tcpServer.start(port: BuzzelProtocol.tcpPort)
    case .ble:
      currentTransport = .ble
      ble.start()
    }

    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.connectionState != .active else { return }
      self.failoverIndex += 1
      self.tryNextFailoverStep()
    }
    failoverWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.failoverTimeout, execute: work)
  }

  private func stopCurrentTransport() {
    os_log("Stopping current transport", log: log, type: .debug)
    tcpServer.stop()
    ble.stop()
    currentTransport = nil
  }

  private func cancelFailover() {
    os_log("Failover cancelled", log: log, type: .debug)
    failoverWork?.cancel()
    failoverWork = nil
  }

  // MARK: - State Machine

  private func transitionTo(_ newState: ConnectionState) {
    let oldState = connectionState
    guard oldState != newState || newState == .active else { return }
    os_log(
      "State: %{public}@ → %{public}@", log: log, type: .info,
      String(describing: oldState), String(describing: newState))
    connectionState = newState

    switch newState {
    case .idle:
      stopKeepalive()
      cancelHandshakeTimeout()
      cancelRetry()
    case .connecting:
      break
    case .handshaking:
      startHandshakeTimeout()
    case .active:
      cancelFailover()
      cancelHandshakeTimeout()
      lastPongTime = Date()
      DispatchQueue.main.async {
        self.hasBeenConnected = true
        self.isConnected = true
        self.activeTransport = self.currentTransport?.rawValue.uppercased() ?? ""
      }
      startKeepalive()
    }

    if newState != .active {
      DispatchQueue.main.async {
        self.isConnected = false
        self.activeTransport = ""
      }
    }
  }

  // MARK: - Handshake Timeout

  private func startHandshakeTimeout() {
    cancelHandshakeTimeout()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.connectionState == .handshaking else { return }
      os_log("Handshake timeout", log: log, type: .error)
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
      // Check pong timeout
      if let last = self.lastPongTime, Date().timeIntervalSince(last) > Self.pongTimeout {
        os_log("Pong timeout", log: log, type: .error)
        self.appendEntry(
          .deviceDisconnected, "Pong timeout",
          status: .failed, error: "No pong for \(Int(Self.pongTimeout))s")
        self.handleDisconnect()
        return
      }
      self.send(BuzzelProtocol.createPing())
    }
    pingTimer = timer
    timer.resume()
  }

  private func stopKeepalive() {
    pingTimer?.cancel()
    pingTimer = nil
    pongTimeoutWork?.cancel()
    pongTimeoutWork = nil
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
        os_log(
          "Retry command seq=%d, attempt=%d", log: log, type: .info,
          self.pendingAckSeq ?? 0, self.pendingRetries)
        if let payload = self.retryPayload { self.send(payload) }
        self.startRetryTimer()
      } else if self.pendingRetries >= 3 {
        os_log("Command failed after 3 retries", log: log, type: .error)
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
    os_log("TransportManager started", log: log, type: .info)
    let prefer = AppStore.shared.transportMethod
    startFailover(prefer: prefer)
  }

  func stop() {
    os_log("TransportManager stopped", log: log, type: .info)
    send(BuzzelProtocol.createGoodbye())
    transitionTo(.idle)
    stopCurrentTransport()
  }

  func unpair() {
    os_log("Unpair requested", log: log, type: .info)
    if connectionState == .active { send(BuzzelProtocol.createUnpair()) }
    hasBeenConnected = false
    transitionTo(.idle)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.stopCurrentTransport()
    }
  }

  private func handleDisconnect() {
    os_log("Handling disconnect", log: log, type: .info)
    transitionTo(.idle)
    stopCurrentTransport()
    startFailover(prefer: AppStore.shared.transportMethod)
  }

  // MARK: - Pairing Mode

  func startPairingMode(sessionId: String, code: String) {
    os_log("Entering pairing mode", log: log, type: .info)
    pairingSessionId = sessionId
    pairingCode = code
    isPairing = false
    pairingError = nil
    startFailover(prefer: AppStore.shared.transportMethod)
  }

  func stopPairingMode() {
    os_log("Exiting pairing mode", log: log, type: .info)
    pairingSessionId = nil
    pairingCode = nil
    isPairing = false
    cancelFailover()
    stopCurrentTransport()
    transitionTo(.idle)
  }

  // MARK: - Pairing

  private func handleIncomingPairingRequest(_ payload: Data) {
    os_log("Pairing request received", log: log, type: .info)
    guard let code = BuzzelProtocol.parsePairRequestCode(payload) else { return }

    if code == pairingCode {
      send(BuzzelProtocol.createPairResponse(accepted: true))
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.appendEntry(.pairingComplete, "Paired with \(self.deviceName)", direction: .incoming)
        self.pairingCode = nil
        self.pairingSessionId = nil
        self.transitionTo(.active)
        self.onPairingComplete?(self.deviceName)
        self.isPairing = false
        self.onDeviceReady?()
      }
    } else {
      send(BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01))
      DispatchQueue.main.async { [weak self] in
        self?.pairingError = "Invalid pairing code"
        self?.appendEntry(
          .pairingFailed, "Invalid pairing code", direction: .incoming, status: .failed)
      }
    }
  }

  // MARK: - Message Handling

  private func send(_ data: Data) {
    guard let transport = currentTransport else { return }
    os_log("Send %d bytes via %{public}@", log: log, type: .debug, data.count, transport.rawValue)

    switch transport {
    case .ble:
      guard ble.isConnected else { return }
      _ = ble.send(data)
    case .wifi:
      guard tcpServer.isConnected else { return }
      _ = tcpServer.send(data)
    }
  }

  private func handleIncoming(_ payload: Data) {
    guard let signalId = BuzzelProtocol.parseSignalId(payload) else { return }
    os_log("Received signal 0x%02x (%d bytes)", log: log, type: .debug, signalId, payload.count)

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
      }

    case Signal.ping:
      send(BuzzelProtocol.createPong())

    case Signal.pong:
      lastPongTime = Date()

    case Signal.ack:
      if let seq = BuzzelProtocol.parseAckSeq(payload), seq == pendingAckSeq {
        os_log("Ack received for seq=%d", log: log, type: .debug, seq)
        pendingAckSeq = nil
        retryPayload = nil
        cancelRetry()
      }

    case Signal.goodbye:
      appendEntry(.deviceDisconnected, "\(deviceName) said goodbye", direction: .incoming)
      handleDisconnect()

    case Signal.unpair:
      appendEntry(.deviceDisconnected, "\(deviceName) unpaired", direction: .incoming)
      transitionTo(.idle)

    case Signal.command:
      if let cmd = BuzzelProtocol.parseCommand(payload) {
        send(BuzzelProtocol.createAck(seq: cmd.seq))
        handleCommand(cmd)
      }

    default:
      os_log("Unknown signal 0x%02x", log: log, type: .error, signalId)
    }
  }

  private func handleCommand(_ cmd: BuzzelProtocol.Command) {
    os_log("Command 0x%02x seq=%d", log: log, type: .debug, cmd.cmd, cmd.seq)
    // All command IDs reserved — dispatch as features are added
  }

  // MARK: - Transport Delegate Helpers

  private func transportDidConnect(_ transport: Transport) {
    let label = transport == .ble ? "BLE" : "WiFi"
    os_log("%{public}@ connected", log: log, type: .info, label)
    appendEntry(.deviceConnected, "Connected to \(deviceName) via \(label)")
    currentTransport = transport
    transitionTo(.handshaking)
    if pairingSessionId == nil { send(BuzzelProtocol.createReady()) }
  }

  private func transportDidDisconnect(_ transport: Transport) {
    let label = transport == .ble ? "BLE" : "WiFi"
    os_log("%{public}@ disconnected", log: log, type: .info, label)
    appendEntry(.deviceDisconnected, "\(label) disconnected from \(deviceName)")
    if connectionState == .active && currentTransport == transport { handleDisconnect() }
  }

  private func transportDidReceiveData(_ data: Data, via transport: Transport) {
    os_log(
      "Received %d bytes via %{public}@", log: log, type: .debug, data.count, transport.rawValue)
    handleIncoming(data)
  }

  // MARK: - BleCentralDelegate

  func bleDidConnect() { transportDidConnect(.ble) }
  func bleDidDisconnect() { transportDidDisconnect(.ble) }
  func bleDidReceiveData(_ data: Data) { transportDidReceiveData(data, via: .ble) }

  // MARK: - TcpServerDelegate

  func tcpServerDidAcceptClient() { transportDidConnect(.wifi) }
  func tcpServerDidDisconnect() { transportDidDisconnect(.wifi) }
  func tcpServerDidReceiveData(_ data: Data) { transportDidReceiveData(data, via: .wifi) }
}
