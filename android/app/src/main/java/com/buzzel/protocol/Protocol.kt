package com.buzzel.protocol

import com.buzzel.debug.FileLogger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID

object Signal {
    const val COMMAND: Byte = 0x00
    const val PAIR_REQUEST: Byte = 0x01
    const val PAIR_RESPONSE: Byte = 0x02
    const val READY: Byte = 0x03
    const val PING: Byte = 0x04
    const val PONG: Byte = 0x05
    const val ACKNOWLEDGMENT: Byte = 0x06
    const val GOODBYE: Byte = 0x07
    const val UNPAIR: Byte = 0x08
}

object BluetoothServiceUUIDs {
    val SERVICE: UUID = UUID.fromString("0000bf01-0000-1000-8000-00805f9b34fb")
    val DATA_CHARACTERISTIC: UUID = UUID.fromString("0000bf02-0000-1000-8000-00805f9b34fb")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

object Protocol {
    private const val TAG = "Protocol"

    const val TCP_PORT = 48155
    const val FRAME_HEADER_SIZE = 2
    const val COMMAND_HEADER_SIZE = 3 // sequenceNumber(2) + commandIdentifier(1)
    const val ATTRIBUTE_PROTOCOL_OVERHEAD = 3
    const val TAG_LENGTH_VALUE_MAXIMUM_VALUE_SIZE = 255 // 1-byte length field
    const val WIFI_MAXIMUM_FRAME_SIZE = 4096

    fun maximumPayloadSize(maximumFrameSize: Int): Int = maximumFrameSize - FRAME_HEADER_SIZE

    fun maximumCommandDataSize(maximumFrameSize: Int): Int =
        maximumPayloadSize(maximumFrameSize) - 1 - COMMAND_HEADER_SIZE

    fun maximumTagLengthValueDataSize(maximumFrameSize: Int): Int =
        minOf(maximumCommandDataSize(maximumFrameSize) - 2, TAG_LENGTH_VALUE_MAXIMUM_VALUE_SIZE)

    fun maximumFrameSizeForMaximumTransmissionUnit(maximumTransmissionUnit: Int): Int =
        maximumTransmissionUnit - ATTRIBUTE_PROTOCOL_OVERHEAD

    private const val QR_CODE_PAYLOAD_SIZE = 24
    private const val QR_CODE_MAGIC_NUMBER = 0xBC1B

    data class QRCodePayload(
        val seed: ByteArray,
        val host: String,
        val preferredTransport: String,
    )

    fun parseQRCodePayload(raw: ByteArray): QRCodePayload? {
        if (raw.size != QR_CODE_PAYLOAD_SIZE) {
            FileLogger.w(TAG, "QR: invalid size ${raw.size}")
            return null
        }
        val buffer = ByteBuffer.wrap(raw).order(ByteOrder.BIG_ENDIAN)
        val magicNumber = buffer.short.toInt() and 0xFFFF
        if (magicNumber != QR_CODE_MAGIC_NUMBER) {
            FileLogger.w(TAG, "QR: invalid magic 0x${magicNumber.toString(16)}")
            return null
        }
        val seed = ByteArray(16)
        buffer.get(seed)
        val hostBytes = ByteArray(4)
        buffer.get(hostBytes)
        val host = hostBytes.joinToString(".") { (it.toInt() and 0xFF).toString() }
        val preferredTransport = if (buffer.get().toInt() == 0x01) "ble" else "wifi"
        return QRCodePayload(seed, host, preferredTransport)
    }

    fun deriveSessionIdentifier(seed: ByteArray): String {
        val hash = computeSHA256(seed)
        val buffer = ByteBuffer.wrap(hash, 0, 16)
        val mostSignificantBits = buffer.long
        val leastSignificantBits = buffer.long
        return UUID(mostSignificantBits, leastSignificantBits).toString().uppercase()
    }

    fun derivePairingCode(seed: ByteArray): String {
        val input = seed + "code".toByteArray(Charsets.UTF_8)
        val hash = computeSHA256(input)
        val numericValue =
            ByteBuffer
                .wrap(hash, 0, 4)
                .order(ByteOrder.BIG_ENDIAN)
                .int
                .toLong() and 0xFFFFFFFFL
        return (numericValue % 1_000_000).toString().padStart(6, '0')
    }

    private fun computeSHA256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    fun createPing(): ByteArray = byteArrayOf(Signal.PING)

    fun createPong(): ByteArray = byteArrayOf(Signal.PONG)

    fun createReady(): ByteArray = byteArrayOf(Signal.READY)

    fun createGoodbye(): ByteArray = byteArrayOf(Signal.GOODBYE)

    fun createUnpair(): ByteArray = byteArrayOf(Signal.UNPAIR)

    fun createPairRequest(code: String): ByteArray {
        val codeBytes = code.toByteArray(Charsets.US_ASCII)
        val payload = ByteArray(1 + 6)
        payload[0] = Signal.PAIR_REQUEST
        System.arraycopy(codeBytes, 0, payload, 1, minOf(codeBytes.size, 6))
        return payload
    }

    fun createPairResponse(
        accepted: Boolean,
        reason: Byte = 0x00,
    ): ByteArray =
        byteArrayOf(
            Signal.PAIR_RESPONSE,
            if (accepted) 0x01 else 0x00,
            reason,
        )

