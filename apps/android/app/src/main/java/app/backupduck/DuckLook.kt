package app.backupduck

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.DrawableRes
import com.google.android.material.R as M
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView

/**
 * The proposed visual language (design/visual-language.md) in Material 3, shown
 * behind the catalog's look switch ([ReceiverEnvironment.proposedLook]) next to
 * today's look. Material roles from the generated scheme
 * (ThemeOverlay.BackupDuck.Scheme), one type scale, one card style, a filled
 * button for the screen's one primary action, tonal buttons inside cards and
 * soft status pills.
 */
internal object DuckLook {
    val on: Boolean get() = ReceiverEnvironment.proposedLook

    /** One card radius for cards and photo groups. */
    const val RADIUS_DP = 20

    /** Applies the generated Material 3 scheme to an activity or dialog theme before its views are built. */
    fun applyScheme(context: Context) { context.theme.applyStyle(R.style.ThemeOverlay_BackupDuck_Scheme, true) }
}

/** The one card: a filled Material card on the surface, no border, 16dp padding. */
internal fun Context.lookCard(parent: LinearLayout, padding: Int = 16, top: Int = 0): LinearLayout {
    val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(padding), dp(padding), dp(padding), dp(padding)) }
    parent.addView(MaterialCardView(this).apply {
        radius = dp(DuckLook.RADIUS_DP).toFloat(); cardElevation = 0f; strokeWidth = 0
        setCardBackgroundColor(themeColor(M.attr.colorSurfaceContainer)); addView(body)
    }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(top) })
    return body
}

/** The screen's one primary action: a filled Material button. */
internal fun Context.lookFilled(text: String, action: () -> Unit) = MaterialButton(this).apply {
    this.text = text; minimumHeight = dp(48); setOnClickListener { action() }
}

/** An action inside a card: a tonal Material button, never link text. */
internal fun Context.lookTonal(text: String, action: () -> Unit) = MaterialButton(this).apply {
    this.text = text; minimumHeight = dp(40); insetTop = 0; insetBottom = 0
    backgroundTintList = ColorStateList.valueOf(themeColor(M.attr.colorSecondaryContainer))
    setTextColor(themeColor(M.attr.colorOnSecondaryContainer)); elevation = 0f; stateListAnimator = null
    setOnClickListener { action() }
}

/** A soft status pill: a colored dot and neutral text on a container, optionally tappable. */
internal fun Context.lookPill(text: String, dot: Int?, action: (() -> Unit)? = null): TextView = TextView(this).apply {
    this.text = text; setTextAppearance(M.style.TextAppearance_Material3_LabelLarge)
    setTextColor(themeColor(M.attr.colorOnSurface)); gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(if (dot == null) 14 else 12), dp(8), dp(14), dp(8)); minHeight = dp(36)
    background = GradientDrawable().apply { cornerRadius = dp(18).toFloat(); setColor(themeColor(M.attr.colorSurfaceContainerHigh)) }
    dot?.let { color ->
        setCompoundDrawablesRelativeWithIntrinsicBounds(GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setSize(dp(8), dp(8)) }, null, null, null)
        compoundDrawablePadding = dp(8)
    }
    action?.let { run -> isClickable = true; isFocusable = true; setOnClickListener { run() } }
}

/** Text in a type role of the one scale, neutral unless secondary. */
internal fun Context.lookText(value: String, appearance: Int, secondary: Boolean = false) = TextView(this).apply {
    text = value; setTextAppearance(appearance)
    setTextColor(themeColor(if (secondary) M.attr.colorOnSurfaceVariant else M.attr.colorOnSurface))
}

/** A neutral title beside one colored glyph: how a problem or a state says its tone. */
internal fun Context.lookGlyphTitle(@DrawableRes icon: Int, tint: Int, title: String): LinearLayout = LinearLayout(this).apply {
    gravity = Gravity.CENTER_VERTICAL
    addView(ImageView(context).apply { setImageResource(icon); imageTintList = ColorStateList.valueOf(tint); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
        LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = dp(12) })
    addView(lookText(title, M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true }, LinearLayout.LayoutParams(0, -2, 1f))
}

/**
 * A mark on a photo: a white glyph with a soft shadow, no badge, as the system
 * Photos apps mark video and favorites. Cached per glyph and size.
 */
internal object PhotoGlyphs {
    private val cache = HashMap<String, Bitmap>()
    fun drawable(context: Context, @DrawableRes icon: Int, sizeDp: Int): Drawable {
        val key = "$icon:$sizeDp:${context.resources.displayMetrics.density}"
        val bitmap = cache.getOrPut(key) {
            val size = context.dp(sizeDp); val pad = context.dp(4)
            val glyph = Bitmap.createBitmap(size + pad * 2, size + pad * 2, Bitmap.Config.ARGB_8888)
            context.getDrawable(icon)!!.mutate().apply {
                // design-exception: media marks are white over photos in every theme (visual-language.md § Marks).
                setTint(android.graphics.Color.WHITE); setBounds(pad, pad, pad + size, pad + size); draw(Canvas(glyph))
            }
            val shadowPaint = Paint().apply { maskFilter = BlurMaskFilter(context.dp(3).toFloat(), BlurMaskFilter.Blur.NORMAL) }
            val offset = IntArray(2)
            val shadow = glyph.extractAlpha(shadowPaint, offset)
            Bitmap.createBitmap(glyph.width, glyph.height, Bitmap.Config.ARGB_8888).also { out ->
                val canvas = Canvas(out)
                // design-exception: the soft shadow under a media mark is black at 45% so the glyph reads on light photos.
                canvas.drawBitmap(shadow, offset[0].toFloat(), offset[1].toFloat() + context.dp(1), Paint().apply { color = android.graphics.Color.BLACK; alpha = 115 })
                canvas.drawBitmap(glyph, 0f, 0f, null)
                shadow.recycle(); glyph.recycle()
            }
        }
        return BitmapDrawable(context.resources, bitmap)
    }
}
