package com.buzzel.config

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

class ConfigStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("buzzel_config", Context.MODE_PRIVATE)

    companion object {
        private const val TAG = "ConfigStore"
        private const val KEY_PAIRING_CODE = "pairing_code"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_MAC_HOST = "mac_host"
        private const val KEY_PREFER_TRANSPORT = "prefer_transport"
    }

    var pairingCode: String?
        get() = prefs.getString(KEY_PAIRING_CODE, null)
        set(value) = prefs.edit().putString(KEY_PAIRING_CODE, value).apply()

    var sessionId: String?
        get() = prefs.getString(KEY_SESSION_ID, null)
        set(value) = prefs.edit().putString(KEY_SESSION_ID, value).apply()

    var macHost: String?
        get() = prefs.getString(KEY_MAC_HOST, null)
        set(value) {
            Log.d(TAG, "Set macHost=$value")
            prefs.edit().putString(KEY_MAC_HOST, value).apply()
        }

    var preferTransport: String?
        get() = prefs.getString(KEY_PREFER_TRANSPORT, "wifi")
        set(value) {
            Log.d(TAG, "Set preferTransport=$value")
            prefs.edit().putString(KEY_PREFER_TRANSPORT, value).apply()
        }

    fun clearPairing() {
        Log.i(TAG, "Pairing data cleared")
        prefs.edit().apply {
            remove(KEY_PAIRING_CODE)
            remove(KEY_SESSION_ID)
            remove(KEY_MAC_HOST)
            remove(KEY_PREFER_TRANSPORT)
            apply()
        }
    }
}
