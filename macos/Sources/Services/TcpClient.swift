import Foundation
import Network

protocol TcpClientDelegate: AnyObject {
    func tcpDidConnect()
    func tcpDidDisconnect()
    func tcpDidReceiveData(_ data: Data)
}

class TcpClient {

    weak var delegate: TcpClientDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "buzzel.tcp")

    var isConnected: Bool {
        connection?.state == .ready
    }

    func connect(host: String, port: UInt16) {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.pendingBody = Data()
                self?.pendingBodyLength = 0
                self?.delegate?.tcpDidConnect()
                self?.startReceiving()
            case .failed, .cancelled:
                self?.pendingBody = Data()
                self?.pendingBodyLength = 0
                self?.delegate?.tcpDidDisconnect()
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ data: Data) -> Bool {
        guard let conn = connection, conn.state == .ready else { return false }

        // Frame: 4-byte big-endian length + body
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)

        conn.send(content: frame, completion: .contentProcessed { _ in })
        return true
    }

    private func startReceiving() {
        readFrame()
    }

    private func readFrame() {
        guard let conn = connection else { return }

        // Read 4-byte length prefix
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let data = content, data.count == 4 else {
                if isComplete || error != nil { self?.delegate?.tcpDidDisconnect() }
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self?.readBody(length: Int(length))
        }
    }

    private var pendingBody = Data()
    private var pendingBodyLength = 0

    private func readBody(length: Int) {
        guard let conn = connection, length > 0, length < 1_000_000 else { return }

        pendingBody = Data()
        pendingBodyLength = length
        readBodyChunk(conn: conn)
    }

    private func readBodyChunk(conn: NWConnection) {
        let remaining = pendingBodyLength - pendingBody.count
        guard remaining > 0 else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let data = content {
                self.pendingBody.append(data)
            }
            if self.pendingBody.count == self.pendingBodyLength {
                self.delegate?.tcpDidReceiveData(self.pendingBody)
                self.pendingBody = Data()
                self.pendingBodyLength = 0
                if isComplete || error != nil {
                    self.delegate?.tcpDidDisconnect()
                    return
                }
                self.readFrame()
            } else if isComplete || error != nil {
                self.delegate?.tcpDidDisconnect()
            } else {
                self.readBodyChunk(conn: conn)
            }
        }
    }
}
