import CommonCrypto
import Foundation

// Simple test runner — no XCTest needed

var passed = 0
var failed = 0
var errors: [String] = []

func assert(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        errors.append("  FAIL: \(name) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ name: String, file: String = #file, line: Int = #line
) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        errors.append("  FAIL: \(name) — expected \(expected), got \(actual) (\(file):\(line))")
    }
}

func assertNil<T>(_ value: T?, _ name: String, file: String = #file, line: Int = #line) {
    if value == nil {
        passed += 1
    } else {
        failed += 1
        errors.append("  FAIL: \(name) — expected nil, got \(value!) (\(file):\(line))")
    }
}

func assertNotNil<T>(_ value: T?, _ name: String, file: String = #file, line: Int = #line) {
    if value != nil {
        passed += 1
    } else {
        failed += 1
        errors.append("  FAIL: \(name) — expected non-nil (\(file):\(line))")
    }
}

/// Fixed seed: 0x00..0x0F
let seed = Data(0...15)

// Cross-platform expected values (verified with Python SHA256)
let expectedSessionIdentifier = "BE45CB26-05BF-36BE-BDE6-84841A28F0FD"
let expectedPairingCode = "279084"

func buildQRCodePayload(seed: Data, host: String, preferredTransport: String) -> Data {
    var buffer = Data(capacity: 24)
    buffer.append(0xBC)
    buffer.append(0x1B)
    buffer.append(seed)
    let parts = host.split(separator: ".").compactMap { UInt8($0) }
    buffer.append(contentsOf: parts)
    buffer.append(preferredTransport == "ble" ? 0x01 : 0x00)
    buffer.append(0x00)
    return buffer
}

// MARK: - QR Code

func testQRCode() {
    // Valid parse
    let qrCodeData = buildQRCodePayload(
        seed: seed, host: "192.168.1.100", preferredTransport: "wifi"
    )
    let result = BuzzelProtocol.parseQRCodePayload(qrCodeData)
    assertNotNil(result, "parseQRCodePayload valid")
    assertEqual(result!.seed, seed, "parseQRCodePayload seed")
    assertEqual(result!.host, "192.168.1.100", "parseQRCodePayload host")
    assertEqual(result!.preferredTransport, "wifi", "parseQRCodePayload preferredTransport")

    // BLE preferred transport
    let bleQRCodeData = buildQRCodePayload(
        seed: seed, host: "10.0.0.1", preferredTransport: "ble"
    )
    let bleResult = BuzzelProtocol.parseQRCodePayload(bleQRCodeData)
    assertNotNil(bleResult, "parseQRCodePayload ble")
    assertEqual(bleResult!.preferredTransport, "ble", "parseQRCodePayload ble preferredTransport")

    // Wrong size
    assertNil(
        BuzzelProtocol.parseQRCodePayload(Data(count: 10)), "parseQRCodePayload wrong size 10")
    assertNil(
        BuzzelProtocol.parseQRCodePayload(Data(count: 25)), "parseQRCodePayload wrong size 25")

    // Wrong magic number
    var badData = buildQRCodePayload(
        seed: seed, host: "1.2.3.4", preferredTransport: "wifi"
    )
    badData[0] = 0xFF
    assertNil(BuzzelProtocol.parseQRCodePayload(badData), "parseQRCodePayload wrong magic")

    // Generate + parse round-trip
    let generated = BuzzelProtocol.generateQRCodePayload(
        seed: seed, host: "10.0.1.50", preferredTransport: "ble"
    )
    assertEqual(generated.count, 24, "generateQRCodePayload size")
    let parsed = BuzzelProtocol.parseQRCodePayload(generated)
    assertNotNil(parsed, "generateQRCodePayload round-trip")
    assertEqual(parsed!.seed, seed, "generateQRCodePayload seed")
    assertEqual(parsed!.host, "10.0.1.50", "generateQRCodePayload host")
    assertEqual(parsed!.preferredTransport, "ble", "generateQRCodePayload preferredTransport")
}

// MARK: - Seed Derivation

func testSeedDerivation() {
    assertEqual(
        BuzzelProtocol.deriveSessionIdentifier(seed), expectedSessionIdentifier,
        "deriveSessionIdentifier cross-platform"
    )
    assertEqual(
        BuzzelProtocol.derivePairingCode(seed), expectedPairingCode,
        "derivePairingCode cross-platform"
    )

    let code = BuzzelProtocol.derivePairingCode(seed)
    assertEqual(code.count, 6, "derivePairingCode length")
    assert(code.allSatisfy { $0.isNumber }, "derivePairingCode all digits")
}

// MARK: - Signals: no-payload

func testNoPayloadSignals() {
    let ping = BuzzelProtocol.createPing()
    assertEqual(ping.count, 1, "ping size")
    assertEqual(ping[0], Signal.ping, "ping id")

    let pong = BuzzelProtocol.createPong()
    assertEqual(pong.count, 1, "pong size")
    assertEqual(pong[0], Signal.pong, "pong id")

    let ready = BuzzelProtocol.createReady()
    assertEqual(ready.count, 1, "ready size")
    assertEqual(ready[0], Signal.ready, "ready id")

    let goodbye = BuzzelProtocol.createGoodbye()
    assertEqual(goodbye.count, 1, "goodbye size")
    assertEqual(goodbye[0], Signal.goodbye, "goodbye id")

    let unpair = BuzzelProtocol.createUnpair()
    assertEqual(unpair.count, 1, "unpair size")
    assertEqual(unpair[0], Signal.unpair, "unpair id")
}

