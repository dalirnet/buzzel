package com.buzzel.transport

import android.util.Log
import com.buzzel.protocol.Protocol
import java.io.IOException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

class TcpClient(
    private val onMessageReceived: (ByteArray) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "TcpClient"
        private const val CONNECT_TIMEOUT_MS = 5000
        private val WIFI_MAX_PAYLOAD = Protocol.maxPayload(Protocol.WIFI_MAX_FRAME)
    }

    private var socket: Socket? = null
    private var outputStream: java.io.OutputStream? = null

    @Volatile
    private var running = false

    val isConnected: Boolean
        get() = socket?.isConnected == true && socket?.isClosed == false

    fun connect(
        host: String,
        port: Int,
    ) {
        Log.i(TAG, "Connecting to $host:$port")
        stop()
        running = true
        Thread({ connectLoop(host, port) }, "TcpClient-Connect").start()
    }

    fun stop() {
        Log.i(TAG, "Disconnecting")
        running = false
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
        outputStream = null
    }

    fun sendData(data: ByteArray): Boolean {
        val out = outputStream ?: return false
        return try {
            Log.d(TAG, "Sending ${data.size} bytes")
            out.write(FrameCodec.encode(data))
            out.flush()
            true
        } catch (e: IOException) {
            Log.w(TAG, "Send failed", e)
            false
        }
    }

    private fun connectLoop(
        host: String,
        port: Int,
    ) {
        try {
            val sock = Socket()
            sock.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            Log.i(TAG, "Connected to $host:$port")
            socket = sock
            outputStream = sock.getOutputStream()
            onConnectionChanged(true)
            readLoop(sock)
        } catch (e: IOException) {
            if (running) Log.w(TAG, "Connect failed: ${e.message}")
        } finally {
            onConnectionChanged(false)
        }
    }

    private fun readLoop(socket: Socket) {
        val input = socket.getInputStream()
        try {
            while (running && !socket.isClosed) {
                val header = readExact(input, FrameCodec.HEADER_SIZE) ?: break
                val length = FrameCodec.decodeLength(header)
                if (length <= 0 || length > WIFI_MAX_PAYLOAD) {
                    Log.w(TAG, "Invalid frame size: $length")
                    break
                }
                val body = readExact(input, length) ?: break
                Log.d(TAG, "Frame received: $length bytes")
                onMessageReceived(body)
            }
        } catch (e: IOException) {
            if (running) Log.w(TAG, "Read error", e)
        }
    }

    private fun readExact(
        input: InputStream,
        size: Int,
    ): ByteArray? {
        val buf = ByteArray(size)
        var read = 0
        while (read < size) {
            val n = input.read(buf, read, size - read)
            if (n < 0) return null
            read += n
        }
        return buf
    }
}
