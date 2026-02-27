package com.buzzel.ui

import android.content.Context
import android.graphics.Typeface
import org.json.JSONObject

object Brand {
    var logoPath = ""
        private set
    var logoViewbox = 512f
        private set

    lateinit var typeface: Typeface
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
        logoViewbox = logo.getDouble("viewbox").toFloat()
    }
}
