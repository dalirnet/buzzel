package com.buzzel.ui

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.provider.Settings
import android.util.TypedValue

object AppColors {
    // Resolved from system theme
    var text: Int = Color.BLACK
        private set
    var secondary: Int = Color.GRAY
        private set
    var surface: Int = Color.WHITE
        private set
    var background: Int = Color.LTGRAY
        private set
    var border: Int = Color.LTGRAY
        private set
    var accent: Int = Color.BLUE
        private set

    // Fixed system colors
    val green: Int = Color.rgb(52, 199, 89)
    val yellow: Int = Color.rgb(255, 204, 0)
    val orange: Int = Color.rgb(255, 149, 0)
    val red: Int = Color.rgb(255, 59, 48)
    val gray: Int = Color.rgb(142, 142, 147)
    val onButton: Int = Color.WHITE

    // Muted adaptive colors for power button fill
    var mutedGray: Int = 0
        private set
    var mutedYellow: Int = 0
        private set
    var mutedOrange: Int = 0
        private set
    var mutedGreen: Int = 0
        private set
    var mutedRed: Int = 0
        private set

    fun resolve(context: Context) {
        val dark = isDarkMode(context)

        if (dark) {
            text = resolveAttr(context, android.R.attr.textColorPrimary, Color.WHITE)
            secondary = resolveAttr(context, android.R.attr.textColorSecondary, Color.rgb(142, 142, 147))
            accent = resolveAttr(context, android.R.attr.colorAccent, Color.rgb(0, 122, 255))
            surface = Color.rgb(28, 28, 30)
            background = Color.rgb(44, 44, 46)
        } else {
            text = Color.BLACK
            secondary = Color.GRAY
            accent = resolveAttr(context, android.R.attr.colorAccent, Color.rgb(0, 122, 255))
            surface = Color.WHITE
            background = Color.LTGRAY
        }

        border = Color.argb(30, Color.red(text), Color.green(text), Color.blue(text))

        mutedGray = if (dark) Color.rgb(115, 115, 122) else Color.rgb(140, 140, 148)
        mutedYellow = if (dark) Color.rgb(235, 191, 20) else Color.rgb(242, 199, 26)
        mutedOrange = if (dark) Color.rgb(235, 128, 20) else Color.rgb(242, 140, 26)
        mutedGreen = if (dark) Color.rgb(46, 179, 89) else Color.rgb(51, 191, 97)
        mutedRed = if (dark) Color.rgb(217, 64, 56) else Color.rgb(230, 71, 64)
    }

    fun isDarkMode(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ — standard night mode flag is reliable
            val mode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            return mode == Configuration.UI_MODE_NIGHT_YES
        }
        // Older devices — vendors (e.g. Nokia Android 9) may not set uiMode correctly
        val themeMode =
            try {
                Settings.Secure.getInt(context.contentResolver, "theme_mode", 0)
            } catch (_: Exception) {
                0
            }
        if (themeMode != 0) return themeMode >= 2
        val mode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }

    fun withAlpha(
        color: Int,
        alpha: Int,
    ): Int = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

    private fun resolveAttr(
        context: Context,
        attr: Int,
        fallback: Int,
    ): Int {
        val tv = TypedValue()
        return if (context.theme.resolveAttribute(attr, tv, true)) {
            if (tv.type >= TypedValue.TYPE_FIRST_COLOR_INT && tv.type <= TypedValue.TYPE_LAST_COLOR_INT) {
                tv.data
            } else {
                try {
                    context.getColor(tv.resourceId)
                } catch (_: Exception) {
                    fallback
                }
            }
        } else {
            fallback
        }
    }
}
