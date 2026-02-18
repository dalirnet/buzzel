package com.buzzel.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.buzzel.BuzzelApp
import com.buzzel.R
import com.buzzel.model.LogDirection
import com.buzzel.model.LogEntry
import com.buzzel.model.LogEventType
import com.buzzel.model.LogStatus
import com.buzzel.protocol.Protocol
import com.buzzel.protocol.Signal
import com.buzzel.transport.TransportManager
import com.buzzel.ui.MainActivity

class BuzzelService : Service() {
    private val app: BuzzelApp get() = application as BuzzelApp

    companion object {
        private const val TAG = "BuzzelService"
        private const val NOTIFICATION_ID = 1
        private const val PING_INTERVAL_MS = 30_000L
        private const val PONG_TIMEOUT_MS = 10_000L
        private const val HANDSHAKE_TIMEOUT_MS = 30_000L
        private const val FAILOVER_DELAY_MS = 10_000L
    }

    enum class ConnectionState { IDLE, CONNECTING, HANDSHAKING, ACTIVE }

    private lateinit var transport: TransportManager

    private val handler = Handler(Looper.getMainLooper())
    private var state = ConnectionState.IDLE
    private var lastPongTime = 0L
    private var started = false
    private var handshakeTimeoutRunnable: Runnable? = null
    private var failoverRunnable: Runnable? = null
    private val deviceName = "Mac"

    // Reliable delivery
    private var nextSeq = 0
    private var pendingAckSeq: Int? = null
    private var pendingRetries = 0
    private var retryPayload: ByteArray? = null
    private var retryRunnable: Runnable? = null

    private data class FailoverStep(
        val transport: String,
    )

    private var failoverSteps: List<FailoverStep> = emptyList()
    private var failoverIndex = 0

