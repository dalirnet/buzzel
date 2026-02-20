package com.buzzel.protocol

import com.buzzel.debug.FileLogger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID

/**
 * Buzzel binary protocol — signals, commands, TLV encoding.
 * See PROTOCOL.md for full specification.
 */

object Signal {
    const val COMMAND: Byte = 0x00
    const val PAIR_REQUEST: Byte = 0x01
    const val PAIR_RESPONSE: Byte = 0x02
    const val READY: Byte = 0x03
    const val PING: Byte = 0x04
    const val PONG: Byte = 0x05
    const val ACK: Byte = 0x06
    const val GOODBYE: Byte = 0x07
    const val UNPAIR: Byte = 0x08
}

object BleUuids {
    val SERVICE: UUID = UUID.fromString("0000bf01-0000-1000-8000-00805f9b34fb")
    val DATA_CHAR: UUID = UUID.fromString("0000bf02-0000-1000-8000-00805f9b34fb")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

object Protocol {
    private const val TAG = "Protocol"

    const val TCP_PORT = 48155
    const val FRAME_HEADER = 2
    const val COMMAND_HEADER = 3 // cmd(1) + seq(2)
    const val ATT_OVERHEAD = 3
    const val TLV_MAX_VALUE = 255 // 1-byte Len field
    const val WIFI_MAX_FRAME = 4096

    fun maxPayload(maxFrame: Int): Int = maxFrame - FRAME_HEADER

    fun maxCmdData(maxFrame: Int): Int = maxPayload(maxFrame) - 1 - COMMAND_HEADER

    fun maxTlvData(maxFrame: Int): Int = minOf(maxCmdData(maxFrame) - 2, TLV_MAX_VALUE)

    fun maxFrameForMtu(mtu: Int): Int = mtu - ATT_OVERHEAD

    // --- QR ---

    private const val QR_SIZE = 24
    private const val QR_MAGIC = 0xBC1B

    data class QrPayload(
        val seed: ByteArray,
        val host: String,
        val prefer: String,
    )

    fun parseQr(raw: ByteArray): QrPayload? {
        if (raw.size != QR_SIZE) {
            FileLogger.w(TAG, "QR: invalid size ${raw.size}")
            return null
        }
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.BIG_ENDIAN)
        val magic = buf.short.toInt() and 0xFFFF
        if (magic != QR_MAGIC) {
            FileLogger.w(TAG, "QR: invalid magic 0x${magic.toString(16)}")
            return null
        }
        val seed = ByteArray(16)
        buf.get(seed)
        val hostBytes = ByteArray(4)
        buf.get(hostBytes)
        val host = hostBytes.joinToString(".") { (it.toInt() and 0xFF).toString() }
        val prefer = if (buf.get().toInt() == 0x01) "ble" else "wifi"
        // skip reserved byte
        return QrPayload(seed, host, prefer)
    }

    fun deriveSessionId(seed: ByteArray): String {
        val hash = sha256(seed)
        // UUID v5 format from first 16 bytes
        val buf = ByteBuffer.wrap(hash, 0, 16)
        val msb = buf.long
        val lsb = buf.long
        return UUID(msb, lsb).toString().uppercase()
    }

    fun derivePairingCode(seed: ByteArray): String {
        val input = seed + "code".toByteArray(Charsets.UTF_8)
        val hash = sha256(input)
        // first 6 digits
        val num =
            ByteBuffer
                .wrap(hash, 0, 4)
                .order(ByteOrder.BIG_ENDIAN)
                .int
                .toLong() and 0xFFFFFFFFL
        return (num % 1_000_000).toString().padStart(6, '0')
    }

    private fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    // --- Signals ---

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

    fun createAck(seq: Int): ByteArray {
        val buf = ByteBuffer.allocate(3).order(ByteOrder.BIG_ENDIAN)
        buf.put(Signal.ACK)
        buf.putShort(seq.toShort())
        return buf.array()
    }

    fun parseSignalId(payload: ByteArray): Byte {
        if (payload.isEmpty()) return -1
        return payload[0]
    }

    fun parsePairRequestCode(payload: ByteArray): String? {
        // payload: [0x01][code 6B]
        if (payload.size < 7 || payload[0] != Signal.PAIR_REQUEST) return null
        return String(payload, 1, 6, Charsets.US_ASCII)
    }

