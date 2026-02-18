import CommonCrypto
import Foundation

// Simple test runner — no XCTest needed

var passed = 0
var failed = 0
var errors = [String]()

func assert(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
  if condition {
    passed += 1
  } else {
    failed += 1
    errors.append("  FAIL: \(name) (\(file):\(line))")
  }
}

func assertEqual<T: Equatable>(
  _ a: T, _ b: T, _ name: String, file: String = #file, line: Int = #line
) {
  if a == b {
    passed += 1
  } else {
    failed += 1
    errors.append("  FAIL: \(name) — expected \(b), got \(a) (\(file):\(line))")
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

// Fixed seed: 0x00..0x0F
let seed = Data(0...15)

// Cross-platform expected values (verified with Python SHA256)
let expectedSessionId = "BE45CB26-05BF-36BE-BDE6-84841A28F0FD"
let expectedPairingCode = "279084"

func buildQr(seed: Data, host: String, prefer: String) -> Data {
  var buf = Data(capacity: 24)
  buf.append(0xBC)
  buf.append(0x1B)
  buf.append(seed)
  let parts = host.split(separator: ".").compactMap { UInt8($0) }
  buf.append(contentsOf: parts)
  buf.append(prefer == "ble" ? 0x01 : 0x00)
  buf.append(0x00)
  return buf
}

// MARK: - QR

func testQr() {
  // Valid parse
  let qr = buildQr(seed: seed, host: "192.168.1.100", prefer: "wifi")
  let r = BuzzelProtocol.parseQr(qr)
  assertNotNil(r, "parseQr valid")
  assertEqual(r!.seed, seed, "parseQr seed")
  assertEqual(r!.host, "192.168.1.100", "parseQr host")
  assertEqual(r!.prefer, "wifi", "parseQr prefer")

  // BLE prefer
  let qr2 = buildQr(seed: seed, host: "10.0.0.1", prefer: "ble")
  let r2 = BuzzelProtocol.parseQr(qr2)
  assertNotNil(r2, "parseQr ble")
  assertEqual(r2!.prefer, "ble", "parseQr ble prefer")

  // Wrong size
  assertNil(BuzzelProtocol.parseQr(Data(count: 10)), "parseQr wrong size 10")
  assertNil(BuzzelProtocol.parseQr(Data(count: 25)), "parseQr wrong size 25")

  // Wrong magic
  var bad = buildQr(seed: seed, host: "1.2.3.4", prefer: "wifi")
  bad[0] = 0xFF
  assertNil(BuzzelProtocol.parseQr(bad), "parseQr wrong magic")

  // Generate + parse round-trip
  let gen = BuzzelProtocol.generateQrPayload(seed: seed, host: "10.0.1.50", prefer: "ble")
  assertEqual(gen.count, 24, "generateQr size")
  let parsed = BuzzelProtocol.parseQr(gen)
  assertNotNil(parsed, "generateQr round-trip")
  assertEqual(parsed!.seed, seed, "generateQr seed")
  assertEqual(parsed!.host, "10.0.1.50", "generateQr host")
  assertEqual(parsed!.prefer, "ble", "generateQr prefer")
}

// MARK: - Seed Derivation

func testSeedDerivation() {
  assertEqual(
    BuzzelProtocol.deriveSessionId(seed), expectedSessionId, "deriveSessionId cross-platform")
  assertEqual(
    BuzzelProtocol.derivePairingCode(seed), expectedPairingCode, "derivePairingCode cross-platform")

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
    "parsePairRequest wrong signal")

  // Too short
  assertNil(
    BuzzelProtocol.parsePairRequestCode(Data([Signal.pairRequest, 0x31])),
    "parsePairRequest too short")
}

// MARK: - pair.response

func testPairResponse() {
  let accepted = BuzzelProtocol.createPairResponse(accepted: true)
  assertEqual(accepted.count, 3, "pairResponse accepted size")
  assertEqual(accepted[0], Signal.pairResponse, "pairResponse signal")
  let r1 = BuzzelProtocol.parsePairResponse(accepted)
  assertNotNil(r1, "parsePairResponse accepted")
  assert(r1!.accepted, "pairResponse accepted value")
  assertEqual(r1!.reason, 0x00, "pairResponse accepted reason")

  let rejected = BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01)
  let r2 = BuzzelProtocol.parsePairResponse(rejected)
  assertNotNil(r2, "parsePairResponse rejected")
  assert(!r2!.accepted, "pairResponse rejected value")
  assertEqual(r2!.reason, 0x01, "pairResponse rejected reason")

  // Too short
  assertNil(
    BuzzelProtocol.parsePairResponse(Data([Signal.pairResponse, 0x01])),
    "parsePairResponse too short")
}

