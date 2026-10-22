package app.backupduck

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.SystemClock
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.coordinatorlayout.widget.CoordinatorLayout
import com.google.android.material.bottomsheet.BottomSheetBehavior
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Catalog-only vsync trace. The tiny frame counter keeps screenrecord sampling idle frames. */
internal object CatalogSheetTrace {
    private var active: Trace? = null
    fun start(activity: NativePhotoViewerActivity) {
        stop(activity)
        active = Trace(activity).also { it.start() }
    }
    fun stop(activity: NativePhotoViewerActivity) {
        active?.let { trace ->
            trace.stop()
            File(activity.getExternalFilesDir(null), "sheet-trace.json").writeText(trace.rows.toString())
        }
        active = null
    }
    private class Trace(val activity: NativePhotoViewerActivity) : Drawable(), Choreographer.FrameCallback {
        val rows = JSONArray()
        private val root = activity.window.decorView
        private val paint = Paint()
        private var running = false
        private var frame = 0
        private var frameTime = 0L
        private var photo: ImageView? = null
        private var sheet: View? = null
        private fun descendants(view: View): Sequence<View> = sequence {
            yield(view)
            if (view is ViewGroup) for (i in 0 until view.childCount) yieldAll(descendants(view.getChildAt(i)))
        }
        fun start() {
            photo = descendants(root).filterIsInstance<ImageView>().firstOrNull {
                it.transitionName?.startsWith("received-photo:") == true && it.isShown && it.getGlobalVisibleRect(android.graphics.Rect())
            }
            sheet = descendants(root).firstOrNull {
                (it.layoutParams as? CoordinatorLayout.LayoutParams)?.behavior is BottomSheetBehavior<*>
            }
            // Invalidate only the counter, rather than marking the whole photo
            // dirty on idle frames. Cache the fixed trace targets outside draws.
            running = true; setBounds(root.width - 72, 100, root.width - 8, 108)
            root.overlay.add(this); Choreographer.getInstance().postFrameCallback(this)
        }
        fun stop() { running = false; Choreographer.getInstance().removeFrameCallback(this); root.overlay.remove(this) }
        override fun doFrame(frameTimeNanos: Long) {
            if (!running || activity.isDestroyed) { stop(); return }
            frame++; frameTime = frameTimeNanos
            invalidateSelf(); Choreographer.getInstance().postFrameCallback(this)
        }
        override fun draw(canvas: Canvas) {
            val photo = photo ?: return
            val sheet = sheet ?: return
            val drawable = photo.drawable ?: return
            val rect = RectF(0f, 0f, drawable.intrinsicWidth.toFloat(), drawable.intrinsicHeight.toFloat())
            photo.imageMatrix.mapRect(rect)
            val location = IntArray(2); photo.getLocationOnScreen(location)
            rect.offset(location[0] + photo.paddingLeft.toFloat(), location[1] + photo.paddingTop.toFloat())
            val behavior = (sheet.layoutParams as CoordinatorLayout.LayoutParams).behavior as BottomSheetBehavior<*>
            rows.put(JSONObject().put("frame", frame).put("vsyncNs", frameTime).put("uptimeMs", SystemClock.uptimeMillis())
                .put("sheetTop", sheet.top).put("sheetState", behavior.state)
                .put("photo", JSONArray(listOf(rect.left, rect.top, rect.right, rect.bottom)))
                .put("paddingTop", photo.paddingTop).put("paddingBottom", photo.paddingBottom))
            // A binary counter outside the media measurement region identifies actual rendered frames.
            for (bit in 0 until 16) {
                paint.color = if ((frame shr bit) and 1 == 1) android.graphics.Color.WHITE else android.graphics.Color.BLACK
                canvas.drawRect(root.width - 72f + bit * 4, 100f, root.width - 68f + bit * 4, 108f, paint)
            }
        }
        override fun setAlpha(alpha: Int) { paint.alpha = alpha }
        override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter }
        @Deprecated("Deprecated in Java") override fun getOpacity() = PixelFormat.TRANSLUCENT
    }
}
