package com.buzzel.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.buzzel.BuzzelApp
import com.buzzel.service.BuzzelService

enum class PowerButtonState {
    RESTRICTED,
    UNPAIRED,
    CONNECTING,
    CONNECTED,
    DISCONNECTED,
    ;

    companion object {
        fun current(app: BuzzelApp): PowerButtonState {
            val btGranted =
                ContextCompat.checkSelfPermission(
                    app,
                    Manifest.permission.BLUETOOTH_CONNECT,
                ) == PackageManager.PERMISSION_GRANTED
            if (!btGranted) return RESTRICTED

            // UNPAIRED = no QR scanned yet (no pairing code stored)
            val hasQr = app.configStore.pairingCode != null
            if (!hasQr) return UNPAIRED

            return when (app.serviceConnectionState) {
                BuzzelService.ConnectionState.ACTIVE -> CONNECTED
                BuzzelService.ConnectionState.IDLE -> DISCONNECTED
                else -> CONNECTING
            }
        }
    }
}