    fun createAcknowledgment(sequenceNumber: Int): ByteArray {
        val buffer = ByteBuffer.allocate(3).order(ByteOrder.BIG_ENDIAN)
        buffer.put(Signal.ACKNOWLEDGMENT)
        buffer.putShort(sequenceNumber.toShort())
        return buffer.array()
    }

    fun parseSignalIdentifier(payload: ByteArray): Byte {
        if (payload.isEmpty()) return -1
        return payload[0]
    }

    fun parsePairRequestCode(payload: ByteArray): String? {
        if (payload.size < 7 || payload[0] != Signal.PAIR_REQUEST) return null
        return String(payload, 1, 6, Charsets.US_ASCII)
    }

    fun parsePairResponse(payload: ByteArray): Pair<Boolean, Byte>? {
        if (payload.size < 3 || payload[0] != Signal.PAIR_RESPONSE) return null
        val accepted = payload[1] == 0x01.toByte()
        val reason = payload[2]
        return Pair(accepted, reason)
    }

    fun parseAcknowledgmentSequenceNumber(payload: ByteArray): Int? {
        if (payload.size < 3 || payload[0] != Signal.ACKNOWLEDGMENT) return null
        return ByteBuffer
            .wrap(payload, 1, 2)
            .order(ByteOrder.BIG_ENDIAN)
            .short
            .toInt() and 0xFFFF
    }

    fun createCommand(
        commandIdentifier: Byte,
        sequenceNumber: Int,
        tagLengthValueData: ByteArray = ByteArray(0),
        maximumTagLengthValueDataSize: Int = TAG_LENGTH_VALUE_MAXIMUM_VALUE_SIZE,
    ): ByteArray {
        val dataLength = minOf(tagLengthValueData.size, maximumTagLengthValueDataSize)
        val buffer = ByteBuffer.allocate(1 + COMMAND_HEADER_SIZE + dataLength).order(ByteOrder.BIG_ENDIAN)
        buffer.put(Signal.COMMAND)
        buffer.putShort(sequenceNumber.toShort())
        buffer.put(commandIdentifier)
        if (dataLength > 0) buffer.put(tagLengthValueData, 0, dataLength)
        return buffer.array()
    }

    data class Command(
        val commandIdentifier: Byte,
        val sequenceNumber: Int,
        val data: ByteArray,
    )

    fun parseCommand(payload: ByteArray): Command? {
        if (payload.size < 4 || payload[0] != Signal.COMMAND) return null
        val sequenceNumber =
            ByteBuffer
                .wrap(payload, 1, 2)
                .order(ByteOrder.BIG_ENDIAN)
                .short
                .toInt() and 0xFFFF
        val commandIdentifier = payload[3]
        val data = if (payload.size > 4) payload.copyOfRange(4, payload.size) else ByteArray(0)
        return Command(commandIdentifier, sequenceNumber, data)
    }

    fun encodeTagLengthValue(
        tag: Byte,
        value: ByteArray,
    ): ByteArray {
        val length = minOf(value.size, TAG_LENGTH_VALUE_MAXIMUM_VALUE_SIZE)
        val result = ByteArray(2 + length)
        result[0] = tag
        result[1] = length.toByte()
        System.arraycopy(value, 0, result, 2, length)
        return result
    }

    fun encodeTagLengthValueString(
        tag: Byte,
        value: String,
    ): ByteArray = encodeTagLengthValue(tag, value.toByteArray(Charsets.UTF_8))

    fun encodeTagLengthValueInteger(
        tag: Byte,
        value: Int,
    ): ByteArray {
        val buffer = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(value)
        return encodeTagLengthValue(tag, buffer.array())
    }

    fun encodeTagLengthValueByte(
        tag: Byte,
        value: Byte,
    ): ByteArray = encodeTagLengthValue(tag, byteArrayOf(value))

    data class TagLengthValueField(
        val tag: Byte,
        val value: ByteArray,
    )

    fun decodeTagLengthValue(data: ByteArray): List<TagLengthValueField> {
        val fields = mutableListOf<TagLengthValueField>()
        var offset = 0
        while (offset + 2 <= data.size) {
            val tag = data[offset]
            val length = data[offset + 1].toInt() and 0xFF
            offset += 2
            if (offset + length > data.size) break
            val value = data.copyOfRange(offset, offset + length)
            fields.add(TagLengthValueField(tag, value))
            offset += length
        }
        return fields
    }

    fun getTagLengthValueString(
        fields: List<TagLengthValueField>,
        tag: Byte,
    ): String? = fields.firstOrNull { it.tag == tag }?.value?.toString(Charsets.UTF_8)

    fun getTagLengthValueInteger(
        fields: List<TagLengthValueField>,
        tag: Byte,
    ): Int? {
        val field = fields.firstOrNull { it.tag == tag } ?: return null
        if (field.value.size < 4) return null
        return ByteBuffer.wrap(field.value).order(ByteOrder.BIG_ENDIAN).int
    }

    fun getTagLengthValueByte(
        fields: List<TagLengthValueField>,
        tag: Byte,
    ): Byte? {
        val field = fields.firstOrNull { it.tag == tag } ?: return null
        if (field.value.isEmpty()) return null
        return field.value[0]
    }
}
