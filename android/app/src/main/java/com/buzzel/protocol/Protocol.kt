package com.buzzel.protocol

import com.buzzel.model.ConfigData
import com.buzzel.model.FilterRule
import com.buzzel.model.FilterType
import com.buzzel.model.SmsData
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

// --- Message Types ---

object MessageType {
    const val SMS = "sms"
    const val CONFIG_SYNC = "config_sync"
    const val CONFIG_ACK = "config_ack"
    const val READY = "ready"
    const val GOODBYE = "goodbye"
    const val PING = "ping"
    const val PONG = "pong"
    const val QUEUE_FLUSH = "queue_flush"
    const val STATUS = "status"
    const val PAIRING_REQUEST = "pairing_request"
    const val PAIRING_RESPONSE = "pairing_response"
    const val UNPAIR = "unpair"
}

// --- BLE UUIDs ---

object BleUuids {
    val SERVICE: UUID = UUID.fromString("0000bf01-0000-1000-8000-00805f9b34fb")
    val CONFIG_CHAR: UUID = UUID.fromString("0000bf02-0000-1000-8000-00805f9b34fb")
    val SMS_CHAR: UUID = UUID.fromString("0000bf03-0000-1000-8000-00805f9b34fb")
    val STATUS_CHAR: UUID = UUID.fromString("0000bf04-0000-1000-8000-00805f9b34fb")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

// --- JSON Serialization ---

object Protocol {

    fun createMessage(type: String, payload: JSONObject? = null): String {
        return JSONObject().apply {
            put("type", type)
            put("id", UUID.randomUUID().toString())
            put("timestamp", System.currentTimeMillis())
            if (payload != null) put("payload", payload)
        }.toString()
    }

    fun createSmsMessage(sms: SmsData): String {
        val payload = JSONObject().apply {
            put("sender", sms.sender)
            put("contactName", sms.contactName ?: JSONObject.NULL)
            put("body", sms.body)
            put("receivedAt", sms.receivedAt)
        }
        return createMessage(MessageType.SMS, payload)
    }

    fun createQueueFlush(messages: List<SmsData>): String {
        val arr = JSONArray()
        for (sms in messages) {
            arr.put(JSONObject().apply {
                put("sender", sms.sender)
                put("contactName", sms.contactName ?: JSONObject.NULL)
                put("body", sms.body)
                put("receivedAt", sms.receivedAt)
            })
        }
        val payload = JSONObject().apply { put("messages", arr) }
        return createMessage(MessageType.QUEUE_FLUSH, payload)
    }

    fun createPing(): String = createMessage(MessageType.PING)
    fun createPong(): String = createMessage(MessageType.PONG)
    fun createReady(): String = createMessage(MessageType.READY)
    fun createGoodbye(): String = createMessage(MessageType.GOODBYE)
    fun createConfigAck(): String = createMessage(MessageType.CONFIG_ACK)

    fun createStatus(connected: Boolean, filterCount: Int, mode: String): String {
        val payload = JSONObject().apply {
            put("connected", connected)
            put("filterCount", filterCount)
            put("mode", mode)
        }
        return createMessage(MessageType.STATUS, payload)
    }

    fun createPairingResponse(): String {
        val payload = JSONObject().apply { put("accepted", true) }
        return createMessage(MessageType.PAIRING_RESPONSE, payload)
    }

    fun parsePairingCode(json: String): String? {
        return try {
            val msg = JSONObject(json)
            if (msg.optString("type") != MessageType.PAIRING_REQUEST) return null
            val p = msg.optJSONObject("payload") ?: return null
            p.optString("code", null)
        } catch (e: Exception) {
            null
        }
    }

    fun parseType(json: String): String? {
        return try {
            JSONObject(json).optString("type", null)
        } catch (e: Exception) {
            null
        }
    }

    fun parseConfig(json: String): ConfigData? {
        return try {
            val msg = JSONObject(json)
            if (msg.optString("type") != MessageType.CONFIG_SYNC) return null
            val p = msg.optJSONObject("payload") ?: return null

            val filters = mutableListOf<FilterRule>()
            val arr = p.optJSONArray("filters")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val f = arr.getJSONObject(i)
                    filters.add(
                        FilterRule(
                            id = f.optString("id", UUID.randomUUID().toString()),
                            enabled = f.optBoolean("enabled", true),
                            type = when (f.optString("type")) {
                                "content" -> FilterType.CONTENT
                                else -> FilterType.SENDER
                            },
                            value = f.optString("value", "")
                        )
                    )
                }
            }

            ConfigData(
                transport = p.optString("transport", "ble"),
                wifiHost = p.optString("wifiHost", null),
                wifiPort = p.optInt("wifiPort", 9876),
                filters = filters
            )
        } catch (e: Exception) {
            null
        }
    }

    // Serialize filters to JSON string for SharedPreferences storage
    fun filtersToJson(filters: List<FilterRule>): String {
        val arr = JSONArray()
        for (f in filters) {
            arr.put(JSONObject().apply {
                put("id", f.id)
                put("enabled", f.enabled)
                put("type", if (f.type == FilterType.CONTENT) "content" else "sender")
                put("value", f.value)
            })
        }
        return arr.toString()
    }

    fun filtersFromJson(json: String): List<FilterRule> {
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val f = arr.getJSONObject(i)
                FilterRule(
                    id = f.optString("id", UUID.randomUUID().toString()),
                    enabled = f.optBoolean("enabled", true),
                    type = when (f.optString("type")) {
                        "content" -> FilterType.CONTENT
                        else -> FilterType.SENDER
                    },
                    value = f.optString("value", "")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