// MARK: - pair.request

func testPairRequest() {
    let payload = BuzzelProtocol.createPairRequest(code: "123456")
    assertEqual(payload.count, 7, "pairRequest size")
    assertEqual(payload[0], Signal.pairRequest, "pairRequest signal")
    let code = BuzzelProtocol.parsePairRequestCode(payload)
    assertEqual(code, "123456", "pairRequest round-trip")

    // Wrong signal
    assertNil(
        BuzzelProtocol.parsePairRequestCode(Data([0x99, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36])),
        "parsePairRequest wrong signal"
    )

    // Too short
    assertNil(
        BuzzelProtocol.parsePairRequestCode(Data([Signal.pairRequest, 0x31])),
        "parsePairRequest too short"
    )
}

// MARK: - pair.response

func testPairResponse() {
    let accepted = BuzzelProtocol.createPairResponse(accepted: true)
    assertEqual(accepted.count, 3, "pairResponse accepted size")
    assertEqual(accepted[0], Signal.pairResponse, "pairResponse signal")
    let result1 = BuzzelProtocol.parsePairResponse(accepted)
    assertNotNil(result1, "parsePairResponse accepted")
    assert(result1!.accepted, "pairResponse accepted value")
    assertEqual(result1!.reason, 0x00, "pairResponse accepted reason")

    let rejected = BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01)
    let result2 = BuzzelProtocol.parsePairResponse(rejected)
    assertNotNil(result2, "parsePairResponse rejected")
    assert(!result2!.accepted, "pairResponse rejected value")
    assertEqual(result2!.reason, 0x01, "pairResponse rejected reason")

    // Too short
    assertNil(
        BuzzelProtocol.parsePairResponse(Data([Signal.pairResponse, 0x01])),
        "parsePairResponse too short"
    )
}

// MARK: - acknowledgment

func testAcknowledgment() {
    let payload = BuzzelProtocol.createAcknowledgment(sequenceNumber: 42)
    assertEqual(payload.count, 3, "acknowledgment size")
    assertEqual(payload[0], Signal.acknowledgment, "acknowledgment signal")
    assertEqual(
        BuzzelProtocol.parseAcknowledgmentSequenceNumber(payload), 42,
        "acknowledgment round-trip"
    )

    assertEqual(
        BuzzelProtocol.parseAcknowledgmentSequenceNumber(
            BuzzelProtocol.createAcknowledgment(sequenceNumber: 65535)
        ), 65535,
        "acknowledgment max sequence"
    )
    assertEqual(
        BuzzelProtocol.parseAcknowledgmentSequenceNumber(
            BuzzelProtocol.createAcknowledgment(sequenceNumber: 0)
        ), 0, "acknowledgment zero"
    )

    assertNil(
        BuzzelProtocol.parseAcknowledgmentSequenceNumber(Data([Signal.acknowledgment])),
        "parseAcknowledgment too short"
    )
}

// MARK: - parseSignalIdentifier

func testParseSignalIdentifier() {
    assertEqual(
        BuzzelProtocol.parseSignalIdentifier(Data([0x00])), Signal.command,
        "signalIdentifier command"
    )
    assertEqual(
        BuzzelProtocol.parseSignalIdentifier(Data([0x01])), Signal.pairRequest,
        "signalIdentifier pairRequest"
    )
    assertEqual(
        BuzzelProtocol.parseSignalIdentifier(Data([0x04])), Signal.ping, "signalIdentifier ping"
    )
    assertEqual(
        BuzzelProtocol.parseSignalIdentifier(Data([0x08])), Signal.unpair,
        "signalIdentifier unpair"
    )
    assertNil(BuzzelProtocol.parseSignalIdentifier(Data()), "signalIdentifier empty")
}

// MARK: - Command

