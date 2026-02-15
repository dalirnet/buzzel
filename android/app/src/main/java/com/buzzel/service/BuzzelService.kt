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
import com.buzzel.ui.MainActivity
import com.buzzel.R
import com.buzzel.model.LogDirection
import com.buzzel.model.LogEntry
import com.buzzel.model.LogEventType
import com.buzzel.model.LogStatus
import com.buzzel.protocol.MessageType
import com.buzzel.protocol.Protocol
import com.buzzel.model.SmsData
import com.buzzel.sms.SmsFilter
import com.buzzel.sms.SmsQueue
import com.buzzel.sms.SmsReceiver
import com.buzzel.transport.TransportManager

class BuzzelService : Service(), SmsReceiver.SmsListener {

    private val app: BuzzelApp get() = application as BuzzelApp

    companion object {
        private const val TAG = "BuzzelService"
        private const val NOTIFICATION_ID = 1
        private const val PING_INTERVAL_MS = 30_000L
        private const val PONG_TIMEOUT_MS = 60_000L
        private const val BLE_LINK_TIMEOUT_MS = 30_000L
    }

    enum class ConnectionState { IDLE, BLE_LINK, ACTIVE }

    private lateinit var transport: TransportManager
    private lateinit var smsFilter: SmsFilter
    private lateinit var smsQueue: SmsQueue

    private val handler = Handler(Looper.getMainLooper())
    private var state = ConnectionState.IDLE
    private var lastPongTime = 0L
    private var bleStarted = false
    private var bleLinkTimeoutRunnable: Runnable? = null
    private val deviceName = "Mac"

