import Foundation
import Network

private let cat = "TcpServer"

protocol TcpServerDelegate: AnyObject {
  func tcpServerDidAcceptNewConnection()
  func tcpServerDidAcceptClient()
  func tcpServerDidDisconnect()
  func tcpServerDidReceiveData(_ data: Data)
}

class TcpServer {

  weak var delegate: TcpServerDelegate?

  private var listener: NWListener?
  private var connection: NWConnection?
  private let queue = DispatchQueue(label: "buzzel.tcpserver")
  private var pendingBody = Data()
  private var pendingBodyLength = 0

  var isConnected: Bool { connection?.state == .ready }

  func start(port: UInt16) {
    FileLogger.info("TCP server starting on port \(port)", category: cat)
    stopInternal()
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
    let tcpOpts = NWProtocolTCP.Options()
    tcpOpts.enableKeepalive = true
    tcpOpts.keepaliveIdle = 5
    tcpOpts.keepaliveInterval = 5
    tcpOpts.keepaliveCount = 2
    let params = NWParameters(tls: nil, tcp: tcpOpts)
    do { listener = try NWListener(using: params, on: nwPort) } catch { return }

    listener?.newConnectionHandler = { [weak self] newConn in
      self?.connection?.cancel()
      self?.connection = newConn
      self?.delegate?.tcpServerDidAcceptNewConnection()
      self?.setupConnection(newConn)
    }
    listener?.start(queue: queue)
  }

  func stop() {
    FileLogger.info("TCP server stopped", category: cat)
    stopInternal()
  }

  private func stopInternal() {
    connection?.cancel()
    connection = nil
    listener?.cancel()
    listener = nil
  }

  func send(_ data: Data) -> Bool {
    guard let conn = connection, conn.state == .ready else { return false }
    FileLogger.debug("TCP send: \(data.count) bytes", category: cat)
    conn.send(content: FrameCodec.encode(data), completion: .contentProcessed { _ in })
    return true
  }

  private func setupConnection(_ conn: NWConnection) {
    FileLogger.info("TCP client connected", category: cat)
    conn.stateUpdateHandler = { [weak self] state in
      FileLogger.debug("TCP connection state: \(state)", category: cat)
      switch state {
      case .ready:
        self?.pendingBody = Data()
        self?.pendingBodyLength = 0
        self?.delegate?.tcpServerDidAcceptClient()
        self?.readFrame()
      case .failed, .cancelled:
        self?.pendingBody = Data()
        self?.pendingBodyLength = 0
        self?.delegate?.tcpServerDidDisconnect()
      default:
        break
      }
    }
    conn.start(queue: queue)
  }

  private func readFrame() {
    guard let conn = connection else { return }
    conn.receive(
      minimumIncompleteLength: FrameCodec.headerSize,
      maximumLength: FrameCodec.headerSize
    ) { [weak self] content, _, isComplete, error in
      guard let data = content, data.count == FrameCodec.headerSize else {
        if isComplete || error != nil { self?.delegate?.tcpServerDidDisconnect() }
        return
      }
      let length = FrameCodec.decodeLength(data)
      self?.readBody(length: length)
    }
  }

  private static let wifiMaxPayload = BuzzelProtocol.maxPayload(BuzzelProtocol.wifiMaxFrame)

  private func readBody(length: Int) {
    guard connection != nil, length > 0, length <= TcpServer.wifiMaxPayload else {
      FileLogger.error("Invalid frame size: \(length)", category: cat)
      delegate?.tcpServerDidDisconnect()
      return
    }
    FileLogger.debug("TCP frame: \(length) bytes", category: cat)
    pendingBody = Data()
    pendingBodyLength = length
    readBodyChunk()
  }

  private func readBodyChunk() {
    guard let conn = connection else { return }
    let remaining = pendingBodyLength - pendingBody.count
    guard remaining > 0 else { return }

    conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
      [weak self] content, _, isComplete, error in
      guard let self = self else { return }
      if let data = content { self.pendingBody.append(data) }

      if self.pendingBody.count == self.pendingBodyLength {
        self.delegate?.tcpServerDidReceiveData(self.pendingBody)
        self.pendingBody = Data()
        self.pendingBodyLength = 0
        if isComplete || error != nil {
          self.delegate?.tcpServerDidDisconnect()
          return
        }
        self.readFrame()
      } else if isComplete || error != nil {
        self.delegate?.tcpServerDidDisconnect()
      } else {
        self.readBodyChunk()
      }
    }
  }
}
