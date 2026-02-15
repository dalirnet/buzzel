package com.buzzel.ui

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.buzzel.BuzzelApp
import com.buzzel.R
import com.buzzel.model.FilterType
import com.buzzel.service.BuzzelService

class MainActivity : Activity() {

    companion object {
        private const val PERMISSION_REQUEST = 1001

        // Design system colors
        private val COLOR_TEXT = Color.parseColor("#1A1A1A")
        private val COLOR_SECONDARY = Color.parseColor("#8E8E93")
        private val COLOR_BACKGROUND = Color.parseColor("#F5F5F7")
        private val COLOR_BORDER = Color.parseColor("#E5E5EA")
        private val COLOR_ACCENT = Color.parseColor("#007AFF")
        private val COLOR_GREEN = Color.parseColor("#34C759")
        private val COLOR_ORANGE = Color.parseColor("#FF9500")
        private val COLOR_RED = Color.parseColor("#FF3B30")
        private val COLOR_GRANTED = Color.parseColor("#C7C7CC")

        private data class PermissionInfo(
            val permission: String,
            val label: String,
            val description: String
        )

        private val REQUIRED_PERMISSIONS: Array<String>
            get() = buildList {
                add(Manifest.permission.RECEIVE_SMS)
                add(Manifest.permission.READ_SMS)
                add(Manifest.permission.READ_CONTACTS)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    add(Manifest.permission.BLUETOOTH_ADVERTISE)
                    add(Manifest.permission.BLUETOOTH_CONNECT)
                    add(Manifest.permission.BLUETOOTH_SCAN)
                } else {
                    add(Manifest.permission.ACCESS_FINE_LOCATION)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    add(Manifest.permission.POST_NOTIFICATIONS)
                }
            }.toTypedArray()

