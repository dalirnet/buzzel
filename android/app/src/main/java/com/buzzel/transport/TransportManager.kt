package com.buzzel.transport

import android.content.Context
import android.util.Log
import java.util.concurrent.Executors

/**
 * Unified transport interface over BLE and TCP.
 * Handles routing messages through the active transport(s).
 */
class TransportManager(
    context: Context,
    private val onMessageReceived: (String) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit
) {
    companion object {
        private const val TAG = "TransportManager"
    }

    private val bleServer: BleGattServer
    private val tcpServer: TcpServer
    private val sendExecutor = Executors.newSingleThreadExecutor()

    init {
        bleServer = BleGattServer(
            context = context,
            onMessageReceived = { handleIncoming(it) },
            onConnectionChanged = { connected ->
                Log.d(TAG, "BLE connection: $connected")
                onConnectionChanged(isConnected)
            }
        )

        tcpServer = TcpServer(
            onMessageReceived = { handleIncoming(it) },
            onConnectionChanged = { connected ->
                Log.d(TAG, "TCP connection: $connected")
                onConnectionChanged(isConnected)
            }
        )
    }

    val isConnected: Boolean
        get() = bleServer.isConnected || tcpServer.isConnected

    /** Start BLE server (always on, even in idle mode for discoverability) */
    fun startBle() {
        bleServer.start()
    }

    /** Start TCP server (only in active mode) */
    fun startTcp(port: Int = 9876) {
        tcpServer.stop()
        tcpServer.port = port
        tcpServer.start()
    }

    fun stopTcp() {
        tcpServer.stop()
    }

    fun stopAll() {
        bleServer.stop()
        tcpServer.stop()
    }

    /** Send goodbye and then stop all transports. Blocks until complete or timeout. */
    fun sendGoodbyeAndStop(goodbyeJson: String) {
        val latch = java.util.concurrent.CountDownLatch(1)
        sendExecutor.execute {
            val data = goodbyeJson.toByteArray(Charsets.UTF_8)
            if (bleServer.isConnected) {
                bleServer.sendData(data)
            }
            if (tcpServer.isConnected) {
                tcpServer.sendData(data)
            }
            latch.countDown()
        }
        latch.await(2, java.util.concurrent.TimeUnit.SECONDS)
        bleServer.stop()
        tcpServer.stop()
    }

    /** Force-disconnect BLE client and restart advertising */
    fun disconnectBle() {
        bleServer.disconnectDevice()
    }

    /** Set BLE advertising power. true = idle/low, false = active/high */
    fun setBleLowPower(enabled: Boolean) {
        bleServer.setLowPower(enabled)
    }

    /** Send a message through all connected transports */
    fun send(json: String): Boolean {
        val type = try {
            org.json.JSONObject(json).optString("type", "?")
        } catch (_: Exception) {
            "?"
        }

        val bleConnected = bleServer.isConnected
        val tcpConnected = tcpServer.isConnected

        if (!bleConnected && !tcpConnected) {
            Log.d(TAG, "SEND [$type] — no transport connected")
            return false
        }

        val via = "${if (bleConnected) "BLE" else ""}${if (tcpConnected) "+TCP" else ""}"
        Log.d(TAG, "SEND [$type] ${json.length} chars via $via")

        val data = json.toByteArray(Charsets.UTF_8)

        // BLE sendData blocks waiting for onNotificationSent, so run off main thread
        sendExecutor.execute {
            if (bleConnected) {
                bleServer.sendData(data)
            }
            if (tcpConnected) {
                tcpServer.sendData(data)
            }
        }
        return true
    }

    /** Update BLE status characteristic */
    fun updateStatus(statusJson: String) {
        bleServer.updateStatus(statusJson.toByteArray(Charsets.UTF_8))
    }

    private fun handleIncoming(raw: ByteArray) {
        val json = String(raw, Charsets.UTF_8)
        val type = try {
            org.json.JSONObject(json).optString("type", "?")
        } catch (e: Exception) {
            Log.w(TAG, "JSON parse error: ${e.message}, raw[0..${minOf(80, json.length)}]: ${json.take(80)}")
            "?"
        }
        Log.d(TAG, "RECV [$type] ${raw.size} bytes -> ${json.length} chars")
        onMessageReceived(json)
    }
}
