package com.buzzel.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.buzzel.BuzzelApp
import com.buzzel.R
import com.buzzel.debug.FileLogger
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
        private const val PING_INTERVAL_MS = 10_000L
        private const val PONG_TIMEOUT_MS = 5_000L
        private const val HANDSHAKE_TIMEOUT_MS = 30_000L
        private const val FAILOVER_DELAY_MS = 10_000L
    }

    enum class ConnectionState { IDLE, CONNECTING, HANDSHAKING, ACTIVE }

    private lateinit var transport: TransportManager

    private val handler = Handler(Looper.getMainLooper())
    private var state = ConnectionState.IDLE
    private var lastPongTime = 0L
    private var lastPingSentTime = 0L
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

    private var failoverSteps: List<String> = emptyList()
    private var failoverIndex = 0
    private var failoverGeneration = 0
    private var reconnectAttempts = 0
    private val maxReconnectAttempts = 2

    private val pingRunnable =
        object : Runnable {
            override fun run() {
                if (state != ConnectionState.ACTIVE) return
                // If we sent a ping and no pong came back within PONG_TIMEOUT_MS, disconnect.
                if (lastPingSentTime > 0 && lastPongTime < lastPingSentTime &&
                    System.currentTimeMillis() - lastPingSentTime > PONG_TIMEOUT_MS
                ) {
                    FileLogger.w(TAG, "Pong timeout")
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
                FileLogger.d(TAG, "Sending ping")
                lastPingSentTime = System.currentTimeMillis()
                transport.send(Protocol.createPing())
                handler.postDelayed(this, PING_INTERVAL_MS)
            }
        }

    // region Failover

    private fun resolvePreferredTransport(): String {
        val pref = app.configStore.preferTransport ?: "auto"
        if (pref == "wifi" || pref == "ble") return pref
        // "auto": check WiFi connectivity
        val cm = getSystemService(ConnectivityManager::class.java)
        val net = cm?.activeNetwork
        val caps = net?.let { cm.getNetworkCapabilities(it) }
        val hasWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        FileLogger.i(TAG, "Auto-detect: WiFi ${if (hasWifi) "available" else "unavailable"}")
        return if (hasWifi) "wifi" else "ble"
    }

    private fun buildFailoverSteps() {
        val primary = resolvePreferredTransport()
        val secondary = if (primary == "wifi") "ble" else "wifi"
        failoverSteps = listOf(primary, secondary)
        FileLogger.d(TAG, "Failover steps: $failoverSteps")
    }

    private fun startFailover() {
        FileLogger.i(TAG, "Starting failover")
        buildFailoverSteps()
        failoverIndex = 0
        tryNextFailoverStep()
    }

    private fun tryNextFailoverStep() {
        cancelFailover()
        if (failoverSteps.isEmpty()) {
            FileLogger.e(TAG, "Failover: no steps configured")
            return
        }
        val preferred = failoverSteps[failoverIndex % failoverSteps.size]
        failoverGeneration++
        val gen = failoverGeneration
        FileLogger.i(TAG, "Failover step $failoverIndex: trying $preferred (gen=$gen, timeout=${FAILOVER_DELAY_MS / 1000}s)")
        transport.stopAll()
        transitionTo(ConnectionState.CONNECTING)
        app.connectingTransport = if (preferred == "wifi") "WiFi" else "BLE"

        when (preferred) {
            "wifi" -> {
                val host = app.configStore.macHost
                if (!host.isNullOrEmpty()) {
                    FileLogger.d(TAG, "WiFi: connecting to $host:${Protocol.TCP_PORT}")
                    transport.startWifiClient(host, Protocol.TCP_PORT)
                } else {
                    FileLogger.i(TAG, "WiFi: no host configured, skipping")
                    advanceFailover()
                    return
                }
            }

            "ble" -> {
                FileLogger.d(TAG, "BLE: starting GATT server + advertising")
                transport.startBle()
                transport.setBleLowPower(false)
            }
        }

        val runnable =
            Runnable {
                if (state == ConnectionState.CONNECTING) {
                    FileLogger.i(TAG, "Failover timeout: $preferred did not connect in ${FAILOVER_DELAY_MS / 1000}s, advancing")
                    advanceFailover()
                }
            }
        failoverRunnable = runnable
        handler.postDelayed(runnable, FAILOVER_DELAY_MS)
    }

    private fun advanceFailover() {
        FileLogger.d(TAG, "Advancing failover")
        failoverIndex++
        tryNextFailoverStep()
    }

    private fun cancelFailover() {
        failoverRunnable?.let { handler.removeCallbacks(it) }
        failoverRunnable = null
    }

    private fun handleDisconnect() {
        transitionTo(ConnectionState.IDLE)

        // Only reconnect when we have valid pairing data
        val hasPairingContext = app.configStore.pairingCode != null
        if (!hasPairingContext) {
            FileLogger.i(TAG, "No pairing context — not reconnecting, stopping service")
            stopSelf()
            return
        }

        if (app.hasBeenConnected) {
            reconnectAttempts++
            if (reconnectAttempts > maxReconnectAttempts) {
                FileLogger.i(TAG, "Max reconnect attempts reached, stopping service")
                reconnectAttempts = 0
                stopSelf()
                return
            }
            FileLogger.i(TAG, "Reconnect attempt $reconnectAttempts/$maxReconnectAttempts")
        }
        startFailover()
    }

    // endregion

    // region State Machine

    private fun transitionTo(newState: ConnectionState) {
        val oldState = state
        if (oldState == newState && newState != ConnectionState.ACTIVE) return
        FileLogger.i(TAG, "State: $oldState → $newState")
        state = newState

        // Set properties BEFORE notifying listeners so UI sees the correct values
        when (newState) {
            ConnectionState.IDLE -> {
                app.isDeviceConnected = false
                app.connectedDeviceName = null
            }
            ConnectionState.CONNECTING -> {
                app.isDeviceConnected = false
            }
            ConnectionState.HANDSHAKING -> {
                app.isDeviceConnected = false
            }
            ConnectionState.ACTIVE -> {
                app.isDeviceConnected = true
                app.hasBeenConnected = true
                app.connectedDeviceName = deviceName
            }
        }

        // Notify listeners — triggers UI refresh
        app.serviceConnectionState = newState

        // Side effects after notification
        when (newState) {
            ConnectionState.IDLE -> {
                handler.removeCallbacks(pingRunnable)
                cancelHandshakeTimeout()
                cancelRetry()
            }

            ConnectionState.CONNECTING -> {}

            ConnectionState.HANDSHAKING -> {
                startHandshakeTimeout()
            }

            ConnectionState.ACTIVE -> {
                cancelHandshakeTimeout()
                cancelFailover()
                lastPongTime = System.currentTimeMillis()
                lastPingSentTime = 0L
                reconnectAttempts = 0
                handler.removeCallbacks(pingRunnable)
                handler.postDelayed(pingRunnable, PING_INTERVAL_MS)
                // Promote to foreground — notification appears only when connected
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
                } else {
                    startForeground(NOTIFICATION_ID, buildNotification())
                }
            }
        }

        if (newState != ConnectionState.CONNECTING) {
            app.connectingTransport = null
        }
        if (newState != ConnectionState.ACTIVE) {
            // Demote from foreground — dismisses the notification
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun startHandshakeTimeout() {
        cancelHandshakeTimeout()
        val runnable =
            Runnable {
                if (state == ConnectionState.HANDSHAKING) {
                    FileLogger.w(TAG, "Handshake timeout")
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
                    FileLogger.w(TAG, "Retry command seq=$pendingAckSeq, attempt=$pendingRetries")
                    retryPayload?.let { transport.send(it) }
                    startRetryTimer()
                } else if (pendingRetries >= 3) {
                    FileLogger.e(TAG, "Command failed after 3 retries")
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
        FileLogger.i(TAG, "Service created")

        transport =
            TransportManager(
                context = this,
                onMessageReceived = { data -> handler.post { handleMessage(data) } },
                onConnectionChanged = { connected ->
                    // Callbacks may fire from background threads; marshal to main handler.
                    // Capture generation at callback time to detect stale transport callbacks.
                    val gen = failoverGeneration
                    handler.post {
                        val label =
                            when (transport.activeTransport) {
                                TransportManager.ActiveTransport.BLE -> "BLE"
                                TransportManager.ActiveTransport.WIFI -> "WiFi"
                                TransportManager.ActiveTransport.NONE -> ""
                            }
                        if (connected) {
                            FileLogger.i(TAG, "$label connected (gen=$gen)")
                            app.connectedTransport = label.ifEmpty { null }
                            app.appendLogEntry(
                                LogEntry(
                                    type = LogEventType.DEVICE_CONNECTED,
                                    message = "Connected to $deviceName via $label",
                                ),
                            )
                            transitionTo(ConnectionState.HANDSHAKING)
                            val code = app.configStore.pairingCode
                            if (code != null && app.configStore.sessionId != null) {
                                // Already paired — reconnection: send ready
                                FileLogger.d(TAG, "Sending ready signal (reconnection)")
                                transport.send(Protocol.createReady())
                            } else if (code != null) {
                                // First pairing: send pair.request
                                FileLogger.d(TAG, "Sending pair request (first pairing)")
                                transport.send(Protocol.createPairRequest(code))
                            } else {
                                FileLogger.e(TAG, "Connected but no pairing code available")
                            }
                        } else {
                            // Ignore callbacks from a previous failover generation
                            if (gen != failoverGeneration) {
                                FileLogger.d(TAG, "Ignoring stale disconnect (gen=$gen, current=$failoverGeneration)")
                                return@post
                            }
                            FileLogger.i(TAG, "$label disconnected (state=$state, gen=$gen)")
                            app.connectedTransport = null
                            app.appendLogEntry(
                                LogEntry(
                                    type = LogEventType.DEVICE_DISCONNECTED,
                                    message = "Disconnected from $deviceName",
                                ),
                            )
                            when (state) {
                                ConnectionState.CONNECTING -> {
                                    FileLogger.i(TAG, "Transport connect failed, advancing failover")
                                    advanceFailover()
                                }

                                ConnectionState.HANDSHAKING, ConnectionState.ACTIVE -> {
                                    FileLogger.i(TAG, "Connection dropped in $state, reconnecting")
                                    handleDisconnect()
                                }

                                else -> {
                                    FileLogger.d(TAG, "Disconnect in $state — no action")
                                }
                            }
                        }
                    }
                },
            )
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        FileLogger.i(TAG, "onStartCommand (started=$started, state=$state)")
        if (!started) {
            started = true
            startFailover()
        } else if (state == ConnectionState.IDLE && app.configStore.pairingCode != null) {
            // Service already running but idle — user tapped power to reconnect
            FileLogger.i(TAG, "Already started but idle — restarting failover")
            startFailover()
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        FileLogger.i(TAG, "Task removed (state=$state)")
        if (state != ConnectionState.ACTIVE) {
            FileLogger.i(TAG, "Not active, stopping service")
            stopSelf()
        } else {
            FileLogger.i(TAG, "Active connection, keeping service alive")
        }
    }

    override fun onDestroy() {
        FileLogger.i(TAG, "Service destroyed (state=$state)")
        val wasActive = state == ConnectionState.ACTIVE || state == ConnectionState.HANDSHAKING
        app.hasBeenConnected = false
        app.configStore.clearPairing()
        transitionTo(ConnectionState.IDLE)
        handler.removeCallbacks(pingRunnable)
        cancelHandshakeTimeout()
        cancelFailover()
        cancelRetry()
        if (wasActive) {
            FileLogger.d(TAG, "Sending goodbye before teardown")
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
        FileLogger.d(TAG, "Received signal 0x${String.format("%02x", signalId)} size=${payload.size}")
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
                } else {
                    FileLogger.i(TAG, "Ignoring ready signal in state $state")
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
                app.hasBeenConnected = false
                app.configStore.clearPairing()
                transitionTo(ConnectionState.IDLE)
                cancelFailover()
                transport.stopAll()
                stopSelf()
            }

            Signal.UNPAIR -> {
                FileLogger.i(TAG, "Received unpair signal, clearing pairing data")
                app.hasBeenConnected = false
                app.configStore.clearPairing()
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "$deviceName unpaired",
                        direction = LogDirection.INCOMING,
                    ),
                )
                transitionTo(ConnectionState.IDLE)
                cancelFailover()
                transport.stopAll()
                stopSelf()
            }

            Signal.PING -> {
                transport.send(Protocol.createPong())
            }

            Signal.PONG -> {
                lastPongTime = System.currentTimeMillis()
            }

            Signal.PAIR_RESPONSE -> {
                val result = Protocol.parsePairResponse(payload)
                FileLogger.i(TAG, "Pair response: accepted=${result?.first}, reason=0x${String.format("%02x", result?.second ?: 0)}")
                if (result != null && result.first) {
                    app.configStore.completePairing()
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
                    FileLogger.d(TAG, "Ack received for seq=$seq")
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
        FileLogger.d(TAG, "Command 0x${String.format("%02x", cmd.cmd)} seq=${cmd.seq}")
        // All command IDs reserved — dispatch as features are added
    }

    // endregion

    // region Notification

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat
            .Builder(this, BuzzelApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title, deviceName))
            .setContentText(getString(R.string.notification_text))
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pending)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    // endregion
}
