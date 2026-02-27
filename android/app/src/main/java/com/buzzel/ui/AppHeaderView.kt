package com.buzzel.ui

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

class AppHeaderView(
    context: Context,
) : LinearLayout(context) {
    private val handler = Handler(Looper.getMainLooper())
    private val titleLabel: TextView
    private val badge: TextView
    private val trailingIcon: SVGIconView
    private val logo: BuzzelLogoView

    private var currentTitle: String = ""
    private var isAnimating = false

    var onTrailingIconClick: (() -> Unit)? = null
    var onLogoClick: (() -> Unit)? = null

    private val leadingGroup: LinearLayout

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val dp = { value: Int -> dp(context, value) }

        setPadding(dp(20), dp(15), dp(20), dp(15))

        // Leading group (logo + title)
        leadingGroup =
            LinearLayout(context).apply {
                this.orientation = HORIZONTAL
                this.gravity = Gravity.CENTER_VERTICAL
                setOnClickListener { onLogoClick?.invoke() }
            }

        // Logo
        logo = BuzzelLogoView(context)
        leadingGroup.addView(
            logo,
            LayoutParams(dp(16), dp(16)).apply {
                marginEnd = dp(10)
            },
        )

        // Title
        titleLabel =
            TextView(context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
                setTextColor(AppColors.text)
                typeface = Brand.typeface
            }
        leadingGroup.addView(titleLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))

        addView(leadingGroup, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))

        // Badge
        badge =
            TextView(context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(AppColors.secondary)
                typeface = Brand.typeface
                setPadding(dp(10), dp(5), dp(10), dp(5))
                background =
                    GradientDrawable().apply {
                        setColor(AppColors.withAlpha(AppColors.secondary, 26)) // 10%
                        cornerRadius = dp(5).toFloat()
                    }
                visibility = View.GONE
            }
        addView(
            badge,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(10)
            },
        )

        // Spacer
        addView(View(context), LayoutParams(0, 0, 1f))

        // Trailing icon
        trailingIcon = SVGIconView(context)
        trailingIcon.isClickable = true
        trailingIcon.isFocusable = true
        trailingIcon.setOnClickListener { onTrailingIconClick?.invoke() }
        addView(trailingIcon, LayoutParams(dp(25), dp(25)))
    }

    fun setTitle(title: String) {
        if (currentTitle == title) return
        if (currentTitle.isEmpty()) {
            currentTitle = title
            titleLabel.text = title
            return
        }
        if (isAnimating) {
            currentTitle = title
            titleLabel.text = title
            return
        }
        animateTitle(title)
    }

    fun setBadge(text: String?) {
        if (text.isNullOrEmpty()) {
            badge.visibility = View.GONE
        } else {
            badge.text = text
            badge.visibility = View.VISIBLE
        }
    }

    fun setLeadingClickable(clickable: Boolean) {
        leadingGroup.isClickable = clickable
        leadingGroup.isFocusable = clickable
    }

    fun setTrailingIcon(
        pathGroups: Array<Array<String>>,
        mode: SVGIconView.IconMode,
        color: Int,
        size: Int = 25,
    ) {
        trailingIcon.pathGroups = pathGroups
        trailingIcon.mode = mode
        trailingIcon.iconColor = color
        val dp = dp(context, size)
        trailingIcon.layoutParams = LayoutParams(dp, dp)
    }

    fun setTrailingIconEnabled(enabled: Boolean) {
        trailingIcon.isEnabled = enabled
        trailingIcon.iconOpacity = if (enabled) 1f else 0.3f
        trailingIcon.visibility = if (enabled) View.VISIBLE else View.GONE
    }

    // Typewriter animation: delete chars then type new chars, 35ms per step
    private fun animateTitle(newTitle: String) {
        isAnimating = true
        val oldText = currentTitle
        currentTitle = newTitle

        val deleteCount = oldText.length
        val typeCount = newTitle.length
        val total = deleteCount + typeCount
        val interval = 35L

        for (step in 0 until total) {
            handler.postDelayed({
                if (step < deleteCount) {
                    titleLabel.text = oldText.substring(0, deleteCount - step - 1)
                } else {
                    titleLabel.text = newTitle.substring(0, step - deleteCount + 1)
                }
                if (step == total - 1) {
                    isAnimating = false
                }
            }, interval * step)
        }
    }
}
