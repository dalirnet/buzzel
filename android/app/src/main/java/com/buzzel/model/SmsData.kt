package com.buzzel.model

data class SmsData(
    val sender: String,
    val contactName: String?,
    val body: String,
    val receivedAt: Long = System.currentTimeMillis()
)
