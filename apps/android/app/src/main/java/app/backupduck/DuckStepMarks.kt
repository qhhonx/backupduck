package app.backupduck

import android.content.Context
import android.content.res.ColorStateList
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout

/** Keep the complete welcome journey above its fixed action area at normal text size. */
internal object DuckFirstRunMetrics {
    fun heroHeight(context: Context) = context.dp(if (context.resources.configuration.fontScale > 1.15f) 140 else 160)
    fun heroSize(context: Context) = context.dp(if (context.resources.configuration.fontScale > 1.15f) 112 else 144)
}

/** V6 optical metrics: original silhouettes share one centre slot, with no offsets or numerals. */
internal class DuckStepMark(context: Context, number: Int, private val current: Boolean = true, compact: Boolean = false) : FrameLayout(context) {
    private val image = ImageView(context)
    private val contrast = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) = updateContrast()
    }
    init {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        val (drawable, width, height) = when (number) {
            1 -> Triple(R.drawable.mark_circle, if (compact) 32 else 24, if (compact) 32 else 24)
            2 -> Triple(R.drawable.mark_wing, if (compact) 48 else 36, if (compact) 24 else 18)
            else -> Triple(R.drawable.mark_sparkle, if (compact) 44 else 34, if (compact) 44 else 34)
        }
        image.setImageResource(drawable)
        val scale = if (compact) 0.8f else 1f
        addView(image, LayoutParams(context.dp((width * scale).toInt()), context.dp((height * scale).toInt()), Gravity.CENTER))
        layoutParams = LinearLayout.LayoutParams(context.dp(36), context.dp(36))
        updateContrast()
    }
    private fun updateContrast() {
        val high = ReceiverEnvironment.stepMarkHighContrast ?: (Settings.Secure.getInt(context.contentResolver,
            "high_text_contrast_enabled", 0) == 1)
        // V6: inactive silhouettes use the faint neutral text role, with the
        // stronger secondary text fallback for increased contrast.
        image.imageTintList = if (current) null else ColorStateList.valueOf(context.getColor(
            if (high) R.color.duck_role_secondary_text else R.color.duck_role_tertiary_text))
        image.alpha = 1f
    }
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        context.contentResolver.registerContentObserver(Settings.Secure.getUriFor("high_text_contrast_enabled"), false, contrast)
        updateContrast()
    }
    override fun onDetachedFromWindow() {
        context.contentResolver.unregisterContentObserver(contrast)
        super.onDetachedFromWindow()
    }
}

/** One localized progress node; its decorative children never repeat the announcement. */
internal class DuckStepProgress(context: Context, current: Int) : LinearLayout(context) {
    init {
        orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        contentDescription = context.getString(R.string.onb_step_of, current)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = true
        for (number in 1..3) addView(DuckStepMark(context, number, number == current),
            LayoutParams(context.dp(36), context.dp(36)).apply {
                if (number < 3) marginEnd = context.token(R.dimen.duck_space_small)
            })
    }
}