// MARK: - ack

func testAck() {
  let payload = BuzzelProtocol.createAck(seq: 42)
  assertEqual(payload.count, 3, "ack size")
  assertEqual(payload[0], Signal.ack, "ack signal")
  assertEqual(BuzzelProtocol.parseAckSeq(payload), 42, "ack round-trip")

  assertEqual(
    BuzzelProtocol.parseAckSeq(BuzzelProtocol.createAck(seq: 65535)), 65535, "ack max seq")
  assertEqual(BuzzelProtocol.parseAckSeq(BuzzelProtocol.createAck(seq: 0)), 0, "ack zero")

  assertNil(BuzzelProtocol.parseAckSeq(Data([Signal.ack])), "parseAck too short")
}

// MARK: - parseSignalId

func testParseSignalId() {
  assertEqual(BuzzelProtocol.parseSignalId(Data([0x00])), Signal.command, "signalId command")
  assertEqual(
    BuzzelProtocol.parseSignalId(Data([0x01])), Signal.pairRequest, "signalId pairRequest")
  assertEqual(BuzzelProtocol.parseSignalId(Data([0x04])), Signal.ping, "signalId ping")
  assertEqual(BuzzelProtocol.parseSignalId(Data([0x08])), Signal.unpair, "signalId unpair")
  assertNil(BuzzelProtocol.parseSignalId(Data()), "signalId empty")
}

// MARK: - Command

func testCommand() {
  // Round-trip with TLV
  let tlv = BuzzelProtocol.tlvEncodeString(tag: 0x01, value: "hello")
  let payload = BuzzelProtocol.createCommand(cmd: 0x30, seq: 5, tlvData: tlv)
  assertEqual(payload[0], Signal.command, "command signal")
  let cmd = BuzzelProtocol.parseCommand(payload)
  assertNotNil(cmd, "parseCommand")
  assertEqual(cmd!.cmd, 0x30, "command cmd")
  assertEqual(cmd!.seq, 5, "command seq")
  assertEqual(cmd!.data, tlv, "command data")

  // Empty data
  let empty = BuzzelProtocol.createCommand(cmd: 0x10, seq: 0)
  let cmd2 = BuzzelProtocol.parseCommand(empty)
  assertNotNil(cmd2, "parseCommand empty")
  assertEqual(cmd2!.cmd, 0x10, "command empty cmd")
  assertEqual(cmd2!.seq, 0, "command empty seq")
  assertEqual(cmd2!.data.count, 0, "command empty data")

  // Max seq
  let maxSeq = BuzzelProtocol.createCommand(cmd: 0x01, seq: 65535)
  assertEqual(BuzzelProtocol.parseCommand(maxSeq)!.seq, 65535, "command max seq")

  // Max TLV (default = 255, capped by TLV Len field)
  let bigData = Data(0..<255)
  let big = BuzzelProtocol.createCommand(cmd: 0x01, seq: 1, tlvData: bigData)
  assertEqual(BuzzelProtocol.parseCommand(big)!.data.count, 255, "command max tlv")

  // Truncate oversize (default maxTlvData = tlvMaxValue = 255)
  let oversized = Data(count: 300)
  let trunc = BuzzelProtocol.createCommand(cmd: 0x01, seq: 1, tlvData: oversized)
  assertEqual(
    BuzzelProtocol.parseCommand(trunc)!.data.count, BuzzelProtocol.tlvMaxValue, "command truncate")

  // Truncate with custom maxTlvData (MTU 247 = Nokia 6)
  let maxFrame247 = BuzzelProtocol.maxFrameForMtu(247)  // 244
  let maxTlv247 = BuzzelProtocol.maxTlvData(maxFrame247)  // 236
  let truncBle = BuzzelProtocol.createCommand(
    cmd: 0x01, seq: 1, tlvData: oversized, maxTlvData: maxTlv247)
  assertEqual(
    BuzzelProtocol.parseCommand(truncBle)!.data.count, maxTlv247, "command truncate ble")

  // Too short
  assertNil(
    BuzzelProtocol.parseCommand(Data([Signal.command, 0x01, 0x00])), "parseCommand too short")

  // Wrong signal
  assertNil(
    BuzzelProtocol.parseCommand(Data([Signal.ping, 0x01, 0x00, 0x01])), "parseCommand wrong signal")
}

