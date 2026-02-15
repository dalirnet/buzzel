package com.buzzel.model

import java.util.UUID

enum class FilterType { SENDER, CONTENT }

data class FilterRule(
    val id: String = UUID.randomUUID().toString(),
    val enabled: Boolean = true,
    val type: FilterType = FilterType.SENDER,
    val value: String = ""
)
