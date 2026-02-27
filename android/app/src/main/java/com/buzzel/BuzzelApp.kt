package com.buzzel

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.buzzel.config.ConfigStore
import com.buzzel.debug.FileLogger
import com.buzzel.model.LogEntry
import com.buzzel.service.BuzzelService

class BuzzelApp : Application() {
    companion object {
        private const val TAG = "BuzzelApp"
        const val CHANNEL_ID = "buzzel_service"
    }

    lateinit var configStore: ConfigStore
        private set

    var isDeviceConnected: Boolean = false
        set(value) {
            FileLogger.i(TAG, "Connection state: $value")
            field = value
            connectionListeners.forEach { it(value) }
        }

    private val connectionListeners = mutableListOf<(Boolean) -> Unit>()

    fun addConnectionListener(listener: (Boolean) -> Unit) {
        connectionListeners.add(listener)
    }

    fun removeConnectionListener(listener: (Boolean) -> Unit) {
        connectionListeners.remove(listener)
    }

    var hasBeenConnected: Boolean = false

    var connectedDeviceName: String? = null

    var isRemoteInFocus: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            remoteInFocusListeners.forEach { it(value) }
        }

    private val remoteInFocusListeners = mutableListOf<(Boolean) -> Unit>()

    fun addRemoteInFocusListener(listener: (Boolean) -> Unit) {
        remoteInFocusListeners.add(listener)
    }

    fun removeRemoteInFocusListener(listener: (Boolean) -> Unit) {
        remoteInFocusListeners.remove(listener)
    }

    var connectedTransport: String? = null

    var connectingTransport: String? = null

    var isAppInForeground: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            foregroundListeners.forEach { it(value) }
        }

    private val foregroundListeners = mutableListOf<(Boolean) -> Unit>()

    fun addForegroundListener(listener: (Boolean) -> Unit) {
        foregroundListeners.add(listener)
    }

    fun removeForegroundListener(listener: (Boolean) -> Unit) {
        foregroundListeners.remove(listener)
    }

    var serviceConnectionState: BuzzelService.ConnectionState = BuzzelService.ConnectionState.IDLE
        set(value) {
            FileLogger.i(TAG, "Service connection state: $value")
            field = value
            serviceConnectionStateListeners.forEach { it(value) }
        }

    private val serviceConnectionStateListeners = mutableListOf<(BuzzelService.ConnectionState) -> Unit>()

    fun addServiceConnectionStateListener(listener: (BuzzelService.ConnectionState) -> Unit) {
        serviceConnectionStateListeners.add(listener)
    }

    fun removeServiceConnectionStateListener(listener: (BuzzelService.ConnectionState) -> Unit) {
        serviceConnectionStateListeners.remove(listener)
    }

    private val logEntryList = mutableListOf<LogEntry>()
    private val logEntryListeners = mutableListOf<(LogEntry) -> Unit>()
    private val maxLogEntries = 200

    fun appendLogEntry(entry: LogEntry) {
        synchronized(logEntryList) {
            logEntryList.add(entry)
            if (logEntryList.size > maxLogEntries) logEntryList.removeAt(0)
        }
        logEntryListeners.forEach { it(entry) }
    }

    fun getLogEntrySnapshot(): List<LogEntry> {
        synchronized(logEntryList) { return logEntryList.toList() }
    }

    fun addLogEntryListener(listener: (LogEntry) -> Unit) {
        logEntryListeners.add(listener)
    }

    fun removeLogEntryListener(listener: (LogEntry) -> Unit) {
        logEntryListeners.remove(listener)
    }

    override fun onCreate() {
        super.onCreate()
        FileLogger.init(this)
        FileLogger.i(TAG, "Application created — log: ${FileLogger.path()}")
        configStore = ConfigStore(this)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Buzzel background service"
                setShowBadge(false)
            }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }
}