// MARK: - TLV

func testTlv() {
  // Raw round-trip
  let encoded = BuzzelProtocol.tlvEncode(tag: 0x01, value: Data([0x0A, 0x0B, 0x0C]))
  assertEqual(encoded.count, 5, "tlv size")
  let fields = BuzzelProtocol.tlvDecode(encoded)
  assertEqual(fields.count, 1, "tlv field count")
  assertEqual(fields[0].tag, 0x01, "tlv tag")
  assertEqual(fields[0].value, Data([0x0A, 0x0B, 0x0C]), "tlv value")

  // String
  let str = BuzzelProtocol.tlvEncodeString(tag: 0x10, value: "hello")
  let sf = BuzzelProtocol.tlvDecode(str)
  assertEqual(BuzzelProtocol.tlvGetString(sf, tag: 0x10), "hello", "tlv string")

  // Int
  let intData = BuzzelProtocol.tlvEncodeInt(tag: 0x20, value: 42)
  let intf = BuzzelProtocol.tlvDecode(intData)
  assertEqual(BuzzelProtocol.tlvGetInt(intf, tag: 0x20), 42, "tlv int")

  // Byte
  let byteData = BuzzelProtocol.tlvEncodeByte(tag: 0x30, value: 0xFF)
  let bf = BuzzelProtocol.tlvDecode(byteData)
  assertEqual(BuzzelProtocol.tlvGetByte(bf, tag: 0x30), 0xFF, "tlv byte")

  // Multiple fields
  var multi = BuzzelProtocol.tlvEncodeString(tag: 0x01, value: "a")
  multi.append(BuzzelProtocol.tlvEncodeInt(tag: 0x02, value: 99))
  multi.append(BuzzelProtocol.tlvEncodeByte(tag: 0x03, value: 0x07))
  let mf = BuzzelProtocol.tlvDecode(multi)
  assertEqual(mf.count, 3, "tlv multi count")
  assertEqual(BuzzelProtocol.tlvGetString(mf, tag: 0x01), "a", "tlv multi string")
  assertEqual(BuzzelProtocol.tlvGetInt(mf, tag: 0x02), 99, "tlv multi int")
  assertEqual(BuzzelProtocol.tlvGetByte(mf, tag: 0x03), 0x07, "tlv multi byte")

  // Missing tag
  assertNil(BuzzelProtocol.tlvGetString(sf, tag: 0x99), "tlv missing string")
  assertNil(BuzzelProtocol.tlvGetInt(sf, tag: 0x99), "tlv missing int")
  assertNil(BuzzelProtocol.tlvGetByte(sf, tag: 0x99), "tlv missing byte")

  // Empty
  let emptyFields = BuzzelProtocol.tlvDecode(Data())
  assert(emptyFields.isEmpty, "tlv empty")
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
  let wifiMaxPayload = BuzzelProtocol.maxPayload(BuzzelProtocol.wifiMaxFrame)
  let maxFrame = FrameCodec.encode(Data(count: wifiMaxPayload))
  assertEqual(maxFrame.count, wifiMaxPayload + 2, "frame max size")
  assertEqual(FrameCodec.decodeLength(maxFrame), wifiMaxPayload, "frame max decodeLength")

  // Max payload (BLE MTU 247)
  let bleMaxPayload = BuzzelProtocol.maxPayload(BuzzelProtocol.maxFrameForMtu(247))  // 242
  let bleFrame = FrameCodec.encode(Data(count: bleMaxPayload), maxPayload: bleMaxPayload)
  assertEqual(bleFrame.count, bleMaxPayload + 2, "frame ble max size")

  // Truncate for BLE (MTU 185)
  let ble185 = BuzzelProtocol.maxPayload(BuzzelProtocol.maxFrameForMtu(185))  // 180
  let truncFrame = FrameCodec.encode(Data(count: 300), maxPayload: ble185)
  assertEqual(truncFrame.count, ble185 + 2, "frame ble truncate size")

  // Extract frames
  var combined = FrameCodec.encode(BuzzelProtocol.createPing())
  combined.append(FrameCodec.encode(BuzzelProtocol.createPong()))
  var frames = [Data]()
  FrameCodec.extractFrames(from: &combined) { frames.append($0) }
  assertEqual(frames.count, 2, "frame extract count")
  assertEqual(frames[0][0], Signal.ping, "frame extract ping")
  assertEqual(frames[1][0], Signal.pong, "frame extract pong")
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
    "wireSize pairRequest")

  // pair.response: 2 + 3 = 5
  assertEqual(
    FrameCodec.encode(BuzzelProtocol.createPairResponse(accepted: true)).count, 5,
    "wireSize pairResponse")

  // ack: 2 + 3 = 5
  assertEqual(FrameCodec.encode(BuzzelProtocol.createAck(seq: 1)).count, 5, "wireSize ack")

  // command (empty): 2 + 4 = 6
  assertEqual(
    FrameCodec.encode(BuzzelProtocol.createCommand(cmd: 0x01, seq: 0)).count, 6,
    "wireSize commandEmpty")

  // command (max TLV) at WiFi cap
  let wifiMaxTlv = BuzzelProtocol.maxTlvData(BuzzelProtocol.wifiMaxFrame)
  let tlv = Data(count: wifiMaxTlv)
  let cmdFrame = FrameCodec.encode(
    BuzzelProtocol.createCommand(cmd: 0x01, seq: 0, tlvData: tlv, maxTlvData: wifiMaxTlv))
  // signal(1) + cmd(1) + seq(2) + tlvData + frameHeader(2)
  assertEqual(
    cmdFrame.count, 2 + 1 + BuzzelProtocol.commandHeader + wifiMaxTlv, "wireSize commandMaxTlv wifi"
  )

  // command at MTU 247 (Nokia 6) — fill to max frame
  let maxFrame247 = BuzzelProtocol.maxFrameForMtu(247)  // 244
  let maxCmd247 = BuzzelProtocol.maxCmdData(maxFrame247)  // 238 (total TLV data area)
  let blePayload = BuzzelProtocol.createCommand(
    cmd: 0x01, seq: 0, tlvData: Data(count: maxCmd247), maxTlvData: maxCmd247)
  let bleFrame = FrameCodec.encode(blePayload, maxPayload: BuzzelProtocol.maxPayload(maxFrame247))
  assertEqual(bleFrame.count, maxFrame247, "wireSize commandMaxTlv ble")
}

