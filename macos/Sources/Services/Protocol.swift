import CommonCrypto
import Foundation
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "Protocol")

// MARK: - Signal IDs

enum Signal {
  static let command: UInt8 = 0x00
  static let pairRequest: UInt8 = 0x01
  static let pairResponse: UInt8 = 0x02
  static let ready: UInt8 = 0x03
  static let ping: UInt8 = 0x04
  static let pong: UInt8 = 0x05
  static let ack: UInt8 = 0x06
  static let goodbye: UInt8 = 0x07
  static let unpair: UInt8 = 0x08
}

// MARK: - BLE UUIDs

enum BleUuids {
  static let service = "0000BF01-0000-1000-8000-00805F9B34FB"
  static let dataChar = "0000BF02-0000-1000-8000-00805F9B34FB"
}

// MARK: - Protocol

enum BuzzelProtocol {

  static let tcpPort: UInt16 = 48155
  static let frameHeader = 2
  static let commandHeader = 3  // cmd(1) + seq(2)
  static let attOverhead = 3
  static let tlvMaxValue = 255  // 1-byte Len field
  static let wifiMaxFrame = 4096

  static func maxPayload(_ maxFrame: Int) -> Int { maxFrame - frameHeader }
  static func maxCmdData(_ maxFrame: Int) -> Int { maxPayload(maxFrame) - 1 - commandHeader }
  static func maxTlvData(_ maxFrame: Int) -> Int { min(maxCmdData(maxFrame) - 2, tlvMaxValue) }
  static func maxFrameForMtu(_ mtu: Int) -> Int { mtu - attOverhead }

  // MARK: QR

  static let qrSize = 24
  private static let qrMagic: UInt16 = 0xBC1B

  struct QrPayload {
    let seed: Data
    let host: String
    let prefer: String
  }

  static func generateQrPayload(seed: Data, host: String, prefer: String) -> Data {
    var buf = Data(capacity: qrSize)
    var magic = qrMagic.bigEndian
    buf.append(Data(bytes: &magic, count: 2))
    buf.append(seed)
    // IPv4 host to 4 bytes
    let parts = host.split(separator: ".").compactMap { UInt8($0) }
    if parts.count == 4 {
      buf.append(contentsOf: parts)
    } else {
      buf.append(contentsOf: [0, 0, 0, 0])
    }
    buf.append(prefer == "ble" ? 0x01 : 0x00)
    buf.append(0x00)  // reserved
    return buf
  }

  static func deriveSessionId(_ seed: Data) -> String {
    let hash = sha256(seed)
    let uuid = NSUUID(uuidBytes: [UInt8](hash.prefix(16)))
    return uuid.uuidString
  }

  static func derivePairingCode(_ seed: Data) -> String {
    var input = seed
    input.append("code".data(using: .utf8)!)
    let hash = sha256(input)
    let num = UInt32(hash[0]) << 24 | UInt32(hash[1]) << 16 | UInt32(hash[2]) << 8 | UInt32(hash[3])
    let code = num % 1_000_000
    return String(format: "%06d", code)
  }

  private static func sha256(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
    return Data(hash)
  }

  // MARK: Signals

  static func createPing() -> Data { Data([Signal.ping]) }
  static func createPong() -> Data { Data([Signal.pong]) }
  static func createReady() -> Data { Data([Signal.ready]) }
  static func createGoodbye() -> Data { Data([Signal.goodbye]) }
  static func createUnpair() -> Data { Data([Signal.unpair]) }

  static func createPairRequest(code: String) -> Data {
    var buf = Data(capacity: 7)
    buf.append(Signal.pairRequest)
    let codeBytes = Array(code.utf8.prefix(6))
    buf.append(contentsOf: codeBytes)
    while buf.count < 7 { buf.append(0x30) }  // pad with '0'
    return buf
  }

  static func createPairResponse(accepted: Bool, reason: UInt8 = 0x00) -> Data {
    Data([Signal.pairResponse, accepted ? 0x01 : 0x00, reason])
  }

  static func createAck(seq: UInt16) -> Data {
    var buf = Data(capacity: 3)
    buf.append(Signal.ack)
    buf.append(UInt8(seq >> 8))
    buf.append(UInt8(seq & 0xFF))
    return buf
  }

  static func parseSignalId(_ payload: Data) -> UInt8? {
    guard !payload.isEmpty else { return nil }
    return payload[0]
  }

  static func parsePairRequestCode(_ payload: Data) -> String? {
    guard payload.count >= 7, payload[0] == Signal.pairRequest else { return nil }
    return String(data: payload.subdata(in: 1..<7), encoding: .ascii)
  }

