import CommonCrypto
import Foundation
import os.log

private let log = OSLog(subsystem: "com.buzzel", category: "Protocol")

// MARK: - Signal Identifiers

enum Signal {
    static let command: UInt8 = 0x00
    static let pairRequest: UInt8 = 0x01
    static let pairResponse: UInt8 = 0x02
    static let ready: UInt8 = 0x03
    static let ping: UInt8 = 0x04
    static let pong: UInt8 = 0x05
    static let acknowledgment: UInt8 = 0x06
    static let goodbye: UInt8 = 0x07
    static let unpair: UInt8 = 0x08
}

// MARK: - Bluetooth Low Energy UUIDs

enum BluetoothServiceUUIDs {
    static let service = "0000BF01-0000-1000-8000-00805F9B34FB"
    static let dataCharacteristic = "0000BF02-0000-1000-8000-00805F9B34FB"
}

// MARK: - Protocol

enum BuzzelProtocol {
    static let tcpPort: UInt16 = 48155
    static let frameHeaderSize = 2
    static let commandHeaderSize = 3  // sequenceNumber(2) + commandIdentifier(1)
    static let attributeProtocolOverhead = 3
    static let tagLengthValueMaximumValueSize = 255  // 1-byte length field
    static let wifiMaximumFrameSize = 4096

    static func maximumPayloadSize(_ maximumFrameSize: Int) -> Int {
        maximumFrameSize - frameHeaderSize
    }

    static func maximumCommandDataSize(_ maximumFrameSize: Int) -> Int {
        maximumPayloadSize(maximumFrameSize) - 1 - commandHeaderSize
    }

    static func maximumTagLengthValueDataSize(_ maximumFrameSize: Int) -> Int {
        min(maximumCommandDataSize(maximumFrameSize) - 2, tagLengthValueMaximumValueSize)
    }

    static func maximumFrameSizeForMaximumTransmissionUnit(_ maximumTransmissionUnit: Int) -> Int {
        maximumTransmissionUnit - attributeProtocolOverhead
    }

    // MARK: QR Code

    static let qrCodePayloadSize = 24
    private static let qrCodeMagicNumber: UInt16 = 0xBC1B

    struct QRCodePayload {
        let seed: Data
        let host: String
        let preferredTransport: String
    }

    static func generateQRCodePayload(seed: Data, host: String, preferredTransport: String) -> Data {
        var buffer = Data(capacity: qrCodePayloadSize)
        var magicNumber = qrCodeMagicNumber.bigEndian
        buffer.append(Data(bytes: &magicNumber, count: 2))
        buffer.append(seed)
        let hostParts = host.split(separator: ".").compactMap { UInt8($0) }
        if hostParts.count == 4 {
            buffer.append(contentsOf: hostParts)
        } else {
            buffer.append(contentsOf: [0, 0, 0, 0])
        }
        buffer.append(preferredTransport == "ble" ? 0x01 : 0x00)
        buffer.append(0x00)  // reserved
        return buffer
    }

    static func deriveSessionIdentifier(_ seed: Data) -> String {
        let hash = computeSHA256(seed)
        let uuid = NSUUID(uuidBytes: [UInt8](hash.prefix(16)))
        return uuid.uuidString
    }

    static func derivePairingCode(_ seed: Data) -> String {
        var input = seed
        input.append("code".data(using: .utf8)!)
        let hash = computeSHA256(input)
        let byte0 = UInt32(hash[0]) << 24
        let byte1 = UInt32(hash[1]) << 16
        let byte2 = UInt32(hash[2]) << 8
        let byte3 = UInt32(hash[3])
        let numericValue = byte0 | byte1 | byte2 | byte3
        let code = numericValue % 1_000_000
        return String(format: "%06d", code)
    }