// MARK: - Big-Endian Byte-Level Verification

func testBigEndian() {
  // ack seq 0x0100
  let ack1 = BuzzelProtocol.createAck(seq: 0x0100)
  assertEqual(ack1[0], Signal.ack, "BE ack signal")
  assertEqual(ack1[1], 0x01, "BE ack 0x0100 hi")
  assertEqual(ack1[2], 0x00, "BE ack 0x0100 lo")

  // ack seq 0xFF00
  let ack2 = BuzzelProtocol.createAck(seq: 0xFF00)
  assertEqual(ack2[1], 0xFF, "BE ack 0xFF00 hi")
  assertEqual(ack2[2], 0x00, "BE ack 0xFF00 lo")

  // ack seq 0x00FF
  let ack3 = BuzzelProtocol.createAck(seq: 0x00FF)
  assertEqual(ack3[1], 0x00, "BE ack 0x00FF hi")
  assertEqual(ack3[2], 0xFF, "BE ack 0x00FF lo")

  // command seq 0x0102
  let cmd = BuzzelProtocol.createCommand(cmd: 0x30, seq: 0x0102)
  assertEqual(cmd[0], Signal.command, "BE cmd signal")
  assertEqual(cmd[1], 0x30, "BE cmd byte")
  assertEqual(cmd[2], 0x01, "BE cmd seq hi")
  assertEqual(cmd[3], 0x02, "BE cmd seq lo")

  // TLV int 0x01020304
  let tlvInt = BuzzelProtocol.tlvEncodeInt(tag: 0x01, value: 0x0102_0304)
  assertEqual(tlvInt[0], 0x01, "BE tlvInt tag")
  assertEqual(tlvInt[1], 0x04, "BE tlvInt len")
  assertEqual(tlvInt[2], 0x01, "BE tlvInt byte0 MSB")
  assertEqual(tlvInt[3], 0x02, "BE tlvInt byte1")
  assertEqual(tlvInt[4], 0x03, "BE tlvInt byte2")
  assertEqual(tlvInt[5], 0x04, "BE tlvInt byte3 LSB")

  // Frame header for 200-byte payload
  let frame = FrameCodec.encode(Data(count: 200))
  assertEqual(frame[0], 0x00, "BE frame header hi")
  assertEqual(frame[1], 200, "BE frame header lo")
}

