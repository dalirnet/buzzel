package com.buzzel.ui

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
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

    /** When true and state is DISCONNECTED, shows "ready" appearance instead of "lost". */
    var ready: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            readyChanged = true
            // Re-trigger state setter to update color/icon
            state = state
        }

    private var readyChanged = false

    var onTap: (() -> Unit)? = null

    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val ripplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    private val shieldStrokePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = AppColors.onButton
        }
    private val innerStrokePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = AppColors.onButton
        }
    private val innerFillPaint =
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

    private var pulseAnimator: ValueAnimator? = null
    private var colorAnimator: ValueAnimator? = null
    private var pressAnimator: ValueAnimator? = null
    private var rippleAnimator: ValueAnimator? = null
    private var haloAnimator: ValueAnimator? = null

    init {
        isClickable = true
        setOnClickListener {
            animatePress()
            onTap?.invoke()
        }
        updatePulse()
    }

    private fun stateColor(s: PowerButtonState): Int =
        when (s) {
            PowerButtonState.RESTRICTED -> AppColors.mutedYellow
            PowerButtonState.UNPAIRED -> AppColors.mutedGray
            PowerButtonState.CONNECTING -> AppColors.mutedOrange
            PowerButtonState.CONNECTED -> AppColors.mutedGreen
            PowerButtonState.DISCONNECTED -> if (ready) AppColors.accent else AppColors.mutedRed
        }

    // region Animation

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
    }

    private fun animatePress() {
        pressAnimator?.cancel()
        rippleAnimator?.cancel()

        pressAnimator =
            ValueAnimator.ofFloat(1f, 0.85f).apply {
                duration = 100
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
                    val f = it.animatedValue as Float
                    rippleScale = 1f + f * 0.3f
                    rippleAlpha = if (f < 0.3f) f / 0.3f * 0.3f else 0.3f * (1f - (f - 0.3f) / 0.7f)
                    invalidate()
                }
                start()
            }

        postDelayed({
            pressAnimator?.cancel()
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
        }, 200)
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

    // endregion

    // region Lifecycle

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startHaloPulse()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        pulseAnimator?.cancel()
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
            haloAnimator?.cancel()
            haloAnimator = null
            haloFraction = 0f
            rippleAnimator?.cancel()
            rippleAlpha = 0f
            invalidate()
        }
    }

    // endregion

    // region Drawing

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val viewRadius = min(cx, cy)
        val btnRadius = viewRadius * pressScale

        val haloScale = 1.15f + haloFraction * 0.15f
        val haloAlpha = (13 + haloFraction * 13).toInt()
        val haloRadius = btnRadius * haloScale
        haloPaint.color = AppColors.withAlpha(currentColor, haloAlpha)
        canvas.drawCircle(cx, cy, haloRadius, haloPaint)

        if (rippleAlpha > 0f) {
            val rr = btnRadius * rippleScale
            ripplePaint.color = AppColors.withAlpha(currentColor, (rippleAlpha * 255).toInt())
            ripplePaint.strokeWidth = viewRadius * 0.04f
            canvas.drawCircle(cx, cy, rr, ripplePaint)
        }

        val circleRadius = btnRadius * pulseScale
        circlePaint.color = currentColor
        canvas.drawCircle(cx, cy, circleRadius, circlePaint)

        val iconSize = circleRadius * 2 * 0.45f
        val iconScale = iconSize / 24f
        drawShieldIcon(canvas, cx, cy, iconScale)
    }

    private fun drawShieldIcon(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        shieldStrokePaint.strokeWidth = scale * 1.5f
        shieldStrokePaint.strokeCap = Paint.Cap.BUTT
        shieldStrokePaint.strokeJoin = Paint.Join.MITER

        val matrix =
            Matrix().apply {
                postTranslate(-12f, -12f)
                postScale(scale, scale)
                postTranslate(cx, cy)
            }

        val shieldPath = PathParser.createPathFromPathData(SHIELD_PATH)
        shieldPath.transform(matrix)
        canvas.drawPath(shieldPath, shieldStrokePaint)

        when (state) {
            PowerButtonState.RESTRICTED -> drawWarning(canvas, cx, cy, scale)
            PowerButtonState.UNPAIRED -> drawKeyhole(canvas, cx, cy, scale)
            PowerButtonState.CONNECTING -> drawUp(canvas, cx, cy, scale)
            PowerButtonState.CONNECTED -> drawCheck(canvas, cx, cy, scale)
            PowerButtonState.DISCONNECTED -> if (ready) drawPlay(canvas, cx, cy, scale) else drawCross(canvas, cx, cy, scale)
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

    private fun drawCheck(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.ROUND
        innerStrokePaint.strokeJoin = Paint.Join.ROUND
        val p = PathParser.createPathFromPathData("M9.5 12.4l1.429 1.6l3.571-4")
        p.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(p, innerStrokePaint)
    }

    private fun drawCross(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.ROUND
        innerStrokePaint.strokeJoin = Paint.Join.MITER
        val p = PathParser.createPathFromPathData("M14.5 9.5l-5 5m0-5l5 5")
        p.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(p, innerStrokePaint)
    }

    private fun drawKeyhole(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.BUTT
        innerStrokePaint.strokeJoin = Paint.Join.ROUND
        val p =
            PathParser.createPathFromPathData(
                "M11.5 16h1a1 1 0 0 0 1-1v-1.401A2.999 2.999 0 0 0 12 8a3 3 0 0 0-1.5 5.599V15a1 1 0 0 0 1 1Z",
            )
        p.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(p, innerStrokePaint)
    }

    private fun drawUp(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.ROUND
        innerStrokePaint.strokeJoin = Paint.Join.ROUND
        val p =
            PathParser.createPathFromPathData(
                "M16 11.55L12.6 9a1 1 0 0 0-1.2 0L8 11.55m6 2.5l-2-1.5l-2 1.5",
            )
        p.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(p, innerStrokePaint)
    }

    private fun drawPlay(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.ROUND
        innerStrokePaint.strokeJoin = Paint.Join.ROUND
        val p = PathParser.createPathFromPathData("M10 8l6 4l-6 4z")
        p.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(p, innerStrokePaint)
    }

    private fun drawWarning(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.ROUND
        innerStrokePaint.strokeJoin = Paint.Join.MITER
        val line = PathParser.createPathFromPathData("M12 8v4")
        line.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(line, innerStrokePaint)
        canvas.drawCircle(cx, cy + 3f * scale, scale, innerFillPaint)
    }

    // endregion

    companion object {
        private const val SHIELD_PATH =
            "M3 10.417c0-3.198 0-4.797.378-5.335c.377-.537 1.88-1.052 4.887-2.081l.573-.196C10.405 2.268 11.188 2 12 2s1.595.268 3.162.805l.573.196c3.007 1.029 4.51 1.544 4.887 2.081C21 5.62 21 7.22 21 10.417v1.574c0 5.638-4.239 8.375-6.899 9.536C13.38 21.842 13.02 22 12 22s-1.38-.158-2.101-.473C7.239 20.365 3 17.63 3 11.991z"
    }
}