        private val PERMISSION_DETAILS: List<PermissionInfo>
            get() = buildList {
                add(PermissionInfo(Manifest.permission.RECEIVE_SMS, "SMS", "Listen for incoming messages"))
                add(PermissionInfo(Manifest.permission.READ_SMS, "Read SMS", "Read message content"))
                add(PermissionInfo(Manifest.permission.READ_CONTACTS, "Contacts", "Resolve sender names"))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    add(
                        PermissionInfo(
                            Manifest.permission.BLUETOOTH_ADVERTISE,
                            "Bluetooth Advertise",
                            "Let Mac discover this device"
                        )
                    )
                    add(
                        PermissionInfo(
                            Manifest.permission.BLUETOOTH_CONNECT,
                            "Bluetooth Connect",
                            "Connect to paired Mac"
                        )
                    )
                    add(PermissionInfo(Manifest.permission.BLUETOOTH_SCAN, "Bluetooth Scan", "Find nearby devices"))
                } else {
                    add(
                        PermissionInfo(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            "Location",
                            "Required for Bluetooth on this device"
                        )
                    )
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    add(PermissionInfo(Manifest.permission.POST_NOTIFICATIONS, "Notifications", "Show service status"))
                }
            }
    }

    // UI references
    private lateinit var rootLayout: LinearLayout
    private var statusDot: View? = null
    private var statusText: TextView? = null
    private var filtersContainer: LinearLayout? = null
    private var connectionListener: ((Boolean) -> Unit)? = null
    private var configListener: (() -> Unit)? = null

    private val dp = { value: Int ->
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
    }

    // --- Lifecycle ---

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        @Suppress("DEPRECATION")
        window.statusBarColor = Color.WHITE
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.WHITE
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.WHITE)
            isFillViewport = true
        }
        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        scroll.addView(rootLayout, matchWrap())
        setContentView(scroll)
        updateUI()
    }

    override fun onResume() {
        super.onResume()
        updateUI()
    }

    override fun onDestroy() {
        val app = application as BuzzelApp
        connectionListener?.let { app.removeConnectionListener(it) }
        connectionListener = null
        configListener?.let { app.removeConfigListener(it) }
        configListener = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) updateUI()
    }

    // --- UI Building ---

    private fun updateUI() {
        // Clean up old listeners before rebuilding
        val app = application as BuzzelApp
        connectionListener?.let { app.removeConnectionListener(it) }
        connectionListener = null
        configListener?.let { app.removeConfigListener(it) }
        configListener = null

        rootLayout.removeAllViews()
        if (!hasAllPermissions()) {
            buildPermissionsUI()
        } else if (!isBluetoothEnabled()) {
            buildEnableBluetoothUI()
        } else if (!areNotificationsEnabled()) {
            buildEnableNotificationsUI()
        } else {
            buildPairingUI()
        }
    }

    private fun isBluetoothEnabled(): Boolean {
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bm?.adapter?.isEnabled == true
    }

    private fun areNotificationsEnabled(): Boolean {
        return NotificationManagerCompat.from(this).areNotificationsEnabled()
    }

    private fun buildPermissionsUI() {
        addSpacer(dp(48))

        rootLayout.addView(TextView(this).apply {
            text = "Buzzel"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTextColor(COLOR_TEXT)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            gravity = Gravity.CENTER
        }, matchWrap().apply { bottomMargin = dp(8) })

        rootLayout.addView(TextView(this).apply {
            text = "Grant permissions to get started"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(COLOR_SECONDARY)
            gravity = Gravity.CENTER
        }, matchWrap().apply { bottomMargin = dp(32) })

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), 0, dp(24), 0)
        }
        for (info in PERMISSION_DETAILS) {
            val granted = ContextCompat.checkSelfPermission(this, info.permission) == PackageManager.PERMISSION_GRANTED
            container.addView(buildPermissionRow(info, granted))
        }
        rootLayout.addView(container, matchWrap().apply { bottomMargin = dp(32) })

        val buttonContainer = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(dp(24), 0, dp(24), 0)
        }
        buttonContainer.addView(Button(this).apply {
            text = "Grant Permissions"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            isAllCaps = false
            stateListAnimator = null
            elevation = 0f
            background = GradientDrawable().apply {
                setColor(COLOR_ACCENT)
                cornerRadius = dp(12).toFloat()
            }
            setPadding(dp(32), dp(14), dp(32), dp(14))
            setOnClickListener {
                ActivityCompat.requestPermissions(
                    this@MainActivity,
                    REQUIRED_PERMISSIONS,
                    PERMISSION_REQUEST
                )
            }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        rootLayout.addView(buttonContainer, matchWrap())

        addSpacer(dp(48))
    }

    private fun buildEnableBluetoothUI() {
        buildSetupScreen(
            title = "Bluetooth Required",
            subtitle = "Buzzel uses Bluetooth to communicate with your Mac",
            buttonText = "Enable Bluetooth",
            onClick = {
                @Suppress("DEPRECATION")
                startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            }
        )
    }

    private fun buildEnableNotificationsUI() {
        buildSetupScreen(
            title = "Notifications Required",
            subtitle = "Buzzel needs notifications to show its background service status",
            buttonText = "Open Notification Settings",
            onClick = {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
                startActivity(intent)
            }
        )
    }

    private fun buildSetupScreen(title: String, subtitle: String, buttonText: String, onClick: () -> Unit) {
        addSpacer(dp(48))

        rootLayout.addView(TextView(this).apply {
            text = "Buzzel"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTextColor(COLOR_TEXT)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            gravity = Gravity.CENTER
        }, matchWrap().apply { bottomMargin = dp(8) })

        rootLayout.addView(TextView(this).apply {
            text = subtitle
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(COLOR_SECONDARY)
            gravity = Gravity.CENTER
            setPadding(dp(24), 0, dp(24), 0)
        }, matchWrap().apply { bottomMargin = dp(32) })

        // Status row
        val statusContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), 0, dp(24), 0)
        }
        statusContainer.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(COLOR_BACKGROUND)
                cornerRadius = dp(10).toFloat()
            }

            addView(View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(COLOR_ORANGE)
                }
            }, LinearLayout.LayoutParams(dp(8), dp(8)).apply { marginEnd = dp(14) })

            addView(TextView(context).apply {
                text = title
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setTextColor(COLOR_TEXT)
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }, matchWrap())
        rootLayout.addView(statusContainer, matchWrap().apply { bottomMargin = dp(32) })

        // Button
        val buttonContainer = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(dp(24), 0, dp(24), 0)
        }
        buttonContainer.addView(Button(this).apply {
            text = buttonText
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            isAllCaps = false
            stateListAnimator = null
            elevation = 0f
            background = GradientDrawable().apply {
                setColor(COLOR_ACCENT)
                cornerRadius = dp(12).toFloat()
            }
            setPadding(dp(32), dp(14), dp(32), dp(14))
            setOnClickListener { onClick() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        rootLayout.addView(buttonContainer, matchWrap())

        addSpacer(dp(48))
    }

    private fun buildPermissionRow(info: PermissionInfo, granted: Boolean): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(COLOR_BACKGROUND)
                cornerRadius = dp(10).toFloat()
            }
            layoutParams = matchWrap().apply { bottomMargin = dp(8) }

            addView(View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(if (granted) COLOR_GREEN else COLOR_GRANTED)
                }
            }, LinearLayout.LayoutParams(dp(8), dp(8)).apply { marginEnd = dp(14) })

            val textContainer = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            textContainer.addView(TextView(context).apply {
                text = info.label
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setTextColor(COLOR_TEXT)
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            }, matchWrap())
            textContainer.addView(TextView(context).apply {
                text = info.description
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(COLOR_SECONDARY)
            }, matchWrap())
            addView(textContainer, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            if (granted) {
                addView(TextView(context).apply {
                    text = "Granted"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setTextColor(COLOR_GREEN)
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                }, wrapWrap().apply { marginStart = dp(8) })
            }
        }
    }

    private fun buildPairingUI() {
        val app = application as BuzzelApp
        val code = app.configStore.pairingCode ?: generatePairingCode().also {
            app.configStore.pairingCode = it
        }

        // Top spacer
        rootLayout.addView(View(this), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        // Title
        rootLayout.addView(TextView(this).apply {
            text = "Pairing Code"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTextColor(COLOR_TEXT)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            gravity = Gravity.CENTER
        }, matchWrap().apply { bottomMargin = dp(8) })

        // Subtitle
        rootLayout.addView(TextView(this).apply {
            text = "Enter this code in the Mac app to pair"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(COLOR_SECONDARY)
            gravity = Gravity.CENTER
        }, matchWrap().apply { bottomMargin = dp(40) })

        // Code digits
        rootLayout.addView(buildCodeRow(code), matchWrap().apply { bottomMargin = dp(40) })

        // Status card
        buildStatusCard(app)

        // Filters table
        buildFiltersSection(app)

        // Buttons
        buildButtonRow()

        startService()
    }

    // --- Pairing UI Components ---

    private fun buildCodeRow(code: String): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER

            for ((i, ch) in code.withIndex()) {
                if (i == 3) addView(View(context), LinearLayout.LayoutParams(dp(16), 1))

                val digitBox = LinearLayout(context).apply {
                    gravity = Gravity.CENTER
                    background = GradientDrawable().apply {
                        setColor(COLOR_BACKGROUND)
                        cornerRadius = dp(10).toFloat()
                        setStroke(dp(1), COLOR_BORDER)
                    }
                }
                digitBox.addView(TextView(context).apply {
                    text = ch.toString()
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
                    setTextColor(COLOR_TEXT)
                    typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
                    gravity = Gravity.CENTER
                }, LinearLayout.LayoutParams(dp(48), dp(60)))

                addView(digitBox, LinearLayout.LayoutParams(dp(48), dp(60)).apply {
                    marginStart = if (i == 0 || i == 3) 0 else dp(8)
                })
            }
        }
    }

    private fun buildStatusCard(app: BuzzelApp) {
        val statusCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(COLOR_BACKGROUND)
                cornerRadius = dp(10).toFloat()
            }
        }

        val dot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(if (app.isDeviceConnected) COLOR_GREEN else COLOR_ORANGE)
            }
        }
        statusDot = dot
        statusCard.addView(dot, LinearLayout.LayoutParams(dp(8), dp(8)).apply { marginEnd = dp(12) })

        val stv = TextView(this).apply {
            text = if (app.isDeviceConnected) "Connected to Mac" else "Waiting for Mac to connect"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(if (app.isDeviceConnected) COLOR_GREEN else COLOR_SECONDARY)
        }
        statusText = stv
        statusCard.addView(stv, wrapWrap())

        val container = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(dp(24), 0, dp(24), 0)
        }
        container.addView(statusCard, matchWrap())
        rootLayout.addView(container, matchWrap())

        connectionListener = { connected ->
            runOnUiThread {
                statusText?.text = if (connected) "Connected to Mac" else "Waiting for Mac to connect"
                statusText?.setTextColor(if (connected) COLOR_GREEN else COLOR_SECONDARY)
                (statusDot?.background as? GradientDrawable)?.setColor(if (connected) COLOR_GREEN else COLOR_ORANGE)
            }
        }
        app.addConnectionListener(connectionListener!!)
    }

    private fun buildFiltersSection(app: BuzzelApp) {
        val wrapper = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(16), dp(24), 0)
        }

        wrapper.addView(TextView(this).apply {
            text = "Filters"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(COLOR_SECONDARY)
            setPadding(dp(4), 0, 0, dp(8))
        }, matchWrap())

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(COLOR_BACKGROUND)
                cornerRadius = dp(10).toFloat()
            }
            setPadding(dp(16), dp(4), dp(16), dp(4))
        }
        filtersContainer = container

        populateFilters(container, app)

        wrapper.addView(container, matchWrap())
        rootLayout.addView(wrapper, matchWrap())

        configListener = {
            runOnUiThread { populateFilters(container, app) }
        }
        app.addConfigListener(configListener!!)
    }

    private fun populateFilters(container: LinearLayout, app: BuzzelApp) {
        container.removeAllViews()
        val filters = app.configStore.getFilters()

        if (filters.isEmpty()) {
            container.addView(TextView(this).apply {
                text = "No filters — all SMS forwarded"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTextColor(COLOR_SECONDARY)
                gravity = Gravity.CENTER
                setPadding(0, dp(12), 0, dp(12))
            }, matchWrap())
        } else {
            for ((i, filter) in filters.withIndex()) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(0, dp(10), 0, dp(10))
                }

                row.addView(TextView(this).apply {
                    text = filter.value
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    setTextColor(COLOR_TEXT)
                    maxLines = 1
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

                row.addView(TextView(this).apply {
                    text = if (filter.type == FilterType.SENDER) "Sender" else "Content"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(COLOR_SECONDARY)
                }, wrapWrap().apply { marginStart = dp(8) })

                container.addView(row, matchWrap())

                // Divider between rows
                if (i < filters.size - 1) {
                    container.addView(View(this).apply {
                        setBackgroundColor(COLOR_BORDER)
                    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)))
                }
            }
        }
    }

    private fun buildButtonRow() {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(32))
        }

        // Activity Log button
        container.addView(
            Button(this).apply {
                text = "Activity Log"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTextColor(COLOR_ACCENT)
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                isAllCaps = false
                stateListAnimator = null
                elevation = 0f
                background = GradientDrawable().apply {
                    setColor(COLOR_BACKGROUND)
                    cornerRadius = dp(12).toFloat()
                }
                setPadding(dp(32), dp(14), dp(32), dp(14))
                setOnClickListener {
                    startActivity(Intent(this@MainActivity, LogActivity::class.java))
                }
            },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply {
                    bottomMargin = dp(12)
                })

        // Done + Quit row
        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        buttonRow.addView(
            buildOutlineButton("Done", COLOR_ACCENT) { finish() },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(8) })

        buttonRow.addView(buildOutlineButton("Quit", COLOR_RED) {
            stopService(Intent(this@MainActivity, BuzzelService::class.java))
            finishAffinity()
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(8) })

        container.addView(buttonRow, matchWrap())
        rootLayout.addView(container, matchWrap())
    }

    private fun buildOutlineButton(label: String, color: Int, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(color)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            isAllCaps = false
            stateListAnimator = null
            elevation = 0f
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                cornerRadius = dp(12).toFloat()
                setStroke(dp(1), color)
            }
            setPadding(dp(32), dp(14), dp(32), dp(14))
            setOnClickListener { onClick() }
        }
    }

    // --- Helpers ---

    private fun hasAllPermissions(): Boolean =
        REQUIRED_PERMISSIONS.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }

    private fun startService() {
        ContextCompat.startForegroundService(this, Intent(this, BuzzelService::class.java))
    }

    private fun generatePairingCode(): String = (100000..999999).random().toString()

    private fun addSpacer(height: Int) {
        rootLayout.addView(View(this), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height))
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
    )

    private fun wrapWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
    )
}
