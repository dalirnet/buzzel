package com.buzzel.model

data class ConfigData(
    val transport: String = "ble",
    val wifiHost: String? = null,
    val wifiPort: Int = 9876,
    val filters: List<FilterRule> = emptyList()
)
