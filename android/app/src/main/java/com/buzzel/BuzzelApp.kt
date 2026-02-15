package com.buzzel

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.buzzel.config.ConfigStore
import com.buzzel.model.LogEntry

class BuzzelApp : Application() {

    lateinit var configStore: ConfigStore
        private set

    /** Observable connection state — set by BuzzelService, read by MainActivity */
    var isDeviceConnected: Boolean = false
        set(value) {
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

    /** Config change listeners — notified when config_sync arrives */
    private val configListeners = mutableListOf<() -> Unit>()

    fun addConfigListener(listener: () -> Unit) {
        configListeners.add(listener)
    }

    fun removeConfigListener(listener: () -> Unit) {
        configListeners.remove(listener)
    }

    fun notifyConfigChanged() {
        configListeners.forEach { it() }
    }

    /** Structured activity log — visible in UI */
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
        configStore = ConfigStore(this)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Buzzel background service"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "buzzel_service"
    }
}