    private val pingRunnable =
        object : Runnable {
            override fun run() {
                if (state != ConnectionState.ACTIVE) return
                if (lastPongTime > 0 && System.currentTimeMillis() - lastPongTime > PONG_TIMEOUT_MS) {
                    Log.w(TAG, "Pong timeout")
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.DEVICE_DISCONNECTED,
                            message = "Pong timeout",
                            direction = LogDirection.LOCAL,
                            status = LogStatus.FAILED,
                            error = "No pong for ${PONG_TIMEOUT_MS / 1000}s",
                        ),
                    )
                    handleDisconnect()
                    return
                }
                Log.d(TAG, "Sending ping")
                transport.send(Protocol.createPing())
                handler.postDelayed(this, PING_INTERVAL_MS)
            }
        }

    // region Failover

    private fun buildFailoverSteps() {
        val primary = app.configStore.preferTransport ?: "wifi"
        val secondary = if (primary == "wifi") "ble" else "wifi"
        failoverSteps = listOf(FailoverStep(primary), FailoverStep(secondary))
        Log.d(TAG, "Failover steps: ${failoverSteps.map { it.transport }}")
    }

    private fun startFailover() {
        Log.i(TAG, "Starting failover")
        buildFailoverSteps()
        failoverIndex = 0
        tryNextFailoverStep()
    }

    private fun tryNextFailoverStep() {
        cancelFailover()
        if (failoverSteps.isEmpty()) return
        val step = failoverSteps[failoverIndex % failoverSteps.size]
        Log.i(TAG, "Failover step: ${step.transport}")
        transport.stopAll()
        transitionTo(ConnectionState.CONNECTING)

        when (step.transport) {
            "wifi" -> {
                val host = app.configStore.macHost
                if (!host.isNullOrEmpty()) {
                    transport.startWifiClient(host, Protocol.TCP_PORT)
                } else {
                    advanceFailover()
                    return
                }
            }

            "ble" -> {
                transport.startBle()
                transport.setBleLowPower(false)
            }
        }

        val runnable =
            Runnable {
                if (state != ConnectionState.ACTIVE) advanceFailover()
            }
        failoverRunnable = runnable
        handler.postDelayed(runnable, FAILOVER_DELAY_MS)
    }

    private fun advanceFailover() {
        Log.d(TAG, "Advancing failover")
        failoverIndex++
        tryNextFailoverStep()
    }

    private fun cancelFailover() {
        failoverRunnable?.let { handler.removeCallbacks(it) }
        failoverRunnable = null
    }

    private fun handleDisconnect() {
        transitionTo(ConnectionState.IDLE)
        startFailover()
    }

    // endregion

    // region State Machine

    private fun transitionTo(newState: ConnectionState) {
        val oldState = state
        if (oldState == newState && newState != ConnectionState.ACTIVE) return
        Log.i(TAG, "State: $oldState → $newState")
        state = newState
        app.serviceConnectionState = newState

        when (newState) {
            ConnectionState.IDLE -> {
                handler.removeCallbacks(pingRunnable)
                cancelHandshakeTimeout()
                cancelRetry()
                app.isDeviceConnected = false
            }

            ConnectionState.CONNECTING -> {
                app.isDeviceConnected = false
            }

            ConnectionState.HANDSHAKING -> {
                startHandshakeTimeout()
                app.isDeviceConnected = false
            }

            ConnectionState.ACTIVE -> {
                cancelHandshakeTimeout()
                cancelFailover()
                lastPongTime = System.currentTimeMillis()
                app.isDeviceConnected = true
                app.hasBeenConnected = true
                handler.removeCallbacks(pingRunnable)
                handler.postDelayed(pingRunnable, PING_INTERVAL_MS)
            }
        }
        updateNotification()
    }

    private fun startHandshakeTimeout() {
        cancelHandshakeTimeout()
        val runnable =
            Runnable {
                if (state == ConnectionState.HANDSHAKING) {
                    Log.w(TAG, "Handshake timeout")
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.DEVICE_DISCONNECTED,
                            message = "Handshake timeout",
                            direction = LogDirection.LOCAL,
                            status = LogStatus.FAILED,
                            error = "No response",
                        ),
                    )
                    handleDisconnect()
                }
            }
        handshakeTimeoutRunnable = runnable
        handler.postDelayed(runnable, HANDSHAKE_TIMEOUT_MS)
    }

    private fun cancelHandshakeTimeout() {
        handshakeTimeoutRunnable?.let { handler.removeCallbacks(it) }
        handshakeTimeoutRunnable = null
    }

    // endregion

    // region Reliable Delivery

    fun sendCommand(
        cmd: Byte,
        tlvData: ByteArray = ByteArray(0),
    ) {
        val seq = nextSeq++
        val payload = Protocol.createCommand(cmd, seq, tlvData)
        retryPayload = payload
        pendingAckSeq = seq
        pendingRetries = 0
        transport.send(payload)
        startRetryTimer()
    }

    private fun startRetryTimer() {
        cancelRetry()
        val runnable =
            Runnable {
                if (pendingAckSeq != null && pendingRetries < 3) {
                    pendingRetries++
                    Log.w(TAG, "Retry command seq=$pendingAckSeq, attempt=$pendingRetries")
                    retryPayload?.let { transport.send(it) }
                    startRetryTimer()
                } else if (pendingRetries >= 3) {
                    Log.e(TAG, "Command failed after 3 retries")
                    handleDisconnect()
                }
            }
        retryRunnable = runnable
        handler.postDelayed(runnable, 5_000L)
    }

    private fun cancelRetry() {
        retryRunnable?.let { handler.removeCallbacks(it) }
        retryRunnable = null
    }

    // endregion

    // region Lifecycle

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Service created")

        transport =
            TransportManager(
                context = this,
                onMessageReceived = { handleMessage(it) },
                onConnectionChanged = { connected ->
                    val label =
                        when (transport.activeTransport) {
                            TransportManager.ActiveTransport.BLE -> "BLE"
                            TransportManager.ActiveTransport.WIFI -> "WiFi"
                            TransportManager.ActiveTransport.NONE -> ""
                        }
                    app.appendLogEntry(
                        LogEntry(
                            type = if (connected) LogEventType.DEVICE_CONNECTED else LogEventType.DEVICE_DISCONNECTED,
                            message = if (connected) "Connected to $deviceName via $label" else "Disconnected from $deviceName",
                        ),
                    )
                    if (connected) {
                        transitionTo(ConnectionState.HANDSHAKING)
                        val code = app.configStore.pairingCode
                        if (code != null && app.configStore.sessionId != null) {
                            // Already paired — reconnection: send ready
                            transport.send(Protocol.createReady())
                        } else if (code != null) {
                            // First pairing: send pair.request
                            transport.send(Protocol.createPairRequest(code))
                        }
                    } else if (state != ConnectionState.IDLE) {
                        handleDisconnect()
                    }
                },
            )
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        Log.i(TAG, "Service started")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
        if (!started) {
            started = true
            startFailover()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "Service destroyed")
        handler.removeCallbacks(pingRunnable)
        cancelHandshakeTimeout()
        cancelFailover()
        cancelRetry()
        if (state == ConnectionState.ACTIVE || state == ConnectionState.HANDSHAKING) {
            transport.sendAndStop(Protocol.createGoodbye())
        } else {
            transport.stopAll()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // endregion

    // region Message Handling

    private fun handleMessage(payload: ByteArray) {
        if (payload.isEmpty()) return
        val signalId = payload[0]
        Log.d(TAG, "Received signal 0x${String.format("%02x", signalId)} size=${payload.size}")
        if (state == ConnectionState.ACTIVE) lastPongTime = System.currentTimeMillis()

        when (signalId) {
            Signal.READY -> {
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_CONNECTED,
                        message = "$deviceName is ready",
                        direction = LogDirection.INCOMING,
                    ),
                )
                if (state == ConnectionState.HANDSHAKING) {
                    transitionTo(ConnectionState.ACTIVE)
                }
            }

            Signal.GOODBYE -> {
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "$deviceName said goodbye",
                        direction = LogDirection.INCOMING,
                    ),
                )
                handleDisconnect()
            }

            Signal.UNPAIR -> {
                app.configStore.clearPairing()
                app.hasBeenConnected = false
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "$deviceName unpaired",
                        direction = LogDirection.INCOMING,
                    ),
                )
                transitionTo(ConnectionState.IDLE)
            }

            Signal.PING -> {
                transport.send(Protocol.createPong())
            }

            Signal.PONG -> {
                lastPongTime = System.currentTimeMillis()
            }

            Signal.PAIR_RESPONSE -> {
                val result = Protocol.parsePairResponse(payload)
                if (result != null && result.first) {
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.PAIRING_COMPLETE,
                            message = "Paired with $deviceName",
                            direction = LogDirection.INCOMING,
                        ),
                    )
                    transitionTo(ConnectionState.ACTIVE)
                } else {
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.PAIRING_FAILED,
                            message = "Pairing rejected",
                            direction = LogDirection.INCOMING,
                            status = LogStatus.FAILED,
                        ),
                    )
                    handleDisconnect()
                }
            }

            Signal.ACK -> {
                val seq = Protocol.parseAckSeq(payload)
                if (seq != null && seq == pendingAckSeq) {
                    Log.d(TAG, "Ack received for seq=$seq")
                    pendingAckSeq = null
                    retryPayload = null
                    cancelRetry()
                }
            }

            Signal.COMMAND -> {
                val cmd = Protocol.parseCommand(payload)
                if (cmd != null) {
                    // Ack immediately
                    transport.send(Protocol.createAck(cmd.seq))
                    handleCommand(cmd)
                }
            }
        }
    }

    private fun handleCommand(cmd: Protocol.Command) {
        Log.d(TAG, "Command 0x${String.format("%02x", cmd.cmd)} seq=${cmd.seq}")
        // All command IDs reserved — dispatch as features are added
    }

    // endregion

    // region Notification

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        val text =
            when (state) {
                ConnectionState.ACTIVE -> "Connected"
                ConnectionState.HANDSHAKING -> "Handshaking..."
                ConnectionState.CONNECTING -> "Connecting..."
                ConnectionState.IDLE -> "Connecting..."
            }
        return NotificationCompat
            .Builder(this, BuzzelApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pending)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun updateNotification() {
        getSystemService(android.app.NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
    }

    // endregion
}