    fun parsePairResponse(payload: ByteArray): Pair<Boolean, Byte>? {
        // payload: [0x02][accepted 1B][reason 1B]
        if (payload.size < 3 || payload[0] != Signal.PAIR_RESPONSE) return null
        val accepted = payload[1] == 0x01.toByte()
        val reason = payload[2]
        return Pair(accepted, reason)
    }

    fun parseAckSeq(payload: ByteArray): Int? {
        // payload: [0x06][seq 2B]
        if (payload.size < 3 || payload[0] != Signal.ACK) return null
        return ByteBuffer
            .wrap(payload, 1, 2)
            .order(ByteOrder.BIG_ENDIAN)
            .short
            .toInt() and 0xFFFF
    }

    // --- Commands ---

    fun createCommand(
        cmd: Byte,
        seq: Int,
        tlvData: ByteArray = ByteArray(0),
        maxTlvData: Int = TLV_MAX_VALUE,
    ): ByteArray {
        val dataLen = minOf(tlvData.size, maxTlvData)
        val buf = ByteBuffer.allocate(1 + COMMAND_HEADER + dataLen).order(ByteOrder.BIG_ENDIAN)
        buf.put(Signal.COMMAND)
        buf.put(cmd)
        buf.putShort(seq.toShort())
        if (dataLen > 0) buf.put(tlvData, 0, dataLen)
        return buf.array()
    }

    data class Command(
        val cmd: Byte,
        val seq: Int,
        val data: ByteArray,
    )

    fun parseCommand(payload: ByteArray): Command? {
        // payload: [0x00][cmd 1B][seq 2B][TLV 0-NB]
        if (payload.size < 4 || payload[0] != Signal.COMMAND) return null
        val cmd = payload[1]
        val seq =
            ByteBuffer
                .wrap(payload, 2, 2)
                .order(ByteOrder.BIG_ENDIAN)
                .short
                .toInt() and 0xFFFF
        val data = if (payload.size > 4) payload.copyOfRange(4, payload.size) else ByteArray(0)
        return Command(cmd, seq, data)
    }

    // --- TLV ---

    fun tlvEncode(
        tag: Byte,
        value: ByteArray,
    ): ByteArray {
        val len = minOf(value.size, TLV_MAX_VALUE)
        val result = ByteArray(2 + len)
        result[0] = tag
        result[1] = len.toByte()
        System.arraycopy(value, 0, result, 2, len)
        return result
    }

    fun tlvEncodeString(
        tag: Byte,
        value: String,
    ): ByteArray = tlvEncode(tag, value.toByteArray(Charsets.UTF_8))

    fun tlvEncodeInt(
        tag: Byte,
        value: Int,
    ): ByteArray {
        val buf = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(value)
        return tlvEncode(tag, buf.array())
    }

    fun tlvEncodeByte(
        tag: Byte,
        value: Byte,
    ): ByteArray = tlvEncode(tag, byteArrayOf(value))

    data class TlvField(
        val tag: Byte,
        val value: ByteArray,
    )

    fun tlvDecode(data: ByteArray): List<TlvField> {
        val fields = mutableListOf<TlvField>()
        var offset = 0
        while (offset + 2 <= data.size) {
            val tag = data[offset]
            val len = data[offset + 1].toInt() and 0xFF
            offset += 2
            if (offset + len > data.size) break
            val value = data.copyOfRange(offset, offset + len)
            fields.add(TlvField(tag, value))
            offset += len
        }
        return fields
    }

    fun tlvGetString(
        fields: List<TlvField>,
        tag: Byte,
    ): String? = fields.firstOrNull { it.tag == tag }?.value?.toString(Charsets.UTF_8)

    fun tlvGetInt(
        fields: List<TlvField>,
        tag: Byte,
    ): Int? {
        val field = fields.firstOrNull { it.tag == tag } ?: return null
        if (field.value.size < 4) return null
        return ByteBuffer.wrap(field.value).order(ByteOrder.BIG_ENDIAN).int
    }

    fun tlvGetByte(
        fields: List<TlvField>,
        tag: Byte,
    ): Byte? {
        val field = fields.firstOrNull { it.tag == tag } ?: return null
        if (field.value.isEmpty()) return null
        return field.value[0]
    }
}
