package com.buzzel.transport

import android.content.Context
import android.util.Log
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
        Log.i(TAG, "Starting BLE transport")
        bleServer.start()
    }

    fun startWifiClient(
        host: String,
        port: Int,
    ) {
        Log.i(TAG, "Starting WiFi transport: $host:$port")
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
        Log.d(TAG, "Stopping WiFi")
        tcpClient?.stop()
        tcpClient = null
        if (activeTransport == ActiveTransport.WIFI) activeTransport = ActiveTransport.NONE
    }

    fun stopBle() {
        Log.d(TAG, "Stopping BLE")
        bleServer.stop()
        if (activeTransport == ActiveTransport.BLE) activeTransport = ActiveTransport.NONE
    }

    fun stopAll() {
        Log.i(TAG, "Stopping all transports")
        bleServer.stop()
        tcpClient?.stop()
        tcpClient = null
        activeTransport = ActiveTransport.NONE
    }

    fun sendAndStop(payload: ByteArray) {
        Log.i(TAG, "Sending final payload and stopping")
        val latch = CountDownLatch(1)
        sendExecutor.execute {
            when (activeTransport) {
                ActiveTransport.BLE -> {
                    if (bleServer.isConnected) bleServer.sendData(payload)
                }

                ActiveTransport.WIFI -> {
                    tcpClient?.sendData(payload)
                }

                ActiveTransport.NONE -> {}
            }
            latch.countDown()
        }
        latch.await(2, TimeUnit.SECONDS)
        stopAll()
    }

    fun disconnectBle() {
        Log.d(TAG, "Disconnecting BLE device")
        bleServer.disconnectDevice()
    }

    fun setBleLowPower(enabled: Boolean) {
        Log.d(TAG, "BLE low power: $enabled")
        bleServer.setLowPower(enabled)
    }

    fun send(payload: ByteArray): Boolean {
        Log.d(TAG, "Send via $activeTransport: ${payload.size} bytes")
        return when (activeTransport) {
            ActiveTransport.BLE -> {
                if (!bleServer.isConnected) return false
                sendExecutor.execute { bleServer.sendData(payload) }
                true
            }

            ActiveTransport.WIFI -> {
                val client = tcpClient ?: return false
                if (!client.isConnected) return false
                sendExecutor.execute { client.sendData(payload) }
                true
            }

            ActiveTransport.NONE -> {
                false
            }
        }
    }
}
