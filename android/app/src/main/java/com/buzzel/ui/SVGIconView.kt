package com.buzzel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.view.View
import androidx.core.graphics.PathParser
import kotlin.math.min

class SVGIconView(
    context: Context,
    pathGroups: Array<Array<String>> = emptyArray(),
    var mode: IconMode = IconMode.STROKE
) : View(context) {

    var pathGroups: Array<Array<String>> = pathGroups
        set(value) {
            field = value; invalidate()
        }

    enum class IconMode { STROKE, FILL, MIXED }

    var iconColor: Int = 0xFF000000.toInt()
        set(value) {
            field = value; invalidate()
        }

    var iconOpacity: Float = 1f
        set(value) {
            field = value; invalidate()
        }

    var strokeWidth: Float = 1.5f

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = min(width, height).toFloat()
        val scale = size / 24f

        val alphaInt = (iconOpacity * 255).toInt().coerceIn(0, 255)

        strokePaint.color = iconColor
        strokePaint.alpha = alphaInt
        strokePaint.strokeWidth = scale * strokeWidth

        fillPaint.color = iconColor
        fillPaint.alpha = alphaInt

        val ox = (width - size) / 2f
        val oy = (height - size) / 2f

        when (mode) {
            IconMode.STROKE -> {
                for (group in pathGroups) {
                    for (pathData in group) {
                        drawPath(canvas, pathData, scale, ox, oy, strokePaint)
                    }
                }
            }

            IconMode.FILL -> {
                for (group in pathGroups) {
                    for (pathData in group) {
                        drawPath(canvas, pathData, scale, ox, oy, fillPaint)
                    }
                }
            }

            IconMode.MIXED -> {
                // First 3 groups: stroke, rest: fill (matching macOS convention)
                for ((i, group) in pathGroups.withIndex()) {
                    val paint = if (i < 3) strokePaint else fillPaint
                    for (pathData in group) {
                        drawPath(canvas, pathData, scale, ox, oy, paint)
                    }
                }
            }
        }
    }

    private fun drawPath(canvas: Canvas, pathData: String, scale: Float, ox: Float, oy: Float, paint: Paint) {
        val parsed = PathParser.createPathFromPathData(pathData)
        val matrix = Matrix().apply {
            postScale(scale, scale)
            postTranslate(ox, oy)
        }
        parsed.transform(matrix)
        canvas.drawPath(parsed, paint)
    }
}
