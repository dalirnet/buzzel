package com.buzzel.model

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class LogEventType {
    SMS_RECEIVED,
    SMS_FORWARDED,
    SMS_QUEUED,
    SMS_FILTERED,
    QUEUE_FLUSHED,
    DEVICE_CONNECTED,
    DEVICE_DISCONNECTED,
    PAIRING_STARTED,
    PAIRING_COMPLETE,
    PAIRING_FAILED,
    FILTER_UPDATED,
    CONFIG_SYNCED
}

enum class LogDirection {
    INCOMING,
    OUTGOING,
    LOCAL
}

enum class LogStatus {
    SUCCESS,
    FAILED
}

data class LogEntry(
    val timestamp: Long = System.currentTimeMillis(),
    val type: LogEventType,
    val message: String,
    val direction: LogDirection = LogDirection.LOCAL,
    val status: LogStatus = LogStatus.SUCCESS,
    val error: String? = null
) {
    val timeString: String
        get() = TIME_FORMAT.format(Date(timestamp))

    companion object {
        private val TIME_FORMAT = SimpleDateFormat("HH:mm", Locale.getDefault())
    }
}