// MARK: - TLV 255-Byte Limit

func testTlvLimits() {
  // Max value = 255 bytes (1-byte Len field)
  let maxValue = Data(0..<255)
  let encoded = BuzzelProtocol.tlvEncode(tag: 0x01, value: maxValue)
  assertEqual(encoded.count, 257, "tlvLimit max encoded size")
  let fields = BuzzelProtocol.tlvDecode(encoded)
  assertEqual(fields.count, 1, "tlvLimit max field count")
  assertEqual(fields[0].value.count, 255, "tlvLimit max value size")

  // Oversized truncated
  let oversized = Data(count: 300)
  let enc2 = BuzzelProtocol.tlvEncode(tag: 0x01, value: oversized)
  assertEqual(enc2.count, 257, "tlvLimit oversized encoded size")
  let f2 = BuzzelProtocol.tlvDecode(enc2)
  assertEqual(f2[0].value.count, 255, "tlvLimit oversized value size")

  // Zero-length value
  let empty = BuzzelProtocol.tlvEncode(tag: 0x01, value: Data())
  assertEqual(empty.count, 2, "tlvLimit empty encoded size")
  let f3 = BuzzelProtocol.tlvDecode(empty)
  assertEqual(f3.count, 1, "tlvLimit empty field count")
  assertEqual(f3[0].value.count, 0, "tlvLimit empty value size")

  // Single byte value
  let single = BuzzelProtocol.tlvEncode(tag: 0x05, value: Data([0xAB]))
  assertEqual(single.count, 3, "tlvLimit single size")
  let f4 = BuzzelProtocol.tlvDecode(single)
  assertEqual(f4[0].value[0], 0xAB, "tlvLimit single value")

  // String max 255
  let longStr = String(repeating: "a", count: 255)
  let strEnc = BuzzelProtocol.tlvEncodeString(tag: 0x01, value: longStr)
  let sf = BuzzelProtocol.tlvDecode(strEnc)
  assertEqual(BuzzelProtocol.tlvGetString(sf, tag: 0x01), longStr, "tlvLimit string max")

  // String oversized truncated
  let overStr = String(repeating: "a", count: 300)
  let overEnc = BuzzelProtocol.tlvEncodeString(tag: 0x01, value: overStr)
  let of = BuzzelProtocol.tlvDecode(overEnc)
  assertEqual(of[0].value.count, 255, "tlvLimit string oversized")
}

// MARK: - Malformed Input Edge Cases

