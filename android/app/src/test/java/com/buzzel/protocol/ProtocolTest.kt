package com.buzzel.protocol

import com.buzzel.transport.FrameCodec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class ProtocolTest {
    // Fixed seed: 0x00..0x0F
    private val seed = ByteArray(16) { it.toByte() }

    // Cross-platform expected values (verified with Python SHA256)
    private val expectedSessionId = "BE45CB26-05BF-36BE-BDE6-84841A28F0FD"
    private val expectedPairingCode = "279084"

    // --- QR ---

    @Test
    fun parseQr_valid() {
        val qr = buildQr(seed, "192.168.1.100", "wifi")
        val result = Protocol.parseQr(qr)
        assertNotNull(result)
        assertArrayEquals(seed, result!!.seed)
        assertEquals("192.168.1.100", result.host)
        assertEquals("wifi", result.prefer)
    }

    @Test
    fun parseQr_blePrefer() {
        val qr = buildQr(seed, "10.0.0.1", "ble")
        val result = Protocol.parseQr(qr)
        assertNotNull(result)
        assertEquals("10.0.0.1", result!!.host)
        assertEquals("ble", result.prefer)
    }

    @Test
    fun parseQr_wrongSize() {
        assertNull(Protocol.parseQr(ByteArray(10)))
        assertNull(Protocol.parseQr(ByteArray(25)))
    }

    @Test
    fun parseQr_wrongMagic() {
        val qr = buildQr(seed, "192.168.1.1", "wifi")
        qr[0] = 0xFF.toByte()
        assertNull(Protocol.parseQr(qr))
    }

    // --- Seed Derivation ---

    @Test
    fun deriveSessionId_crossPlatform() {
        assertEquals(expectedSessionId, Protocol.deriveSessionId(seed))
    }

    @Test
    fun derivePairingCode_crossPlatform() {
        assertEquals(expectedPairingCode, Protocol.derivePairingCode(seed))
    }

    @Test
    fun derivePairingCode_zeroPadded() {
        // Verify it's always 6 digits
        val code = Protocol.derivePairingCode(seed)
        assertEquals(6, code.length)
        assertTrue(code.all { it.isDigit() })
    }

    // --- Signals: no-payload ---

    @Test
    fun createPing() {
        val p = Protocol.createPing()
        assertEquals(1, p.size)
        assertEquals(Signal.PING, p[0])
    }

    @Test
    fun createPong() {
        val p = Protocol.createPong()
        assertEquals(1, p.size)
        assertEquals(Signal.PONG, p[0])
    }

    @Test
    fun createReady() {
        val p = Protocol.createReady()
        assertEquals(1, p.size)
        assertEquals(Signal.READY, p[0])
    }

    @Test
    fun createGoodbye() {
        val p = Protocol.createGoodbye()
        assertEquals(1, p.size)
        assertEquals(Signal.GOODBYE, p[0])
    }

    @Test
    fun createUnpair() {
        val p = Protocol.createUnpair()
        assertEquals(1, p.size)
        assertEquals(Signal.UNPAIR, p[0])
    }

    // --- pair.request ---

    @Test
    fun pairRequest_roundTrip() {
        val payload = Protocol.createPairRequest("123456")
        assertEquals(7, payload.size)
        assertEquals(Signal.PAIR_REQUEST, payload[0])
        val code = Protocol.parsePairRequestCode(payload)
        assertEquals("123456", code)
    }

    @Test
    fun parsePairRequestCode_wrongSignal() {
        assertNull(Protocol.parsePairRequestCode(byteArrayOf(0x99.toByte(), 0x31, 0x32, 0x33, 0x34, 0x35, 0x36)))
    }

    @Test
    fun parsePairRequestCode_tooShort() {
        assertNull(Protocol.parsePairRequestCode(byteArrayOf(Signal.PAIR_REQUEST, 0x31)))
    }

    // --- pair.response ---

    @Test
    fun pairResponse_accepted() {
        val payload = Protocol.createPairResponse(accepted = true)
        assertEquals(3, payload.size)
        assertEquals(Signal.PAIR_RESPONSE, payload[0])
        val result = Protocol.parsePairResponse(payload)
        assertNotNull(result)
        assertTrue(result!!.first)
        assertEquals(0x00.toByte(), result.second)
    }

    @Test
    fun pairResponse_rejected() {
        val payload = Protocol.createPairResponse(accepted = false, reason = 0x01)
        val result = Protocol.parsePairResponse(payload)
        assertNotNull(result)
        assertFalse(result!!.first)
        assertEquals(0x01.toByte(), result.second)
    }

    @Test
    fun parsePairResponse_tooShort() {
        assertNull(Protocol.parsePairResponse(byteArrayOf(Signal.PAIR_RESPONSE, 0x01)))
    }

    // --- ack ---

    @Test
    fun ack_roundTrip() {
        val payload = Protocol.createAck(42)
        assertEquals(3, payload.size)
        assertEquals(Signal.ACK, payload[0])
        assertEquals(42, Protocol.parseAckSeq(payload))
    }

    @Test
    fun ack_maxSeq() {
        val payload = Protocol.createAck(65535)
        assertEquals(65535, Protocol.parseAckSeq(payload))
    }

    @Test
    fun ack_zero() {
        val payload = Protocol.createAck(0)
        assertEquals(0, Protocol.parseAckSeq(payload))
    }

    @Test
    fun parseAckSeq_tooShort() {
        assertNull(Protocol.parseAckSeq(byteArrayOf(Signal.ACK)))
    }

    // --- parseSignalId ---

    @Test
    fun parseSignalId_all() {
        assertEquals(Signal.COMMAND, Protocol.parseSignalId(byteArrayOf(0x00)))
        assertEquals(Signal.PAIR_REQUEST, Protocol.parseSignalId(byteArrayOf(0x01)))
        assertEquals(Signal.PING, Protocol.parseSignalId(byteArrayOf(0x04)))
        assertEquals(Signal.UNPAIR, Protocol.parseSignalId(byteArrayOf(0x08)))
    }

    @Test
    fun parseSignalId_empty() {
        assertEquals((-1).toByte(), Protocol.parseSignalId(ByteArray(0)))
    }

    // --- Command ---

    @Test
    fun command_roundTrip() {
        val tlv = Protocol.tlvEncodeString(0x01, "hello")
        val payload = Protocol.createCommand(0x30, 5, tlv)
        assertEquals(Signal.COMMAND, payload[0])

        val cmd = Protocol.parseCommand(payload)
        assertNotNull(cmd)
        assertEquals(0x30.toByte(), cmd!!.cmd)
        assertEquals(5, cmd.seq)
        assertArrayEquals(tlv, cmd.data)
    }

    @Test
    fun command_emptyData() {
        val payload = Protocol.createCommand(0x10, 0)
        val cmd = Protocol.parseCommand(payload)
        assertNotNull(cmd)
        assertEquals(0x10.toByte(), cmd!!.cmd)
        assertEquals(0, cmd.seq)
        assertEquals(0, cmd.data.size)
    }

    @Test
    fun command_maxSeq() {
        val payload = Protocol.createCommand(0x01, 65535)
        val cmd = Protocol.parseCommand(payload)
        assertNotNull(cmd)
        assertEquals(65535, cmd!!.seq)
    }

    @Test
    fun command_maxTlvData() {
        val bigData = ByteArray(250) { it.toByte() }
        val payload = Protocol.createCommand(0x01, 1, bigData)
        val cmd = Protocol.parseCommand(payload)
        assertNotNull(cmd)
        assertEquals(250, cmd!!.data.size)
    }

    @Test
    fun command_truncatesOversize() {
        val oversized = ByteArray(300) { it.toByte() }
        val payload = Protocol.createCommand(0x01, 1, oversized)
        val cmd = Protocol.parseCommand(payload)
        assertNotNull(cmd)
        assertEquals(Protocol.MAX_TLV_DATA, cmd!!.data.size)
    }

    @Test
    fun parseCommand_tooShort() {
        assertNull(Protocol.parseCommand(byteArrayOf(Signal.COMMAND, 0x01, 0x00)))
    }

    @Test
    fun parseCommand_wrongSignal() {
        assertNull(Protocol.parseCommand(byteArrayOf(Signal.PING, 0x01, 0x00, 0x01)))
    }

    // --- TLV ---

    @Test
    fun tlv_roundTrip() {
        val encoded = Protocol.tlvEncode(0x01, byteArrayOf(0x0A, 0x0B, 0x0C))
        assertEquals(5, encoded.size) // tag(1) + len(1) + value(3)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(1, fields.size)
        assertEquals(0x01.toByte(), fields[0].tag)
        assertArrayEquals(byteArrayOf(0x0A, 0x0B, 0x0C), fields[0].value)
    }

    @Test
    fun tlvString_roundTrip() {
        val encoded = Protocol.tlvEncodeString(0x10, "hello")
        val fields = Protocol.tlvDecode(encoded)
        assertEquals("hello", Protocol.tlvGetString(fields, 0x10))
    }

    @Test
    fun tlvInt_roundTrip() {
        val encoded = Protocol.tlvEncodeInt(0x20, 42)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(42, Protocol.tlvGetInt(fields, 0x20))
    }

    @Test
    fun tlvByte_roundTrip() {
        val encoded = Protocol.tlvEncodeByte(0x30, 0xFF.toByte())
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(0xFF.toByte(), Protocol.tlvGetByte(fields, 0x30))
    }

    @Test
    fun tlv_multipleFields() {
        val buf =
            Protocol.tlvEncodeString(0x01, "a") +
                Protocol.tlvEncodeInt(0x02, 99) +
                Protocol.tlvEncodeByte(0x03, 0x07)
        val fields = Protocol.tlvDecode(buf)
        assertEquals(3, fields.size)
        assertEquals("a", Protocol.tlvGetString(fields, 0x01))
        assertEquals(99, Protocol.tlvGetInt(fields, 0x02))
        assertEquals(0x07.toByte(), Protocol.tlvGetByte(fields, 0x03))
    }

    @Test
    fun tlv_missingTag() {
        val encoded = Protocol.tlvEncodeString(0x01, "x")
        val fields = Protocol.tlvDecode(encoded)
        assertNull(Protocol.tlvGetString(fields, 0x99.toByte()))
        assertNull(Protocol.tlvGetInt(fields, 0x99.toByte()))
        assertNull(Protocol.tlvGetByte(fields, 0x99.toByte()))
    }

    @Test
    fun tlv_emptyData() {
        val fields = Protocol.tlvDecode(ByteArray(0))
        assertTrue(fields.isEmpty())
    }

    // --- FrameCodec ---

    @Test
    fun frameCodec_encode() {
        val payload = byteArrayOf(0x04) // ping
        val frame = FrameCodec.encode(payload)
        assertEquals(3, frame.size)
        // 2-byte BE header
        assertEquals(0x00.toByte(), frame[0])
        assertEquals(0x01.toByte(), frame[1])
        assertEquals(0x04.toByte(), frame[2])
    }

    @Test
    fun frameCodec_decodeLength() {
        val frame = FrameCodec.encode(byteArrayOf(0x01, 0x02, 0x03))
        val header = frame.copyOfRange(0, 2)
        assertEquals(3, FrameCodec.decodeLength(header))
    }

    @Test
    fun frameCodec_maxPayload() {
        val payload = ByteArray(FrameCodec.MAX_PAYLOAD) { it.toByte() }
        val frame = FrameCodec.encode(payload)
        assertEquals(FrameCodec.MAX_PAYLOAD + 2, frame.size)
        val header = frame.copyOfRange(0, 2)
        assertEquals(FrameCodec.MAX_PAYLOAD, FrameCodec.decodeLength(header))
    }

    @Test
    fun frameCodec_extractFrames() {
        val ping = FrameCodec.encode(Protocol.createPing())
        val pong = FrameCodec.encode(Protocol.createPong())
        val combined = ping + pong
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(combined) { frames.add(it) }
        assertEquals(2, frames.size)
        assertEquals(Signal.PING, frames[0][0])
        assertEquals(Signal.PONG, frames[1][0])
        assertEquals(0, remaining.size)
    }

    // --- Wire Size Verification ---

    @Test
    fun wireSize_ping() {
        val frame = FrameCodec.encode(Protocol.createPing())
        assertEquals(3, frame.size) // 2-byte header + 1-byte payload
    }

    @Test
    fun wireSize_pong() {
        val frame = FrameCodec.encode(Protocol.createPong())
        assertEquals(3, frame.size)
    }

    @Test
    fun wireSize_ready() {
        val frame = FrameCodec.encode(Protocol.createReady())
        assertEquals(3, frame.size)
    }

    @Test
    fun wireSize_goodbye() {
        val frame = FrameCodec.encode(Protocol.createGoodbye())
        assertEquals(3, frame.size)
    }

    @Test
    fun wireSize_unpair() {
        val frame = FrameCodec.encode(Protocol.createUnpair())
        assertEquals(3, frame.size)
    }

    @Test
    fun wireSize_pairRequest() {
        val frame = FrameCodec.encode(Protocol.createPairRequest("123456"))
        assertEquals(9, frame.size) // 2-byte header + 7-byte payload
    }

    @Test
    fun wireSize_pairResponse() {
        val frame = FrameCodec.encode(Protocol.createPairResponse(true))
        assertEquals(5, frame.size) // 2-byte header + 3-byte payload
    }

    @Test
    fun wireSize_ack() {
        val frame = FrameCodec.encode(Protocol.createAck(1))
        assertEquals(5, frame.size) // 2-byte header + 3-byte payload
    }

    @Test
    fun wireSize_commandEmpty() {
        val frame = FrameCodec.encode(Protocol.createCommand(0x01, 0))
        assertEquals(6, frame.size) // 2-byte header + 4-byte payload (signal + cmd + seq*2)
    }

    @Test
    fun wireSize_commandMaxTlv() {
        val tlv = ByteArray(Protocol.MAX_TLV_DATA)
        val frame = FrameCodec.encode(Protocol.createCommand(0x01, 0, tlv))
        assertEquals(Protocol.MAX_FRAME, frame.size) // exactly 256 bytes
    }

    // --- Big-Endian Byte-Level Verification ---

    @Test
    fun bigEndian_ackSeq_0x0100() {
        val payload = Protocol.createAck(0x0100)
        assertEquals(Signal.ACK, payload[0])
        assertEquals(0x01.toByte(), payload[1]) // high byte
        assertEquals(0x00.toByte(), payload[2]) // low byte
    }

    @Test
    fun bigEndian_ackSeq_0xFF00() {
        val payload = Protocol.createAck(0xFF00)
        assertEquals(0xFF.toByte(), payload[1])
        assertEquals(0x00.toByte(), payload[2])
    }

    @Test
    fun bigEndian_ackSeq_0x00FF() {
        val payload = Protocol.createAck(0x00FF)
        assertEquals(0x00.toByte(), payload[1])
        assertEquals(0xFF.toByte(), payload[2])
    }

    @Test
    fun bigEndian_commandSeq() {
        val payload = Protocol.createCommand(0x30, 0x0102)
        assertEquals(Signal.COMMAND, payload[0])
        assertEquals(0x30.toByte(), payload[1]) // cmd
        assertEquals(0x01.toByte(), payload[2]) // seq high
        assertEquals(0x02.toByte(), payload[3]) // seq low
    }

    @Test
    fun bigEndian_tlvInt() {
        val encoded = Protocol.tlvEncodeInt(0x01, 0x01020304)
        // tag=0x01, len=4, value=01 02 03 04
        assertEquals(0x01.toByte(), encoded[0]) // tag
        assertEquals(0x04.toByte(), encoded[1]) // len
        assertEquals(0x01.toByte(), encoded[2]) // int byte 0 (MSB)
        assertEquals(0x02.toByte(), encoded[3]) // int byte 1
        assertEquals(0x03.toByte(), encoded[4]) // int byte 2
        assertEquals(0x04.toByte(), encoded[5]) // int byte 3 (LSB)
    }

    @Test
    fun bigEndian_frameHeader() {
        val payload = ByteArray(200) { 0x00 }
        val frame = FrameCodec.encode(payload)
        assertEquals(0x00.toByte(), frame[0]) // high byte
        assertEquals(200.toByte(), frame[1]) // low byte = 0xC8
    }

    // --- TLV 248-Byte Limit ---

    @Test
    fun tlv_maxValueSize() {
        val value = ByteArray(248) { it.toByte() }
        val encoded = Protocol.tlvEncode(0x01, value)
        assertEquals(250, encoded.size) // tag(1) + len(1) + value(248)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(1, fields.size)
        assertEquals(248, fields[0].value.size)
    }

    @Test
    fun tlv_oversizedValueTruncated() {
        val value = ByteArray(300) { it.toByte() }
        val encoded = Protocol.tlvEncode(0x01, value)
        assertEquals(250, encoded.size) // tag(1) + len(1) + capped at 248
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(248, fields[0].value.size)
    }

    @Test
    fun tlv_zeroLengthValue() {
        val encoded = Protocol.tlvEncode(0x01, ByteArray(0))
        assertEquals(2, encoded.size) // tag(1) + len(1)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(1, fields.size)
        assertEquals(0, fields[0].value.size)
    }

    @Test
    fun tlv_singleByteValue() {
        val encoded = Protocol.tlvEncode(0x05, byteArrayOf(0xAB.toByte()))
        assertEquals(3, encoded.size)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(0xAB.toByte(), fields[0].value[0])
    }

    @Test
    fun tlv_stringMaxLength() {
        val longStr = "a".repeat(248)
        val encoded = Protocol.tlvEncodeString(0x01, longStr)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(longStr, Protocol.tlvGetString(fields, 0x01))
    }

    @Test
    fun tlv_stringOversizedTruncated() {
        val longStr = "a".repeat(300)
        val encoded = Protocol.tlvEncodeString(0x01, longStr)
        val fields = Protocol.tlvDecode(encoded)
        assertEquals(248, fields[0].value.size)
    }

    // --- Malformed Input Edge Cases ---

    @Test
    fun parseCommand_emptyPayload() {
        assertNull(Protocol.parseCommand(ByteArray(0)))
    }

    @Test
    fun parsePairRequest_emptyPayload() {
        assertNull(Protocol.parsePairRequestCode(ByteArray(0)))
    }

    @Test
    fun parsePairResponse_emptyPayload() {
        assertNull(Protocol.parsePairResponse(ByteArray(0)))
    }

    @Test
    fun parseAckSeq_emptyPayload() {
        assertNull(Protocol.parseAckSeq(ByteArray(0)))
    }

    @Test
    fun parseAckSeq_wrongSignal() {
        assertNull(Protocol.parseAckSeq(byteArrayOf(Signal.PING, 0x00, 0x01)))
    }

    @Test
    fun parseCommand_exactlyMinimumSize() {
        // 4 bytes = signal + cmd + seq(2), no TLV data
        val payload = byteArrayOf(Signal.COMMAND, 0x10, 0x00, 0x00)
        val cmd = Protocol.parseCommand(payload)
        assertNotNull(cmd)
        assertEquals(0x10.toByte(), cmd!!.cmd)
        assertEquals(0, cmd.seq)
        assertEquals(0, cmd.data.size)
    }

    @Test
    fun tlvDecode_truncatedField() {
        // tag=0x01, len=5, but only 2 bytes of value follow
        val truncated = byteArrayOf(0x01, 0x05, 0xAA.toByte(), 0xBB.toByte())
        val fields = Protocol.tlvDecode(truncated)
        assertEquals(0, fields.size) // should skip truncated field
    }

    @Test
    fun tlvDecode_singleByte() {
        // Only 1 byte — not enough for tag+len
        val fields = Protocol.tlvDecode(byteArrayOf(0x01))
        assertEquals(0, fields.size)
    }

    @Test
    fun tlvDecode_multipleWithLastTruncated() {
        // First field valid: tag=0x01, len=1, value=0xAA
        // Second field truncated: tag=0x02, len=3, but only 1 byte
        val data = byteArrayOf(0x01, 0x01, 0xAA.toByte(), 0x02, 0x03, 0xBB.toByte())
        val fields = Protocol.tlvDecode(data)
        assertEquals(1, fields.size) // only first field should parse
        assertEquals(0x01.toByte(), fields[0].tag)
    }

    @Test
    fun tlvGetInt_tooShortValue() {
        // Encode a 2-byte value but try to read as int (needs 4 bytes)
        val encoded = Protocol.tlvEncode(0x01, byteArrayOf(0x01, 0x02))
        val fields = Protocol.tlvDecode(encoded)
        assertNull(Protocol.tlvGetInt(fields, 0x01))
    }

    @Test
    fun tlvGetByte_emptyValue() {
        val encoded = Protocol.tlvEncode(0x01, ByteArray(0))
        val fields = Protocol.tlvDecode(encoded)
        assertNull(Protocol.tlvGetByte(fields, 0x01))
    }

    @Test
    fun parseQr_emptyPayload() {
        assertNull(Protocol.parseQr(ByteArray(0)))
    }

    @Test
    fun pairRequest_exactCode() {
        // Code exactly 6 chars
        val payload = Protocol.createPairRequest("000000")
        val code = Protocol.parsePairRequestCode(payload)
        assertEquals("000000", code)
    }

    @Test
    fun pairRequest_numericCodes() {
        val payload = Protocol.createPairRequest("999999")
        val code = Protocol.parsePairRequestCode(payload)
        assertEquals("999999", code)
    }

    @Test
    fun pairResponse_allReasons() {
        // reason 0x00 = success
        val r0 = Protocol.parsePairResponse(Protocol.createPairResponse(false, 0x00))
        assertEquals(0x00.toByte(), r0!!.second)
        // reason 0x01 = code mismatch
        val r1 = Protocol.parsePairResponse(Protocol.createPairResponse(false, 0x01))
        assertEquals(0x01.toByte(), r1!!.second)
        // reason 0x02 = user rejected
        val r2 = Protocol.parsePairResponse(Protocol.createPairResponse(false, 0x02))
        assertEquals(0x02.toByte(), r2!!.second)
    }

    // --- FrameCodec Edge Cases ---

    @Test
    fun frameCodec_singleBytePayload() {
        val frame = FrameCodec.encode(byteArrayOf(0xFF.toByte()))
        assertEquals(3, frame.size)
        assertEquals(0x00.toByte(), frame[0])
        assertEquals(0x01.toByte(), frame[1])
        assertEquals(0xFF.toByte(), frame[2])
    }

    @Test
    fun frameCodec_oversizedPayloadTruncated() {
        val payload = ByteArray(300) { it.toByte() }
        val frame = FrameCodec.encode(payload)
        assertEquals(FrameCodec.MAX_PAYLOAD + 2, frame.size) // capped at 254 + 2
    }

    @Test
    fun frameCodec_extractFrames_partialFrame() {
        // Complete frame (ping) + partial frame header
        val ping = FrameCodec.encode(Protocol.createPing())
        val partial = ping + byteArrayOf(0x00, 0x05) // header says 5 bytes but no payload
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(partial) { frames.add(it) }
        assertEquals(1, frames.size)
        assertEquals(Signal.PING, frames[0][0])
        assertEquals(2, remaining.size) // the partial header remains
    }

    @Test
    fun frameCodec_extractFrames_emptyBuffer() {
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(ByteArray(0)) { frames.add(it) }
        assertEquals(0, frames.size)
        assertEquals(0, remaining.size)
    }

    @Test
    fun frameCodec_extractFrames_headerOnly() {
        // Just 2 bytes (header) with no payload
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(byteArrayOf(0x00, 0x03)) { frames.add(it) }
        assertEquals(0, frames.size)
        assertEquals(2, remaining.size)
    }

    @Test
    fun frameCodec_extractFrames_invalidLength() {
        // length=0 is invalid per implementation
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(byteArrayOf(0x00, 0x00, 0x04)) { frames.add(it) }
        assertEquals(0, frames.size)
        assertEquals(0, remaining.size) // buffer reset on invalid
    }

    @Test
    fun frameCodec_extractFrames_threeFrames() {
        val ping = FrameCodec.encode(Protocol.createPing())
        val pong = FrameCodec.encode(Protocol.createPong())
        val ready = FrameCodec.encode(Protocol.createReady())
        val combined = ping + pong + ready
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(combined) { frames.add(it) }
        assertEquals(3, frames.size)
        assertEquals(Signal.PING, frames[0][0])
        assertEquals(Signal.PONG, frames[1][0])
        assertEquals(Signal.READY, frames[2][0])
        assertEquals(0, remaining.size)
    }

    @Test
    fun frameCodec_roundTrip_command() {
        val tlv = Protocol.tlvEncodeString(0x01, "test") + Protocol.tlvEncodeInt(0x02, 42)
        val payload = Protocol.createCommand(0x10, 100, tlv)
        val frame = FrameCodec.encode(payload)
        val header = frame.copyOfRange(0, 2)
        val len = FrameCodec.decodeLength(header)
        val extracted = frame.copyOfRange(2, 2 + len)
        val cmd = Protocol.parseCommand(extracted)
        assertNotNull(cmd)
        assertEquals(0x10.toByte(), cmd!!.cmd)
        assertEquals(100, cmd.seq)
        assertEquals("test", Protocol.tlvGetString(Protocol.tlvDecode(cmd.data), 0x01))
        assertEquals(42, Protocol.tlvGetInt(Protocol.tlvDecode(cmd.data), 0x02))
    }

    // --- Helpers ---

    private fun buildQr(
        seed: ByteArray,
        host: String,
        prefer: String,
    ): ByteArray {
        val buf = ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN)
        buf.putShort(0xBC1B.toShort())
        buf.put(seed)
        host.split(".").forEach { buf.put(it.toInt().toByte()) }
        buf.put(if (prefer == "ble") 0x01 else 0x00)
        buf.put(0x00) // reserved
        return buf.array()
    }
}
