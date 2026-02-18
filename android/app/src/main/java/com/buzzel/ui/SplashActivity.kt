package com.buzzel.ui

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
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
                setImageResource(R.drawable.mesh_gradient)
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
        logoView.startUndraw {
            logoView.postDelayed({
                startActivity(Intent(this, MainActivity::class.java))
                finish()
                @Suppress("DEPRECATION")
                overridePendingTransition(R.anim.stay, R.anim.slide_down_out)
            }, LogoDrawView.DELAY_AFTER_MS)
        }
    }

    // --- Logo draw/undraw animation view ---

    class LogoDrawView(
        context: Context,
        private val onDone: () -> Unit,
    ) : View(context) {
        companion object {
            const val DURATION_MS = 1000L
            const val DELAY_BEFORE_MS = 250L
            const val DELAY_AFTER_MS = 500L
            private val DRAW_INTERPOLATOR = PathInterpolator(0.25f, 0.7f, 0.2f, 1f)
            private val UNDRAW_INTERPOLATOR = PathInterpolator(0.8f, 0f, 0.75f, 0.3f)
        }

        private val srcPath = PathParser.createPathFromPathData(Brand.logoPathReversed)
        private val drawPath = Path()
        private lateinit var pathMeasure: PathMeasure
        private var pathLength = 0f
        private var progress = 0f
        private var eraseProgress = 0f
        private var animatorStarted = false

        private val paint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = Brand.logoStrokeWidth
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
                color =
                    if (AppColors.isDarkMode(context)) {
                        Brand.splashLogoColorDark
                    } else {
                        Brand.splashLogoColorLight
                    }
            }

        override fun onSizeChanged(
            w: Int,
            h: Int,
            oldw: Int,
            oldh: Int,
        ) {
            super.onSizeChanged(w, h, oldw, oldh)
            val size = min(w, h) * Brand.splashLogoScale
            val scale = size / Brand.logoViewbox
            srcPath.transform(
                Matrix().apply {
                    postScale(scale, scale)
                    postTranslate((w - size) / 2f, (h - size) / 2f)
                },
            )
            paint.strokeWidth = Brand.logoStrokeWidth * scale
            pathMeasure = PathMeasure(srcPath, false)
            pathLength = pathMeasure.length
            if (!animatorStarted) {
                animatorStarted = true
                postDelayed({ startDrawAnimation() }, DELAY_BEFORE_MS)
            }
        }

        private fun startDrawAnimation() {
            animate(DURATION_MS, DRAW_INTERPOLATOR, { progress = it }) {
                post { onDone() }
            }
        }

        fun startUndraw(onFinished: () -> Unit) {
            animate(DURATION_MS, UNDRAW_INTERPOLATOR, { eraseProgress = it }) {
                post { onFinished() }
            }
        }

        private fun animate(
            duration: Long,
            interpolator: PathInterpolator,
            onUpdate: (Float) -> Unit,
            onEnd: () -> Unit,
        ) {
            ValueAnimator
                .ofFloat(0f, 1f)
                .apply {
                    this.duration = duration
                    this.interpolator = interpolator
                    addUpdateListener {
                        onUpdate(it.animatedValue as Float)
                        invalidate()
                    }
                    addListener(
                        object : AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: Animator) = onEnd()
                        },
                    )
                }.start()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (pathLength <= 0f || progress <= 0f) return
            val start = pathLength * eraseProgress
            val end = pathLength * progress
            if (start >= end) return
            drawPath.reset()
            pathMeasure.getSegment(start, end, drawPath, true)
            canvas.drawPath(drawPath, paint)
        }
    }
}