    private val pingRunnable = object : Runnable {
        override fun run() {
            if (state != ConnectionState.ACTIVE) return
            if (lastPongTime > 0 && System.currentTimeMillis() - lastPongTime > PONG_TIMEOUT_MS) {
                Log.d(TAG, "Pong timeout")
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "Pong timeout",
                        direction = LogDirection.LOCAL,
                        status = LogStatus.FAILED,
                        error = "No pong for ${PONG_TIMEOUT_MS / 1000}s"
                    )
                )
                transitionTo(ConnectionState.IDLE)
                return
            }
            transport.send(Protocol.createPing())
            handler.postDelayed(this, PING_INTERVAL_MS)
        }
    }

    // --- State Machine ---

    private fun transitionTo(newState: ConnectionState) {
        val oldState = state
        // Allow ACTIVE -> ACTIVE (re-ready from macOS restart)
        if (oldState == newState && newState != ConnectionState.ACTIVE) return
        Log.d(TAG, "State: $oldState -> $newState")
        state = newState

        when (newState) {
            ConnectionState.IDLE -> {
                handler.removeCallbacks(pingRunnable)
                cancelBleLinkTimeout()
                transport.disconnectBle()
                transport.setBleLowPower(true)
                transport.stopTcp()
                app.isDeviceConnected = false
            }

            ConnectionState.BLE_LINK -> {
                startBleLinkTimeout()
                app.isDeviceConnected = false
            }

            ConnectionState.ACTIVE -> {
                cancelBleLinkTimeout()
                lastPongTime = System.currentTimeMillis()
                transport.setBleLowPower(false)
                app.isDeviceConnected = true

                val config = app.configStore.getConfig()
                if (config.transport == "wifi" || config.transport == "auto") {
                    transport.startTcp(config.wifiPort)
                }

                handler.removeCallbacks(pingRunnable)
                handler.postDelayed(pingRunnable, PING_INTERVAL_MS)
            }
        }
        updateNotification()
    }

    private fun startBleLinkTimeout() {
        cancelBleLinkTimeout()
        val runnable = Runnable {
            if (state == ConnectionState.BLE_LINK) {
                Log.d(TAG, "BLE_LINK timeout — no ready received")
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "Connection timeout",
                        direction = LogDirection.LOCAL,
                        status = LogStatus.FAILED,
                        error = "No handshake received"
                    )
                )
                transitionTo(ConnectionState.IDLE)
            }
        }
        bleLinkTimeoutRunnable = runnable
        handler.postDelayed(runnable, BLE_LINK_TIMEOUT_MS)
    }

    private fun cancelBleLinkTimeout() {
        bleLinkTimeoutRunnable?.let { handler.removeCallbacks(it) }
        bleLinkTimeoutRunnable = null
    }

    // --- Lifecycle ---

    override fun onCreate() {
        super.onCreate()

        smsFilter = SmsFilter()
        smsQueue = SmsQueue(this)

        transport = TransportManager(
            context = this,
            onMessageReceived = { handleMessage(it) },
            onConnectionChanged = { connected ->
                Log.d(TAG, "Connection changed: $connected")
                app.appendLogEntry(
                    LogEntry(
                        type = if (connected) LogEventType.DEVICE_CONNECTED else LogEventType.DEVICE_DISCONNECTED,
                        message = if (connected) "Connected to $deviceName" else "Disconnected from $deviceName"
                    )
                )
                if (connected) {
                    transitionTo(ConnectionState.BLE_LINK)
                } else {
                    transitionTo(ConnectionState.IDLE)
                }
            }
        )

        SmsReceiver.listener = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }

        if (!bleStarted) {
            bleStarted = true
            transport.startBle()
            transport.setBleLowPower(true)
            Log.d(TAG, "Service started")
        }

        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pingRunnable)
        cancelBleLinkTimeout()
        if (state == ConnectionState.ACTIVE || state == ConnectionState.BLE_LINK) {
            transport.sendGoodbyeAndStop(Protocol.createGoodbye())
        } else {
            transport.stopAll()
        }
        SmsReceiver.listener = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // --- SMS Handling ---

    override fun onSmsReceived(sender: String, contactName: String?, body: String) {
        val filters = app.configStore.getFilters()
        val sms = SmsData(sender, contactName, body)
        val displayName = contactName ?: sender

        if (!smsFilter.shouldForward(sender, body, filters)) {
            Log.d(TAG, "SMS filtered out from $sender")
            app.appendLogEntry(
                LogEntry(
                    type = LogEventType.SMS_FILTERED,
                    message = "Filtered SMS from $displayName",
                    direction = LogDirection.LOCAL
                )
            )
            return
        }

        if (state == ConnectionState.ACTIVE && transport.isConnected) {
            transport.send(Protocol.createSmsMessage(sms))
            Log.d(TAG, "SMS forwarded from $sender")
            app.appendLogEntry(
                LogEntry(
                    type = LogEventType.SMS_FORWARDED,
                    message = "Forwarded SMS from $displayName",
                    direction = LogDirection.OUTGOING
                )
            )
        } else {
            smsQueue.enqueue(sms)
            Log.d(TAG, "SMS queued from $sender (queue size: ${smsQueue.size()})")
            app.appendLogEntry(
                LogEntry(
                    type = LogEventType.SMS_QUEUED,
                    message = "Queued SMS from $displayName",
                    direction = LogDirection.LOCAL
                )
            )
        }
    }

    // --- Message Handling ---

    private fun handleMessage(json: String) {
        val type = Protocol.parseType(json) ?: return
        Log.d(TAG, "handleMessage: $type")

        // Reset pong timer on any incoming message while active
        if (state == ConnectionState.ACTIVE) {
            lastPongTime = System.currentTimeMillis()
        }

        when (type) {
            MessageType.READY -> {
                Log.d(TAG, "Device is ready")
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_CONNECTED,
                        message = "$deviceName is ready",
                        direction = LogDirection.INCOMING
                    )
                )
                transitionTo(ConnectionState.ACTIVE)
                flushQueue()
            }

            MessageType.GOODBYE -> {
                Log.d(TAG, "Device said goodbye")
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "$deviceName said goodbye",
                        direction = LogDirection.INCOMING
                    )
                )
                transitionTo(ConnectionState.IDLE)
            }

            MessageType.UNPAIR -> {
                Log.d(TAG, "Device unpaired")
                app.configStore.clearPairing()
                app.appendLogEntry(
                    LogEntry(
                        type = LogEventType.DEVICE_DISCONNECTED,
                        message = "$deviceName unpaired — pairing cleared",
                        direction = LogDirection.INCOMING
                    )
                )
                transitionTo(ConnectionState.IDLE)
            }

            MessageType.PING -> {
                transport.send(Protocol.createPong())
            }

            MessageType.PAIRING_REQUEST -> handlePairingRequest(json)
            MessageType.CONFIG_SYNC -> handleConfigSync(json)
        }
    }

    private fun handlePairingRequest(json: String) {
        val pairingCode = Protocol.parsePairingCode(json) ?: return
        val expectedCode = app.configStore.pairingCode ?: run {
            Log.w(TAG, "Pairing request received but no pairing code set")
            app.appendLogEntry(
                LogEntry(
                    type = LogEventType.PAIRING_FAILED,
                    message = "Pairing failed",
                    direction = LogDirection.INCOMING,
                    status = LogStatus.FAILED,
                    error = "No pairing code set"
                )
            )
            return
        }

        if (pairingCode != expectedCode) {
            Log.w(TAG, "Pairing code mismatch")
            app.appendLogEntry(
                LogEntry(
                    type = LogEventType.PAIRING_FAILED,
                    message = "Pairing failed",
                    direction = LogDirection.INCOMING,
                    status = LogStatus.FAILED,
                    error = "Code mismatch"
                )
            )
            return
        }

        transport.send(Protocol.createPairingResponse())
        Log.d(TAG, "Pairing complete")
        app.appendLogEntry(
            LogEntry(
                type = LogEventType.PAIRING_COMPLETE,
                message = "Paired with $deviceName",
                direction = LogDirection.OUTGOING
            )
        )
    }

    private fun handleConfigSync(json: String) {
        val config = Protocol.parseConfig(json) ?: run {
            app.appendLogEntry(
                LogEntry(
                    type = LogEventType.CONFIG_SYNCED,
                    message = "Config sync failed",
                    direction = LogDirection.INCOMING,
                    status = LogStatus.FAILED,
                    error = "Invalid config data"
                )
            )
            return
        }
        app.configStore.applyConfig(config)
        transport.send(Protocol.createConfigAck())
        Log.d(TAG, "Config applied: ${config.filters.size} filters")
        app.appendLogEntry(
            LogEntry(
                type = LogEventType.CONFIG_SYNCED,
                message = "Synced ${config.filters.size} filters from $deviceName",
                direction = LogDirection.INCOMING
            )
        )
        app.notifyConfigChanged()

        if (config.transport == "wifi" || config.transport == "auto") {
            transport.startTcp(config.wifiPort)
        }
    }

    // --- Queue ---

    private fun flushQueue() {
        val queued = smsQueue.flush()
        if (queued.isEmpty()) return

        transport.send(Protocol.createQueueFlush(queued))
        Log.d(TAG, "Flushed ${queued.size} queued messages")
        app.appendLogEntry(
            LogEntry(
                type = LogEventType.QUEUE_FLUSHED,
                message = "Delivered ${queued.size} queued messages",
                direction = LogDirection.OUTGOING
            )
        )
    }

    // --- Notification ---

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        val text = when (state) {
            ConnectionState.ACTIVE -> "Connected — forwarding SMS"
            ConnectionState.BLE_LINK -> "Device connected — handshaking..."
            ConnectionState.IDLE -> "Listening for connections"
        }

        return NotificationCompat.Builder(this, BuzzelApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pending)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun updateNotification() {
        val nm = getSystemService(android.app.NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification())
    }
}
