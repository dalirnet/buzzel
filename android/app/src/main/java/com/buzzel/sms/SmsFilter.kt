package com.buzzel.sms

import com.buzzel.model.FilterRule
import com.buzzel.model.FilterType

class SmsFilter {

    /**
     * Determines if an SMS should be forwarded based on filter rules.
     * - No filters = forward everything
     * - Has filters = only forward if at least one filter matches
     * - Wildcard matching: * = any characters, case-insensitive
     */
    fun shouldForward(sender: String, body: String, filters: List<FilterRule>): Boolean {
        val active = filters.filter { it.enabled }
        if (active.isEmpty()) return true

        return active.any { filter ->
            when (filter.type) {
                FilterType.SENDER -> wildcardMatch(sender, filter.value)
                FilterType.CONTENT -> wildcardMatch(body, filter.value)
            }
        }
    }

    /**
     * Simple wildcard matching where * matches any number of characters.
     * Case-insensitive.
     */
    private fun wildcardMatch(text: String, pattern: String): Boolean {
        val t = text.lowercase()
        val p = pattern.lowercase()

        // Convert wildcard pattern to regex: escape special chars, replace * with .*
        val regex = buildString {
            append("^")
            for (ch in p) {
                when (ch) {
                    '*' -> append(".*")
                    '.', '\\', '(', ')', '[', ']', '{', '}', '^', '$', '|', '?', '+' -> {
                        append('\\')
                        append(ch)
                    }

                    else -> append(ch)
                }
            }
            append("$")
        }

        return try {
            Regex(regex).matches(t)
        } catch (e: Exception) {
            false
        }
    }
}