func testMalformedInput() {
  // Empty payloads
  assertNil(BuzzelProtocol.parseCommand(Data()), "malformed command empty")
  assertNil(BuzzelProtocol.parsePairRequestCode(Data()), "malformed pairRequest empty")
  assertNil(BuzzelProtocol.parsePairResponse(Data()), "malformed pairResponse empty")
  assertNil(BuzzelProtocol.parseAckSeq(Data()), "malformed ackSeq empty")
  assertNil(BuzzelProtocol.parseSignalId(Data()), "malformed signalId empty")
  assertNil(BuzzelProtocol.parseQr(Data()), "malformed qr empty")

  // Wrong signal for ack
  assertNil(
    BuzzelProtocol.parseAckSeq(Data([Signal.ping, 0x00, 0x01])), "malformed ack wrong signal")

  // Exact minimum command size (4 bytes)
  let minCmd = Data([Signal.command, 0x10, 0x00, 0x00])
  let cmd = BuzzelProtocol.parseCommand(minCmd)
  assertNotNil(cmd, "malformed cmd minimum")
  assertEqual(cmd!.cmd, 0x10, "malformed cmd minimum cmd")
  assertEqual(cmd!.seq, 0, "malformed cmd minimum seq")
  assertEqual(cmd!.data.count, 0, "malformed cmd minimum data")

  // Truncated TLV: tag=0x01, len=5, but only 2 bytes of value
  let truncated = Data([0x01, 0x05, 0xAA, 0xBB])
  let tf = BuzzelProtocol.tlvDecode(truncated)
  assertEqual(tf.count, 0, "malformed tlv truncated")

  // Single byte — not enough for tag+len
  let singleByte = BuzzelProtocol.tlvDecode(Data([0x01]))
  assertEqual(singleByte.count, 0, "malformed tlv single byte")

  // Multiple TLV fields, last truncated
  let multiTrunc = Data([0x01, 0x01, 0xAA, 0x02, 0x03, 0xBB])
  let mtf = BuzzelProtocol.tlvDecode(multiTrunc)
  assertEqual(mtf.count, 1, "malformed tlv multi truncated count")
  assertEqual(mtf[0].tag, 0x01, "malformed tlv multi truncated tag")

  // tlvGetInt with value too short (2 bytes instead of 4)
  let shortInt = BuzzelProtocol.tlvEncode(tag: 0x01, value: Data([0x01, 0x02]))
  let sif = BuzzelProtocol.tlvDecode(shortInt)
  assertNil(BuzzelProtocol.tlvGetInt(sif, tag: 0x01), "malformed tlvGetInt short")

  // tlvGetByte with empty value
  let emptyByte = BuzzelProtocol.tlvEncode(tag: 0x01, value: Data())
  let ebf = BuzzelProtocol.tlvDecode(emptyByte)
  assertNil(BuzzelProtocol.tlvGetByte(ebf, tag: 0x01), "malformed tlvGetByte empty")

  // Pair request codes
  let code0 = BuzzelProtocol.parsePairRequestCode(BuzzelProtocol.createPairRequest(code: "000000"))
  assertEqual(code0, "000000", "malformed pairRequest all zeros")

  let code9 = BuzzelProtocol.parsePairRequestCode(BuzzelProtocol.createPairRequest(code: "999999"))
  assertEqual(code9, "999999", "malformed pairRequest all nines")

  // All pair.response reasons
  let r0 = BuzzelProtocol.parsePairResponse(
    BuzzelProtocol.createPairResponse(accepted: false, reason: 0x00))
  assertEqual(r0!.reason, 0x00, "malformed pairResponse reason 0x00")
  let r1 = BuzzelProtocol.parsePairResponse(
    BuzzelProtocol.createPairResponse(accepted: false, reason: 0x01))
  assertEqual(r1!.reason, 0x01, "malformed pairResponse reason 0x01")
  let r2 = BuzzelProtocol.parsePairResponse(
    BuzzelProtocol.createPairResponse(accepted: false, reason: 0x02))
  assertEqual(r2!.reason, 0x02, "malformed pairResponse reason 0x02")
}

// MARK: - FrameCodec Edge Cases

