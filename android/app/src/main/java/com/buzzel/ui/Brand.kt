package com.buzzel.ui

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import org.json.JSONObject

object Brand {
    var logoPath = ""
        private set
    var logoPathReversed = ""
        private set
    var logoViewbox = 512f
        private set
    var logoStrokeWidth = 46f
        private set

    lateinit var typeface: Typeface
        private set

    var splashLogoScale = 0.35f
        private set
    var splashLogoColorLight = Color.WHITE
        private set
    var splashLogoColorDark = Color.BLACK
        private set

    private var loaded = false

    fun load(context: Context) {
        if (loaded) return
        loaded = true

        typeface =
            try {
                Typeface.createFromAsset(context.assets, "sofia-sans.ttf")
            } catch (_: Exception) {
                Typeface.DEFAULT
            }

        val root =
            JSONObject(
                context.assets
                    .open("brand.json")
                    .bufferedReader()
                    .readText(),
            )

        val logo = root.getJSONObject("logo")
        logoPath = logo.getString("path")
        logoPathReversed = reversePath(logoPath)
        logoViewbox = logo.getDouble("viewbox").toFloat()
        logoStrokeWidth = logo.getDouble("stroke_width").toFloat()

        val splash = root.getJSONObject("splash")
        splashLogoScale = splash.getDouble("logo_scale").toFloat()
        splashLogoColorLight = Color.parseColor(splash.getString("logo_color_light"))
        splashLogoColorDark = Color.parseColor(splash.getString("logo_color_dark"))
    }

    private fun reversePath(d: String): String {
        val tokens =
            d
                .replace(",", " ")
                .replace(Regex("([A-Za-z])"), " $1 ")
                .trim()
                .split("\\s+".toRegex())
        var i = 0

        if (tokens[i] == "M") i++
        val startX = tokens[i++]
        val startY = tokens[i++]

        data class Curve(
            val c1x: String,
            val c1y: String,
            val c2x: String,
            val c2y: String,
            val ex: String,
            val ey: String,
        )

        val curves = mutableListOf<Curve>()
        while (i < tokens.size) {
            if (tokens[i] == "C" || tokens[i] == "c") i++
            curves.add(Curve(tokens[i], tokens[i + 1], tokens[i + 2], tokens[i + 3], tokens[i + 4], tokens[i + 5]))
            i += 6
        }

        val points = mutableListOf(Pair(startX, startY))
        curves.forEach { points.add(Pair(it.ex, it.ey)) }

        val sb = StringBuilder()
        sb.append("M${points.last().first} ${points.last().second}")
        for (j in curves.indices.reversed()) {
            val c = curves[j]
            val ep = points[j]
            sb.append("C${c.c2x} ${c.c2y} ${c.c1x} ${c.c1y} ${ep.first} ${ep.second}")
        }
        return sb.toString()
    }
}
