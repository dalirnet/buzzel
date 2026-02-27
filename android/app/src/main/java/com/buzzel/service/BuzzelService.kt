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
import android.provider.Settings
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
        private const val PING_INTERVAL_MILLISECONDS = 10_000L
        private const val PONG_TIMEOUT_MILLISECONDS = 5_000L
        private const val HANDSHAKE_TIMEOUT_MILLISECONDS = 30_000L
        private const val FAILOVER_DELAY_MILLISECONDS = 10_000L
        const val ACTION_SOFT_DISCONNECT = "com.buzzel.action.SOFT_DISCONNECT"
        const val ACTION_UNPAIR = "com.buzzel.action.UNPAIR"
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
    private var deviceName = "Mac"
    private lateinit var localDeviceName: String

    private var nextSequenceNumber = 0
    private var pendingAcknowledgmentSequenceNumber: Int? = null
    private var pendingRetries = 0
    private var retryPayload: ByteArray? = null
    private var retryRunnable: Runnable? = null
    private var foregroundListener: ((Boolean) -> Unit)? = null

    private var failoverSteps: List<String> = emptyList()
    private var failoverIndex = 0
    private var failoverGeneration = 0
    private var reconnectAttempts = 0
    private val maxReconnectAttempts = 2

    private val pingRunnable =
        object : Runnable {
            override fun run() {
                if (state != ConnectionState.ACTIVE) return
                if (lastPingSentTime > 0 && lastPongTime < lastPingSentTime &&
                    System.currentTimeMillis() - lastPingSentTime > PONG_TIMEOUT_MILLISECONDS
                ) {
                    FileLogger.w(TAG, "Pong timeout")
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.DEVICE_DISCONNECTED,
                            message = "Pong timeout",
                            direction = LogDirection.LOCAL,
                            status = LogStatus.FAILED,
                            error = "No pong for ${PONG_TIMEOUT_MILLISECONDS / 1000}s",
                        ),
                    )
                    handleDisconnect()
                    return
                }
                FileLogger.d(TAG, "Sending ping")
                lastPingSentTime = System.currentTimeMillis()
                transport.send(Protocol.createPing())
                handler.postDelayed(this, PING_INTERVAL_MILLISECONDS)
            }
        }

    private fun resolvePreferredTransport(): String {
        val preference = app.configStore.preferredTransport ?: "auto"
        if (preference == "wifi" || preference == "ble") return preference
        val connectivityManager = getSystemService(ConnectivityManager::class.java)
        val activeNetwork = connectivityManager?.activeNetwork
        val capabilities = activeNetwork?.let { connectivityManager.getNetworkCapabilities(it) }
        val hasWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
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
        val generation = failoverGeneration
        FileLogger.i(
            TAG,
            "Failover step $failoverIndex: trying $preferred (gen=$generation, timeout=${FAILOVER_DELAY_MILLISECONDS / 1000}s)",
        )
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
                    FileLogger.i(
                        TAG,
                        "Failover timeout: $preferred did not connect in ${FAILOVER_DELAY_MILLISECONDS / 1000}s, advancing",
                    )
                    advanceFailover()
                }
            }
        failoverRunnable = runnable
        handler.postDelayed(runnable, FAILOVER_DELAY_MILLISECONDS)
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

    private fun transitionTo(newState: ConnectionState) {
        val oldState = state
        if (oldState == newState && newState != ConnectionState.ACTIVE) return
        FileLogger.i(TAG, "State: $oldState → $newState")
        state = newState

        when (newState) {
            ConnectionState.IDLE -> {
                app.isDeviceConnected = false
                app.connectedDeviceName = null
                handler.removeCallbacks(pingRunnable)
                cancelHandshakeTimeout()
                cancelRetry()
                app.isRemoteInFocus = false
            }

            ConnectionState.CONNECTING -> {
                app.isDeviceConnected = false
            }

            ConnectionState.HANDSHAKING -> {
                app.isDeviceConnected = false
                startHandshakeTimeout()
            }

            ConnectionState.ACTIVE -> {
                app.isDeviceConnected = true
                app.hasBeenConnected = true
                app.connectedDeviceName = deviceName
                cancelHandshakeTimeout()
                cancelFailover()
                lastPongTime = System.currentTimeMillis()
                lastPingSentTime = 0L
                reconnectAttempts = 0
                handler.removeCallbacks(pingRunnable)
                handler.postDelayed(pingRunnable, PING_INTERVAL_MILLISECONDS)
                if (app.isAppInForeground) {
                    handler.post { sendFocus() }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(
                        NOTIFICATION_ID,
                        buildNotification(),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, buildNotification())
                }
            }
        }

        app.serviceConnectionState = newState

        if (newState != ConnectionState.CONNECTING) {
            app.connectingTransport = null
        }
        if (newState != ConnectionState.ACTIVE) {
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
        handler.postDelayed(runnable, HANDSHAKE_TIMEOUT_MILLISECONDS)
    }

    private fun cancelHandshakeTimeout() {
        handshakeTimeoutRunnable?.let { handler.removeCallbacks(it) }
        handshakeTimeoutRunnable = null
    }

    fun sendCommand(
        commandIdentifier: Byte,
        tagLengthValueData: ByteArray = ByteArray(0),
    ) {
        val sequenceNumber = nextSequenceNumber++
        val payload = Protocol.createCommand(commandIdentifier, sequenceNumber, tagLengthValueData)
        retryPayload = payload
        pendingAcknowledgmentSequenceNumber = sequenceNumber
        pendingRetries = 0
        transport.send(payload)
        startRetryTimer()
    }

    private fun startRetryTimer() {
        cancelRetry()
        val runnable =
            Runnable {
                if (pendingAcknowledgmentSequenceNumber != null && pendingRetries < 3) {
                    pendingRetries++
                    FileLogger.w(TAG, "Retry command seq=$pendingAcknowledgmentSequenceNumber, attempt=$pendingRetries")
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

    override fun onCreate() {
        super.onCreate()
        FileLogger.i(TAG, "Service created")
        localDeviceName =
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                ?: Build.MODEL

        val listener: (Boolean) -> Unit = { inForeground ->
            handler.post { if (inForeground) sendFocus() else sendBlur() }
        }
        foregroundListener = listener
        app.addForegroundListener(listener)

        transport =
            TransportManager(
                context = this,
                onMessageReceived = { data -> handler.post { handleMessage(data) } },
                onConnectionChanged = { connected ->
                    val generation = failoverGeneration
                    handler.post {
                        val label =
                            when (transport.activeTransport) {
                                TransportManager.ActiveTransport.BLE -> "BLE"
                                TransportManager.ActiveTransport.WIFI -> "WiFi"
                                TransportManager.ActiveTransport.NONE -> ""
                            }
                        if (connected) {
                            if (generation != failoverGeneration) {
                                FileLogger.d(
                                    TAG,
                                    "Ignoring stale connect (gen=$generation, current=$failoverGeneration)",
                                )
                                return@post
                            }
                            FileLogger.i(TAG, "$label connected (gen=$generation)")
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
                                FileLogger.d(TAG, "Sending ready signal (reconnection)")
                                transport.send(Protocol.createReady(localDeviceName))
                            } else if (code != null) {
                                FileLogger.d(TAG, "Sending pair request (first pairing)")
                                transport.send(Protocol.createPairRequest(code))
                            } else {
                                FileLogger.e(TAG, "Connected but no pairing code available")
                            }
                        } else {
                            if (generation != failoverGeneration) {
                                FileLogger.d(
                                    TAG,
                                    "Ignoring stale disconnect (gen=$generation, current=$failoverGeneration)",
                                )
                                return@post
                            }
                            FileLogger.i(TAG, "$label disconnected (state=$state, gen=$generation)")
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
        val action = intent?.action
        FileLogger.i(TAG, "onStartCommand action=$action (started=$started, state=$state)")

        when (action) {
            ACTION_SOFT_DISCONNECT -> {
                performSoftDisconnect()
                return START_NOT_STICKY
            }

            ACTION_UNPAIR -> {
                performUnpair()
                return START_NOT_STICKY
            }
        }

        if (!started) {
            started = true
            startFailover()
        } else if (state == ConnectionState.IDLE && app.configStore.pairingCode != null) {
            FileLogger.i(TAG, "Already started but idle — restarting failover")
            startFailover()
        }
        return START_NOT_STICKY
    }

    private fun performSoftDisconnect() {
        FileLogger.i(TAG, "Performing soft disconnect (keep pairing)")
        shutdownWithSignal(Protocol.createGoodbye())
    }

    private fun performUnpair() {
        FileLogger.i(TAG, "Performing unpair (clear pairing)")
        app.hasBeenConnected = false
        app.configStore.clearPairing()
        shutdownWithSignal(Protocol.createUnpair())
    }

    private fun shutdownWithSignal(finalSignal: ByteArray) {
        val wasActive = state == ConnectionState.ACTIVE || state == ConnectionState.HANDSHAKING
        transitionTo(ConnectionState.IDLE)
        handler.removeCallbacks(pingRunnable)
        cancelHandshakeTimeout()
        cancelFailover()
        cancelRetry()
        if (wasActive) {
            transport.sendAndStop(finalSignal)
        } else {
            transport.stopAll()
        }
        stopSelf()
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
        foregroundListener?.let { app.removeForegroundListener(it) }
        foregroundListener = null
        transitionTo(ConnectionState.IDLE)
        handler.removeCallbacks(pingRunnable)
        cancelHandshakeTimeout()
        cancelFailover()
        cancelRetry()
        transport.stopAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun handleMessage(payload: ByteArray) {
        if (payload.isEmpty()) return
        val signalId = payload[0]
        FileLogger.d(TAG, "Received signal 0x${String.format("%02x", signalId)} size=${payload.size}")
        if (state == ConnectionState.ACTIVE) lastPongTime = System.currentTimeMillis()

        when (signalId) {
            Signal.READY -> {
                Protocol.parseReadyDeviceName(payload)?.let { name ->
                    deviceName = name
                    app.connectedDeviceName = name
                }
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
                        message = "$deviceName disconnected",
                        direction = LogDirection.INCOMING,
                    ),
                )
                transitionTo(ConnectionState.IDLE)
                transport.stopAll()
                startFailover()
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
                FileLogger.i(
                    TAG,
                    "Pair response: accepted=${result?.first}, reason=0x${String.format(
                        "%02x",
                        result?.second ?: 0,
                    )}",
                )
                if (result != null && result.first) {
                    app.configStore.completePairing()
                    transport.send(Protocol.createReady(localDeviceName))
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.PAIRING_COMPLETE,
                            message = "Paired with $deviceName",
                            direction = LogDirection.INCOMING,
                        ),
                    )
                    transitionTo(ConnectionState.ACTIVE)
                } else {
                    app.configStore.clearPairing()
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

            Signal.ACKNOWLEDGMENT -> {
                val sequenceNumber = Protocol.parseAcknowledgmentSequenceNumber(payload)
                if (sequenceNumber != null && sequenceNumber == pendingAcknowledgmentSequenceNumber) {
                    FileLogger.d(TAG, "Acknowledgment received for seq=$sequenceNumber")
                    pendingAcknowledgmentSequenceNumber = null
                    retryPayload = null
                    cancelRetry()
                }
            }

            Signal.COMMAND -> {
                val command = Protocol.parseCommand(payload)
                if (command != null) {
                    transport.send(Protocol.createAcknowledgment(command.sequenceNumber))
                    handleCommand(command)
                }
            }

            Signal.FOCUS -> {
                if (state == ConnectionState.ACTIVE) {
                    FileLogger.i(TAG, "Remote focus")
                    app.isRemoteInFocus = true
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.REMOTE_FOCUS,
                            message = "$deviceName gained focus",
                            direction = LogDirection.INCOMING,
                        ),
                    )
                }
            }

            Signal.BLUR -> {
                if (state == ConnectionState.ACTIVE) {
                    FileLogger.i(TAG, "Remote blur")
                    app.isRemoteInFocus = false
                    app.appendLogEntry(
                        LogEntry(
                            type = LogEventType.REMOTE_BLUR,
                            message = "$deviceName lost focus",
                            direction = LogDirection.INCOMING,
                        ),
                    )
                }
            }
        }
    }

    private fun handleCommand(command: Protocol.Command) {
        FileLogger.d(TAG, "Command 0x${String.format("%02x", command.commandIdentifier)} seq=${command.sequenceNumber}")
    }

    fun sendFocus() {
        if (state != ConnectionState.ACTIVE) {
            FileLogger.d(TAG, "Focus skipped (state=$state)")
            return
        }
        FileLogger.d(TAG, "Sending focus")
        transport.send(Protocol.createFocus())
        app.appendLogEntry(
            LogEntry(
                type = LogEventType.REMOTE_FOCUS,
                message = "Gained focus",
                direction = LogDirection.OUTGOING,
            ),
        )
    }

    fun sendBlur() {
        if (state != ConnectionState.ACTIVE) {
            FileLogger.d(TAG, "Blur skipped (state=$state)")
            return
        }
        FileLogger.d(TAG, "Sending blur")
        transport.send(Protocol.createBlur())
        app.appendLogEntry(
            LogEntry(
                type = LogEventType.REMOTE_BLUR,
                message = "Lost focus",
                direction = LogDirection.OUTGOING,
            ),
        )
    }

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
}