    private static func computeSHA256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash)
    }

    // MARK: Signals

    static func createPing() -> Data {
        Data([Signal.ping])
    }

    static func createPong() -> Data {
        Data([Signal.pong])
    }

    static func createReady() -> Data {
        Data([Signal.ready])
    }

    static func createGoodbye() -> Data {
        Data([Signal.goodbye])
    }

    static func createUnpair() -> Data {
        Data([Signal.unpair])
    }

    static func createPairRequest(code: String) -> Data {
        var buffer = Data(capacity: 7)
        buffer.append(Signal.pairRequest)
        let codeBytes = Array(code.utf8.prefix(6))
        buffer.append(contentsOf: codeBytes)
        let paddingNeeded = 7 - buffer.count
        if paddingNeeded > 0 { buffer.append(contentsOf: [UInt8](repeating: 0x30, count: paddingNeeded)) }
        return buffer
    }

    static func createPairResponse(accepted: Bool, reason: UInt8 = 0x00) -> Data {
        Data([Signal.pairResponse, accepted ? 0x01 : 0x00, reason])
    }

    static func createAcknowledgment(sequenceNumber: UInt16) -> Data {
        var buffer = Data(capacity: 3)
        buffer.append(Signal.acknowledgment)
        buffer.append(UInt8(sequenceNumber >> 8))
        buffer.append(UInt8(sequenceNumber & 0xFF))
        return buffer
    }

    static func parseSignalIdentifier(_ payload: Data) -> UInt8? {
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

    static func parseAcknowledgmentSequenceNumber(_ payload: Data) -> UInt16? {
        guard payload.count >= 3, payload[0] == Signal.acknowledgment else { return nil }
        let highByte = UInt16(payload[1]) << 8
        let lowByte = UInt16(payload[2])
        return highByte | lowByte
    }

    // MARK: Commands

    struct Command {
        let commandIdentifier: UInt8
        let sequenceNumber: UInt16
        let data: Data
    }

    static func createCommand(
        commandIdentifier: UInt8, sequenceNumber: UInt16, tagLengthValueData: Data = Data(),
        maximumTagLengthValueDataSize: Int = tagLengthValueMaximumValueSize
    ) -> Data {
        let dataLength = min(tagLengthValueData.count, maximumTagLengthValueDataSize)
        var buffer = Data(capacity: 1 + commandHeaderSize + dataLength)
        buffer.append(Signal.command)
        buffer.append(UInt8(sequenceNumber >> 8))
        buffer.append(UInt8(sequenceNumber & 0xFF))
        buffer.append(commandIdentifier)
        if dataLength > 0 { buffer.append(tagLengthValueData.prefix(dataLength)) }
        return buffer
    }

    static func parseCommand(_ payload: Data) -> Command? {
        guard payload.count >= 4, payload[0] == Signal.command else { return nil }
        let sequenceHighByte = UInt16(payload[1]) << 8
        let sequenceLowByte = UInt16(payload[2])
        let sequenceNumber = sequenceHighByte | sequenceLowByte
        let commandIdentifier = payload[3]
        let data = payload.count > 4 ? payload.subdata(in: 4..<payload.count) : Data()
        return Command(
            commandIdentifier: commandIdentifier, sequenceNumber: sequenceNumber, data: data
        )
    }

    // MARK: QR Code Parsing

    static func parseQRCodePayload(_ rawData: Data) -> QRCodePayload? {
        guard rawData.count == qrCodePayloadSize else { return nil }
        let magicHighByte = UInt16(rawData[0]) << 8
        let magicLowByte = UInt16(rawData[1])
        let magicNumber = magicHighByte | magicLowByte
        guard magicNumber == qrCodeMagicNumber else { return nil }
        let seed = rawData.subdata(in: 2..<18)
        let host = "\(rawData[18]).\(rawData[19]).\(rawData[20]).\(rawData[21])"
        let preferredTransport = rawData[22] == 0x01 ? "ble" : "wifi"
        return QRCodePayload(seed: seed, host: host, preferredTransport: preferredTransport)
    }

    // MARK: Tag-Length-Value Encoding

    struct TagLengthValueField {
        let tag: UInt8
        let value: Data
    }

    static func encodeTagLengthValue(tag: UInt8, value: Data) -> Data {
        let length = min(value.count, tagLengthValueMaximumValueSize)
        var buffer = Data(capacity: 2 + length)
        buffer.append(tag)
        buffer.append(UInt8(length))
        buffer.append(value.prefix(length))
        return buffer
    }

    static func encodeTagLengthValueString(tag: UInt8, value: String) -> Data {
        encodeTagLengthValue(tag: tag, value: value.data(using: .utf8) ?? Data())
    }

    static func encodeTagLengthValueInteger(tag: UInt8, value: Int) -> Data {
        var bigEndianValue = UInt32(bitPattern: Int32(value)).bigEndian
        let bytes = Data(bytes: &bigEndianValue, count: 4)
        return encodeTagLengthValue(tag: tag, value: bytes)
    }

    static func encodeTagLengthValueByte(tag: UInt8, value: UInt8) -> Data {
        encodeTagLengthValue(tag: tag, value: Data([value]))
    }

    static func decodeTagLengthValue(_ data: Data) -> [TagLengthValueField] {
        var fields: [TagLengthValueField] = []
        var offset = 0
        while offset + 2 <= data.count {
            let tag = data[offset]
            let length = Int(data[offset + 1])
            offset += 2
            if offset + length > data.count { break }
            let value = data.subdata(in: offset..<(offset + length))
            fields.append(TagLengthValueField(tag: tag, value: value))
            offset += length
        }
        return fields
    }

    static func getTagLengthValueString(
        _ fields: [TagLengthValueField], tag: UInt8
    ) -> String? {
        guard let field = fields.first(where: { $0.tag == tag }) else { return nil }
        return String(data: field.value, encoding: .utf8)
    }

    static func getTagLengthValueInteger(
        _ fields: [TagLengthValueField], tag: UInt8
    ) -> Int? {
        guard let field = fields.first(where: { $0.tag == tag }), field.value.count >= 4 else {
            return nil
        }
        let byte0 = UInt32(field.value[0]) << 24
        let byte1 = UInt32(field.value[1]) << 16
        let byte2 = UInt32(field.value[2]) << 8
        let byte3 = UInt32(field.value[3])
        let rawValue = byte0 | byte1 | byte2 | byte3
        return Int(Int32(bitPattern: rawValue))
    }

    static func getTagLengthValueByte(
        _ fields: [TagLengthValueField], tag: UInt8
    ) -> UInt8? {
        guard let field = fields.first(where: { $0.tag == tag }), !field.value.isEmpty else {
            return nil
        }
        return field.value[0]
    }
}