func testCommand() {
    // Round-trip with tag-length-value
    let tagLengthValue = BuzzelProtocol.encodeTagLengthValueString(tag: 0x01, value: "hello")
    let payload = BuzzelProtocol.createCommand(
        commandIdentifier: 0x30, sequenceNumber: 5, tagLengthValueData: tagLengthValue
    )
    assertEqual(payload[0], Signal.command, "command signal")
    let command = BuzzelProtocol.parseCommand(payload)
    assertNotNil(command, "parseCommand")
    assertEqual(command!.commandIdentifier, 0x30, "command commandIdentifier")
    assertEqual(command!.sequenceNumber, 5, "command sequenceNumber")
    assertEqual(command!.data, tagLengthValue, "command data")

    // Empty data
    let emptyCommand = BuzzelProtocol.createCommand(commandIdentifier: 0x10, sequenceNumber: 0)
    let parsedEmpty = BuzzelProtocol.parseCommand(emptyCommand)
    assertNotNil(parsedEmpty, "parseCommand empty")
    assertEqual(parsedEmpty!.commandIdentifier, 0x10, "command empty commandIdentifier")
    assertEqual(parsedEmpty!.sequenceNumber, 0, "command empty sequenceNumber")
    assertEqual(parsedEmpty!.data.count, 0, "command empty data")

    // Max sequence number
    let maxSequenceCommand = BuzzelProtocol.createCommand(
        commandIdentifier: 0x01, sequenceNumber: 65535
    )
    assertEqual(
        BuzzelProtocol.parseCommand(maxSequenceCommand)!.sequenceNumber, 65535,
        "command max sequenceNumber"
    )

    // Max tag-length-value (default = 255, capped by tag-length-value length field)
    let bigData = Data(0..<255)
    let bigCommand = BuzzelProtocol.createCommand(
        commandIdentifier: 0x01, sequenceNumber: 1, tagLengthValueData: bigData
    )
    assertEqual(
        BuzzelProtocol.parseCommand(bigCommand)!.data.count, 255,
        "command max tag-length-value"
    )

    // Truncate oversize (default maximumTagLengthValueDataSize = tagLengthValueMaximumValueSize = 255)
    let oversizedData = Data(count: 300)
    let truncatedCommand = BuzzelProtocol.createCommand(
        commandIdentifier: 0x01, sequenceNumber: 1, tagLengthValueData: oversizedData
    )
    assertEqual(
        BuzzelProtocol.parseCommand(truncatedCommand)!.data.count,
        BuzzelProtocol.tagLengthValueMaximumValueSize, "command truncate"
    )

    // Truncate with custom maximumTagLengthValueDataSize (MTU 247 = Nokia 6)
    let maximumFrameSize247 = BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(247)
    let maximumTagLengthValue247 = BuzzelProtocol.maximumTagLengthValueDataSize(maximumFrameSize247)
    let truncatedBleCommand = BuzzelProtocol.createCommand(
        commandIdentifier: 0x01, sequenceNumber: 1, tagLengthValueData: oversizedData,
        maximumTagLengthValueDataSize: maximumTagLengthValue247
    )
    assertEqual(
        BuzzelProtocol.parseCommand(truncatedBleCommand)!.data.count, maximumTagLengthValue247,
        "command truncate ble"
    )

    // Too short
    assertNil(
        BuzzelProtocol.parseCommand(Data([Signal.command, 0x01, 0x00])), "parseCommand too short"
    )

    // Wrong signal
    assertNil(
        BuzzelProtocol.parseCommand(Data([Signal.ping, 0x01, 0x00, 0x01])),
        "parseCommand wrong signal"
    )
}

// MARK: - Tag-Length-Value

func testTagLengthValue() {
    // Raw round-trip
    let encoded = BuzzelProtocol.encodeTagLengthValue(tag: 0x01, value: Data([0x0A, 0x0B, 0x0C]))
    assertEqual(encoded.count, 5, "tagLengthValue size")
    let fields = BuzzelProtocol.decodeTagLengthValue(encoded)
    assertEqual(fields.count, 1, "tagLengthValue field count")
    assertEqual(fields[0].tag, 0x01, "tagLengthValue tag")
    assertEqual(fields[0].value, Data([0x0A, 0x0B, 0x0C]), "tagLengthValue value")

    // String
    let stringEncoded = BuzzelProtocol.encodeTagLengthValueString(tag: 0x10, value: "hello")
    let stringFields = BuzzelProtocol.decodeTagLengthValue(stringEncoded)
    assertEqual(
        BuzzelProtocol.getTagLengthValueString(stringFields, tag: 0x10), "hello",
        "tagLengthValue string"
    )

    // Integer
    let integerEncoded = BuzzelProtocol.encodeTagLengthValueInteger(tag: 0x20, value: 42)
    let integerFields = BuzzelProtocol.decodeTagLengthValue(integerEncoded)
    assertEqual(
        BuzzelProtocol.getTagLengthValueInteger(integerFields, tag: 0x20), 42,
        "tagLengthValue integer"
    )

    // Byte
    let byteEncoded = BuzzelProtocol.encodeTagLengthValueByte(tag: 0x30, value: 0xFF)
    let byteFields = BuzzelProtocol.decodeTagLengthValue(byteEncoded)
    assertEqual(
        BuzzelProtocol.getTagLengthValueByte(byteFields, tag: 0x30), 0xFF, "tagLengthValue byte"
    )

    // Multiple fields
    var multipleFieldsData = BuzzelProtocol.encodeTagLengthValueString(tag: 0x01, value: "a")
    multipleFieldsData.append(BuzzelProtocol.encodeTagLengthValueInteger(tag: 0x02, value: 99))
    multipleFieldsData.append(BuzzelProtocol.encodeTagLengthValueByte(tag: 0x03, value: 0x07))
    let multipleFields = BuzzelProtocol.decodeTagLengthValue(multipleFieldsData)
    assertEqual(multipleFields.count, 3, "tagLengthValue multi count")
    assertEqual(
        BuzzelProtocol.getTagLengthValueString(multipleFields, tag: 0x01), "a",
        "tagLengthValue multi string"
    )
    assertEqual(
        BuzzelProtocol.getTagLengthValueInteger(multipleFields, tag: 0x02), 99,
        "tagLengthValue multi integer"
    )
    assertEqual(
        BuzzelProtocol.getTagLengthValueByte(multipleFields, tag: 0x03), 0x07,
        "tagLengthValue multi byte"
    )

    // Missing tag
    assertNil(
        BuzzelProtocol.getTagLengthValueString(stringFields, tag: 0x99),
        "tagLengthValue missing string"
    )
    assertNil(
        BuzzelProtocol.getTagLengthValueInteger(stringFields, tag: 0x99),
        "tagLengthValue missing integer"
    )
    assertNil(
        BuzzelProtocol.getTagLengthValueByte(stringFields, tag: 0x99),
        "tagLengthValue missing byte"
    )

    // Empty
    let emptyFields = BuzzelProtocol.decodeTagLengthValue(Data())
    assert(emptyFields.isEmpty, "tagLengthValue empty")
}

