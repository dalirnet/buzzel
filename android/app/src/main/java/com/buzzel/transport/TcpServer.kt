package com.buzzel.transport

import android.util.Log
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer

/**
 * TCP server for WiFi transport.
 * Framing: 4-byte big-endian length prefix + UTF-8 JSON body.
 * Only one client connection at a time.
 */
class TcpServer(
    var port: Int = 9876,
    private val onMessageReceived: (ByteArray) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit
) {
    companion object {
        private const val TAG = "TcpServer"
        private const val MAX_FRAME_SIZE = 1_000_000
    }

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null

    @Volatile
    private var running = false

    fun start() {
        if (running) return
        running = true
        Thread(::acceptLoop, "TcpServer-Accept").start()
        Log.d(TAG, "TCP server starting on port $port")
    }

    fun stop() {
        running = false
        try {
            clientSocket?.close()
        } catch (_: Exception) {
        }
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        clientSocket = null
        outputStream = null
        serverSocket = null
        Log.d(TAG, "TCP server stopped")
    }

    fun sendData(data: ByteArray): Boolean {
        val out = outputStream ?: return false
        return try {
            val frame = ByteBuffer.allocate(4 + data.size)
            frame.putInt(data.size)
            frame.put(data)
            out.write(frame.array())
            out.flush()
            true
        } catch (e: IOException) {
            Log.w(TAG, "Send failed", e)
            false
        }
    }

    val isConnected: Boolean
        get() = clientSocket?.isConnected == true && clientSocket?.isClosed == false

    private fun acceptLoop() {
        try {
            serverSocket = ServerSocket(port)
            Log.d(TAG, "TCP server listening on port $port")

            while (running) {
                val socket = try {
                    serverSocket?.accept() ?: break
                } catch (e: IOException) {
                    if (running) Log.w(TAG, "Accept failed", e)
                    break
                }

                // Close previous client
                try {
                    clientSocket?.close()
                } catch (_: Exception) {
                }

                clientSocket = socket
                outputStream = socket.getOutputStream()
                Log.d(TAG, "Client connected: ${socket.inetAddress.hostAddress}")
                onConnectionChanged(true)

                readLoop(socket)

                onConnectionChanged(false)
                Log.d(TAG, "Client disconnected")
            }
        } catch (e: IOException) {
            if (running) Log.e(TAG, "Server error", e)
        }
    }

    private fun readLoop(socket: Socket) {
        val input = socket.getInputStream()
        try {
            while (running && !socket.isClosed) {
                val length = readInt(input) ?: break
                if (length <= 0 || length > MAX_FRAME_SIZE) break

                val body = ByteArray(length)
                var read = 0
                while (read < length) {
                    val n = input.read(body, read, length - read)
                    if (n < 0) return
                    read += n
                }

                onMessageReceived(body)
            }
        } catch (e: IOException) {
            if (running) Log.w(TAG, "Read error", e)
        }
    }

    private fun readInt(input: InputStream): Int? {
        val buf = ByteArray(4)
        var read = 0
        while (read < 4) {
            val n = input.read(buf, read, 4 - read)
            if (n < 0) return null
            read += n
        }
        return ByteBuffer.wrap(buf).int
    }
}
