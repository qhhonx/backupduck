package app.backupduck

import android.content.Context
import android.content.res.ColorStateList
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.DrawableRes

/**
 * Material 3 settings rows for `design/settings.md`: section headers, a
 * monochrome leading icon, headline and supporting text, an optional trailing
 * control and no chevrons, as Android system settings do.
 */
internal fun Context.settingsSection(parent: LinearLayout, title: String): LinearLayout {
    if (DuckLook.on) {
        // The proposed look: a neutral section title above one card (visual-language.md).
        parent.addView(TextView(this).apply {
            text = title; isFocusable = false; isAccessibilityHeading = true
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleSmall)
            setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurfaceVariant))
            setPadding(dp(20), dp(20), dp(20), dp(8))
        })
        val card = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(4), 0, dp(4)) }
        parent.addView(com.google.android.material.card.MaterialCardView(this).apply {
            radius = dp(DuckLook.RADIUS_DP).toFloat(); cardElevation = 0f; strokeWidth = 0
            setCardBackgroundColor(themeColor(com.google.android.material.R.attr.colorSurfaceContainer)); addView(card)
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(16); marginEnd = dp(16) })
        return card
    }
    parent.addView(TextView(this).apply {
        text = title
        setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleSmall)
        setTextColor(themeColor(androidx.appcompat.R.attr.colorPrimary))
        setPadding(dp(16), dp(20), dp(16), dp(8))
        isFocusable = false
        isAccessibilityHeading = true
    })
    return LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }.also { parent.addView(it) }
}

/**
 * Adds a row; returns its supporting text view so callers can refresh the value.
 * [tile] colors the icon's tile in the proposed look's Settings rows; elsewhere icons stay monochrome.
 */
internal fun Context.settingsItem(parent: LinearLayout, @DrawableRes icon: Int, title: String, supporting: String? = null,
    trailing: View? = null, tile: Int? = null, action: (() -> Unit)? = null): TextView {
    val support = TextView(this).apply {
        setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium)
        setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurfaceVariant))
        text = supporting
        visibility = if (supporting.isNullOrEmpty()) View.GONE else View.VISIBLE
    }
    val row = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(if (supporting.isNullOrEmpty()) 56 else 72)
        setPadding(dp(16), dp(8), dp(16), dp(8))
        if (action != null) {
            isClickable = true; isFocusable = true
            background = selectableBackground()
            setOnClickListener { action() }
        }
    }
    if (DuckLook.on && tile != null) row.addView(ImageView(this).apply {
        // A colored tile with the glyph in the surface color, as system settings mark their rows.
        setImageResource(icon); setPadding(dp(6), dp(6), dp(6), dp(6))
        imageTintList = ColorStateList.valueOf(themeColor(com.google.android.material.R.attr.colorSurface))
        background = android.graphics.drawable.GradientDrawable().apply { cornerRadius = dp(10).toFloat(); setColor(tile) }
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }, LinearLayout.LayoutParams(dp(34), dp(34)).apply { marginEnd = dp(16) })
    else row.addView(ImageView(this).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(themeColor(com.google.android.material.R.attr.colorOnSurfaceVariant))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }, LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = dp(16) })
    val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    words.addView(TextView(this).apply {
        text = title
        setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge)
        setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurface))
    })
    words.addView(support)
    row.addView(words, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
    trailing?.let { row.addView(it, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(16) }) }
    parent.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
    return support
}

internal fun TextView.setSupporting(value: String?) {
    text = value
    visibility = if (value.isNullOrEmpty()) View.GONE else View.VISIBLE
}

private fun Context.selectableBackground() = TypedValue().let { value ->
    theme.resolveAttribute(android.R.attr.selectableItemBackground, value, true)
    getDrawable(value.resourceId)
}
