package app.backupduck

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.SystemClock
import android.widget.ImageView

/** Keep a BitmapDrawable so shared-element posters and zoom retain the same image contract. */
private class RefiningPhoto(resources: Resources, bitmap: Bitmap, previous: Bitmap,
    private val duration: Int) : BitmapDrawable(resources, bitmap) {
    private var underlay: BitmapDrawable? = BitmapDrawable(resources, previous)
    private val started = SystemClock.uptimeMillis()
    override fun draw(canvas: Canvas) {
        val fraction = ((SystemClock.uptimeMillis() - started).toFloat() / duration).coerceIn(0f, 1f)
        if (fraction >= 1f) underlay = null
        underlay?.let {
            it.bounds = bounds
            it.alpha = alpha
            it.draw(canvas)
        }
        val opacity = alpha
        alpha = (opacity * fraction).toInt()
        super.draw(canvas)
        alpha = opacity
        if (underlay != null) invalidateSelf()
    }
}

/** Fade sharper pixels over the receipt, with no transparent or empty intermediate frame. */
internal fun ImageView.showPhotoBitmap(bitmap: Bitmap, fade: Boolean = true) {
    val previous = (drawable as? BitmapDrawable)?.bitmap
    if (previous === bitmap) return
    setImageDrawable(if (fade && previous != null && context.photoAnimationsEnabled()) {
        RefiningPhoto(resources, bitmap, previous, resources.getInteger(R.integer.duck_motion_text_ms))
    } else BitmapDrawable(resources, bitmap))
}