// MARK: - FrameCodec

func testFrameCodec() {
    // Encode
    let frame = FrameCodec.encode(Data([0x04]))
    assertEqual(frame.count, 3, "frame encode size")
    assertEqual(frame[0], 0x00, "frame header hi")
    assertEqual(frame[1], 0x01, "frame header lo")
    assertEqual(frame[2], 0x04, "frame payload")

    // Decode length
    let frame2 = FrameCodec.encode(Data([0x01, 0x02, 0x03]))
    assertEqual(FrameCodec.decodeLength(frame2), 3, "frame decodeLength")

    // Max payload (wifi)
    let wifiMaximumPayloadSize = BuzzelProtocol.maximumPayloadSize(
        BuzzelProtocol.wifiMaximumFrameSize
    )
    let maximumFrame = FrameCodec.encode(Data(count: wifiMaximumPayloadSize))
    assertEqual(maximumFrame.count, wifiMaximumPayloadSize + 2, "frame max size")
    assertEqual(
        FrameCodec.decodeLength(maximumFrame), wifiMaximumPayloadSize, "frame max decodeLength")

    // Max payload (BLE MTU 247)
    let bleMaximumPayloadSize = BuzzelProtocol.maximumPayloadSize(
        BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(247)
    )
    let bleFrame = FrameCodec.encode(
        Data(count: bleMaximumPayloadSize), maximumPayloadSize: bleMaximumPayloadSize
    )
    assertEqual(bleFrame.count, bleMaximumPayloadSize + 2, "frame ble max size")

    // Truncate for BLE (MTU 185)
    let ble185MaximumPayloadSize = BuzzelProtocol.maximumPayloadSize(
        BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(185)
    )
    let truncatedFrame = FrameCodec.encode(
        Data(count: 300), maximumPayloadSize: ble185MaximumPayloadSize
    )
    assertEqual(truncatedFrame.count, ble185MaximumPayloadSize + 2, "frame ble truncate size")

    // Extract frames
    var combined = FrameCodec.encode(BuzzelProtocol.createPing())
    combined.append(FrameCodec.encode(BuzzelProtocol.createPong()))
    var extractedFrames: [Data] = []
    FrameCodec.extractFrames(from: &combined) { extractedFrames.append($0) }
    assertEqual(extractedFrames.count, 2, "frame extract count")
    assertEqual(extractedFrames[0][0], Signal.ping, "frame extract ping")
    assertEqual(extractedFrames[1][0], Signal.pong, "frame extract pong")
    assertEqual(combined.count, 0, "frame extract remaining")
}

// MARK: - Wire Size Verification

func testWireSize() {
    // No-payload signals: framed = 2-byte header + 1-byte payload = 3
    assertEqual(FrameCodec.encode(BuzzelProtocol.createPing()).count, 3, "wireSize ping")
    assertEqual(FrameCodec.encode(BuzzelProtocol.createPong()).count, 3, "wireSize pong")
    assertEqual(FrameCodec.encode(BuzzelProtocol.createReady()).count, 3, "wireSize ready")
    assertEqual(FrameCodec.encode(BuzzelProtocol.createGoodbye()).count, 3, "wireSize goodbye")
    assertEqual(FrameCodec.encode(BuzzelProtocol.createUnpair()).count, 3, "wireSize unpair")

    // pair.request: 2 + 7 = 9
    assertEqual(
        FrameCodec.encode(BuzzelProtocol.createPairRequest(code: "123456")).count, 9,
        "wireSize pairRequest"
    )

    // pair.response: 2 + 3 = 5
    assertEqual(
        FrameCodec.encode(BuzzelProtocol.createPairResponse(accepted: true)).count, 5,
        "wireSize pairResponse"
    )

    // acknowledgment: 2 + 3 = 5
    assertEqual(
        FrameCodec.encode(BuzzelProtocol.createAcknowledgment(sequenceNumber: 1)).count, 5,
        "wireSize acknowledgment"
    )

    // command (empty): 2 + 4 = 6
    assertEqual(
        FrameCodec.encode(
            BuzzelProtocol.createCommand(commandIdentifier: 0x01, sequenceNumber: 0)
        ).count, 6,
        "wireSize commandEmpty"
    )

    // command (max tag-length-value) at WiFi cap
    let wifiMaximumTagLengthValue = BuzzelProtocol.maximumTagLengthValueDataSize(
        BuzzelProtocol.wifiMaximumFrameSize
    )
    let tagLengthValueData = Data(count: wifiMaximumTagLengthValue)
    let commandFrame = FrameCodec.encode(
        BuzzelProtocol.createCommand(
            commandIdentifier: 0x01, sequenceNumber: 0, tagLengthValueData: tagLengthValueData,
            maximumTagLengthValueDataSize: wifiMaximumTagLengthValue
        )
    )
    assertEqual(
        commandFrame.count,
        2 + 1 + BuzzelProtocol.commandHeaderSize + wifiMaximumTagLengthValue,
        "wireSize commandMaxTagLengthValue wifi"
    )

    // command at MTU 247 (Nokia 6) — fill to max frame
    let maximumFrameSize247 = BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(247)
    let maximumCommandData247 = BuzzelProtocol.maximumCommandDataSize(maximumFrameSize247)
    let blePayload = BuzzelProtocol.createCommand(
        commandIdentifier: 0x01, sequenceNumber: 0,
        tagLengthValueData: Data(count: maximumCommandData247),
        maximumTagLengthValueDataSize: maximumCommandData247
    )
    let bleFrame = FrameCodec.encode(
        blePayload,
        maximumPayloadSize: BuzzelProtocol.maximumPayloadSize(maximumFrameSize247)
    )
    assertEqual(bleFrame.count, maximumFrameSize247, "wireSize commandMaxTagLengthValue ble")
}

