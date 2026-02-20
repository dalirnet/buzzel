package com.buzzel.transport

import android.content.Context
import com.buzzel.debug.FileLogger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class TransportManager(
    context: Context,
    private val onMessageReceived: (ByteArray) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "TransportManager"
    }

    enum class ActiveTransport { NONE, BLE, WIFI }

    private val bleServer: BleGattServer
    private var tcpClient: TcpClient? = null
    private val sendExecutor = Executors.newSingleThreadExecutor()

    var activeTransport: ActiveTransport = ActiveTransport.NONE
        private set

    init {
        bleServer =
            BleGattServer(
                context = context,
                onMessageReceived = { onMessageReceived(it) },
                onConnectionChanged = { connected ->
                    if (connected) {
                        activeTransport = ActiveTransport.BLE
                    } else if (activeTransport == ActiveTransport.BLE) {
                        activeTransport = ActiveTransport.NONE
                    }
                    onConnectionChanged(connected)
                },
            )
    }

    val isConnected: Boolean
        get() =
            when (activeTransport) {
                ActiveTransport.BLE -> bleServer.isConnected
                ActiveTransport.WIFI -> tcpClient?.isConnected == true
                ActiveTransport.NONE -> false
            }

    fun startBle() {
        FileLogger.i(TAG, "Starting BLE transport")
        bleServer.start()
    }

    fun startWifiClient(
        host: String,
        port: Int,
    ) {
        FileLogger.i(TAG, "Starting WiFi transport: $host:$port")
        stopWifiClient()
        val client =
            TcpClient(
                onMessageReceived = { onMessageReceived(it) },
                onConnectionChanged = { connected ->
                    if (connected) {
                        activeTransport = ActiveTransport.WIFI
                    } else if (activeTransport == ActiveTransport.WIFI) {
                        activeTransport = ActiveTransport.NONE
                    }
                    onConnectionChanged(connected)
                },
            )
        tcpClient = client
        client.connect(host, port)
    }

    fun stopWifiClient() {
        FileLogger.d(TAG, "Stopping WiFi")
        tcpClient?.stop()
        tcpClient = null
        if (activeTransport == ActiveTransport.WIFI) activeTransport = ActiveTransport.NONE
    }

    fun stopBle() {
        FileLogger.d(TAG, "Stopping BLE")
        bleServer.stop()
        if (activeTransport == ActiveTransport.BLE) activeTransport = ActiveTransport.NONE
    }

    fun stopAll() {
        FileLogger.i(TAG, "Stopping all transports")
        bleServer.stop()
        tcpClient?.stop()
        tcpClient = null
        activeTransport = ActiveTransport.NONE
    }

    fun sendAndStop(payload: ByteArray) {
        FileLogger.i(TAG, "Sending final payload (${payload.size} bytes) via $activeTransport and stopping")
        val latch = CountDownLatch(1)
        sendExecutor.execute {
            val sent =
                when (activeTransport) {
                    ActiveTransport.BLE -> {
                        if (bleServer.isConnected) bleServer.sendData(payload) else false
                    }

                    ActiveTransport.WIFI -> {
                        tcpClient?.sendData(payload) ?: false
                    }

                    ActiveTransport.NONE -> false
                }
            FileLogger.d(TAG, "Final payload sent=$sent")
            latch.countDown()
        }
        val delivered = latch.await(2, TimeUnit.SECONDS)
        FileLogger.d(TAG, "sendAndStop latch: delivered=$delivered")
        stopAll()
    }

    fun disconnectBle() {
        FileLogger.d(TAG, "Disconnecting BLE device")
        bleServer.disconnectDevice()
    }

    fun setBleLowPower(enabled: Boolean) {
        FileLogger.d(TAG, "BLE low power: $enabled")
        bleServer.setLowPower(enabled)
    }

    fun send(payload: ByteArray): Boolean {
        FileLogger.d(TAG, "Send via $activeTransport: ${payload.size} bytes")
        return when (activeTransport) {
            ActiveTransport.BLE -> {
                if (!bleServer.isConnected) {
                    FileLogger.w(TAG, "BLE send failed: not connected")
                    return false
                }
                sendExecutor.execute { bleServer.sendData(payload) }
                true
            }

            ActiveTransport.WIFI -> {
                val client = tcpClient
                if (client == null || !client.isConnected) {
                    FileLogger.w(TAG, "WiFi send failed: not connected")
                    return false
                }
                sendExecutor.execute { client.sendData(payload) }
                true
            }

            ActiveTransport.NONE -> {
                FileLogger.w(TAG, "Send failed: no active transport")
                false
            }
        }
    }
}
