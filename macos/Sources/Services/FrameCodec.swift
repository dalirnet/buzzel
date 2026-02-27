import Foundation

enum FrameCodec {
    static let headerSize = BuzzelProtocol.frameHeaderSize

    static func encode(
        _ payload: Data,
        maximumPayloadSize: Int = BuzzelProtocol.maximumPayloadSize(
            BuzzelProtocol.wifiMaximumFrameSize)
    ) -> Data {
        let length = min(payload.count, maximumPayloadSize)
        var frame = Data(capacity: headerSize + length)
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(payload.prefix(length))
        return frame
    }

    static func decodeLength(_ header: Data) -> Int {
        let highByte = Int(header[0]) << 8
        let lowByte = Int(header[1])
        return highByte | lowByte
    }

    static func extractFrames(
        from buffer: inout Data,
        maximumPayloadSize: Int = BuzzelProtocol.maximumPayloadSize(
            BuzzelProtocol.wifiMaximumFrameSize
        ),
        handler: (Data) -> Void
    ) {
        while buffer.count >= headerSize {
            let length = decodeLength(buffer)
            guard length > 0, length <= maximumPayloadSize else {
                buffer = Data()
                return
            }
            let totalNeeded = headerSize + length
            if buffer.count < totalNeeded { break }
            handler(buffer.subdata(in: headerSize..<totalNeeded))
            buffer = Data(buffer.suffix(from: totalNeeded))
        }
    }
}
