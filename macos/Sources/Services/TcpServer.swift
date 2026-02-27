import Foundation
import Network

private let logCategory = "TcpServer"

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

    var isConnected: Bool {
        connection?.state == .ready
    }

    func start(port: UInt16) {
        FileLogger.info("TCP server starting on port \(port)", category: logCategory)
        stopInternal()
        guard let networkPort = NWEndpoint.Port(rawValue: port) else { return }
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 5
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 2
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        do { listener = try NWListener(using: parameters, on: networkPort) } catch { return }

        listener?.newConnectionHandler = { [weak self] newConnection in
            self?.connection?.cancel()
            self?.connection = newConnection
            self?.delegate?.tcpServerDidAcceptNewConnection()
            self?.setupConnection(newConnection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        FileLogger.info("TCP server stopped", category: logCategory)
        stopInternal()
    }

    private func stopInternal() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    func send(_ data: Data) -> Bool {
        guard let activeConnection = connection, activeConnection.state == .ready else {
            return false
        }
        FileLogger.debug("TCP send: \(data.count) bytes", category: logCategory)
        activeConnection.send(
            content: FrameCodec.encode(data), completion: .contentProcessed { _ in }
        )
        return true
    }

    private func setupConnection(_ connection: NWConnection) {
        FileLogger.info("TCP client connected", category: logCategory)
        connection.stateUpdateHandler = { [weak self] state in
            FileLogger.debug("TCP connection state: \(state)", category: logCategory)
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
        connection.start(queue: queue)
    }

    private func readFrame() {
        guard let activeConnection = connection else { return }
        activeConnection.receive(
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

    private static let wifiMaximumPayloadSize = BuzzelProtocol.maximumPayloadSize(
        BuzzelProtocol.wifiMaximumFrameSize
    )

    private func readBody(length: Int) {
        guard connection != nil, length > 0, length <= TcpServer.wifiMaximumPayloadSize else {
            FileLogger.error("Invalid frame size: \(length)", category: logCategory)
            delegate?.tcpServerDidDisconnect()
            return
        }
        FileLogger.debug("TCP frame: \(length) bytes", category: logCategory)
        pendingBody = Data()
        pendingBodyLength = length
        readBodyChunk()
    }

    private func readBodyChunk() {
        guard let activeConnection = connection else { return }
        let remaining = pendingBodyLength - pendingBody.count
        guard remaining > 0 else { return }

        activeConnection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
            [weak self] content, _, isComplete, error in
            self?.handleReceivedBodyChunk(content: content, isComplete: isComplete, error: error)
        }
    }

    private func handleReceivedBodyChunk(content: Data?, isComplete: Bool, error: NWError?) {
        if let content { pendingBody.append(content) }

        let isBodyComplete = pendingBody.count == pendingBodyLength
        let connectionEnded = isComplete || error != nil

        if isBodyComplete {
            delegate?.tcpServerDidReceiveData(pendingBody)
            pendingBody = Data()
            pendingBodyLength = 0
            connectionEnded ? delegate?.tcpServerDidDisconnect() : readFrame()
        } else if connectionEnded {
            delegate?.tcpServerDidDisconnect()
        } else {
            readBodyChunk()
        }
    }
}