// MARK: - Big-Endian Byte-Level Verification

func testBigEndian() {
    // acknowledgment sequenceNumber 0x0100
    let acknowledgment1 = BuzzelProtocol.createAcknowledgment(sequenceNumber: 0x0100)
    assertEqual(acknowledgment1[0], Signal.acknowledgment, "BE acknowledgment signal")
    assertEqual(acknowledgment1[1], 0x01, "BE acknowledgment 0x0100 hi")
    assertEqual(acknowledgment1[2], 0x00, "BE acknowledgment 0x0100 lo")

    // acknowledgment sequenceNumber 0xFF00
    let acknowledgment2 = BuzzelProtocol.createAcknowledgment(sequenceNumber: 0xFF00)
    assertEqual(acknowledgment2[1], 0xFF, "BE acknowledgment 0xFF00 hi")
    assertEqual(acknowledgment2[2], 0x00, "BE acknowledgment 0xFF00 lo")

    // acknowledgment sequenceNumber 0x00FF
    let acknowledgment3 = BuzzelProtocol.createAcknowledgment(sequenceNumber: 0x00FF)
    assertEqual(acknowledgment3[1], 0x00, "BE acknowledgment 0x00FF hi")
    assertEqual(acknowledgment3[2], 0xFF, "BE acknowledgment 0x00FF lo")

    // command sequenceNumber 0x0102
    let command = BuzzelProtocol.createCommand(
        commandIdentifier: 0x30, sequenceNumber: 0x0102
    )
    assertEqual(command[0], Signal.command, "BE command signal")
    assertEqual(command[1], 0x01, "BE command sequenceNumber hi")
    assertEqual(command[2], 0x02, "BE command sequenceNumber lo")
    assertEqual(command[3], 0x30, "BE command byte")

    // Tag-length-value integer 0x01020304
    let tagLengthValueInteger = BuzzelProtocol.encodeTagLengthValueInteger(
        tag: 0x01, value: 0x0102_0304
    )
    assertEqual(tagLengthValueInteger[0], 0x01, "BE tagLengthValueInteger tag")
    assertEqual(tagLengthValueInteger[1], 0x04, "BE tagLengthValueInteger len")
    assertEqual(tagLengthValueInteger[2], 0x01, "BE tagLengthValueInteger byte0 MSB")
    assertEqual(tagLengthValueInteger[3], 0x02, "BE tagLengthValueInteger byte1")
    assertEqual(tagLengthValueInteger[4], 0x03, "BE tagLengthValueInteger byte2")
    assertEqual(tagLengthValueInteger[5], 0x04, "BE tagLengthValueInteger byte3 LSB")

    // Frame header for 200-byte payload
    let frame = FrameCodec.encode(Data(count: 200))
    assertEqual(frame[0], 0x00, "BE frame header hi")
    assertEqual(frame[1], 200, "BE frame header lo")
}

// MARK: - Tag-Length-Value 255-Byte Limit

func testTagLengthValueLimits() {
    // Max value = 255 bytes (1-byte length field)
    let maximumValue = Data(0..<255)
    let encoded = BuzzelProtocol.encodeTagLengthValue(tag: 0x01, value: maximumValue)
    assertEqual(encoded.count, 257, "tagLengthValueLimit max encoded size")
    let fields = BuzzelProtocol.decodeTagLengthValue(encoded)
    assertEqual(fields.count, 1, "tagLengthValueLimit max field count")
    assertEqual(fields[0].value.count, 255, "tagLengthValueLimit max value size")

    // Oversized truncated
    let oversizedData = Data(count: 300)
    let oversizedEncoded = BuzzelProtocol.encodeTagLengthValue(tag: 0x01, value: oversizedData)
    assertEqual(oversizedEncoded.count, 257, "tagLengthValueLimit oversized encoded size")
    let oversizedFields = BuzzelProtocol.decodeTagLengthValue(oversizedEncoded)
    assertEqual(oversizedFields[0].value.count, 255, "tagLengthValueLimit oversized value size")

    // Zero-length value
    let emptyEncoded = BuzzelProtocol.encodeTagLengthValue(tag: 0x01, value: Data())
    assertEqual(emptyEncoded.count, 2, "tagLengthValueLimit empty encoded size")
    let emptyFields = BuzzelProtocol.decodeTagLengthValue(emptyEncoded)
    assertEqual(emptyFields.count, 1, "tagLengthValueLimit empty field count")
    assertEqual(emptyFields[0].value.count, 0, "tagLengthValueLimit empty value size")

    // Single byte value
    let singleByteEncoded = BuzzelProtocol.encodeTagLengthValue(
        tag: 0x05, value: Data([0xAB])
    )
    assertEqual(singleByteEncoded.count, 3, "tagLengthValueLimit single size")
    let singleByteFields = BuzzelProtocol.decodeTagLengthValue(singleByteEncoded)
    assertEqual(singleByteFields[0].value[0], 0xAB, "tagLengthValueLimit single value")

    // String max 255
    let longString = String(repeating: "a", count: 255)
    let longStringEncoded = BuzzelProtocol.encodeTagLengthValueString(tag: 0x01, value: longString)
    let longStringFields = BuzzelProtocol.decodeTagLengthValue(longStringEncoded)
    assertEqual(
        BuzzelProtocol.getTagLengthValueString(longStringFields, tag: 0x01), longString,
        "tagLengthValueLimit string max"
    )

    // String oversized truncated
    let oversizedString = String(repeating: "a", count: 300)
    let oversizedStringEncoded = BuzzelProtocol.encodeTagLengthValueString(
        tag: 0x01, value: oversizedString
    )
    let oversizedStringFields = BuzzelProtocol.decodeTagLengthValue(oversizedStringEncoded)
    assertEqual(
        oversizedStringFields[0].value.count, 255, "tagLengthValueLimit string oversized"
    )
}

