package com.buzzel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.view.View
import androidx.core.graphics.PathParser
import kotlin.math.min

class WaveBLogoView(
    context: Context,
    private var logoColor: Int = AppColors.text,
) : View(context) {
    private val paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = min(width, height).toFloat()
        val scale = size / Brand.logoViewbox

        paint.color = logoColor

        val path = PathParser.createPathFromPathData(Brand.logoPath)
        path.transform(Matrix().apply { postScale(scale, scale) })
        canvas.drawPath(path, paint)
    }
}
