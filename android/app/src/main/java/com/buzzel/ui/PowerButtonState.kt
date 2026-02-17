package com.buzzel.ui

import com.buzzel.BuzzelApp
import com.buzzel.service.BuzzelService

enum class PowerButtonState {
    NO_PERMISSION,
    UNPAIRED,
    CONNECTING,
    CONNECTED,
    DISCONNECTED,
    ;

    companion object {
        fun current(app: BuzzelApp): PowerButtonState {
            val hasPairing = app.configStore.sessionId != null
            val serviceState = app.serviceConnectionState

            if (!hasPairing) return UNPAIRED

            return when (serviceState) {
                BuzzelService.ConnectionState.ACTIVE -> CONNECTED
                else -> if (app.hasBeenConnected) DISCONNECTED else CONNECTING
            }
        }
    }
}