// MARK: - Malformed Input Edge Cases

func testMalformedInput() {
    // Empty payloads
    assertNil(BuzzelProtocol.parseCommand(Data()), "malformed command empty")
    assertNil(BuzzelProtocol.parsePairRequestCode(Data()), "malformed pairRequest empty")
    assertNil(BuzzelProtocol.parsePairResponse(Data()), "malformed pairResponse empty")
    assertNil(
        BuzzelProtocol.parseAcknowledgmentSequenceNumber(Data()),
        "malformed acknowledgmentSequenceNumber empty"
    )
    assertNil(BuzzelProtocol.parseSignalIdentifier(Data()), "malformed signalIdentifier empty")
    assertNil(BuzzelProtocol.parseQRCodePayload(Data()), "malformed qrCodePayload empty")

    // Wrong signal for acknowledgment
    assertNil(
        BuzzelProtocol.parseAcknowledgmentSequenceNumber(Data([Signal.ping, 0x00, 0x01])),
        "malformed acknowledgment wrong signal"
    )

    // Exact minimum command size (4 bytes)
    let minimumCommand = Data([Signal.command, 0x00, 0x00, 0x10])
    let parsedCommand = BuzzelProtocol.parseCommand(minimumCommand)
    assertNotNil(parsedCommand, "malformed command minimum")
    assertEqual(
        parsedCommand!.commandIdentifier, 0x10, "malformed command minimum commandIdentifier")
    assertEqual(parsedCommand!.sequenceNumber, 0, "malformed command minimum sequenceNumber")
    assertEqual(parsedCommand!.data.count, 0, "malformed command minimum data")

    // Truncated tag-length-value: tag=0x01, len=5, but only 2 bytes of value
    let truncatedTagLengthValue = Data([0x01, 0x05, 0xAA, 0xBB])
    let truncatedFields = BuzzelProtocol.decodeTagLengthValue(truncatedTagLengthValue)
    assertEqual(truncatedFields.count, 0, "malformed tagLengthValue truncated")

    // Single byte — not enough for tag+len
    let singleByteFields = BuzzelProtocol.decodeTagLengthValue(Data([0x01]))
    assertEqual(singleByteFields.count, 0, "malformed tagLengthValue single byte")

    // Multiple tag-length-value fields, last truncated
    let multiTruncated = Data([0x01, 0x01, 0xAA, 0x02, 0x03, 0xBB])
    let multiTruncatedFields = BuzzelProtocol.decodeTagLengthValue(multiTruncated)
    assertEqual(multiTruncatedFields.count, 1, "malformed tagLengthValue multi truncated count")
    assertEqual(multiTruncatedFields[0].tag, 0x01, "malformed tagLengthValue multi truncated tag")

    // getTagLengthValueInteger with value too short (2 bytes instead of 4)
    let shortIntegerData = BuzzelProtocol.encodeTagLengthValue(
        tag: 0x01, value: Data([0x01, 0x02]))
    let shortIntegerFields = BuzzelProtocol.decodeTagLengthValue(shortIntegerData)
    assertNil(
        BuzzelProtocol.getTagLengthValueInteger(shortIntegerFields, tag: 0x01),
        "malformed getTagLengthValueInteger short"
    )

    // getTagLengthValueByte with empty value
    let emptyByteData = BuzzelProtocol.encodeTagLengthValue(tag: 0x01, value: Data())
    let emptyByteFields = BuzzelProtocol.decodeTagLengthValue(emptyByteData)
    assertNil(
        BuzzelProtocol.getTagLengthValueByte(emptyByteFields, tag: 0x01),
        "malformed getTagLengthValueByte empty"
    )

    // Pair request codes
    let codeAllZeros = BuzzelProtocol.parsePairRequestCode(
        BuzzelProtocol.createPairRequest(code: "000000")
    )
    assertEqual(codeAllZeros, "000000", "malformed pairRequest all zeros")

    let codeAllNines = BuzzelProtocol.parsePairRequestCode(
        BuzzelProtocol.createPairRequest(code: "999999")
    )
    assertEqual(codeAllNines, "999999", "malformed pairRequest all nines")

    // All pair.response reasons
    let reason0 = BuzzelProtocol.parsePairResponse(
        BuzzelProtocol.createPairResponse(accepted: false, reason: 0x00)
    )
    assertEqual(reason0!.reason, 0x00, "malformed pairResponse reason 0x00")
    let reason1 = BuzzelProtocol.parsePairResponse(
        BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01)
    )
    assertEqual(reason1!.reason, 0x01, "malformed pairResponse reason 0x01")
    let reason2 = BuzzelProtocol.parsePairResponse(
        BuzzelProtocol.createPairResponse(accepted: false, reason: 0x02)
    )
    assertEqual(reason2!.reason, 0x02, "malformed pairResponse reason 0x02")
}

