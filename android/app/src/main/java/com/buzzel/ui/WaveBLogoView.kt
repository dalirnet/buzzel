package com.buzzel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.view.View
import androidx.core.graphics.PathParser
import kotlin.math.min

class WaveBLogoView(context: Context) : View(context) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    companion object {
        private const val PATH_DATA =
            "M170 86 C140 86 130 120 150 150 C170 180 170 200 150 230 C110 290 130 370 200 400 C270 430 370 400 380 320 C390 240 340 190 270 190 C220 190 180 230 180 280"
        private const val VIEWBOX = 512f
        private const val STROKE_IN_VIEWBOX = 64f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = min(width, height).toFloat()
        val scale = size / VIEWBOX

        paint.color = AppColors.text
        paint.strokeWidth = STROKE_IN_VIEWBOX * scale

        val path = PathParser.createPathFromPathData(PATH_DATA)
        val matrix = Matrix().apply { postScale(scale, scale) }
        path.transform(matrix)

        canvas.drawPath(path, paint)
    }
}
