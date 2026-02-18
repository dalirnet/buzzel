package com.buzzel.ui

import android.Manifest
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.buzzel.BuzzelApp
import com.buzzel.protocol.Protocol
import com.buzzel.service.BuzzelService

class MainActivity : Activity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val PERMISSION_REQUEST = 1001
        private const val SCAN_QR_REQUEST = 1002

        // undo-left icon paths
        private val ICON_BACK =
            arrayOf(
                arrayOf(
                    "M4 7h11c1.87 0 2.804 0 3.5.402A3 3 0 0 1 19.598 8.5C20 9.196 20 10.13 20 12s0 2.804-.402 3.5a3 3 0 0 1-1.098 1.098C17.804 17 16.87 17 15 17H8M4 7l3-3M4 7l3 3",
                ),
            )

        // qr-code icon paths: first 3 groups = stroke, rest = fill
        private val ICON_QR =
            arrayOf(
                arrayOf(
                    "M2 16.9c0-1.31 0-1.964.295-2.445a2 2 0 0 1 .66-.66c.48-.295 1.136-.295 2.445-.295h1.1c1.886 0 2.828 0 3.414.586s.586 1.528.586 3.414v1.1c0 1.31 0 1.964-.295 2.445a2 2 0 0 1-.66.66C9.065 22 8.409 22 7.1 22c-1.964 0-2.946 0-3.667-.442a3 3 0 0 1-.99-.99C2 19.845 2 18.864 2 16.9Z",
                ),
                arrayOf(
                    "M13.5 5.4c0-1.31 0-1.964.295-2.445a2 2 0 0 1 .66-.66C14.935 2 15.591 2 16.9 2c1.964 0 2.946 0 3.668.442a3 3 0 0 1 .99.99C22 4.155 22 5.137 22 7.1c0 1.31 0 1.964-.295 2.445a2 2 0 0 1-.66.66c-.48.295-1.136.295-2.445.295h-1.1c-1.886 0-2.828 0-3.414-.586S13.5 8.386 13.5 6.5z",
                ),
                arrayOf(
                    "M2 7.1c0-1.964 0-2.946.442-3.667a3 3 0 0 1 .99-.99C4.155 2 5.137 2 7.1 2c1.31 0 1.964 0 2.445.295a2 2 0 0 1 .66.66c.295.48.295 1.136.295 2.445v1.1c0 1.886 0 2.828-.586 3.414S8.386 10.5 6.5 10.5H5.4c-1.31 0-1.964 0-2.445-.295a2 2 0 0 1-.66-.66C2 9.065 2 8.409 2 7.1Z",
                ),
                arrayOf(
                    "M16.5 6.25c0-.515 0-.773.13-.955a.7.7 0 0 1 .165-.166C16.977 5 17.235 5 17.75 5s.773 0 .955.13a.7.7 0 0 1 .166.165c.129.182.129.44.129.955s0 .773-.13.955a.7.7 0 0 1-.165.166c-.182.129-.44.129-.955.129s-.773 0-.955-.13a.7.7 0 0 1-.166-.165c-.129-.182-.129-.44-.129-.955",
                ),
                arrayOf(
                    "M5 6.25c0-.515 0-.773.13-.955a.7.7 0 0 1 .165-.166C5.477 5 5.735 5 6.25 5s.773 0 .955.13a.7.7 0 0 1 .166.165c.129.182.129.44.129.955s0 .773-.13.955a.7.7 0 0 1-.165.166c-.182.129-.44.129-.955.129s-.773 0-.955-.13a.7.7 0 0 1-.166-.165C5 7.023 5 6.765 5 6.25",
                ),
                arrayOf(
                    "M5 17.75c0-.515 0-.773.13-.955a.7.7 0 0 1 .165-.166c.182-.129.44-.129.955-.129s.773 0 .955.13a.7.7 0 0 1 .166.165c.129.182.129.44.129.955s0 .773-.13.955a.7.7 0 0 1-.165.166C7.023 19 6.765 19 6.25 19s-.773 0-.955-.13a.7.7 0 0 1-.166-.165C5 18.523 5 18.265 5 17.75",
                ),
                arrayOf(
                    "M16 17.75c0-.702 0-1.053.169-1.306a1 1 0 0 1 .275-.275C16.697 16 17.048 16 17.75 16s1.053 0 1.306.169a1 1 0 0 1 .275.275c.169.253.169.604.169 1.306s0 1.053-.169 1.306a1 1 0 0 1-.275.275c-.253.169-.604.169-1.306.169s-1.053 0-1.306-.169a1 1 0 0 1-.275-.275C16 18.803 16 18.452 16 17.75",
                ),
                arrayOf("M12.75 22a.75.75 0 0 0 1.5 0z"),
                arrayOf("M14.389 13.837l.417.624z"),
                arrayOf("M13.837 14.389l-.623-.417z"),
                arrayOf(
                    "M17 12.75c-.687 0-1.258 0-1.719.046c-.474.048-.913.153-1.309.418l.834 1.247c.108-.073.272-.137.627-.173c.367-.037.85-.038 1.567-.038z",
                ),
                arrayOf(
                    "M14.25 17c0-.718 0-1.2.038-1.567c.036-.355.1-.519.173-.627l-1.248-.834c-.264.396-.369.835-.417 1.309c-.047.461-.046 1.032-.046 1.719z",
                ),
                arrayOf("M13.972 14.028c-.3.2-.558.458-.758.758l1.247.834a1.3 1.3 0 0 1 .345-.345z"),
                arrayOf("M22.75 13.5a.75.75 0 0 0-1.5 0z"),
                arrayOf("M21.052 21.848l.287.693z"),
                arrayOf("M22.135 20.765l-.693-.287z"),
                arrayOf(
                    "M19 22.75c.456 0 .835 0 1.145-.02c.317-.022.617-.069.907-.19l-.574-1.385c-.077.032-.194.061-.435.078c-.247.017-.567.017-1.043.017z",
                ),
                arrayOf(
                    "M21.25 19c0 .476 0 .796-.017 1.043c-.017.241-.046.358-.078.435l1.386.574c.12-.29.167-.59.188-.907c.021-.31.021-.69.021-1.145z",
                ),
                arrayOf("M21.052 21.54a2.75 2.75 0 0 0 1.489-1.488l-1.386-.574a1.25 1.25 0 0 1-.677.677z"),
            )

        private val REQUIRED_PERMISSIONS: Array<String>
            get() =
                buildList {
                    add(Manifest.permission.CAMERA)
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
    }

    private val app: BuzzelApp get() = application as BuzzelApp
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var rootLayout: LinearLayout
    private lateinit var headerView: AppHeaderView
    private lateinit var powerButton: PowerButtonView
    private lateinit var statusLine: TextView
    private lateinit var orbitRings: OrbitRingsView
    private lateinit var activityLogContainer: LinearLayout
    private lateinit var mainPanel: LinearLayout

    private var showActivityLog = false
    private var currentStatusText = ""
    private var lastDarkMode = false
    private var stateListener: ((BuzzelService.ConnectionState) -> Unit)? = null
    private var logListener: ((com.buzzel.model.LogEntry) -> Unit)? = null

    private fun dp(value: Int) = dp(this as Context, value)

    // --- Lifecycle ---

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "Activity created")
        Brand.load(this)
        AppColors.resolve(this)
        lastDarkMode = AppColors.isDarkMode(this)

        // System bars
        @Suppress("DEPRECATION")
        window.statusBarColor = AppColors.surface
        @Suppress("DEPRECATION")
        window.navigationBarColor = AppColors.surface
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            if (AppColors.isDarkMode(this)) {
                0
            } else {
                View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            }

        buildLayout()
        setContentView(rootLayout)

        refreshState()
        observeState()
    }

    override fun onResume() {
        super.onResume()
        if (AppColors.isDarkMode(this) != lastDarkMode) {
            recreate()
            return
        }
        refreshState()
    }

    override fun onDestroy() {
        stateListener?.let { app.removeServiceConnectionStateListener(it) }
        logListener?.let { app.removeLogEntryListener(it) }
        stateListener = null
        logListener = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) refreshState()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCAN_QR_REQUEST && resultCode == RESULT_OK) {
            val qrBytes = data?.getByteArrayExtra(ScanActivity.RESULT_QR_BYTES) ?: return
            handleQrResult(qrBytes)
        }
    }

    @Deprecated("Use onBackPressedDispatcher")
    override fun onBackPressed() {
        if (showActivityLog) {
            showMainView()
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    // --- QR ---

    private fun handleQrResult(raw: ByteArray) {
        val qr = Protocol.parseQr(raw) ?: return
        val store = app.configStore
        store.sessionId = Protocol.deriveSessionId(qr.seed)
        store.pairingCode = Protocol.derivePairingCode(qr.seed)
        store.macHost = qr.host
        store.preferTransport = qr.prefer
        app.hasBeenConnected = false
        startService()
        refreshState()
    }

    // --- Layout ---

    private fun buildLayout() {
        rootLayout =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(AppColors.surface)
            }

        // Header
        headerView =
            AppHeaderView(this).apply {
                onTrailingIconClick = { onTrailingIconTap() }
            }
        rootLayout.addView(
            headerView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(60),
            ),
        )

        // Main panel (contains orbit + status line)
        mainPanel = buildMainPanel()
        rootLayout.addView(
            mainPanel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        // Activity log container (hidden by default)
        activityLogContainer =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                visibility = View.GONE
            }
        rootLayout.addView(
            activityLogContainer,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
    }

    private fun buildMainPanel(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            clipChildren = false
            clipToPadding = false

            // Top spacer
            addView(
                View(context),
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                ),
            )

            // Orbit rings with power button inside
            orbitRings = OrbitRingsView(context)
            powerButton = PowerButtonView(context)
            val btnSize = dp(112) // 90pt * 1.25 scale
            val contentFrame =
                FrameLayout(context).apply {
                    clipChildren = false
                    clipToPadding = false
                }
            contentFrame.addView(powerButton, FrameLayout.LayoutParams(btnSize, btnSize, Gravity.CENTER))
            orbitRings.clipChildren = false
            orbitRings.clipToPadding = false
            orbitRings.addView(
                contentFrame,
                FrameLayout.LayoutParams(
                    dp(150),
                    dp(150),
                    Gravity.CENTER, // 120pt * 1.25
                ),
            )
            addView(
                orbitRings,
                LinearLayout.LayoutParams(dp(350), dp(350)).apply {
                    // 280pt * 1.25
                    gravity = Gravity.CENTER_HORIZONTAL
                },
            )

            // Bottom spacer
            addView(
                View(context),
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                ),
            )

            // Status line
            statusLine =
                TextView(context).apply {
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    setTextColor(AppColors.secondary)
                    gravity = Gravity.CENTER
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(dp(20), dp(10), dp(20), dp(10))
                    background =
                        GradientDrawable().apply {
                            setColor(AppColors.withAlpha(AppColors.secondary, 13)) // 5%
                            cornerRadius = dp(100).toFloat()
                        }
                    isClickable = true
                    setOnClickListener { onStatusLineTap() }
                }
            addView(
                statusLine,
                LinearLayout
                    .LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        gravity = Gravity.CENTER_HORIZONTAL
                        bottomMargin = dp(30)
                    },
            )
        }

    // --- State ---

    private fun observeState() {
        val sl = { _: BuzzelService.ConnectionState -> runOnUiThread { refreshState() } }
        stateListener = sl
        app.addServiceConnectionStateListener(sl)

        val ll = { _: com.buzzel.model.LogEntry -> runOnUiThread { refreshStatusLine() } }
        logListener = ll
        app.addLogEntryListener(ll)
    }

    private fun refreshState() {
        val state = computeState()
        powerButton.state = state
        powerButton.onTap = { onPowerButtonTap(state) }

        // Header
        val title = if (showActivityLog) "Activity Log" else "Buzzel"
        headerView.setTitle(title)

        // Badge
        val connected = state == PowerButtonState.CONNECTED
        val badgeText = if (!showActivityLog && connected) app.connectedDeviceName else null
        headerView.setBadge(badgeText)

        // Trailing icon
        val isSubView = showActivityLog
        if (isSubView) {
            headerView.setTrailingIcon(ICON_BACK, SVGIconView.IconMode.STROKE, AppColors.text)
            headerView.setTrailingIconEnabled(true)
        } else {
            headerView.setTrailingIcon(ICON_QR, SVGIconView.IconMode.MIXED, AppColors.accent)
            val disabled = connected || state == PowerButtonState.NO_PERMISSION
            headerView.setTrailingIconEnabled(!disabled)
        }

        refreshStatusLine()

        if (app.configStore.sessionId != null && state != PowerButtonState.NO_PERMISSION) {
            startService()
        }
    }

    private fun computeState(): PowerButtonState {
        if (!hasAllPermissions()) return PowerButtonState.NO_PERMISSION
        return PowerButtonState.current(app)
    }

    private fun refreshStatusLine() {
        val state = computeState()
        val newText =
            when (state) {
                PowerButtonState.NO_PERMISSION -> {
                    firstMissingPermissionText()
                }

                PowerButtonState.UNPAIRED -> {
                    "No device paired yet"
                }

                PowerButtonState.CONNECTING -> {
                    "Looking for your device"
                }

                PowerButtonState.CONNECTED -> {
                    val entries = app.getLogEntrySnapshot()
                    if (entries.isNotEmpty()) {
                        val last = entries.last()
                        "${last.message} \u00B7 ${last.timeString}"
                    } else {
                        "Connected and ready"
                    }
                }

                PowerButtonState.DISCONNECTED -> {
                    val entries = app.getLogEntrySnapshot()
                    if (entries.isNotEmpty()) {
                        val last = entries.last()
                        "${last.message} \u00B7 ${last.timeString}"
                    } else {
                        "Tap to reconnect"
                    }
                }
            }
        setStatusText(newText)
    }

    private fun firstMissingPermissionText(): String {
        val missing =
            REQUIRED_PERMISSIONS.firstOrNull {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            } ?: return "Grant permissions"
        val label = permLabel(missing)
        return "Tap to grant $label access"
    }

    private fun permLabel(perm: String): String =
        when {
            perm == Manifest.permission.CAMERA -> "Camera"
            perm.contains("BLUETOOTH") -> "Bluetooth"
            perm.contains("LOCATION") -> "Location"
            perm.contains("NOTIFICATION") -> "Notification"
            else -> "Permission"
        }

    // Status line flip animation (3D rotation on X-axis)
    private fun setStatusText(newText: String) {
        if (newText == currentStatusText) return
        if (currentStatusText.isEmpty()) {
            currentStatusText = newText
            statusLine.text = newText
            return
        }
        currentStatusText = newText

        // Flip out
        val flipOut =
            ValueAnimator.ofFloat(0f, 90f).apply {
                duration = 250
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { statusLine.rotationX = it.animatedValue as Float }
            }
        flipOut.start()

        handler.postDelayed({
            statusLine.text = newText
            statusLine.rotationX = -90f
            // Flip in with spring-like feel
            val flipIn =
                ValueAnimator.ofFloat(-90f, 0f).apply {
                    duration = 350
                    interpolator = android.view.animation.OvershootInterpolator(1.2f)
                    addUpdateListener { statusLine.rotationX = it.animatedValue as Float }
                }
            flipIn.start()
        }, 250)
    }

    // --- Navigation ---

    private fun onTrailingIconTap() {
        if (showActivityLog) {
            showMainView()
        } else {
            openScanner()
        }
    }

    private fun showActivityLogView() {
        showActivityLog = true
        mainPanel.visibility = View.GONE
        activityLogContainer.visibility = View.VISIBLE
        activityLogContainer.removeAllViews()

        val logView = buildActivityLogView()
        activityLogContainer.addView(
            logView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        refreshState()
    }

    private fun showMainView() {
        showActivityLog = false
        mainPanel.visibility = View.VISIBLE
        activityLogContainer.visibility = View.GONE
        activityLogContainer.removeAllViews()
        refreshState()
    }

    private fun buildActivityLogView(): View {
        val ctx = this
        val container =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
            }

        val scroll = android.widget.ScrollView(ctx)
        val entries =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
            }

        val snapshot = app.getLogEntrySnapshot().reversed()
        if (snapshot.isEmpty()) {
            entries.addView(
                TextView(ctx).apply {
                    text = "No activity yet"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    setTextColor(AppColors.secondary)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(40), 0, 0)
                },
                matchWrap(),
            )
        } else {
            for ((i, entry) in snapshot.withIndex()) {
                entries.addView(buildLogEntryRow(entry))
                if (i < snapshot.size - 1) {
                    val divider = View(ctx).apply { setBackgroundColor(AppColors.border) }
                    entries.addView(
                        divider,
                        LinearLayout
                            .LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                1,
                            ).apply { marginStart = dp(35) },
                    ) // layout 1.25x
                }
            }
        }

        scroll.addView(entries, matchWrap())
        container.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        // Listen for new entries
        val listener: (com.buzzel.model.LogEntry) -> Unit = { entry ->
            runOnUiThread {
                if (entries.childCount == 1 && entries.getChildAt(0) is TextView) {
                    entries.removeAllViews()
                }
                if (entries.childCount > 0) {
                    val divider = View(ctx).apply { setBackgroundColor(AppColors.border) }
                    entries.addView(
                        divider,
                        0,
                        LinearLayout
                            .LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                1,
                            ).apply { marginStart = dp(35) },
                    ) // layout 1.25x
                }
                entries.addView(buildLogEntryRow(entry), 0)
            }
        }
        app.addLogEntryListener(listener)

        return container
    }

    private fun buildLogEntryRow(entry: com.buzzel.model.LogEntry): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(20), dp(10), dp(20), dp(10)) // layout 1.25x: 16×8 → 20×10
            gravity = Gravity.TOP

            // Status dot (detail 1.0x: stays 8dp)
            val dot =
                View(context).apply {
                    val dotColor =
                        if (entry.status == com.buzzel.model.LogStatus.SUCCESS) AppColors.green else AppColors.red
                    background =
                        GradientDrawable().apply {
                            shape = GradientDrawable.OVAL
                            setColor(dotColor)
                        }
                }
            addView(
                dot,
                LinearLayout.LayoutParams(dp(8), dp(8)).apply {
                    topMargin = dp(6)
                    marginEnd = dp(10) // layout 1.25x: 8 → 10
                },
            )

            // Center
            val center = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            center.addView(
                TextView(context).apply {
                    text = entry.message
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f) // typo 1.15x: 13 → 15
                    setTextColor(AppColors.text)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                },
                matchWrap(),
            )
            if (entry.error != null) {
                center.addView(
                    TextView(context).apply {
                        text = entry.error
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f) // typo 1.15x: 11 → 13
                        setTextColor(AppColors.red)
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.END
                    },
                    matchWrap().apply { topMargin = dp(2) },
                )
            }
            addView(center, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            // Right
            val right =
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.END
                }
            right.addView(
                TextView(context).apply {
                    text = entry.timeString
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f) // typo 1.15x: 11 → 13
                    setTextColor(AppColors.secondary)
                },
                wrapWrap(),
            )
            if (entry.direction != com.buzzel.model.LogDirection.LOCAL) {
                right.addView(
                    TextView(context).apply {
                        text = if (entry.direction == com.buzzel.model.LogDirection.INCOMING) "IN" else "OUT"
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f) // typo 1.15x: 9 → 10
                        setTextColor(AppColors.secondary)
                        typeface =
                            android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                    },
                    wrapWrap().apply { topMargin = dp(2) },
                )
            }
            addView(
                right,
                LinearLayout
                    .LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { marginStart = dp(10) },
            ) // layout 1.25x: 8 → 10
        }

    // --- Actions ---

    private fun onPowerButtonTap(state: PowerButtonState) {
        when (state) {
            PowerButtonState.NO_PERMISSION -> {
                ActivityCompat.requestPermissions(this, REQUIRED_PERMISSIONS, PERMISSION_REQUEST)
            }

            PowerButtonState.UNPAIRED -> { // no-op
            }

            PowerButtonState.CONNECTING -> { // no-op
            }

            PowerButtonState.CONNECTED -> {
                stopService(Intent(this, BuzzelService::class.java))
            }

            PowerButtonState.DISCONNECTED -> {
                startService()
            }
        }
    }

    private fun onStatusLineTap() {
        val state = computeState()
        if (state == PowerButtonState.CONNECTED) {
            showActivityLogView()
        }
    }

    private fun openScanner() {
        @Suppress("DEPRECATION")
        startActivityForResult(Intent(this, ScanActivity::class.java), SCAN_QR_REQUEST)
    }

    // --- Helpers ---

    private fun hasAllPermissions(): Boolean =
        REQUIRED_PERMISSIONS.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }

    private fun startService() {
        ContextCompat.startForegroundService(this, Intent(this, BuzzelService::class.java))
    }
}
