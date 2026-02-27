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
    private val expectedSessionIdentifier = "BE45CB26-05BF-36BE-BDE6-84841A28F0FD"
    private val expectedPairingCode = "279084"

    // --- QR Code ---

    @Test
    fun parseQRCodePayload_valid() {
        val qrData = buildQRCodePayload(seed, "192.168.1.100", "wifi")
        val result = Protocol.parseQRCodePayload(qrData)
        assertNotNull(result)
        assertArrayEquals(seed, result!!.seed)
        assertEquals("192.168.1.100", result.host)
        assertEquals("wifi", result.preferredTransport)
    }

    @Test
    fun parseQRCodePayload_blePreferred() {
        val qrData = buildQRCodePayload(seed, "10.0.0.1", "ble")
        val result = Protocol.parseQRCodePayload(qrData)
        assertNotNull(result)
        assertEquals("10.0.0.1", result!!.host)
        assertEquals("ble", result.preferredTransport)
    }

    @Test
    fun parseQRCodePayload_wrongSize() {
        assertNull(Protocol.parseQRCodePayload(ByteArray(10)))
        assertNull(Protocol.parseQRCodePayload(ByteArray(25)))
    }

    @Test
    fun parseQRCodePayload_wrongMagic() {
        val qrData = buildQRCodePayload(seed, "192.168.1.1", "wifi")
        qrData[0] = 0xFF.toByte()
        assertNull(Protocol.parseQRCodePayload(qrData))
    }

    // --- Seed Derivation ---

    @Test
    fun deriveSessionIdentifier_crossPlatform() {
        assertEquals(expectedSessionIdentifier, Protocol.deriveSessionIdentifier(seed))
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
        val payload = Protocol.createPing()
        assertEquals(1, payload.size)
        assertEquals(Signal.PING, payload[0])
    }

    @Test
    fun createPong() {
        val payload = Protocol.createPong()
        assertEquals(1, payload.size)
        assertEquals(Signal.PONG, payload[0])
    }

    @Test
    fun createReady() {
        val payload = Protocol.createReady()
        assertEquals(1, payload.size)
        assertEquals(Signal.READY, payload[0])
        assertNull(Protocol.parseReadyDeviceName(payload))
    }

    @Test
    fun createReadyWithDeviceName() {
        val payload = Protocol.createReady("Pixel 7")
        assertEquals(Signal.READY, payload[0])
        assertEquals(1 + "Pixel 7".toByteArray(Charsets.UTF_8).size, payload.size)
        assertEquals("Pixel 7", Protocol.parseReadyDeviceName(payload))
    }

    @Test
    fun parseReadyDeviceNameEmpty() {
        assertNull(Protocol.parseReadyDeviceName(byteArrayOf()))
    }

    @Test
    fun createGoodbye() {
        val payload = Protocol.createGoodbye()
        assertEquals(1, payload.size)
        assertEquals(Signal.GOODBYE, payload[0])
    }

    @Test
    fun createUnpair() {
        val payload = Protocol.createUnpair()
        assertEquals(1, payload.size)
        assertEquals(Signal.UNPAIR, payload[0])
    }

    @Test
    fun createFocus() {
        val payload = Protocol.createFocus()
        assertEquals(1, payload.size)
        assertEquals(Signal.FOCUS, payload[0])
    }

    @Test
    fun createBlur() {
        val payload = Protocol.createBlur()
        assertEquals(1, payload.size)
        assertEquals(Signal.BLUR, payload[0])
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

    // --- acknowledgment ---

    @Test
    fun acknowledgment_roundTrip() {
        val payload = Protocol.createAcknowledgment(42)
        assertEquals(3, payload.size)
        assertEquals(Signal.ACKNOWLEDGMENT, payload[0])
        assertEquals(42, Protocol.parseAcknowledgmentSequenceNumber(payload))
    }

    @Test
    fun acknowledgment_maxSequenceNumber() {
        val payload = Protocol.createAcknowledgment(65535)
        assertEquals(65535, Protocol.parseAcknowledgmentSequenceNumber(payload))
    }

    @Test
    fun acknowledgment_zero() {
        val payload = Protocol.createAcknowledgment(0)
        assertEquals(0, Protocol.parseAcknowledgmentSequenceNumber(payload))
    }

    @Test
    fun parseAcknowledgmentSequenceNumber_tooShort() {
        assertNull(Protocol.parseAcknowledgmentSequenceNumber(byteArrayOf(Signal.ACKNOWLEDGMENT)))
    }

    // --- parseSignalIdentifier ---

    @Test
    fun parseSignalIdentifier_all() {
        assertEquals(Signal.COMMAND, Protocol.parseSignalIdentifier(byteArrayOf(0x00)))
        assertEquals(Signal.PAIR_REQUEST, Protocol.parseSignalIdentifier(byteArrayOf(0x01)))
        assertEquals(Signal.PING, Protocol.parseSignalIdentifier(byteArrayOf(0x04)))
        assertEquals(Signal.UNPAIR, Protocol.parseSignalIdentifier(byteArrayOf(0x08)))
        assertEquals(Signal.FOCUS, Protocol.parseSignalIdentifier(byteArrayOf(0x09)))
        assertEquals(Signal.BLUR, Protocol.parseSignalIdentifier(byteArrayOf(0x0A)))
    }

    @Test
    fun parseSignalIdentifier_empty() {
        assertEquals((-1).toByte(), Protocol.parseSignalIdentifier(ByteArray(0)))
    }

    // --- Command ---

    @Test
    fun command_roundTrip() {
        val tagLengthValueData = Protocol.encodeTagLengthValueString(0x01, "hello")
        val payload = Protocol.createCommand(0x30, 5, tagLengthValueData)
        assertEquals(Signal.COMMAND, payload[0])

        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(0x30.toByte(), command!!.commandIdentifier)
        assertEquals(5, command.sequenceNumber)
        assertArrayEquals(tagLengthValueData, command.data)
    }

    @Test
    fun command_emptyData() {
        val payload = Protocol.createCommand(0x10, 0)
        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(0x10.toByte(), command!!.commandIdentifier)
        assertEquals(0, command.sequenceNumber)
        assertEquals(0, command.data.size)
    }

    @Test
    fun command_maxSequenceNumber() {
        val payload = Protocol.createCommand(0x01, 65535)
        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(65535, command!!.sequenceNumber)
    }

    @Test
    fun command_maxTagLengthValueData() {
        val bigData = ByteArray(255) { it.toByte() }
        val payload = Protocol.createCommand(0x01, 1, bigData)
        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(255, command!!.data.size)
    }

    @Test
    fun command_truncatesOversize() {
        val oversized = ByteArray(300) { it.toByte() }
        val payload = Protocol.createCommand(0x01, 1, oversized)
        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(Protocol.TAG_LENGTH_VALUE_MAXIMUM_VALUE_SIZE, command!!.data.size)
    }

    @Test
    fun command_truncatesWithCustomMaximumTagLengthValueDataSize() {
        val oversized = ByteArray(300) { it.toByte() }
        val maximumFrameSize = Protocol.maximumFrameSizeForMaximumTransmissionUnit(247)
        val maximumTagLengthValueDataSize = Protocol.maximumTagLengthValueDataSize(maximumFrameSize)
        val payload = Protocol.createCommand(0x01, 1, oversized, maximumTagLengthValueDataSize)
        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(maximumTagLengthValueDataSize, command!!.data.size)
    }

    @Test
    fun parseCommand_tooShort() {
        assertNull(Protocol.parseCommand(byteArrayOf(Signal.COMMAND, 0x01, 0x00)))
    }

    @Test
    fun parseCommand_wrongSignal() {
        assertNull(Protocol.parseCommand(byteArrayOf(Signal.PING, 0x01, 0x00, 0x01)))
    }

    // --- Tag-Length-Value ---

    @Test
    fun tagLengthValue_roundTrip() {
        val encoded = Protocol.encodeTagLengthValue(0x01, byteArrayOf(0x0A, 0x0B, 0x0C))
        assertEquals(5, encoded.size) // tag(1) + len(1) + value(3)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(1, fields.size)
        assertEquals(0x01.toByte(), fields[0].tag)
        assertArrayEquals(byteArrayOf(0x0A, 0x0B, 0x0C), fields[0].value)
    }

    @Test
    fun tagLengthValueString_roundTrip() {
        val encoded = Protocol.encodeTagLengthValueString(0x10, "hello")
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals("hello", Protocol.getTagLengthValueString(fields, 0x10))
    }

    @Test
    fun tagLengthValueInteger_roundTrip() {
        val encoded = Protocol.encodeTagLengthValueInteger(0x20, 42)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(42, Protocol.getTagLengthValueInteger(fields, 0x20))
    }

    @Test
    fun tagLengthValueByte_roundTrip() {
        val encoded = Protocol.encodeTagLengthValueByte(0x30, 0xFF.toByte())
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(0xFF.toByte(), Protocol.getTagLengthValueByte(fields, 0x30))
    }

    @Test
    fun tagLengthValue_multipleFields() {
        val buffer =
            Protocol.encodeTagLengthValueString(0x01, "a") +
                Protocol.encodeTagLengthValueInteger(0x02, 99) +
                Protocol.encodeTagLengthValueByte(0x03, 0x07)
        val fields = Protocol.decodeTagLengthValue(buffer)
        assertEquals(3, fields.size)
        assertEquals("a", Protocol.getTagLengthValueString(fields, 0x01))
        assertEquals(99, Protocol.getTagLengthValueInteger(fields, 0x02))
        assertEquals(0x07.toByte(), Protocol.getTagLengthValueByte(fields, 0x03))
    }

    @Test
    fun tagLengthValue_missingTag() {
        val encoded = Protocol.encodeTagLengthValueString(0x01, "x")
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertNull(Protocol.getTagLengthValueString(fields, 0x99.toByte()))
        assertNull(Protocol.getTagLengthValueInteger(fields, 0x99.toByte()))
        assertNull(Protocol.getTagLengthValueByte(fields, 0x99.toByte()))
    }

    @Test
    fun tagLengthValue_emptyData() {
        val fields = Protocol.decodeTagLengthValue(ByteArray(0))
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
    fun frameCodec_maximumPayloadSize_wifi() {
        val wifiMaximumPayloadSize = Protocol.maximumPayloadSize(Protocol.WIFI_MAXIMUM_FRAME_SIZE)
        val payload = ByteArray(wifiMaximumPayloadSize) { it.toByte() }
        val frame = FrameCodec.encode(payload)
        assertEquals(wifiMaximumPayloadSize + 2, frame.size)
        val header = frame.copyOfRange(0, 2)
        assertEquals(wifiMaximumPayloadSize, FrameCodec.decodeLength(header))
    }

    @Test
    fun frameCodec_maximumPayloadSize_ble() {
        val maximumTransmissionUnit = 247
        val maximumFrameSize = Protocol.maximumFrameSizeForMaximumTransmissionUnit(maximumTransmissionUnit)
        val bluetoothMaximumPayloadSize = Protocol.maximumPayloadSize(maximumFrameSize)
        val payload = ByteArray(bluetoothMaximumPayloadSize) { it.toByte() }
        val frame = FrameCodec.encode(payload, bluetoothMaximumPayloadSize)
        assertEquals(bluetoothMaximumPayloadSize + 2, frame.size)
    }

    @Test
    fun frameCodec_truncatesForBle() {
        val maximumTransmissionUnit = 185
        val maximumFrameSize = Protocol.maximumFrameSizeForMaximumTransmissionUnit(maximumTransmissionUnit)
        val bluetoothMaximumPayloadSize = Protocol.maximumPayloadSize(maximumFrameSize)
        val oversized = ByteArray(300) { it.toByte() }
        val frame = FrameCodec.encode(oversized, bluetoothMaximumPayloadSize)
        assertEquals(bluetoothMaximumPayloadSize + 2, frame.size)
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
        assertEquals(3, frame.size)
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
    fun wireSize_focus() {
        val frame = FrameCodec.encode(Protocol.createFocus())
        assertEquals(3, frame.size)
    }

    @Test
    fun wireSize_blur() {
        val frame = FrameCodec.encode(Protocol.createBlur())
        assertEquals(3, frame.size)
    }

    @Test
    fun wireSize_pairRequest() {
        val frame = FrameCodec.encode(Protocol.createPairRequest("123456"))
        assertEquals(9, frame.size)
    }

    @Test
    fun wireSize_pairResponse() {
        val frame = FrameCodec.encode(Protocol.createPairResponse(true))
        assertEquals(5, frame.size)
    }

    @Test
    fun wireSize_acknowledgment() {
        val frame = FrameCodec.encode(Protocol.createAcknowledgment(1))
        assertEquals(5, frame.size)
    }

    @Test
    fun wireSize_commandEmpty() {
        val frame = FrameCodec.encode(Protocol.createCommand(0x01, 0))
        assertEquals(6, frame.size)
    }

    @Test
    fun wireSize_commandMaxTagLengthValue_wifi() {
        val wifiMaximumTagLengthValueDataSize = Protocol.maximumTagLengthValueDataSize(Protocol.WIFI_MAXIMUM_FRAME_SIZE)
        val tagLengthValueData = ByteArray(wifiMaximumTagLengthValueDataSize)
        val frame =
            FrameCodec.encode(
                Protocol.createCommand(0x01, 0, tagLengthValueData, wifiMaximumTagLengthValueDataSize),
            )
        assertEquals(2 + 1 + Protocol.COMMAND_HEADER_SIZE + wifiMaximumTagLengthValueDataSize, frame.size)
    }

    @Test
    fun wireSize_dynamicMaximumTransmissionUnit() {
        val maximumFrameSize = Protocol.maximumFrameSizeForMaximumTransmissionUnit(247)
        val maximumCommandDataSize = Protocol.maximumCommandDataSize(maximumFrameSize)
        val tagLengthValueData = ByteArray(maximumCommandDataSize)
        val payload = Protocol.createCommand(0x01, 0, tagLengthValueData, maximumCommandDataSize)
        val frame = FrameCodec.encode(payload, Protocol.maximumPayloadSize(maximumFrameSize))
        assertEquals(maximumFrameSize, frame.size)
    }

    // --- Big-Endian Byte-Level Verification ---

    @Test
    fun bigEndian_acknowledgmentSequenceNumber_0x0100() {
        val payload = Protocol.createAcknowledgment(0x0100)
        assertEquals(Signal.ACKNOWLEDGMENT, payload[0])
        assertEquals(0x01.toByte(), payload[1])
        assertEquals(0x00.toByte(), payload[2])
    }

    @Test
    fun bigEndian_acknowledgmentSequenceNumber_0xFF00() {
        val payload = Protocol.createAcknowledgment(0xFF00)
        assertEquals(0xFF.toByte(), payload[1])
        assertEquals(0x00.toByte(), payload[2])
    }

    @Test
    fun bigEndian_acknowledgmentSequenceNumber_0x00FF() {
        val payload = Protocol.createAcknowledgment(0x00FF)
        assertEquals(0x00.toByte(), payload[1])
        assertEquals(0xFF.toByte(), payload[2])
    }

    @Test
    fun bigEndian_commandSequenceNumber() {
        val payload = Protocol.createCommand(0x30, 0x0102)
        assertEquals(Signal.COMMAND, payload[0])
        assertEquals(0x01.toByte(), payload[1]) // sequenceNumber high
        assertEquals(0x02.toByte(), payload[2]) // sequenceNumber low
        assertEquals(0x30.toByte(), payload[3]) // commandIdentifier
    }

    @Test
    fun bigEndian_tagLengthValueInteger() {
        val encoded = Protocol.encodeTagLengthValueInteger(0x01, 0x01020304)
        assertEquals(0x01.toByte(), encoded[0]) // tag
        assertEquals(0x04.toByte(), encoded[1]) // length
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

    // --- Tag-Length-Value 255-Byte Limit ---

    @Test
    fun tagLengthValue_maxValueSize() {
        val value = ByteArray(255) { it.toByte() }
        val encoded = Protocol.encodeTagLengthValue(0x01, value)
        assertEquals(257, encoded.size)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(1, fields.size)
        assertEquals(255, fields[0].value.size)
    }

    @Test
    fun tagLengthValue_oversizedValueTruncated() {
        val value = ByteArray(300) { it.toByte() }
        val encoded = Protocol.encodeTagLengthValue(0x01, value)
        assertEquals(257, encoded.size)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(255, fields[0].value.size)
    }

    @Test
    fun tagLengthValue_zeroLengthValue() {
        val encoded = Protocol.encodeTagLengthValue(0x01, ByteArray(0))
        assertEquals(2, encoded.size)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(1, fields.size)
        assertEquals(0, fields[0].value.size)
    }

    @Test
    fun tagLengthValue_singleByteValue() {
        val encoded = Protocol.encodeTagLengthValue(0x05, byteArrayOf(0xAB.toByte()))
        assertEquals(3, encoded.size)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(0xAB.toByte(), fields[0].value[0])
    }

    @Test
    fun tagLengthValue_stringMaxLength() {
        val longString = "a".repeat(255)
        val encoded = Protocol.encodeTagLengthValueString(0x01, longString)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(longString, Protocol.getTagLengthValueString(fields, 0x01))
    }

    @Test
    fun tagLengthValue_stringOversizedTruncated() {
        val longString = "a".repeat(300)
        val encoded = Protocol.encodeTagLengthValueString(0x01, longString)
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertEquals(255, fields[0].value.size)
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
    fun parseAcknowledgmentSequenceNumber_emptyPayload() {
        assertNull(Protocol.parseAcknowledgmentSequenceNumber(ByteArray(0)))
    }

    @Test
    fun parseAcknowledgmentSequenceNumber_wrongSignal() {
        assertNull(Protocol.parseAcknowledgmentSequenceNumber(byteArrayOf(Signal.PING, 0x00, 0x01)))
    }

    @Test
    fun parseCommand_exactlyMinimumSize() {
        val payload = byteArrayOf(Signal.COMMAND, 0x00, 0x00, 0x10)
        val command = Protocol.parseCommand(payload)
        assertNotNull(command)
        assertEquals(0x10.toByte(), command!!.commandIdentifier)
        assertEquals(0, command.sequenceNumber)
        assertEquals(0, command.data.size)
    }

    @Test
    fun decodeTagLengthValue_truncatedField() {
        val truncated = byteArrayOf(0x01, 0x05, 0xAA.toByte(), 0xBB.toByte())
        val fields = Protocol.decodeTagLengthValue(truncated)
        assertEquals(0, fields.size)
    }

    @Test
    fun decodeTagLengthValue_singleByte() {
        val fields = Protocol.decodeTagLengthValue(byteArrayOf(0x01))
        assertEquals(0, fields.size)
    }

    @Test
    fun decodeTagLengthValue_multipleWithLastTruncated() {
        val data = byteArrayOf(0x01, 0x01, 0xAA.toByte(), 0x02, 0x03, 0xBB.toByte())
        val fields = Protocol.decodeTagLengthValue(data)
        assertEquals(1, fields.size)
        assertEquals(0x01.toByte(), fields[0].tag)
    }

    @Test
    fun getTagLengthValueInteger_tooShortValue() {
        val encoded = Protocol.encodeTagLengthValue(0x01, byteArrayOf(0x01, 0x02))
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertNull(Protocol.getTagLengthValueInteger(fields, 0x01))
    }

    @Test
    fun getTagLengthValueByte_emptyValue() {
        val encoded = Protocol.encodeTagLengthValue(0x01, ByteArray(0))
        val fields = Protocol.decodeTagLengthValue(encoded)
        assertNull(Protocol.getTagLengthValueByte(fields, 0x01))
    }

    @Test
    fun parseQRCodePayload_emptyPayload() {
        assertNull(Protocol.parseQRCodePayload(ByteArray(0)))
    }

    @Test
    fun pairRequest_exactCode() {
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
        val r0 = Protocol.parsePairResponse(Protocol.createPairResponse(false, 0x00))
        assertEquals(0x00.toByte(), r0!!.second)
        val r1 = Protocol.parsePairResponse(Protocol.createPairResponse(false, 0x01))
        assertEquals(0x01.toByte(), r1!!.second)
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
        val wifiMaximumPayloadSize = Protocol.maximumPayloadSize(Protocol.WIFI_MAXIMUM_FRAME_SIZE)
        val payload = ByteArray(wifiMaximumPayloadSize + 100) { it.toByte() }
        val frame = FrameCodec.encode(payload)
        assertEquals(wifiMaximumPayloadSize + 2, frame.size)
    }

    @Test
    fun frameCodec_extractFrames_partialFrame() {
        val ping = FrameCodec.encode(Protocol.createPing())
        val partial = ping + byteArrayOf(0x00, 0x05)
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(partial) { frames.add(it) }
        assertEquals(1, frames.size)
        assertEquals(Signal.PING, frames[0][0])
        assertEquals(2, remaining.size)
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
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(byteArrayOf(0x00, 0x03)) { frames.add(it) }
        assertEquals(0, frames.size)
        assertEquals(2, remaining.size)
    }

    @Test
    fun frameCodec_extractFrames_invalidLength() {
        val frames = mutableListOf<ByteArray>()
        val remaining = FrameCodec.extractFrames(byteArrayOf(0x00, 0x00, 0x04)) { frames.add(it) }
        assertEquals(0, frames.size)
        assertEquals(0, remaining.size)
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
        val tagLengthValueData =
            Protocol.encodeTagLengthValueString(0x01, "test") + Protocol.encodeTagLengthValueInteger(0x02, 42)
        val payload = Protocol.createCommand(0x10, 100, tagLengthValueData)
        val frame = FrameCodec.encode(payload)
        val header = frame.copyOfRange(0, 2)
        val length = FrameCodec.decodeLength(header)
        val extracted = frame.copyOfRange(2, 2 + length)
        val command = Protocol.parseCommand(extracted)
        assertNotNull(command)
        assertEquals(0x10.toByte(), command!!.commandIdentifier)
        assertEquals(100, command.sequenceNumber)
        assertEquals("test", Protocol.getTagLengthValueString(Protocol.decodeTagLengthValue(command.data), 0x01))
        assertEquals(42, Protocol.getTagLengthValueInteger(Protocol.decodeTagLengthValue(command.data), 0x02))
    }

    // --- Dynamic Sizing ---

    @Test
    fun dynamicSizing_helpers() {
        // WiFi: maximumFrameSize=4096
        assertEquals(4094, Protocol.maximumPayloadSize(4096))
        assertEquals(4090, Protocol.maximumCommandDataSize(4096))
        assertEquals(255, Protocol.maximumTagLengthValueDataSize(4096))

        // BLE MTU 247 (Nokia 6): maximumFrameSize=244
        assertEquals(244, Protocol.maximumFrameSizeForMaximumTransmissionUnit(247))
        assertEquals(242, Protocol.maximumPayloadSize(244))
        assertEquals(238, Protocol.maximumCommandDataSize(244))
        assertEquals(236, Protocol.maximumTagLengthValueDataSize(244))

        // BLE MTU 185 (iPhone): maximumFrameSize=182
        assertEquals(182, Protocol.maximumFrameSizeForMaximumTransmissionUnit(185))
        assertEquals(180, Protocol.maximumPayloadSize(182))
        assertEquals(176, Protocol.maximumCommandDataSize(182))
        assertEquals(174, Protocol.maximumTagLengthValueDataSize(182))

        // BLE MTU 23 (minimum): maximumFrameSize=20
        assertEquals(20, Protocol.maximumFrameSizeForMaximumTransmissionUnit(23))
        assertEquals(18, Protocol.maximumPayloadSize(20))
        assertEquals(14, Protocol.maximumCommandDataSize(20))
        assertEquals(12, Protocol.maximumTagLengthValueDataSize(20))
    }

    @Test
    fun dynamicSizing_signalsFitMinimumTransmissionUnit() {
        val minimumMaximumPayloadSize =
            Protocol.maximumPayloadSize(Protocol.maximumFrameSizeForMaximumTransmissionUnit(23))
        assertTrue(Protocol.createPing().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createPong().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createReady().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createGoodbye().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createUnpair().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createFocus().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createBlur().size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createPairRequest("123456").size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createPairResponse(true).size <= minimumMaximumPayloadSize)
        assertTrue(Protocol.createAcknowledgment(65535).size <= minimumMaximumPayloadSize)
    }

    // --- Helpers ---

    private fun buildQRCodePayload(
        seed: ByteArray,
        host: String,
        preferredTransport: String,
    ): ByteArray {
        val buffer = ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN)
        buffer.putShort(0xBC1B.toShort())
        buffer.put(seed)
        host.split(".").forEach { buffer.put(it.toInt().toByte()) }
        buffer.put(if (preferredTransport == "ble") 0x01 else 0x00)
        buffer.put(0x00) // reserved
        return buffer.array()
    }
}
