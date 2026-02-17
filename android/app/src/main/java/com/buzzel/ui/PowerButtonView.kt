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
            if (field == value) return
            val oldColor = stateColor(field)
            field = value
            val newColor = stateColor(value)
            animateColorChange(oldColor, newColor)
            updatePulse()
        }

    var onTap: (() -> Unit)? = null

    // Paints
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

    // Animation state
    private var currentColor: Int = stateColor(state)
    private var pulseScale: Float = 1f
    private var pressScale: Float = 1f
    private var rippleScale: Float = 1f
    private var rippleAlpha: Float = 0f
    private var haloFraction: Float = 0f // 0=min, 1=max

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
            PowerButtonState.NO_PERMISSION -> AppColors.mutedYellow
            PowerButtonState.UNPAIRED -> AppColors.mutedGray
            PowerButtonState.CONNECTING -> AppColors.mutedOrange
            PowerButtonState.CONNECTED -> AppColors.mutedGreen
            PowerButtonState.DISCONNECTED -> AppColors.mutedRed
        }

    // --- Color Animation (300ms easeInOut) ---

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

    // --- Pulse Animation (connecting) ---

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

    // --- Press Animation (tap: scale 0.85, spring back) ---

    private fun animatePress() {
        pressAnimator?.cancel()
        rippleAnimator?.cancel()

        // Press down
        pressAnimator =
            ValueAnimator.ofFloat(1f, 0.85f).apply {
                duration = 100
                addUpdateListener {
                    pressScale = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        // Ripple ring
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

        // Spring back after 200ms
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

    // --- Draw ---

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val viewRadius = min(cx, cy)

        // Button radius: 90dp maps to the view size
        val btnRadius = viewRadius * pressScale

        // 1. Soft halo (pulsing scale 1.10→1.25, opacity 5%→10%)
        val haloScale = 1.15f + haloFraction * 0.15f
        val haloAlpha = (13 + haloFraction * 13).toInt() // 5%=13, 10%=26
        val haloRadius = btnRadius * haloScale
        haloPaint.color = AppColors.withAlpha(currentColor, haloAlpha)
        canvas.drawCircle(cx, cy, haloRadius, haloPaint)

        // 2. Ripple ring (on tap)
        if (rippleAlpha > 0f) {
            val rr = btnRadius * rippleScale
            ripplePaint.color = AppColors.withAlpha(currentColor, (rippleAlpha * 255).toInt())
            ripplePaint.strokeWidth = viewRadius * 0.04f
            canvas.drawCircle(cx, cy, rr, ripplePaint)
        }

        // 3. Solid circle (pulses when connecting)
        val circleRadius = btnRadius * pulseScale
        circlePaint.color = currentColor
        canvas.drawCircle(cx, cy, circleRadius, circlePaint)

        // 4. Shield icon (45% of button diameter, pulses with circle)
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
        // Shield outline: default cap/join (butt/miter)
        shieldStrokePaint.strokeCap = Paint.Cap.BUTT
        shieldStrokePaint.strokeJoin = Paint.Join.MITER

        val matrix =
            Matrix().apply {
                postTranslate(-12f, -12f)
                postScale(scale, scale)
                postTranslate(cx, cy)
            }

        // Draw shield outline
        val shieldPath = PathParser.createPathFromPathData(SHIELD_PATH)
        shieldPath.transform(matrix)
        canvas.drawPath(shieldPath, shieldStrokePaint)

        // Draw inner icon
        when (state) {
            PowerButtonState.NO_PERMISSION -> drawWarning(canvas, cx, cy, scale)
            PowerButtonState.UNPAIRED -> drawKeyhole(canvas, cx, cy, scale)
            PowerButtonState.CONNECTING -> drawUp(canvas, cx, cy, scale)
            PowerButtonState.CONNECTED -> drawCheck(canvas, cx, cy, scale)
            PowerButtonState.DISCONNECTED -> drawCross(canvas, cx, cy, scale)
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

    // shield-check: round cap + round join
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

    // shield-cross: round cap
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

    // shield-keyhole: round join (uses arcs)
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

    // shield-up: round cap + round join
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

    // shield-warning: line with round cap + filled dot
    private fun drawWarning(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float,
    ) {
        innerStrokePaint.strokeWidth = scale * 1.5f
        innerStrokePaint.strokeCap = Paint.Cap.ROUND
        innerStrokePaint.strokeJoin = Paint.Join.MITER
        // Exclamation line
        val line = PathParser.createPathFromPathData("M12 8v4")
        line.transform(makeMatrix(cx, cy, scale))
        canvas.drawPath(line, innerStrokePaint)
        // Dot (filled circle at cx=12, cy=15, r=1)
        val dotCx = cx + (12f - 12f) * scale
        val dotCy = cy + (15f - 12f) * scale
        canvas.drawCircle(dotCx, dotCy, scale, innerFillPaint)
    }

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

    companion object {
        private const val SHIELD_PATH =
            "M3 10.417c0-3.198 0-4.797.378-5.335c.377-.537 1.88-1.052 4.887-2.081l.573-.196C10.405 2.268 11.188 2 12 2s1.595.268 3.162.805l.573.196c3.007 1.029 4.51 1.544 4.887 2.081C21 5.62 21 7.22 21 10.417v1.574c0 5.638-4.239 8.375-6.899 9.536C13.38 21.842 13.02 22 12 22s-1.38-.158-2.101-.473C7.239 20.365 3 17.63 3 11.991z"
    }
}
