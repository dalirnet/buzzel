import Foundation

enum FrameCodec {

  static let headerSize = BuzzelProtocol.frameHeader  // 2

  static func encode(
    _ payload: Data, maxPayload: Int = BuzzelProtocol.maxPayload(BuzzelProtocol.wifiMaxFrame)
  ) -> Data {
    let length = min(payload.count, maxPayload)
    var frame = Data(capacity: headerSize + length)
    frame.append(UInt8((length >> 8) & 0xFF))
    frame.append(UInt8(length & 0xFF))
    frame.append(payload.prefix(length))
    return frame
  }

  static func decodeLength(_ header: Data) -> Int {
    Int(header[0]) << 8 | Int(header[1])
  }

  static func extractFrames(
    from buffer: inout Data,
    maxPayload: Int = BuzzelProtocol.maxPayload(BuzzelProtocol.wifiMaxFrame),
    handler: (Data) -> Void
  ) {
    while buffer.count >= headerSize {
      let length = decodeLength(buffer)
      guard length > 0, length <= maxPayload else {
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
