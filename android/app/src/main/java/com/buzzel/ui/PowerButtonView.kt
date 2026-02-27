package com.buzzel.ui

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.graphics.PathParser
import kotlin.math.min

class PowerButtonView(
    context: Context,
) : View(context) {
    var state: PowerButtonState = PowerButtonState.UNPAIRED
        set(value) {
            if (field == value && !readyChanged) return
            readyChanged = false
            val oldColor = currentColor
            field = value
            val newColor = stateColor(value)
            animateColorChange(oldColor, newColor)
            updatePulse()
        }

    var ready: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            readyChanged = true
            state = state
        }

    private var readyChanged = false

    var onTap: (() -> Unit)? = null
    var onUnpairWarning: (() -> Unit)? = null
    var onUnpair: (() -> Unit)? = null
    var onHoldCancel: (() -> Unit)? = null

    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val ripplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    private val iconFillPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = AppColors.onButton
        }

    private var currentColor: Int = stateColor(state)
    private var pulseScale: Float = 1f
    private var pressScale: Float = 1f
    private var rippleScale: Float = 1f
    private var rippleAlpha: Float = 0f
    private var haloFraction: Float = 0f

    private var spinAngle: Float = 0f
    private var unpairProgress: Float = 0f
    private var pulseAnimator: ValueAnimator? = null
    private var spinAnimator: ValueAnimator? = null
    private var colorAnimator: ValueAnimator? = null
    private var pressAnimator: ValueAnimator? = null
    private var rippleAnimator: ValueAnimator? = null
    private var haloAnimator: ValueAnimator? = null

    private val canUnpair: Boolean
        get() =
            state == PowerButtonState.CONNECTING || state == PowerButtonState.CONNECTED ||
                state == PowerButtonState.DISCONNECTED

    private var holdWarningFired = false
    private var holdUnpairFired = false
    private var holdStartTime = 0L
    private val holdTickRunnable =
        object : Runnable {
            override fun run() {
                if (holdStartTime == 0L || holdUnpairFired) return
                val elapsed = System.currentTimeMillis() - holdStartTime
                if (elapsed >= HOLD_UNPAIR_MILLISECONDS) {
                    holdUnpairFired = true
                    unpairProgress = 1f
                    invalidate()
                    onUnpair?.invoke()
                    animatePress()
                    return
                }
                if (elapsed >= HOLD_WARNING_MILLISECONDS) {
                    if (!holdWarningFired) {
                        holdWarningFired = true
                        onUnpairWarning?.invoke()
                    }
                    val progressDuration = HOLD_UNPAIR_MILLISECONDS - HOLD_WARNING_MILLISECONDS
                    unpairProgress = (elapsed - HOLD_WARNING_MILLISECONDS).toFloat() / progressDuration.toFloat()
                    invalidate()
                }
                postDelayed(this, 16)
            }
        }

    init {
        isClickable = true
        updatePulse()
    }

    @Suppress("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                holdWarningFired = false
                holdUnpairFired = false
                unpairProgress = 0f
                pressAnimator?.cancel()
                pressScale = 0.85f
                invalidate()
                if (canUnpair) {
                    holdStartTime = System.currentTimeMillis()
                    post(holdTickRunnable)
                }
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(holdTickRunnable)
                holdStartTime = 0L
                if (!holdUnpairFired && !holdWarningFired) {
                    onTap?.invoke()
                }
                if (holdWarningFired && !holdUnpairFired) {
                    onHoldCancel?.invoke()
                }
                unpairProgress = 0f
                holdWarningFired = false
                holdUnpairFired = false
                animatePress()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun stateColor(buttonState: PowerButtonState): Int =
        when (buttonState) {
            PowerButtonState.RESTRICTED -> AppColors.mutedYellow
            PowerButtonState.UNPAIRED -> AppColors.mutedGray
            PowerButtonState.CONNECTING -> AppColors.mutedOrange
            PowerButtonState.CONNECTED -> AppColors.mutedGreen
            PowerButtonState.DISCONNECTED -> if (ready) AppColors.accent else AppColors.mutedRed
        }

    private val argbEvaluator = ArgbEvaluator()

    private fun displayColor(): Int {
        if (unpairProgress > 0f) {
            return argbEvaluator.evaluate(unpairProgress.coerceIn(0f, 1f), currentColor, AppColors.mutedGray) as Int
        }
        return currentColor
    }

    private fun animateColorChange(
        from: Int,
        to: Int,
    ) {
        colorAnimator?.cancel()
        val evaluator = ArgbEvaluator()
        colorAnimator =
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 300
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener {
                    currentColor = evaluator.evaluate(it.animatedValue as Float, from, to) as Int
                    invalidate()
                }
                start()
            }
    }

    private fun updatePulse() {
        val shouldPulse = state == PowerButtonState.CONNECTING
        if (shouldPulse && pulseAnimator == null) {
            pulseAnimator =
                ValueAnimator.ofFloat(1f, 0.88f).apply {
                    duration = 900
                    repeatMode = ValueAnimator.REVERSE
                    repeatCount = ValueAnimator.INFINITE
                    interpolator = AccelerateDecelerateInterpolator()
                    addUpdateListener {
                        pulseScale = it.animatedValue as Float
                        invalidate()
                    }
                    start()
                }
        } else if (!shouldPulse) {
            pulseAnimator?.cancel()
            pulseAnimator = null
            pulseScale = 1f
            invalidate()
        }
        if (shouldPulse && spinAnimator == null) {
            spinAnimator =
                ValueAnimator.ofFloat(0f, 360f).apply {
                    duration = 1200
                    repeatCount = ValueAnimator.INFINITE
                    interpolator = LinearInterpolator()
                    addUpdateListener {
                        spinAngle = it.animatedValue as Float
                        invalidate()
                    }
                    start()
                }
        } else if (!shouldPulse) {
            spinAnimator?.cancel()
            spinAnimator = null
            spinAngle = 0f
        }
    }

    private fun animatePress() {
        pressAnimator?.cancel()
        rippleAnimator?.cancel()

        pressAnimator =
            ValueAnimator.ofFloat(pressScale, 1f).apply {
                duration = 300
                interpolator = OvershootInterpolator(2f)
                addUpdateListener {
                    pressScale = it.animatedValue as Float
                    invalidate()
                }
                start()
            }

        rippleAnimator =
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 400
                addUpdateListener {
                    val fraction = it.animatedValue as Float
                    rippleScale = 1f + fraction * 0.3f
                    rippleAlpha =
                        if (fraction < 0.3f) fraction / 0.3f * 0.3f else 0.3f * (1f - (fraction - 0.3f) / 0.7f)
                    invalidate()
                }
                start()
            }
    }

    private fun startHaloPulse() {
        if (haloAnimator != null) return
        haloAnimator =
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 2000
                repeatMode = ValueAnimator.REVERSE
                repeatCount = ValueAnimator.INFINITE
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener {
                    haloFraction = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startHaloPulse()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        removeCallbacks(holdTickRunnable)
        holdStartTime = 0L
        pulseAnimator?.cancel()
        spinAnimator?.cancel()
        colorAnimator?.cancel()
        pressAnimator?.cancel()
        rippleAnimator?.cancel()
        haloAnimator?.cancel()
        haloAnimator = null
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (hasWindowFocus) {
            updatePulse()
            startHaloPulse()
        } else {
            pulseAnimator?.cancel()
            pulseAnimator = null
            pulseScale = 1f
            spinAnimator?.cancel()
            spinAnimator = null
            spinAngle = 0f
            haloAnimator?.cancel()
            haloAnimator = null
            haloFraction = 0f
            rippleAnimator?.cancel()
            rippleAlpha = 0f
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val viewRadius = min(cx, cy)
        val btnRadius = viewRadius * pressScale

        val color = displayColor()

        val haloScale = 1.15f + haloFraction * 0.15f
        val haloAlpha = (13 + haloFraction * 13).toInt()
        val haloRadius = btnRadius * haloScale
        haloPaint.color = AppColors.withAlpha(color, haloAlpha)
        canvas.drawCircle(cx, cy, haloRadius, haloPaint)

        if (rippleAlpha > 0f) {
            val rr = btnRadius * rippleScale
            ripplePaint.color = AppColors.withAlpha(color, (rippleAlpha * 255).toInt())
            ripplePaint.strokeWidth = viewRadius * 0.04f
            canvas.drawCircle(cx, cy, rr, ripplePaint)
        }

        val circleRadius = btnRadius * pulseScale
        circlePaint.color = color
        canvas.drawCircle(cx, cy, circleRadius, circlePaint)

        val iconSize = circleRadius * 2 * 0.38f
        val iconScale = iconSize / 24f
        drawIcon(canvas, cx, cy, iconScale)
    }

    private fun drawIcon(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        when (state) {
            PowerButtonState.RESTRICTED -> drawFilled(canvas, cx, cy, scale, FINGER_ACCESS_PATH)
            PowerButtonState.UNPAIRED -> drawFilled(canvas, cx, cy, scale, ZAP_PATH)
            PowerButtonState.CONNECTING -> drawFilledRotated(canvas, cx, cy, scale, LOADING_PATH)
            PowerButtonState.CONNECTED -> drawFilled(canvas, cx, cy, scale, ZAP_PATH)
            PowerButtonState.DISCONNECTED -> drawFilled(canvas, cx, cy, scale, ZAP_PATH)
        }
    }

    private fun makeMatrix(
        cx: Float,
        cy: Float,
        scale: Float,
    ): Matrix =
        Matrix().apply {
            postTranslate(-12f, -12f)
            postScale(scale, scale)
            postTranslate(cx, cy)
        }

    private fun drawFilled(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
        pathData: String,
    ) {
        val path = PathParser.createPathFromPathData(pathData)
        path.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(path, iconFillPaint)
    }

    private fun drawFilledRotated(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
        pathData: String,
    ) {
        canvas.save()
        canvas.rotate(spinAngle, cx, cy)
        drawFilled(canvas, cx, cy, scale, pathData)
        canvas.restore()
    }

    companion object {
        const val HOLD_WARNING_MILLISECONDS = 2000L
        const val HOLD_UNPAIR_MILLISECONDS = 4000L

        private const val FINGER_ACCESS_PATH =
            "M12,3.75C7.444,3.75 3.75,7.444 3.75,12C3.75,12.631 3.821,13.245 3.954,13.834C4.046,14.238 3.793,14.64 3.389,14.731C2.985,14.823 2.583,14.57 2.492,14.166C2.333,13.469 2.25,12.744 2.25,12C2.25,6.615 6.615,2.25 12,2.25C17.385,2.25 21.75,6.615 21.75,12C21.75,14.071 20.071,15.75 18,15.75C15.929,15.75 14.25,14.071 14.25,12C14.25,10.757 13.243,9.75 12,9.75C10.757,9.75 9.75,10.757 9.75,12C9.75,12.746 9.861,13.997 10.607,15.47C11.352,16.942 12.753,18.681 15.403,20.367C15.752,20.59 15.855,21.053 15.633,21.403C15.41,21.752 14.947,21.855 14.597,21.633C11.747,19.819 10.148,17.886 9.268,16.147C8.389,14.41 8.25,12.911 8.25,12C8.25,9.929 9.929,8.25 12,8.25C14.071,8.25 15.75,9.929 15.75,12C15.75,13.243 16.757,14.25 18,14.25C19.243,14.25 20.25,13.243 20.25,12C20.25,7.444 16.556,3.75 12,3.75ZM12,6.75C9.1,6.75 6.75,9.1 6.75,12C6.75,15.106 7.666,17.132 9.586,19.531C9.844,19.855 9.792,20.327 9.468,20.586C9.145,20.844 8.673,20.792 8.414,20.469C6.334,17.868 5.25,15.521 5.25,12C5.25,8.272 8.272,5.25 12,5.25C15.728,5.25 18.75,8.272 18.75,12C18.75,12.414 18.414,12.75 18,12.75C17.586,12.75 17.25,12.414 17.25,12C17.25,9.1 14.899,6.75 12,6.75ZM12.746,11.925C12.971,14.171 14.204,15.758 15.426,16.806C16.035,17.328 16.632,17.707 17.076,17.954C17.297,18.078 17.479,18.167 17.602,18.225C17.664,18.254 17.711,18.275 17.741,18.288L17.773,18.302L17.779,18.304C18.163,18.458 18.35,18.894 18.196,19.279C18.043,19.663 17.606,19.85 17.222,19.696L17.218,19.695L17.213,19.693L17.198,19.687C17.191,19.684 17.182,19.68 17.172,19.676C17.164,19.673 17.156,19.669 17.146,19.665C17.103,19.646 17.042,19.619 16.966,19.584C16.814,19.513 16.601,19.407 16.346,19.264C15.836,18.981 15.152,18.547 14.45,17.944C13.046,16.742 11.529,14.829 11.254,12.075C11.213,11.663 11.513,11.295 11.925,11.254C12.338,11.213 12.705,11.513 12.746,11.925Z"

        private const val LOADING_PATH =
            "M12,22.75C6.072,22.75 1.25,17.928 1.25,12C1.25,6.072 6.072,1.25 12,1.25C17.928,1.25 22.75,6.072 22.75,12C22.75,12.914 22.634,13.82 22.405,14.69C22.257,15.274 21.877,15.759 21.336,16.047C20.755,16.357 20.056,16.403 19.418,16.176C18.368,15.812 17.787,14.653 18.072,13.482C18.191,12.998 18.251,12.499 18.251,11.999C18.251,8.553 15.447,5.749 12.001,5.749C8.555,5.749 5.751,8.553 5.751,11.999C5.751,15.445 8.555,18.249 12.001,18.249C13.127,18.249 14.243,17.94 15.228,17.354C15.584,17.143 16.044,17.259 16.256,17.616C16.468,17.973 16.351,18.432 15.994,18.644C14.777,19.367 13.397,19.749 12.001,19.749C7.728,19.749 4.251,16.272 4.251,11.999C4.251,7.726 7.728,4.249 12.001,4.249C16.274,4.249 19.751,7.726 19.751,11.999C19.751,12.62 19.676,13.238 19.529,13.838C19.444,14.187 19.568,14.64 19.917,14.761C20.161,14.848 20.426,14.833 20.631,14.724C20.747,14.662 20.897,14.541 20.954,14.316C21.152,13.563 21.251,12.786 21.251,12C21.251,6.9 17.101,2.75 12.001,2.75C6.901,2.75 2.751,6.9 2.751,12C2.751,17.1 6.901,21.25 12.001,21.25C14.028,21.25 15.946,20.611 17.549,19.401C17.88,19.151 18.35,19.217 18.599,19.548C18.848,19.879 18.783,20.349 18.452,20.598C16.587,22.005 14.356,22.749 12,22.749L12,22.75Z"

        internal const val ZAP_PATH =
            "M16.017,2.325C16.542,2.403 17.114,2.593 17.441,3.16C17.768,3.726 17.648,4.316 17.456,4.811C17.271,5.288 16.944,5.864 16.562,6.536L15.461,8.473C15.253,8.839 15.119,9.076 15.033,9.257C14.969,9.394 14.958,9.45 14.956,9.459C14.959,9.57 15.018,9.67 15.109,9.727C15.119,9.73 15.173,9.746 15.318,9.758C15.517,9.773 15.788,9.774 16.207,9.774L16.238,9.774C16.727,9.774 17.137,9.774 17.457,9.798C17.766,9.822 18.13,9.875 18.435,10.078C19.028,10.472 19.337,11.175 19.229,11.877C19.173,12.239 18.968,12.543 18.777,12.789C18.58,13.043 18.305,13.348 17.976,13.712L12.384,19.895C11.871,20.462 11.439,20.94 11.088,21.246C10.909,21.402 10.698,21.562 10.463,21.658C10.203,21.763 9.861,21.808 9.521,21.631C9.182,21.454 9.023,21.149 8.959,20.877C8.902,20.63 8.91,20.366 8.934,20.13C8.98,19.665 9.119,19.035 9.285,18.286L9.983,15.128C10.122,14.501 10.206,14.11 10.228,13.824C10.238,13.69 10.231,13.617 10.222,13.58C10.217,13.553 10.212,13.547 10.209,13.544L10.208,13.543C10.206,13.54 10.202,13.535 10.179,13.524C10.145,13.508 10.077,13.485 9.945,13.466C9.664,13.425 9.267,13.424 8.628,13.424L8.109,13.424C7.417,13.424 6.815,13.424 6.35,13.354C5.857,13.281 5.329,13.104 4.997,12.592C4.667,12.08 4.721,11.526 4.854,11.045C4.98,10.59 5.224,10.036 5.506,9.399C5.514,9.382 5.521,9.365 5.529,9.348L7.356,5.214C7.617,4.625 7.836,4.129 8.059,3.741C8.296,3.33 8.57,2.98 8.97,2.719C9.37,2.458 9.8,2.348 10.271,2.298C10.715,2.25 11.255,2.25 11.896,2.25L14.084,2.25C14.852,2.25 15.513,2.25 16.017,2.325ZM15.796,3.809C15.416,3.752 14.869,3.75 14.024,3.75L11.935,3.75C11.244,3.75 10.785,3.751 10.431,3.789C10.095,3.825 9.921,3.889 9.79,3.975C9.658,4.061 9.529,4.195 9.359,4.49C9.18,4.801 8.993,5.222 8.713,5.857L6.901,9.954C6.59,10.658 6.392,11.109 6.299,11.445C6.255,11.605 6.248,11.694 6.25,11.741C6.252,11.773 6.256,11.777 6.257,11.777C6.257,11.778 6.258,11.783 6.285,11.797C6.325,11.817 6.408,11.846 6.571,11.871C6.913,11.922 7.402,11.924 8.169,11.924L8.68,11.924C9.251,11.924 9.758,11.924 10.16,11.982C10.594,12.044 11.05,12.193 11.381,12.608C11.712,13.022 11.757,13.499 11.724,13.937C11.693,14.343 11.583,14.841 11.459,15.401L10.761,18.558C10.658,19.027 10.574,19.406 10.515,19.712C10.729,19.488 10.988,19.203 11.307,18.849L16.843,12.729C17.197,12.336 17.434,12.074 17.592,11.871C17.712,11.715 17.743,11.647 17.748,11.637C17.761,11.518 17.71,11.403 17.616,11.335C17.604,11.331 17.533,11.309 17.342,11.294C17.087,11.274 16.735,11.274 16.207,11.274L16.178,11.274C15.796,11.274 15.465,11.274 15.201,11.253C14.934,11.232 14.63,11.185 14.355,11.024C13.802,10.699 13.462,10.107 13.456,9.467C13.453,9.149 13.562,8.862 13.676,8.619C13.789,8.378 13.953,8.09 14.143,7.756L15.229,5.846C15.648,5.109 15.918,4.629 16.058,4.269C16.125,4.096 16.142,3.997 16.145,3.945C16.146,3.924 16.144,3.915 16.144,3.913L16.143,3.913C16.143,3.913 16.143,3.912 16.142,3.91L16.141,3.908C16.14,3.908 16.139,3.906 16.135,3.904C16.132,3.902 16.125,3.897 16.115,3.892C16.071,3.869 15.978,3.836 15.796,3.809Z"
    }
}
