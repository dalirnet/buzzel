package com.buzzel.sms

import android.content.Context
import android.content.SharedPreferences
import com.buzzel.model.SmsData
import org.json.JSONArray
import org.json.JSONObject

/**
 * Queues SMS messages while the Mac app is offline.
 * Stored in SharedPreferences as JSON array.
 * Flushed when Mac sends "ready" signal.
 */
class SmsQueue(context: Context) {

    companion object {
        private const val MAX_QUEUE_SIZE = 50
        private const val MAX_AGE_MS = 24 * 60 * 60 * 1000L // 24 hours
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences("buzzel_queue", Context.MODE_PRIVATE)

    fun enqueue(sms: SmsData) {
        val queue = loadQueue().toMutableList()
        queue.add(sms)

        // Trim by size
        while (queue.size > MAX_QUEUE_SIZE) {
            queue.removeAt(0)
        }

        saveQueue(queue)
    }

    fun flush(): List<SmsData> {
        val queue = loadQueue()
        clear()
        // Filter out expired messages
        val now = System.currentTimeMillis()
        return queue.filter { now - it.receivedAt < MAX_AGE_MS }
    }

    fun clear() {
        prefs.edit().remove("queue").apply()
    }

    fun size(): Int = loadQueue().size

    private fun loadQueue(): List<SmsData> {
        val json = prefs.getString("queue", null) ?: return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                SmsData(
                    sender = obj.getString("sender"),
                    contactName = obj.optString("contactName", null),
                    body = obj.getString("body"),
                    receivedAt = obj.getLong("receivedAt")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun saveQueue(queue: List<SmsData>) {
        val arr = JSONArray()
        for (sms in queue) {
            arr.put(JSONObject().apply {
                put("sender", sms.sender)
                put("contactName", sms.contactName ?: JSONObject.NULL)
                put("body", sms.body)
                put("receivedAt", sms.receivedAt)
            })
        }
        prefs.edit().putString("queue", arr.toString()).apply()
    }
}
