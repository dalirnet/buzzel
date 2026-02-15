package com.buzzel.config

import android.content.Context
import android.content.SharedPreferences
import com.buzzel.model.ConfigData
import com.buzzel.model.FilterRule
import com.buzzel.protocol.Protocol

class ConfigStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("buzzel_config", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_TRANSPORT = "transport"
        private const val KEY_WIFI_HOST = "wifi_host"
        private const val KEY_WIFI_PORT = "wifi_port"
        private const val KEY_FILTERS = "filters"
        private const val KEY_PAIRED_ADDRESS = "paired_address"
        private const val KEY_PAIRED_NAME = "paired_name"
        private const val KEY_PAIRING_CODE = "pairing_code"
    }

    var transport: String
        get() = prefs.getString(KEY_TRANSPORT, "ble") ?: "ble"
        set(value) = prefs.edit().putString(KEY_TRANSPORT, value).apply()

    var wifiHost: String?
        get() = prefs.getString(KEY_WIFI_HOST, null)
        set(value) = prefs.edit().putString(KEY_WIFI_HOST, value).apply()

    var wifiPort: Int
        get() = prefs.getInt(KEY_WIFI_PORT, 9876)
        set(value) = prefs.edit().putInt(KEY_WIFI_PORT, value).apply()

    var pairedAddress: String?
        get() = prefs.getString(KEY_PAIRED_ADDRESS, null)
        set(value) = prefs.edit().putString(KEY_PAIRED_ADDRESS, value).apply()

    var pairedName: String?
        get() = prefs.getString(KEY_PAIRED_NAME, null)
        set(value) = prefs.edit().putString(KEY_PAIRED_NAME, value).apply()

    var pairingCode: String?
        get() = prefs.getString(KEY_PAIRING_CODE, null)
        set(value) = prefs.edit().putString(KEY_PAIRING_CODE, value).apply()

    fun getFilters(): List<FilterRule> {
        val json = prefs.getString(KEY_FILTERS, null) ?: return emptyList()
        return Protocol.filtersFromJson(json)
    }

    fun saveFilters(filters: List<FilterRule>) {
        prefs.edit().putString(KEY_FILTERS, Protocol.filtersToJson(filters)).apply()
    }

    fun getConfig(): ConfigData {
        return ConfigData(
            transport = transport,
            wifiHost = wifiHost,
            wifiPort = wifiPort,
            filters = getFilters()
        )
    }

    fun applyConfig(config: ConfigData) {
        prefs.edit().apply {
            putString(KEY_TRANSPORT, config.transport)
            putString(KEY_WIFI_HOST, config.wifiHost)
            putInt(KEY_WIFI_PORT, config.wifiPort)
            putString(KEY_FILTERS, Protocol.filtersToJson(config.filters))
            apply()
        }
    }

    fun isPaired(): Boolean = pairedAddress != null

    fun clearPairing() {
        prefs.edit().apply {
            remove(KEY_PAIRED_ADDRESS)
            remove(KEY_PAIRED_NAME)
            remove(KEY_PAIRING_CODE)
            apply()
        }
    }
}