  static func parsePairResponse(_ payload: Data) -> (accepted: Bool, reason: UInt8)? {
    guard payload.count >= 3, payload[0] == Signal.pairResponse else { return nil }
    return (payload[1] == 0x01, payload[2])
  }

  static func parseAckSeq(_ payload: Data) -> UInt16? {
    guard payload.count >= 3, payload[0] == Signal.ack else { return nil }
    return UInt16(payload[1]) << 8 | UInt16(payload[2])
  }

  // MARK: Commands

  struct Command {
    let cmd: UInt8
    let seq: UInt16
    let data: Data
  }

  static func createCommand(
    cmd: UInt8, seq: UInt16, tlvData: Data = Data(), maxTlvData: Int = tlvMaxValue
  ) -> Data {
    let dataLen = min(tlvData.count, maxTlvData)
    var buf = Data(capacity: 1 + commandHeader + dataLen)
    buf.append(Signal.command)
    buf.append(cmd)
    buf.append(UInt8(seq >> 8))
    buf.append(UInt8(seq & 0xFF))
    if dataLen > 0 { buf.append(tlvData.prefix(dataLen)) }
    return buf
  }

  static func parseCommand(_ payload: Data) -> Command? {
    guard payload.count >= 4, payload[0] == Signal.command else { return nil }
    let cmd = payload[1]
    let seq = UInt16(payload[2]) << 8 | UInt16(payload[3])
    let data = payload.count > 4 ? payload.subdata(in: 4..<payload.count) : Data()
    return Command(cmd: cmd, seq: seq, data: data)
  }

  // MARK: QR Parse

  static func parseQr(_ raw: Data) -> QrPayload? {
    guard raw.count == qrSize else { return nil }
    let magic = UInt16(raw[0]) << 8 | UInt16(raw[1])
    guard magic == qrMagic else { return nil }
    let seed = raw.subdata(in: 2..<18)
    let host = "\(raw[18]).\(raw[19]).\(raw[20]).\(raw[21])"
    let prefer = raw[22] == 0x01 ? "ble" : "wifi"
    return QrPayload(seed: seed, host: host, prefer: prefer)
  }

  // MARK: TLV

  struct TlvField {
    let tag: UInt8
    let value: Data
  }

  static func tlvEncode(tag: UInt8, value: Data) -> Data {
    let len = min(value.count, tlvMaxValue)
    var buf = Data(capacity: 2 + len)
    buf.append(tag)
    buf.append(UInt8(len))
    buf.append(value.prefix(len))
    return buf
  }

  static func tlvEncodeString(tag: UInt8, value: String) -> Data {
    tlvEncode(tag: tag, value: value.data(using: .utf8) ?? Data())
  }

  static func tlvEncodeInt(tag: UInt8, value: Int) -> Data {
    var be = UInt32(bitPattern: Int32(value)).bigEndian
    let bytes = Data(bytes: &be, count: 4)
    return tlvEncode(tag: tag, value: bytes)
  }

  static func tlvEncodeByte(tag: UInt8, value: UInt8) -> Data {
    tlvEncode(tag: tag, value: Data([value]))
  }

  static func tlvDecode(_ data: Data) -> [TlvField] {
    var fields = [TlvField]()
    var offset = 0
    while offset + 2 <= data.count {
      let tag = data[offset]
      let len = Int(data[offset + 1])
      offset += 2
      if offset + len > data.count { break }
      let value = data.subdata(in: offset..<(offset + len))
      fields.append(TlvField(tag: tag, value: value))
      offset += len
    }
    return fields
  }

  static func tlvGetString(_ fields: [TlvField], tag: UInt8) -> String? {
    guard let field = fields.first(where: { $0.tag == tag }) else { return nil }
    return String(data: field.value, encoding: .utf8)
  }

  static func tlvGetInt(_ fields: [TlvField], tag: UInt8) -> Int? {
    guard let field = fields.first(where: { $0.tag == tag }), field.value.count >= 4 else {
      return nil
    }
    let val32 =
      UInt32(field.value[0]) << 24 | UInt32(field.value[1]) << 16 | UInt32(field.value[2]) << 8
      | UInt32(field.value[3])
    return Int(Int32(bitPattern: val32))
  }

  static func tlvGetByte(_ fields: [TlvField], tag: UInt8) -> UInt8? {
    guard let field = fields.first(where: { $0.tag == tag }), !field.value.isEmpty else {
      return nil
    }
    return field.value[0]
  }

}