func testFrameCodecEdgeCases() {
  // Single byte payload
  let single = FrameCodec.encode(Data([0xFF]))
  assertEqual(single.count, 3, "frameEdge single size")
  assertEqual(single[0], 0x00, "frameEdge single h0")
  assertEqual(single[1], 0x01, "frameEdge single h1")
  assertEqual(single[2], 0xFF, "frameEdge single payload")

  // Oversized payload truncated (wifi default)
  let wifiMaxPayload = BuzzelProtocol.maxPayload(BuzzelProtocol.wifiMaxFrame)
  let oversized = FrameCodec.encode(Data(count: wifiMaxPayload + 100))
  assertEqual(oversized.count, wifiMaxPayload + 2, "frameEdge oversized size")

  // extractFrames: partial frame
  var partial = FrameCodec.encode(BuzzelProtocol.createPing())
  partial.append(Data([0x00, 0x05]))  // header says 5 bytes but no payload
  var partialFrames = [Data]()
  FrameCodec.extractFrames(from: &partial) { partialFrames.append($0) }
  assertEqual(partialFrames.count, 1, "frameEdge partial count")
  assertEqual(partialFrames[0][0], Signal.ping, "frameEdge partial ping")
  assertEqual(partial.count, 2, "frameEdge partial remaining")

  // extractFrames: empty buffer
  var emptyBuf = Data()
  var emptyFrames = [Data]()
  FrameCodec.extractFrames(from: &emptyBuf) { emptyFrames.append($0) }
  assertEqual(emptyFrames.count, 0, "frameEdge empty count")
  assertEqual(emptyBuf.count, 0, "frameEdge empty remaining")

  // extractFrames: header only (no payload bytes)
  var headerOnly = Data([0x00, 0x03])
  var headerFrames = [Data]()
  FrameCodec.extractFrames(from: &headerOnly) { headerFrames.append($0) }
  assertEqual(headerFrames.count, 0, "frameEdge headerOnly count")
  assertEqual(headerOnly.count, 2, "frameEdge headerOnly remaining")

  // extractFrames: invalid length (0)
  var invalidLen = Data([0x00, 0x00, 0x04])
  var invalidFrames = [Data]()
  FrameCodec.extractFrames(from: &invalidLen) { invalidFrames.append($0) }
  assertEqual(invalidFrames.count, 0, "frameEdge invalidLen count")
  assertEqual(invalidLen.count, 0, "frameEdge invalidLen reset")

  // extractFrames: three frames
  var three = FrameCodec.encode(BuzzelProtocol.createPing())
  three.append(FrameCodec.encode(BuzzelProtocol.createPong()))
  three.append(FrameCodec.encode(BuzzelProtocol.createReady()))
  var threeFrames = [Data]()
  FrameCodec.extractFrames(from: &three) { threeFrames.append($0) }
  assertEqual(threeFrames.count, 3, "frameEdge three count")
  assertEqual(threeFrames[0][0], Signal.ping, "frameEdge three ping")
  assertEqual(threeFrames[1][0], Signal.pong, "frameEdge three pong")
  assertEqual(threeFrames[2][0], Signal.ready, "frameEdge three ready")
  assertEqual(three.count, 0, "frameEdge three remaining")

  // Full round-trip: command with TLV through frame encode/decode
  var tlv = BuzzelProtocol.tlvEncodeString(tag: 0x01, value: "test")
  tlv.append(BuzzelProtocol.tlvEncodeInt(tag: 0x02, value: 42))
  let cmdPayload = BuzzelProtocol.createCommand(cmd: 0x10, seq: 100, tlvData: tlv)
  let frame = FrameCodec.encode(cmdPayload)
  let len = FrameCodec.decodeLength(frame)
  let extracted = frame.subdata(in: 2..<(2 + len))
  let cmd = BuzzelProtocol.parseCommand(extracted)
  assertNotNil(cmd, "frameEdge roundTrip cmd")
  assertEqual(cmd!.cmd, 0x10, "frameEdge roundTrip cmd byte")
  assertEqual(cmd!.seq, 100, "frameEdge roundTrip seq")
  let cmdFields = BuzzelProtocol.tlvDecode(cmd!.data)
  assertEqual(
    BuzzelProtocol.tlvGetString(cmdFields, tag: 0x01), "test", "frameEdge roundTrip string")
  assertEqual(BuzzelProtocol.tlvGetInt(cmdFields, tag: 0x02), 42, "frameEdge roundTrip int")
}

