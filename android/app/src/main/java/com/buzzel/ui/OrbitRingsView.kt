package com.buzzel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.Choreographer
import android.view.View
import android.widget.FrameLayout
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

class OrbitRingsView(
    context: Context,
) : FrameLayout(context) {
    private data class OrbitDot(
        val offset: Double,
        val size: Float,
        val color: Int,
    )

    private data class Ring(
        val radius: Float,
        val durationSeconds: Double, // negative = counter-clockwise
        val dots: List<OrbitDot>,
    )

    // 1.25x scale from macOS pt values for visual parity on phone screens
    private val rings =
        listOf(
            Ring(
                100f,
                12.0,
                listOf(
                    OrbitDot(0.0, 7.5f, AppColors.accent),
                    OrbitDot(0.55, 5f, AppColors.green),
                ),
            ),
            Ring(
                131f,
                -18.0,
                listOf(
                    OrbitDot(0.2, 6f, AppColors.orange),
                    OrbitDot(0.7, 4f, AppColors.accent),
                ),
            ),
            Ring(
                162f,
                25.0,
                listOf(
                    OrbitDot(0.4, 5f, AppColors.red),
                    OrbitDot(0.85, 4f, AppColors.green),
                ),
            ),
        )

    private val ringPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }

    private val dotPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

    private val glowPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

    private var startTime = System.nanoTime()
    private var running = false

    private val choreographer = Choreographer.getInstance()
    private val frameCallback =
        object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                if (running) {
                    invalidate()
                    choreographer.postFrameCallback(this)
                }
            }
        }

    init {
        setWillNotDraw(false)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startTime = System.nanoTime()
        running = true
        choreographer.postFrameCallback(frameCallback)
    }

    override fun onDetachedFromWindow() {
        running = false
        choreographer.removeFrameCallback(frameCallback)
        super.onDetachedFromWindow()
    }

    override fun dispatchDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val density = resources.displayMetrics.density
        val elapsed = (System.nanoTime() - startTime) / 1_000_000_000.0

        for (ring in rings) {
            val radiusPx = ring.radius * density
            val progress = elapsed / kotlin.math.abs(ring.durationSeconds)
            val direction = if (ring.durationSeconds > 0) 1.0 else -1.0
            val angleDeg = progress * 360.0 * direction

            // Ring circle
            ringPaint.color = AppColors.withAlpha(AppColors.secondary, 20) // 8%
            ringPaint.strokeWidth = density
            canvas.drawCircle(cx, cy, radiusPx, ringPaint)

            // Dots
            for (dot in ring.dots) {
                val dotAngle = Math.toRadians(angleDeg + dot.offset * 360.0)
                val dx = cx + radiusPx * cos(dotAngle).toFloat()
                val dy = cy + radiusPx * sin(dotAngle).toFloat()
                val dotRadius = dot.size * density / 2f

                // Shadow glow
                glowPaint.color = AppColors.withAlpha(dot.color, 102) // 40%
                val glowRadius = dotRadius + dotRadius * 0.8f
                canvas.drawCircle(dx, dy, glowRadius, glowPaint)

                // Dot
                dotPaint.color = AppColors.withAlpha(dot.color, 153) // 60%
                canvas.drawCircle(dx, dy, dotRadius, dotPaint)
            }
        }

        // Draw children (power button, etc.) on top
        super.dispatchDraw(canvas)
    }
}
