package com.buzzel.ui

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.ImageReader
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.buzzel.protocol.Protocol
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

class ScanActivity : Activity() {
    companion object {
        private const val TAG = "ScanActivity"
        private const val CAMERA_REQUEST = 2001
        const val RESULT_QR_BYTES = "qr_bytes"
    }

    private lateinit var textureView: TextureView
    private var statusText: TextView? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var scannerInitialized = false
    private val scanner by lazy {
        scannerInitialized = true
        BarcodeScanning.getClient()
    }

    @Volatile
    private var scanning = true

    private val dp = { value: Int ->
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            @Suppress("DEPRECATION")
            window.statusBarColor = Color.BLACK
            @Suppress("DEPRECATION")
            window.navigationBarColor = Color.BLACK

            val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }

            textureView = TextureView(this)
            root.addView(
                textureView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )

            val overlay =
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    setPadding(dp(24), dp(16), dp(24), dp(32))
                }

            statusText =
                TextView(this).apply {
                    text = "Point camera at QR code"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    setTextColor(Color.WHITE)
                    typeface = Brand.typeface
                    gravity = Gravity.CENTER
                }
            overlay.addView(
                statusText,
                LinearLayout
                    .LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = dp(16) },
            )

            overlay.addView(
                android.widget.Button(this).apply {
                    text = "Cancel"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    setTextColor(Color.WHITE)
                    typeface = Brand.typeface
                    isAllCaps = false
                    stateListAnimator = null
                    elevation = 0f
                    background =
                        GradientDrawable().apply {
                            setColor(Color.parseColor("#44FFFFFF"))
                            cornerRadius = dp(10).toFloat()
                        }
                    setPadding(dp(24), dp(10), dp(24), dp(10))
                    setOnClickListener {
                        setResult(RESULT_CANCELED)
                        finish()
                    }
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )

            root.addView(
                overlay,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM,
                ),
            )

            setContentView(root)

            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.CAMERA,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
            } else {
                startCamera()
            }
            Log.d(TAG, "Scanner initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize scanner", e)
            setResult(RESULT_CANCELED)
            finish()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Camera permission: $granted")
            if (granted) {
                startCamera()
            } else {
                setResult(RESULT_CANCELED)
                finish()
            }
        }
    }

    override fun onDestroy() {
        scanning = false
        try {
            captureSession?.close()
            cameraDevice?.close()
            imageReader?.close()
            bgThread?.quitSafely()
            if (scannerInitialized) scanner.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error during cleanup", e)
        }
        super.onDestroy()
    }

    private fun startCamera() {
        bgThread = HandlerThread("CameraBackground").also { it.start() }
        bgHandler = Handler(bgThread!!.looper)

        textureView.surfaceTextureListener =
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
                ) {
                }

                override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true

                override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
            }
        if (textureView.isAvailable) openCamera()
    }

    private fun openCamera() {
        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        try {
            val cameraId =
                manager.cameraIdList.firstOrNull { id ->
                    manager
                        .getCameraCharacteristics(id)
                        .get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                } ?: manager.cameraIdList.firstOrNull() ?: return

            val map =
                manager
                    .getCameraCharacteristics(cameraId)
                    .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
            val previewSize =
                map
                    .getOutputSizes(SurfaceTexture::class.java)
                    ?.filter { it.width <= 1920 && it.height <= 1080 }
                    ?.maxByOrNull { it.width * it.height }
                    ?: Size(1280, 720)

            Log.d(TAG, "Opening camera: $cameraId, preview=${previewSize.width}x${previewSize.height}")
            imageReader = ImageReader.newInstance(previewSize.width, previewSize.height, ImageFormat.YUV_420_888, 2)
            imageReader!!.setOnImageAvailableListener({ reader ->
                val image =
                    try {
                        reader.acquireLatestImage()
                    } catch (_: Exception) {
                        null
                    }
                        ?: return@setOnImageAvailableListener
                if (!scanning) {
                    image.close()
                    return@setOnImageAvailableListener
                }
                try {
                    val inputImage = InputImage.fromMediaImage(image, 0)
                    scanner
                        .process(inputImage)
                        .addOnSuccessListener { handleBarcodes(it) }
                        .addOnFailureListener { image.close() }
                        .addOnCompleteListener { image.close() }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing image", e)
                    image.close()
                }
            }, bgHandler)

            if (ActivityCompat.checkSelfPermission(
                    this,
                    Manifest.permission.CAMERA,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                return
            }

            manager.openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        cameraDevice = camera
                        createPreviewSession(camera, previewSize)
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
            Log.e(TAG, "Failed to open camera", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun createPreviewSession(
        camera: CameraDevice,
        size: Size,
    ) {
        try {
            val texture = textureView.surfaceTexture ?: return
            texture.setDefaultBufferSize(size.width, size.height)
            val previewSurface = Surface(texture)
            val readerSurface = imageReader!!.surface
            val request =
                camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                    addTarget(previewSurface)
                    addTarget(readerSurface)
                }
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
            Log.e(TAG, "Failed to create preview session", e)
        }
    }

    private fun handleBarcodes(barcodes: List<Barcode>) {
        if (!scanning) return
        for (barcode in barcodes) {
            if (barcode.format != Barcode.FORMAT_QR_CODE) continue
            val raw = barcode.rawBytes ?: continue
            if (Protocol.parseQr(raw) == null) {
                Log.d(TAG, "QR rejected: invalid binary payload")
                continue
            }

            Log.i(TAG, "Valid QR code scanned")
            scanning = false
            mainHandler.post {
                setResult(RESULT_OK, Intent().apply { putExtra(RESULT_QR_BYTES, raw) })
                finish()
            }
            return
        }
    }
}
