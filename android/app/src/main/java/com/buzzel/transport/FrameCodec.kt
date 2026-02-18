package com.buzzel.transport

import android.util.Log
import com.buzzel.protocol.Protocol

object FrameCodec {
    private const val TAG = "FrameCodec"
    const val HEADER_SIZE = Protocol.FRAME_HEADER // 2

    fun encode(
        payload: ByteArray,
        maxPayload: Int = Protocol.WIFI_MAX_FRAME - HEADER_SIZE,
    ): ByteArray {
        val length = minOf(payload.size, maxPayload)
        val frame = ByteArray(HEADER_SIZE + length)
        frame[0] = ((length shr 8) and 0xFF).toByte()
        frame[1] = (length and 0xFF).toByte()
        System.arraycopy(payload, 0, frame, HEADER_SIZE, length)
        return frame
    }

    fun decodeLength(header: ByteArray): Int =
        (header[0].toInt() and 0xFF shl 8) or
            (header[1].toInt() and 0xFF)

    fun extractFrames(
        buffer: ByteArray,
        maxPayload: Int = Protocol.WIFI_MAX_FRAME - HEADER_SIZE,
        onFrame: (ByteArray) -> Unit,
    ): ByteArray {
        var remaining = buffer
        while (remaining.size >= HEADER_SIZE) {
            val length = decodeLength(remaining)
            if (length <= 0 || length > maxPayload) {
                Log.w(TAG, "Invalid frame size: $length, resetting buffer")
                return ByteArray(0)
            }
            val totalNeeded = HEADER_SIZE + length
            if (remaining.size < totalNeeded) break
            onFrame(remaining.copyOfRange(HEADER_SIZE, totalNeeded))
            remaining = remaining.copyOfRange(totalNeeded, remaining.size)
        }
        return remaining
    }
}
