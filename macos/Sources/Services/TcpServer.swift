import Foundation
import Network
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "TcpServer")

protocol TcpServerDelegate: AnyObject {
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
  var isListening: Bool { listener?.state == .ready }

  func start(port: UInt16) {
    os_log("TCP server starting on port %d", log: log, type: .info, port)
    stop()
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
    do { listener = try NWListener(using: .tcp, on: nwPort) } catch { return }

    listener?.stateUpdateHandler = { _ in }
    listener?.newConnectionHandler = { [weak self] newConn in
      self?.connection?.cancel()
      self?.connection = newConn
      self?.setupConnection(newConn)
    }
    listener?.start(queue: queue)
  }

  func stop() {
    os_log("TCP server stopped", log: log, type: .info)
    connection?.cancel()
    connection = nil
    listener?.cancel()
    listener = nil
  }

  func send(_ data: Data) -> Bool {
    guard let conn = connection, conn.state == .ready else { return false }
    os_log("TCP send: %d bytes", log: log, type: .debug, data.count)
    conn.send(content: FrameCodec.encode(data), completion: .contentProcessed { _ in })
    return true
  }

  private func setupConnection(_ conn: NWConnection) {
    os_log("TCP client connected", log: log, type: .info)
    conn.stateUpdateHandler = { [weak self] state in
      os_log("TCP connection state: %{public}@", log: log, type: .debug, String(describing: state))
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

  private func readBody(length: Int) {
    guard connection != nil, length > 0, length <= FrameCodec.maxPayload else {
      if length <= 0 || length > FrameCodec.maxPayload {
        os_log("Invalid frame size: %d", log: log, type: .error, length)
      }
      return
    }
    os_log("TCP frame: %d bytes", log: log, type: .debug, length)
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
