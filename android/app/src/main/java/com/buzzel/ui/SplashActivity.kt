package com.buzzel.ui

import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Bundle
import android.view.View
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.graphics.PathParser
import com.buzzel.R
import kotlin.math.min

class SplashActivity : Activity() {
    private lateinit var logoView: LogoDrawView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Brand.load(this)
        AppColors.resolve(this)

        val root = FrameLayout(this)
        val lp =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )

        root.addView(
            ImageView(this).apply {
                setImageResource(R.drawable.mesh)
                scaleType = ImageView.ScaleType.CENTER_CROP
            },
            lp,
        )

        logoView = LogoDrawView(this) { onDrawDone() }
        root.addView(logoView, lp)

        setContentView(root)

        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
    }

    private fun onDrawDone() {
        logoView.postDelayed({
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            @Suppress("DEPRECATION")
            overridePendingTransition(R.anim.stay, R.anim.slide_down_out)
        }, DELAY_AFTER_MS)
    }

    companion object {
        const val DELAY_BEFORE_MS = 0L
        const val DELAY_AFTER_MS = 500L
    }

    // --- Logo draw animation view ---

    class LogoDrawView(
        context: Context,
        private val onDone: () -> Unit,
    ) : View(context) {
        companion object {
            // Bar timings
            const val BAR1_DUR = 250L
            const val BAR2_DUR = 200L
            const val BAR3_DUR = 250L
            const val BAR2_BEGIN = 200L
            const val BAR3_BEGIN = 350L

            // Bar path data
            const val BAR1_PATH = "M410.094 160.783H17.871l102.254-160.79h391.868z"
            const val BAR2_PATH = "M305.464 336.398H108.914l101.529-160.79h191.956Z"
            const val BAR3_PATH = "M391.781 512.0H0.0l100.601-160.79h392.506z"

            // Easing curves
            private val BAR1_INTERP = PathInterpolator(0.25f, 0.1f, 0.25f, 1f)
            private val BAR2_INTERP = PathInterpolator(0.42f, 0f, 0.58f, 1f)
            private val BAR3_INTERP = PathInterpolator(0.25f, 0.1f, 0.6f, 1f)
        }

        private data class Bar(
            val path: Path,
            val bounds: RectF,
            val fromRight: Boolean,
            var drawProgress: Float = 0f,
        )

        private val bars = mutableListOf<Bar>()
        private var animatorStarted = false
        private val clipPath = Path()

        private val paint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
                color =
                    if (AppColors.isDarkMode(context)) {
                        Brand.SPLASH_LOGO_COLOR_DARK
                    } else {
                        Brand.SPLASH_LOGO_COLOR_LIGHT
                    }
            }

        override fun onSizeChanged(
            w: Int,
            h: Int,
            oldw: Int,
            oldh: Int,
        ) {
            super.onSizeChanged(w, h, oldw, oldh)
            val size = min(w, h) * Brand.SPLASH_LOGO_SCALE
            val scale = size / Brand.logoViewbox
            val matrix =
                Matrix().apply {
                    postScale(scale, scale)
                    postTranslate((w - size) / 2f, (h - size) / 2f)
                }

            bars.clear()
            for ((pathData, fromRight) in listOf(
                BAR1_PATH to false,
                BAR2_PATH to true,
                BAR3_PATH to false,
            )) {
                val path = PathParser.createPathFromPathData(pathData)
                path.transform(matrix)
                val bounds = RectF()
                path.computeBounds(bounds, true)
                bars.add(Bar(path, bounds, fromRight))
            }

            if (!animatorStarted) {
                animatorStarted = true
                postDelayed({ startDrawAnimation() }, DELAY_BEFORE_MS)
            }
        }

        private fun startDrawAnimation() {
            animateBar(0, BAR1_DUR, BAR1_INTERP, 0L)
            animateBar(1, BAR2_DUR, BAR2_INTERP, BAR2_BEGIN)
            animateBar(2, BAR3_DUR, BAR3_INTERP, BAR3_BEGIN)

            val drawEnd = BAR3_BEGIN + BAR3_DUR + 300L
            postDelayed({ onDone() }, drawEnd)
        }

        private fun animateBar(
            index: Int,
            duration: Long,
            interpolator: PathInterpolator,
            delay: Long,
        ) {
            postDelayed({
                ValueAnimator
                    .ofFloat(0f, 1f)
                    .apply {
                        this.duration = duration
                        this.interpolator = interpolator
                        addUpdateListener {
                            bars[index].drawProgress = it.animatedValue as Float
                            invalidate()
                        }
                    }.start()
            }, delay)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            for (bar in bars) {
                if (bar.drawProgress <= 0f) continue
                val b = bar.bounds
                val clipLeft: Float
                val clipRight: Float
                if (bar.fromRight) {
                    clipRight = b.right
                    clipLeft = b.right - b.width() * bar.drawProgress
                } else {
                    clipLeft = b.left
                    clipRight = b.left + b.width() * bar.drawProgress
                }
                if (clipLeft >= clipRight) continue
                canvas.save()
                clipPath.reset()
                clipPath.addRect(clipLeft, b.top, clipRight, b.bottom, Path.Direction.CW)
                canvas.clipPath(clipPath)
                canvas.drawPath(bar.path, paint)
                canvas.restore()
            }
        }
    }
}