// MARK: - FrameCodec Edge Cases

func testFrameCodecEdgeCases() {
    // Single byte payload
    let singleFrame = FrameCodec.encode(Data([0xFF]))
    assertEqual(singleFrame.count, 3, "frameEdge single size")
    assertEqual(singleFrame[0], 0x00, "frameEdge single h0")
    assertEqual(singleFrame[1], 0x01, "frameEdge single h1")
    assertEqual(singleFrame[2], 0xFF, "frameEdge single payload")

    // Oversized payload truncated (wifi default)
    let wifiMaximumPayloadSize = BuzzelProtocol.maximumPayloadSize(
        BuzzelProtocol.wifiMaximumFrameSize
    )
    let oversizedFrame = FrameCodec.encode(Data(count: wifiMaximumPayloadSize + 100))
    assertEqual(oversizedFrame.count, wifiMaximumPayloadSize + 2, "frameEdge oversized size")

    // extractFrames: partial frame
    var partialBuffer = FrameCodec.encode(BuzzelProtocol.createPing())
    partialBuffer.append(Data([0x00, 0x05]))  // header says 5 bytes but no payload
    var partialFrames: [Data] = []
    FrameCodec.extractFrames(from: &partialBuffer) { partialFrames.append($0) }
    assertEqual(partialFrames.count, 1, "frameEdge partial count")
    assertEqual(partialFrames[0][0], Signal.ping, "frameEdge partial ping")
    assertEqual(partialBuffer.count, 2, "frameEdge partial remaining")

    // extractFrames: empty buffer
    var emptyBuffer = Data()
    var emptyFrames: [Data] = []
    FrameCodec.extractFrames(from: &emptyBuffer) { emptyFrames.append($0) }
    assertEqual(emptyFrames.count, 0, "frameEdge empty count")
    assertEqual(emptyBuffer.count, 0, "frameEdge empty remaining")

    // extractFrames: header only (no payload bytes)
    var headerOnlyBuffer = Data([0x00, 0x03])
    var headerOnlyFrames: [Data] = []
    FrameCodec.extractFrames(from: &headerOnlyBuffer) { headerOnlyFrames.append($0) }
    assertEqual(headerOnlyFrames.count, 0, "frameEdge headerOnly count")
    assertEqual(headerOnlyBuffer.count, 2, "frameEdge headerOnly remaining")

    // extractFrames: invalid length (0)
    var invalidLengthBuffer = Data([0x00, 0x00, 0x04])
    var invalidLengthFrames: [Data] = []
    FrameCodec.extractFrames(from: &invalidLengthBuffer) { invalidLengthFrames.append($0) }
    assertEqual(invalidLengthFrames.count, 0, "frameEdge invalidLength count")
    assertEqual(invalidLengthBuffer.count, 0, "frameEdge invalidLength reset")

    // extractFrames: three frames
    var threeFrameBuffer = FrameCodec.encode(BuzzelProtocol.createPing())
    threeFrameBuffer.append(FrameCodec.encode(BuzzelProtocol.createPong()))
    threeFrameBuffer.append(FrameCodec.encode(BuzzelProtocol.createReady()))
    var threeFrames: [Data] = []
    FrameCodec.extractFrames(from: &threeFrameBuffer) { threeFrames.append($0) }
    assertEqual(threeFrames.count, 3, "frameEdge three count")
    assertEqual(threeFrames[0][0], Signal.ping, "frameEdge three ping")
    assertEqual(threeFrames[1][0], Signal.pong, "frameEdge three pong")
    assertEqual(threeFrames[2][0], Signal.ready, "frameEdge three ready")
    assertEqual(threeFrameBuffer.count, 0, "frameEdge three remaining")

    // Full round-trip: command with tag-length-value through frame encode/decode
    var roundTripTagLengthValue = BuzzelProtocol.encodeTagLengthValueString(
        tag: 0x01, value: "test"
    )
    roundTripTagLengthValue.append(
        BuzzelProtocol.encodeTagLengthValueInteger(tag: 0x02, value: 42)
    )
    let commandPayload = BuzzelProtocol.createCommand(
        commandIdentifier: 0x10, sequenceNumber: 100,
        tagLengthValueData: roundTripTagLengthValue
    )
    let encodedFrame = FrameCodec.encode(commandPayload)
    let decodedLength = FrameCodec.decodeLength(encodedFrame)
    let extractedPayload = encodedFrame.subdata(in: 2..<(2 + decodedLength))
    let parsedCommand = BuzzelProtocol.parseCommand(extractedPayload)
    assertNotNil(parsedCommand, "frameEdge roundTrip command")
    assertEqual(parsedCommand!.commandIdentifier, 0x10, "frameEdge roundTrip commandIdentifier")
    assertEqual(parsedCommand!.sequenceNumber, 100, "frameEdge roundTrip sequenceNumber")
    let commandFields = BuzzelProtocol.decodeTagLengthValue(parsedCommand!.data)
    assertEqual(
        BuzzelProtocol.getTagLengthValueString(commandFields, tag: 0x01), "test",
        "frameEdge roundTrip string"
    )
    assertEqual(
        BuzzelProtocol.getTagLengthValueInteger(commandFields, tag: 0x02), 42,
        "frameEdge roundTrip integer"
    )
}