// MARK: - Dynamic Sizing

func testDynamicSizing() {
  // WiFi: maxFrame=4096
  assertEqual(BuzzelProtocol.maxPayload(4096), 4094, "dynamic wifi maxPayload")
  assertEqual(BuzzelProtocol.maxCmdData(4096), 4090, "dynamic wifi maxCmdData")
  assertEqual(BuzzelProtocol.maxTlvData(4096), 255, "dynamic wifi maxTlvData")  // capped by tlvMaxValue

  // BLE MTU 247 (Nokia 6): maxFrame=244
  assertEqual(BuzzelProtocol.maxFrameForMtu(247), 244, "dynamic mtu247 maxFrame")
  assertEqual(BuzzelProtocol.maxPayload(244), 242, "dynamic mtu247 maxPayload")
  assertEqual(BuzzelProtocol.maxCmdData(244), 238, "dynamic mtu247 maxCmdData")
  assertEqual(BuzzelProtocol.maxTlvData(244), 236, "dynamic mtu247 maxTlvData")  // 238 - 2 (tag+len)

  // BLE MTU 185 (iPhone): maxFrame=182
  assertEqual(BuzzelProtocol.maxFrameForMtu(185), 182, "dynamic mtu185 maxFrame")
  assertEqual(BuzzelProtocol.maxPayload(182), 180, "dynamic mtu185 maxPayload")
  assertEqual(BuzzelProtocol.maxCmdData(182), 176, "dynamic mtu185 maxCmdData")
  assertEqual(BuzzelProtocol.maxTlvData(182), 174, "dynamic mtu185 maxTlvData")  // 176 - 2 (tag+len)

  // BLE MTU 23 (minimum): maxFrame=20
  assertEqual(BuzzelProtocol.maxFrameForMtu(23), 20, "dynamic mtu23 maxFrame")
  assertEqual(BuzzelProtocol.maxPayload(20), 18, "dynamic mtu23 maxPayload")
  assertEqual(BuzzelProtocol.maxCmdData(20), 14, "dynamic mtu23 maxCmdData")
  assertEqual(BuzzelProtocol.maxTlvData(20), 12, "dynamic mtu23 maxTlvData")  // 14 - 2 (tag+len)

  // All session signals fit at minimum MTU (23)
  let minMaxPayload = BuzzelProtocol.maxPayload(BuzzelProtocol.maxFrameForMtu(23))  // 18
  assert(BuzzelProtocol.createPing().count <= minMaxPayload, "dynamic ping fits min MTU")
  assert(BuzzelProtocol.createPong().count <= minMaxPayload, "dynamic pong fits min MTU")
  assert(BuzzelProtocol.createReady().count <= minMaxPayload, "dynamic ready fits min MTU")
  assert(BuzzelProtocol.createGoodbye().count <= minMaxPayload, "dynamic goodbye fits min MTU")
  assert(BuzzelProtocol.createUnpair().count <= minMaxPayload, "dynamic unpair fits min MTU")
  assert(
    BuzzelProtocol.createPairRequest(code: "123456").count <= minMaxPayload,
    "dynamic pairRequest fits min MTU")
  assert(
    BuzzelProtocol.createPairResponse(accepted: true).count <= minMaxPayload,
    "dynamic pairResponse fits min MTU")
  assert(
    BuzzelProtocol.createAck(seq: 65535).count <= minMaxPayload, "dynamic ack fits min MTU")
}

// MARK: - Run

@main
struct TestRunner {
  static func main() {
    testQr()
    testSeedDerivation()
    testNoPayloadSignals()
    testPairRequest()
    testPairResponse()
    testAck()
    testParseSignalId()
    testCommand()
    testTlv()
    testFrameCodec()
    testWireSize()
    testBigEndian()
    testTlvLimits()
    testMalformedInput()
    testFrameCodecEdgeCases()
    testDynamicSizing()

    print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
    if !errors.isEmpty {
      for e in errors { print(e) }
    }
    exit(failed > 0 ? 1 : 0)
  }
}
