package com.buzzel.ui

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.buzzel.BuzzelApp
import com.buzzel.model.LogDirection
import com.buzzel.model.LogEntry
import com.buzzel.model.LogStatus

class LogActivity : Activity() {

    companion object {
        private val COLOR_TEXT = Color.parseColor("#1A1A1A")
        private val COLOR_SECONDARY = Color.parseColor("#8E8E93")
        private val COLOR_BACKGROUND = Color.parseColor("#F5F5F7")
        private val COLOR_BORDER = Color.parseColor("#E5E5EA")
        private val COLOR_ACCENT = Color.parseColor("#007AFF")
        private val COLOR_ERROR = Color.parseColor("#FF3B30")
        private val COLOR_ERROR_BG = Color.parseColor("#FFF0EF")
        private val COLOR_INCOMING = Color.parseColor("#007AFF")
        private val COLOR_OUTGOING = Color.parseColor("#34C759")
    }

    private var logContainer: LinearLayout? = null
    private var logScrollView: ScrollView? = null
    private var logEntryListener: ((LogEntry) -> Unit)? = null

    private val dp = { value: Int ->
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        @Suppress("DEPRECATION")
        window.statusBarColor = Color.WHITE
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.WHITE
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        val app = application as BuzzelApp
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }

        // Header
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(12))
        }

        header.addView(TextView(this).apply {
            text = "Activity"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setTextColor(COLOR_TEXT)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        val clearBtn = TextView(this).apply {
            text = "Clear"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(COLOR_SECONDARY)
            setOnClickListener {
                val container = logContainer ?: return@setOnClickListener
                container.removeAllViews()
                container.addView(buildEmptyState())
            }
        }
        header.addView(clearBtn, wrapWrap())

        root.addView(header, matchWrap())

        // Divider
        root.addView(View(this).apply {
            setBackgroundColor(COLOR_BORDER)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)))

        // Log list
        val logScroll = ScrollView(this).apply {
            setBackgroundColor(Color.WHITE)
        }
        logScrollView = logScroll

        val logList = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(10))
        }
        logContainer = logList

        val snapshot = app.getLogEntrySnapshot()

        if (snapshot.isEmpty()) {
            logList.addView(buildEmptyState())
        } else {
            for (entry in snapshot) {
                logList.addView(buildLogEntryRow(entry))
            }
        }

        logScroll.addView(logList, matchWrap())
        root.addView(
            logScroll, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
            )
        )

        // Footer — Done button
        root.addView(View(this).apply {
            setBackgroundColor(COLOR_BORDER)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)))

        val footer = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(12), dp(16), dp(16))
        }
        footer.addView(TextView(this).apply {
            text = "Done"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(COLOR_ACCENT)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(10), dp(24), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), COLOR_ACCENT)
            }
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        root.addView(footer, matchWrap())

        setContentView(root)

        // Listen for new entries
        logEntryListener = { entry ->
            runOnUiThread {
                val container = logContainer ?: return@runOnUiThread
                if (container.childCount == 1 && container.getChildAt(0).tag == "empty") {
                    container.removeAllViews()
                }
                container.addView(buildLogEntryRow(entry))
                logScrollView?.post { logScrollView?.fullScroll(View.FOCUS_DOWN) }
            }
        }
        app.addLogEntryListener(logEntryListener!!)

        logScroll.post { logScroll.fullScroll(View.FOCUS_DOWN) }
    }

    override fun onDestroy() {
        logEntryListener?.let { (application as BuzzelApp).removeLogEntryListener(it) }
        logEntryListener = null
        super.onDestroy()
    }

    private fun buildEmptyState(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(64), dp(24), dp(64))
            tag = "empty"

            addView(TextView(context).apply {
                text = "No activity yet"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTextColor(COLOR_SECONDARY)
                gravity = Gravity.CENTER
            }, matchWrap())
        }
    }

    private fun buildLogEntryRow(entry: LogEntry): LinearLayout {
        val isFailed = entry.status == LogStatus.FAILED
        val bgColor = if (isFailed) COLOR_ERROR_BG else COLOR_BACKGROUND

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = dp(8).toFloat()
            }
            layoutParams = matchWrap().apply { bottomMargin = dp(6) }

            // Main row: direction icon + message + time
            val mainRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(10), dp(12), if (entry.error != null) dp(4) else dp(10))
            }

            // Direction icon
            mainRow.addView(TextView(context).apply {
                text = when (entry.direction) {
                    LogDirection.INCOMING -> "↙"
                    LogDirection.OUTGOING -> "↗"
                    LogDirection.LOCAL -> "•"
                }
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTextColor(
                    when (entry.direction) {
                        LogDirection.INCOMING -> COLOR_INCOMING
                        LogDirection.OUTGOING -> COLOR_OUTGOING
                        LogDirection.LOCAL -> COLOR_SECONDARY
                    }
                )
                gravity = Gravity.CENTER
            }, LinearLayout.LayoutParams(dp(20), LinearLayout.LayoutParams.WRAP_CONTENT))

            // Message
            mainRow.addView(TextView(context).apply {
                text = entry.message
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTextColor(if (isFailed) COLOR_ERROR else COLOR_TEXT)
                maxLines = 2
                setPadding(dp(4), 0, 0, 0)
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            // Failed icon
            if (isFailed) {
                mainRow.addView(TextView(context).apply {
                    text = "!"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                    setTextColor(Color.WHITE)
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.CENTER
                    background = GradientDrawable().apply {
                        setColor(COLOR_ERROR)
                        cornerRadius = dp(7).toFloat()
                    }
                }, LinearLayout.LayoutParams(dp(14), dp(14)).apply { marginStart = dp(6) })
            }

            // Time
            mainRow.addView(TextView(context).apply {
                text = entry.timeString
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                setTextColor(COLOR_SECONDARY)
            }, wrapWrap().apply { marginStart = dp(8) })

            addView(mainRow, matchWrap())

            // Error message row
            if (entry.error != null) {
                addView(TextView(context).apply {
                    text = entry.error
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(COLOR_ERROR)
                    setPadding(dp(36), 0, dp(12), dp(10))
                }, matchWrap())
            }
        }
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
    )

    private fun wrapWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
    )
}
