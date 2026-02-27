package com.buzzel.ui

import android.Manifest
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Outline
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.MeteringRectangle
import android.media.ImageReader
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.buzzel.BuzzelApp
import com.buzzel.debug.FileLogger
import com.buzzel.model.LogDirection
import com.buzzel.model.LogEntry
import com.buzzel.model.LogStatus
import com.buzzel.protocol.Protocol
import com.buzzel.service.BuzzelService
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

class MainActivity : Activity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val PERMISSION_REQUEST = 1001

        private val ICON_ARROW_DOWN = arrayOf(arrayOf("M12 5v14M5 12l7 7 7-7"))
        private val ICON_ARROW_UP = arrayOf(arrayOf("M12 19V5M5 12l7-7 7 7"))
        private val ICON_DOT = arrayOf(arrayOf("M12 12m-4 0a4 4 0 1 0 8 0a4 4 0 1 0-8 0"))

        private val ICON_ZAP = arrayOf(arrayOf(PowerButtonView.ZAP_PATH))

        private val ICON_SETTINGS =
            arrayOf(
                arrayOf(
                    "M10.026,2.25 L13.974,2.25 C14.744,2.25 15.376,2.25 15.896,2.301 C16.441,2.355 16.921,2.468 17.376,2.73 C17.831,2.991 18.17,3.349 18.49,3.793 C18.795,4.217 19.111,4.763 19.497,5.428 L21.458,8.808 C21.845,9.475 22.163,10.024 22.38,10.5 C22.608,11 22.75,11.474 22.75,12 C22.75,12.526 22.608,13 22.38,13.5 C22.163,13.976 21.845,14.525 21.458,15.192 L21.458,15.192 L19.497,18.572 L19.497,18.572 C19.111,19.237 18.795,19.783 18.49,20.207 C18.17,20.651 17.831,21.009 17.376,21.27 C16.921,21.532 16.441,21.645 15.896,21.699 C15.376,21.75 14.744,21.75 13.974,21.75 L10.026,21.75 C9.256,21.75 8.624,21.75 8.104,21.699 C7.559,21.645 7.079,21.532 6.624,21.27 C6.169,21.009 5.83,20.651 5.51,20.207 C5.205,19.783 4.889,19.237 4.503,18.572 L2.542,15.192 C2.155,14.525 1.837,13.977 1.62,13.5 C1.392,13 1.25,12.526 1.25,12 C1.25,11.474 1.392,11 1.62,10.5 C1.837,10.024 2.155,9.475 2.542,8.808 L4.503,5.428 C4.889,4.763 5.205,4.217 5.51,3.793 C5.83,3.349 6.169,2.991 6.624,2.73 C7.079,2.468 7.559,2.355 8.104,2.301 C8.624,2.25 9.256,2.25 10.026,2.25 L10.026,2.25 Z M7.372,4.03 C7.166,4.148 6.975,4.326 6.728,4.67 C6.471,5.026 6.191,5.508 5.782,6.213 L3.858,9.528 C3.448,10.236 3.168,10.72 2.985,11.122 C2.809,11.508 2.75,11.763 2.75,12 C2.75,12.237 2.809,12.492 2.985,12.878 C3.168,13.28 3.448,13.764 3.858,14.472 L5.782,17.787 C6.191,18.492 6.471,18.974 6.728,19.33 C6.975,19.674 7.166,19.852 7.372,19.97 C7.578,20.088 7.828,20.165 8.25,20.206 C8.688,20.249 9.247,20.25 10.063,20.25 L13.937,20.25 C14.753,20.25 15.311,20.249 15.75,20.206 C16.172,20.165 16.422,20.088 16.628,19.97 C16.834,19.852 17.025,19.674 17.272,19.33 C17.529,18.974 17.809,18.492 18.218,17.787 L20.142,14.472 C20.552,13.764 20.832,13.28 21.015,12.878 C21.191,12.492 21.25,12.237 21.25,12 C21.25,11.763 21.191,11.508 21.015,11.122 C20.832,10.72 20.552,10.236 20.142,9.528 L18.218,6.213 C17.809,5.508 17.529,5.026 17.272,4.67 C17.025,4.326 16.834,4.148 16.628,4.03 C16.422,3.912 16.172,3.835 15.75,3.794 C15.311,3.751 14.753,3.75 13.937,3.75 L10.063,3.75 C9.247,3.75 8.688,3.751 8.25,3.794 C7.828,3.835 7.578,3.912 7.372,4.03 Z M12,7.75 C14.347,7.75 16.25,9.653 16.25,12 C16.25,14.347 14.347,16.25 12,16.25 C9.653,16.25 7.75,14.347 7.75,12 C7.75,9.653 9.653,7.75 12,7.75 Z M9.25,12 C9.25,13.519 10.481,14.75 12,14.75 C13.519,14.75 14.75,13.519 14.75,12 C14.75,10.481 13.519,9.25 12,9.25 C10.481,9.25 9.25,10.481 9.25,12 Z",
                ),
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
    private lateinit var settingsContainer: LinearLayout
    private lateinit var mainPanel: LinearLayout

    private var showActivityLog = false
    private var showSettings = false
    private var scanMode = false
    private var currentStatusText = ""
    private var lastDarkMode = false
    private var permissionsEverRequested = false
    private var stateListener: ((BuzzelService.ConnectionState) -> Unit)? = null
    private var logListener: ((LogEntry) -> Unit)? = null
    private var remoteInFocusListener: ((Boolean) -> Unit)? = null

    // Camera / QR scanning
    private lateinit var cameraTextureView: TextureView
    private lateinit var cameraFrame: FrameLayout
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var previewRequest: CaptureRequest.Builder? = null
    private var sensorArraySize: Rect? = null
    private var imageReader: ImageReader? = null
    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null
    private var scannerInitialized = false
    private val scanner by lazy {
        scannerInitialized = true
        BarcodeScanning.getClient()
    }

    @Volatile private var scanning = false

    @Volatile private var processingFrame = false

    private fun dp(value: Int) = dp(this as Context, value)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FileLogger.d(TAG, "Activity created")
        Brand.load(this)
        AppColors.resolve(this)
        lastDarkMode = AppColors.isDarkMode(this)

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

        permissionsEverRequested =
            REQUIRED_PERMISSIONS.any {
                ActivityCompat.shouldShowRequestPermissionRationale(this, it)
            }

        buildLayout()
        setContentView(rootLayout)

        refreshState()
        observeState()
    }

    override fun onStart() {
        super.onStart()
        FileLogger.d(TAG, "App foreground (onStart)")
        app.isAppInForeground = true
    }

    override fun onStop() {
        super.onStop()
        FileLogger.d(TAG, "App background (onStop)")
        app.isAppInForeground = false
    }

    override fun onResume() {
        super.onResume()
        if (AppColors.isDarkMode(this) != lastDarkMode) {
            recreate()
            return
        }
        refreshState()
        if (hasAllPermissions()) {
            requestNotificationPermission()
        }
    }

    override fun onDestroy() {
        stateListener?.let { app.removeServiceConnectionStateListener(it) }
        logListener?.let { app.removeLogEntryListener(it) }
        remoteInFocusListener?.let { app.removeRemoteInFocusListener(it) }
        stateListener = null
        logListener = null
        remoteInFocusListener = null
        stopCamera()
        if (scannerInitialized) scanner.close()
        if (!app.isDeviceConnected) {
            stopService(Intent(this, BuzzelService::class.java))
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            val granted = permissions.zip(grantResults.toTypedArray())
            FileLogger.i(
                TAG,
                "onPermissionResult: ${granted.joinToString {
                    "${it.first.substringAfterLast(
                        '.',
                    )}=${if (it.second == PackageManager.PERMISSION_GRANTED) "OK" else "DENIED"}"
                }}",
            )
            if (hasAllPermissions()) {
                FileLogger.i(TAG, "All permissions granted — proceeding")
                requestNotificationPermission()
                if (app.configStore.pairingCode != null) {
                    startService()
                }
            } else {
                val still = missingPermissions()
                FileLogger.i(TAG, "Still missing: ${still.map { it.substringAfterLast('.') }}")
                val permanentlyDenied =
                    still.filter {
                        !ActivityCompat.shouldShowRequestPermissionRationale(this, it)
                    }
                if (permanentlyDenied.size == still.size) {
                    FileLogger.i(TAG, "All remaining permanently denied — opening settings")
                    openAppSettings()
                } else {
                    FileLogger.i(TAG, "Some can still be requested — will prompt on next tap")
                }
            }
            refreshState()
        }
    }

    @Deprecated("Use onBackPressedDispatcher")
    override fun onBackPressed() {
        if (scanMode) {
            exitScanMode()
            return
        }
        if (showActivityLog || showSettings) {
            showMainView()
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    private fun handleQRCodeResult(raw: ByteArray) {
        val qrPayload = Protocol.parseQRCodePayload(raw) ?: return
        val store = app.configStore
        store.sessionId = null
        store.pairingCode = Protocol.derivePairingCode(qrPayload.seed)
        store.pendingSessionId = Protocol.deriveSessionIdentifier(qrPayload.seed)
        store.macHost = qrPayload.host
        app.hasBeenConnected = false
        startService()
        refreshState()
    }

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

        // Settings container (hidden by default)
        settingsContainer =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                visibility = View.GONE
            }
        rootLayout.addView(
            settingsContainer,
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
            val btnSize = dp(112)
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
                FrameLayout.LayoutParams(dp(150), dp(150), Gravity.CENTER),
            )

            // Camera preview overlay — circular FrameLayout on top of orbit rings, same size
            cameraTextureView = TextureView(context)
            cameraFrame =
                FrameLayout(context).apply {
                    visibility = View.GONE
                    outlineProvider =
                        object : ViewOutlineProvider() {
                            override fun getOutline(
                                view: View,
                                outline: Outline,
                            ) {
                                outline.setOval(0, 0, view.width, view.height)
                            }
                        }
                    clipToOutline = true
                }
            cameraFrame.addView(
                cameraTextureView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            cameraFrame.setOnTouchListener { v, event ->
                if (event.action == MotionEvent.ACTION_UP) {
                    triggerFocus(event.x / v.width.toFloat(), event.y / v.height.toFloat())
                }
                true
            }

            val orbitFrame =
                FrameLayout(context).apply {
                    clipChildren = false
                    clipToPadding = false
                }
            orbitFrame.addView(
                orbitRings,
                FrameLayout.LayoutParams(dp(350), dp(350), Gravity.CENTER),
            )
            orbitFrame.addView(
                cameraFrame,
                FrameLayout.LayoutParams(dp(350), dp(350), Gravity.CENTER),
            )
            addView(
                orbitFrame,
                LinearLayout.LayoutParams(dp(350), dp(350)).apply {
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
                    typeface = Brand.typeface
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

    private fun observeState() {
        val stateCallback = { _: BuzzelService.ConnectionState -> runOnUiThread { refreshState() } }
        stateListener = stateCallback
        app.addServiceConnectionStateListener(stateCallback)

        val logCallback = { _: LogEntry -> runOnUiThread { refreshStatusLine() } }
        logListener = logCallback
        app.addLogEntryListener(logCallback)

        val focusCallback = { _: Boolean -> runOnUiThread { refreshState() } }
        remoteInFocusListener = focusCallback
        app.addRemoteInFocusListener(focusCallback)
    }

    private fun refreshState() {
        val state = computeState()
        powerButton.ready = state == PowerButtonState.DISCONNECTED && !app.hasBeenConnected
        powerButton.state = state
        powerButton.onTap = { onPowerButtonTap(state) }
        powerButton.onUnpairWarning = { onPowerButtonHoldWarning(state) }
        powerButton.onUnpair = { onPowerButtonUnpair(state) }
        powerButton.onHoldCancel = { refreshStatusLine() }

        val title =
            when {
                showActivityLog -> "Activity Log"
                showSettings -> "Settings"
                scanMode -> "Quick Setup"
                else -> "Buzzel"
            }
        headerView.setTitle(title)

        val trailingIcon = if (showActivityLog || showSettings || scanMode) ICON_ZAP else ICON_SETTINGS
        headerView.setTrailingIcon(trailingIcon, SVGIconView.IconMode.FILL, AppColors.text)
        headerView.setTrailingIconEnabled(true)

        val isPaired = app.configStore.pairingCode != null
        orbitRings.deviceName = if (isPaired) app.connectedDeviceName ?: "Mac" else null
        orbitRings.isDeviceConnected = state == PowerButtonState.CONNECTED
        orbitRings.isRemoteFocused = app.isRemoteInFocus

        refreshStatusLine()
    }

    private fun computeState(): PowerButtonState {
        if (!hasAllPermissions()) {
            FileLogger.d(
                TAG,
                "computeState: RESTRICTED — missing: ${missingPermissions().map { it.substringAfterLast('.') }}",
            )
            return PowerButtonState.RESTRICTED
        }
        val state = PowerButtonState.current(app)
        FileLogger.d(TAG, "computeState: $state")
        return state
    }

    private fun refreshStatusLine() {
        if (scanMode) {
            setStatusText("Point camera at QR code")
            return
        }
        val state = computeState()
        val newText =
            when (state) {
                PowerButtonState.RESTRICTED -> {
                    firstMissingPermissionText()
                }

                PowerButtonState.UNPAIRED -> {
                    "No device paired"
                }

                PowerButtonState.CONNECTING -> {
                    val transport = app.connectingTransport
                    if (transport.isNullOrEmpty()) "Searching for device" else "Searching via $transport"
                }

                PowerButtonState.CONNECTED -> {
                    val transport = app.connectedTransport
                    if (transport.isNullOrEmpty()) "Connected" else "Connected via $transport"
                }

                PowerButtonState.DISCONNECTED -> {
                    if (app.hasBeenConnected) "Connection lost" else "Ready to connect"
                }
            }
        setStatusText(newText)
    }

    private fun firstMissingPermissionText(): String {
        val missing =
            REQUIRED_PERMISSIONS.firstOrNull {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            } ?: return "Required permissions are missing"
        val label = permissionLabel(missing)
        return "$label access is required"
    }

    private fun permissionLabel(permission: String): String =
        when {
            permission == Manifest.permission.CAMERA -> "Camera"
            permission.contains("BLUETOOTH") -> "Bluetooth"
            permission.contains("LOCATION") -> "Location"
            permission.contains("NOTIFICATION") -> "Notification"
            else -> "Permission"
        }

    private fun setStatusText(newText: String) {
        if (newText == currentStatusText) return
        if (currentStatusText.isEmpty()) {
            currentStatusText = newText
            statusLine.text = newText
            return
        }
        currentStatusText = newText

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
            val flipIn =
                ValueAnimator.ofFloat(-90f, 0f).apply {
                    duration = 350
                    interpolator = OvershootInterpolator(1.2f)
                    addUpdateListener { statusLine.rotationX = it.animatedValue as Float }
                }
            flipIn.start()
        }, 250)
    }

    private fun onTrailingIconTap() {
        when {
            showActivityLog || showSettings -> showMainView()
            scanMode -> exitScanMode()
            else -> showSettingsView()
        }
    }

    private fun showSettingsView() {
        showSettings = true
        mainPanel.visibility = View.GONE
        settingsContainer.visibility = View.VISIBLE
        settingsContainer.removeAllViews()

        val view = buildSettingsView()
        settingsContainer.addView(
            view,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        refreshState()
    }

    private fun buildSettingsView(): View {
        val store = app.configStore
        val labels = arrayOf("Auto", "WiFi", "Bluetooth")
        val values = arrayOf("auto", "wifi", "ble")

        val container =
            LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(16), dp(20), dp(16), 0)
            }

        // Section label
        container.addView(
            TextView(this@MainActivity).apply {
                text = "Preferred Transport"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                typeface = Brand.typeface
                setTextColor(AppColors.secondary)
                setPadding(0, 0, 0, dp(10))
            },
            matchWrap(),
        )

        // Segmented control container
        val segmentContainer =
            LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                background =
                    GradientDrawable().apply {
                        setColor(AppColors.withAlpha(AppColors.secondary, 20))
                        cornerRadius = dp(10).toFloat()
                    }
                setPadding(dp(4), dp(4), dp(4), dp(4))
            }

        val current = store.preferredTransport ?: "auto"
        val segmentViews = mutableListOf<TextView>()

        for ((i, label) in labels.withIndex()) {
            val selected = values[i] == current
            val segmentView =
                TextView(this@MainActivity).apply {
                    text = label
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    typeface = Brand.typeface
                    gravity = Gravity.CENTER
                    setPadding(0, dp(10), 0, dp(10))
                    setTextColor(if (selected) AppColors.onButton else AppColors.secondary)
                    background =
                        if (selected) {
                            GradientDrawable().apply {
                                setColor(AppColors.accent)
                                cornerRadius = dp(7).toFloat()
                            }
                        } else {
                            null
                        }
                    isClickable = true
                }
            segmentViews.add(segmentView)
            segmentContainer.addView(
                segmentView,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
        }

        for ((i, segmentView) in segmentViews.withIndex()) {
            segmentView.setOnClickListener {
                store.preferredTransport = values[i]
                for ((j, other) in segmentViews.withIndex()) {
                    val selected = j == i
                    other.setTextColor(if (selected) AppColors.onButton else AppColors.secondary)
                    other.background =
                        if (selected) {
                            GradientDrawable().apply {
                                setColor(AppColors.accent)
                                cornerRadius = dp(7).toFloat()
                            }
                        } else {
                            null
                        }
                }
            }
        }

        container.addView(segmentContainer, matchWrap())

        return container
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
        showSettings = false
        mainPanel.visibility = View.VISIBLE
        activityLogContainer.visibility = View.GONE
        activityLogContainer.removeAllViews()
        settingsContainer.visibility = View.GONE
        settingsContainer.removeAllViews()
        refreshState()
    }

    private fun buildActivityLogView(): View {
        val container =
            LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
            }

        val scroll = ScrollView(this@MainActivity)
        val entries =
            LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
            }

        val snapshot = app.getLogEntrySnapshot()
        if (snapshot.isEmpty()) {
            val emptyState =
                LinearLayout(this@MainActivity).apply {
                    tag = "empty"
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                }
            emptyState.addView(
                WaveBLogoView(this@MainActivity, AppColors.withAlpha(AppColors.secondary, 77)).also {
                    it.layoutParams =
                        LinearLayout.LayoutParams(dp(32), dp(32)).apply {
                            gravity = Gravity.CENTER_HORIZONTAL
                        }
                },
            )
            emptyState.addView(
                TextView(this@MainActivity).apply {
                    text = "No activity yet"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    typeface = Brand.typeface
                    setTextColor(AppColors.secondary)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(12), 0, 0)
                },
                matchWrap(),
            )
            emptyState.addView(
                TextView(this@MainActivity).apply {
                    text = "Events will appear here"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    typeface = Brand.typeface
                    setTextColor(AppColors.withAlpha(AppColors.secondary, 153))
                    gravity = Gravity.CENTER
                    setPadding(0, dp(4), 0, 0)
                },
                matchWrap(),
            )
            container.addView(
                emptyState,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                ),
            )
            return container
        } else {
            for ((i, entry) in snapshot.withIndex()) {
                entries.addView(buildLogEntryRow(entry))
                if (i < snapshot.size - 1) {
                    val divider = View(this@MainActivity).apply { setBackgroundColor(AppColors.border) }
                    entries.addView(
                        divider,
                        LinearLayout
                            .LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                1,
                            ).apply { marginStart = dp(38) },
                    )
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

        // Auto-scroll to bottom on initial load
        scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }

        // Listen for new entries
        val listener: (LogEntry) -> Unit = { entry ->
            runOnUiThread {
                if (entries.childCount > 0) {
                    val divider = View(this@MainActivity).apply { setBackgroundColor(AppColors.border) }
                    entries.addView(
                        divider,
                        LinearLayout
                            .LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                1,
                            ).apply { marginStart = dp(38) },
                    )
                }
                entries.addView(buildLogEntryRow(entry))
                val isAtBottom = !scroll.canScrollVertically(1)
                if (isAtBottom) {
                    scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
                }
            }
        }
        app.addLogEntryListener(listener)

        return container
    }

    private fun buildLogEntryRow(entry: LogEntry): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(16), dp(8), dp(16), dp(8))
            gravity = Gravity.TOP

            // Direction icon
            val iconColor = if (entry.status == LogStatus.SUCCESS) AppColors.green else AppColors.red
            val iconPath =
                when (entry.direction) {
                    LogDirection.INCOMING -> ICON_ARROW_DOWN
                    LogDirection.OUTGOING -> ICON_ARROW_UP
                    LogDirection.LOCAL -> ICON_DOT
                }
            val iconMode =
                if (entry.direction ==
                    LogDirection.LOCAL
                ) {
                    SVGIconView.IconMode.FILL
                } else {
                    SVGIconView.IconMode.STROKE
                }
            addView(
                SVGIconView(context, iconPath, iconMode).apply {
                    this.iconColor = iconColor
                    strokeWidth = 2f
                },
                LinearLayout.LayoutParams(dp(14), dp(14)).apply {
                    topMargin = dp(3)
                    marginEnd = dp(8)
                },
            )

            // Center
            val center = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            center.addView(
                TextView(context).apply {
                    text = entry.message
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    typeface = Brand.typeface
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
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                        typeface = Brand.typeface
                        setTextColor(AppColors.red)
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.END
                    },
                    matchWrap().apply { topMargin = dp(2) },
                )
            }
            addView(center, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            // Time
            addView(
                TextView(context).apply {
                    text = entry.timeString
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    typeface = Brand.typeface
                    setTextColor(AppColors.secondary)
                    setPadding(dp(8), dp(2), 0, 0)
                },
                wrapWrap(),
            )
        }

    private fun onPowerButtonTap(state: PowerButtonState) {
        when (state) {
            PowerButtonState.RESTRICTED -> {
                val missing = missingPermissions()
                FileLogger.i(TAG, "RESTRICTED tap — missing: ${missing.map { it.substringAfterLast('.') }}")
                if (missing.isEmpty()) {
                    FileLogger.i(TAG, "All permissions already granted — refreshing")
                    refreshState()
                } else {
                    val permanentlyDenied =
                        missing.filter {
                            !ActivityCompat.shouldShowRequestPermissionRationale(this, it)
                        }
                    if (permissionsEverRequested && permanentlyDenied.size == missing.size) {
                        FileLogger.i(TAG, "All missing permissions permanently denied — opening settings")
                        openAppSettings()
                    } else {
                        FileLogger.i(TAG, "Requesting permissions: ${missing.map { it.substringAfterLast('.') }}")
                        permissionsEverRequested = true
                        ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST)
                    }
                }
            }

            PowerButtonState.UNPAIRED -> {
                enterScanMode()
            }

            PowerButtonState.CONNECTING, PowerButtonState.CONNECTED -> {
                startService(
                    Intent(this, BuzzelService::class.java).apply {
                        action = BuzzelService.ACTION_SOFT_DISCONNECT
                    },
                )
            }

            PowerButtonState.DISCONNECTED -> {
                startService()
            }
        }
    }

    private fun onPowerButtonHoldWarning(state: PowerButtonState) {
        if (state == PowerButtonState.CONNECTING || state == PowerButtonState.CONNECTED ||
            state == PowerButtonState.DISCONNECTED
        ) {
            setStatusText("Keep pressing to unpair")
        }
    }

    private fun onPowerButtonUnpair(state: PowerButtonState) {
        if (state == PowerButtonState.CONNECTING || state == PowerButtonState.CONNECTED ||
            state == PowerButtonState.DISCONNECTED
        ) {
            startService(
                Intent(this, BuzzelService::class.java).apply {
                    action = BuzzelService.ACTION_UNPAIR
                },
            )
            refreshState()
        }
    }

    private fun onStatusLineTap() {
        showActivityLogView()
    }

    private fun enterScanMode() {
        scanMode = true
        scanning = true
        processingFrame = false
        cameraFrame.visibility = View.VISIBLE
        refreshState()
        startCamera()
    }

    private fun exitScanMode() {
        scanMode = false
        scanning = false
        stopCamera()
        cameraFrame.visibility = View.GONE
        refreshState()
    }

    private fun startCamera() {
        bgThread = HandlerThread("CameraBackground").also { it.start() }
        bgHandler = Handler(bgThread!!.looper)

        cameraTextureView.surfaceTextureListener =
            object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(
                    surface: SurfaceTexture,
                    width: Int,
                    height: Int,
                ) {
                    openCamera()
                }

                override fun onSurfaceTextureSizeChanged(
                    surface: SurfaceTexture,
                    width: Int,
                    height: Int,
                ) {}

                override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true

                override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
            }
        if (cameraTextureView.isAvailable) openCamera()
    }

    private fun openCamera() {
        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        try {
            val cameraId =
                manager.cameraIdList.firstOrNull { id ->
                    manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) ==
                        CameraCharacteristics.LENS_FACING_BACK
                } ?: manager.cameraIdList.firstOrNull() ?: return

            val characteristics = manager.getCameraCharacteristics(cameraId)
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            sensorArraySize = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
            val previewSize =
                map
                    .getOutputSizes(SurfaceTexture::class.java)
                    ?.filter { it.width <= 1920 && it.height <= 1080 }
                    ?.maxByOrNull { it.width * it.height }
                    ?: Size(1280, 720)

            imageReader = ImageReader.newInstance(previewSize.width, previewSize.height, ImageFormat.YUV_420_888, 3)
            imageReader!!.setOnImageAvailableListener({ reader ->
                val image =
                    try {
                        reader.acquireLatestImage()
                    } catch (_: Exception) {
                        null
                    }
                        ?: return@setOnImageAvailableListener
                if (!scanning || processingFrame) {
                    image.close()
                    return@setOnImageAvailableListener
                }
                processingFrame = true
                try {
                    val inputImage = InputImage.fromMediaImage(image, sensorOrientation)
                    scanner
                        .process(inputImage)
                        .addOnSuccessListener { handleBarcodes(it) }
                        .addOnCompleteListener {
                            image.close()
                            processingFrame = false
                        }
                } catch (e: Exception) {
                    FileLogger.e(TAG, "Error processing image", e)
                    image.close()
                    processingFrame = false
                }
            }, bgHandler)

            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return
            }

            manager.openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        cameraDevice = camera
                        createPreviewSession(camera, previewSize, sensorOrientation)
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        camera.close()
                    }

                    override fun onError(
                        camera: CameraDevice,
                        error: Int,
                    ) {
                        camera.close()
                    }
                },
                bgHandler,
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "Failed to open camera", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun createPreviewSession(
        camera: CameraDevice,
        size: Size,
        sensorOrientation: Int,
    ) {
        try {
            val texture = cameraTextureView.surfaceTexture ?: return
            texture.setDefaultBufferSize(size.width, size.height)

            handler.post { applyPreviewTransform(size) }

            val previewSurface = Surface(texture)
            val readerSurface = imageReader!!.surface
            val request =
                camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                    addTarget(previewSurface)
                    addTarget(readerSurface)
                    set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                }
            previewRequest = request
            camera.createCaptureSession(
                listOf(previewSurface, readerSurface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        session.setRepeatingRequest(request.build(), null, bgHandler)
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {}
                },
                bgHandler,
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "Failed to create preview session", e)
        }
    }

    private fun applyPreviewTransform(previewSize: Size) {
        val viewW = cameraTextureView.width.toFloat()
        val viewH = cameraTextureView.height.toFloat()
        if (viewW == 0f || viewH == 0f) return

        val streamW = previewSize.width.toFloat()
        val streamH = previewSize.height.toFloat()

        val scaleX = viewW / streamH
        val scaleY = viewH / streamW
        val scale = maxOf(scaleX, scaleY)

        val matrix = Matrix()
        matrix.setScale(scale * streamH / viewW, scale * streamW / viewH, viewW / 2f, viewH / 2f)
        cameraTextureView.setTransform(matrix)
    }

    private fun handleBarcodes(barcodes: List<Barcode>) {
        if (!scanning) return
        for (barcode in barcodes) {
            if (barcode.format != Barcode.FORMAT_QR_CODE) continue
            val raw =
                barcode.rawBytes
                    ?: barcode.rawValue?.toByteArray(Charsets.ISO_8859_1)
                    ?: continue
            if (Protocol.parseQRCodePayload(raw) == null) continue
            scanning = false
            runOnUiThread {
                exitScanMode()
                handleQRCodeResult(raw)
            }
            return
        }
    }

    private fun triggerFocus(
        nx: Float,
        ny: Float,
    ) {
        val session = captureSession ?: return
        val request = previewRequest ?: return
        val sensor = sensorArraySize ?: return

        val halfSize = 150
        val cx = (nx * sensor.width()).toInt().coerceIn(halfSize, sensor.width() - halfSize)
        val cy = (ny * sensor.height()).toInt().coerceIn(halfSize, sensor.height() - halfSize)
        val focusRect =
            MeteringRectangle(
                cx - halfSize,
                cy - halfSize,
                halfSize * 2,
                halfSize * 2,
                MeteringRectangle.METERING_WEIGHT_MAX,
            )

        try {
            request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL)
            session.capture(request.build(), null, bgHandler)

            request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
            request.set(CaptureRequest.CONTROL_AF_REGIONS, arrayOf(focusRect))
            request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START)
            session.capture(request.build(), null, bgHandler)

            handler.postDelayed({
                request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
                request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                try {
                    session.setRepeatingRequest(request.build(), null, bgHandler)
                } catch (_: Exception) {
                }
            }, 2000)
        } catch (e: Exception) {
            FileLogger.e(TAG, "Focus trigger failed", e)
        }
    }

    private fun stopCamera() {
        scanning = false
        try {
            captureSession?.close()
            cameraDevice?.close()
            imageReader?.close()
            bgThread?.quitSafely()
        } catch (e: Exception) {
            FileLogger.e(TAG, "Error stopping camera", e)
        }
        captureSession = null
        cameraDevice = null
        imageReader = null
        previewRequest = null
        sensorArraySize = null
        bgThread = null
        bgHandler = null
    }

    private fun hasAllPermissions(): Boolean =
        REQUIRED_PERMISSIONS.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }

    private fun missingPermissions(): List<String> =
        REQUIRED_PERMISSIONS.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST + 1,
            )
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            },
        )
    }

    private fun startService() {
        startService(Intent(this, BuzzelService::class.java))
    }
}