// MARK: - Dynamic Sizing

func testDynamicSizing() {
    // WiFi: maximumFrameSize=4096
    assertEqual(
        BuzzelProtocol.maximumPayloadSize(4096), 4094, "dynamic wifi maximumPayloadSize"
    )
    assertEqual(
        BuzzelProtocol.maximumCommandDataSize(4096), 4090, "dynamic wifi maximumCommandDataSize"
    )
    assertEqual(
        BuzzelProtocol.maximumTagLengthValueDataSize(4096), 255,
        "dynamic wifi maximumTagLengthValueDataSize"
    )  // capped by tagLengthValueMaximumValueSize

    // BLE MTU 247 (Nokia 6): maximumFrameSize=244
    assertEqual(
        BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(247), 244,
        "dynamic mtu247 maximumFrameSize"
    )
    assertEqual(BuzzelProtocol.maximumPayloadSize(244), 242, "dynamic mtu247 maximumPayloadSize")
    assertEqual(
        BuzzelProtocol.maximumCommandDataSize(244), 238, "dynamic mtu247 maximumCommandDataSize"
    )
    assertEqual(
        BuzzelProtocol.maximumTagLengthValueDataSize(244), 236,
        "dynamic mtu247 maximumTagLengthValueDataSize"
    )

    // BLE MTU 185 (iPhone): maximumFrameSize=182
    assertEqual(
        BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(185), 182,
        "dynamic mtu185 maximumFrameSize"
    )
    assertEqual(BuzzelProtocol.maximumPayloadSize(182), 180, "dynamic mtu185 maximumPayloadSize")
    assertEqual(
        BuzzelProtocol.maximumCommandDataSize(182), 176, "dynamic mtu185 maximumCommandDataSize"
    )
    assertEqual(
        BuzzelProtocol.maximumTagLengthValueDataSize(182), 174,
        "dynamic mtu185 maximumTagLengthValueDataSize"
    )

    // BLE MTU 23 (minimum): maximumFrameSize=20
    assertEqual(
        BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(23), 20,
        "dynamic mtu23 maximumFrameSize"
    )
    assertEqual(BuzzelProtocol.maximumPayloadSize(20), 18, "dynamic mtu23 maximumPayloadSize")
    assertEqual(
        BuzzelProtocol.maximumCommandDataSize(20), 14, "dynamic mtu23 maximumCommandDataSize"
    )
    assertEqual(
        BuzzelProtocol.maximumTagLengthValueDataSize(20), 12,
        "dynamic mtu23 maximumTagLengthValueDataSize"
    )

    // All session signals fit at minimum MTU (23)
    let minimumMaximumPayloadSize = BuzzelProtocol.maximumPayloadSize(
        BuzzelProtocol.maximumFrameSizeForMaximumTransmissionUnit(23)
    )
    assert(
        BuzzelProtocol.createPing().count <= minimumMaximumPayloadSize,
        "dynamic ping fits min MTU"
    )
    assert(
        BuzzelProtocol.createPong().count <= minimumMaximumPayloadSize,
        "dynamic pong fits min MTU"
    )
    assert(
        BuzzelProtocol.createReady().count <= minimumMaximumPayloadSize,
        "dynamic ready fits min MTU"
    )
    assert(
        BuzzelProtocol.createGoodbye().count <= minimumMaximumPayloadSize,
        "dynamic goodbye fits min MTU"
    )
    assert(
        BuzzelProtocol.createUnpair().count <= minimumMaximumPayloadSize,
        "dynamic unpair fits min MTU"
    )
    assert(
        BuzzelProtocol.createPairRequest(code: "123456").count <= minimumMaximumPayloadSize,
        "dynamic pairRequest fits min MTU"
    )
    assert(
        BuzzelProtocol.createPairResponse(accepted: true).count <= minimumMaximumPayloadSize,
        "dynamic pairResponse fits min MTU"
    )
    assert(
        BuzzelProtocol.createAcknowledgment(sequenceNumber: 65535).count
            <= minimumMaximumPayloadSize,
        "dynamic acknowledgment fits min MTU"
    )
}

// MARK: - Run

@main
struct TestRunner {
    static func main() {
        testQRCode()
        testSeedDerivation()
        testNoPayloadSignals()
        testPairRequest()
        testPairResponse()
        testAcknowledgment()
        testParseSignalIdentifier()
        testCommand()
        testTagLengthValue()
        testFrameCodec()
        testWireSize()
        testBigEndian()
        testTagLengthValueLimits()
        testMalformedInput()
        testFrameCodecEdgeCases()
        testDynamicSizing()

        print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
        if !errors.isEmpty {
            for error in errors {
                print(error)
            }
        }
        exit(failed > 0 ? 1 : 0)
    }
}
