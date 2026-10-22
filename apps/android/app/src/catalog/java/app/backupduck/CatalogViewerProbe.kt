package app.backupduck

import android.graphics.Rect
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import org.json.JSONObject
import java.io.File

/** Optional native multi-pointer input for device review; no system settings or media writes. */
internal object CatalogViewerProbe {
    var pending: String? = null
    private var current = java.lang.ref.WeakReference<NativePhotoViewerActivity>(null)
    fun install(context: android.content.Context) {
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
                val activity = current.get()?.takeUnless { it.isFinishing || it.isDestroyed } ?: return
                val root = activity.window.decorView
                when (intent.getStringExtra("gesture")) {
                    "doubleTap" -> {
                        val down = SystemClock.uptimeMillis()
                        fun tap() {
                            for (action in intArrayOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
                                val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, root.width / 2f, root.height / 2f, 0)
                                event.source = InputDevice.SOURCE_TOUCHSCREEN
                                activity.dispatchTouchEvent(event); event.recycle()
                            }
                        }
                        tap(); root.postDelayed({ tap() }, 120)
                        root.postDelayed({ audit(activity, "doubleTap") }, 450)
                    }
                    "audit" -> audit(activity, "audit")
                    "settleStart" -> CatalogSheetTrace.start(activity)
                    "settleStop" -> CatalogSheetTrace.stop(activity)
                }
            }
        }
        val filter = android.content.IntentFilter("app.backupduck.catalog.VIEWER_PROBE")
        if (android.os.Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, android.content.Context.RECEIVER_EXPORTED)
        else { @Suppress("DEPRECATION") context.registerReceiver(receiver, filter) }
    }
    private fun photo(view: View): ImageView? {
        if (view is ImageView && view.transitionName?.startsWith("received-photo:") == true && view.getGlobalVisibleRect(Rect())) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) photo(view.getChildAt(i))?.let { return it }
        return null
    }
    private fun audit(activity: NativePhotoViewerActivity, kind: String) {
        val photo = photo(activity.window.decorView) ?: return
        val values = FloatArray(9); photo.imageMatrix.getValues(values)
        File(activity.getExternalFilesDir(null), "viewer-probe.json").writeText(JSONObject()
            .put("probe", kind).put("photo", photo.transitionName).put("scaleType", photo.scaleType.name)
            .put("paddingTop", photo.paddingTop).put("paddingBottom", photo.paddingBottom)
            .put("width", photo.width).put("height", photo.height)
            .put("matrix", org.json.JSONArray(values.toList())).toString(2))
    }
    fun attach(activity: NativePhotoViewerActivity) {
        current = java.lang.ref.WeakReference(activity)
        if (pending != "pinch") return
        pending = null
        val root = activity.window.decorView
        root.postDelayed({
            if (activity.isFinishing || activity.isDestroyed) return@postDelayed
            val photo = photo(root) ?: return@postDelayed
            val down = SystemClock.uptimeMillis()
            val x = root.width / 2f; val y = root.height / 2f
            fun send(action: Int, count: Int, distance: Float) {
                val properties = Array(count) { i -> MotionEvent.PointerProperties().apply { id = i; toolType = MotionEvent.TOOL_TYPE_FINGER } }
                val coords = Array(count) { i -> MotionEvent.PointerCoords().apply {
                    this.x = x + if (i == 0) -distance / 2 else distance / 2
                    this.y = y; pressure = 1f; size = 1f
                } }
                val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, count, properties, coords,
                    0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
                activity.dispatchTouchEvent(event); event.recycle()
            }
            send(MotionEvent.ACTION_DOWN, 1, x / 2)
            send(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, x / 2)
            fun frame(step: Int) {
                if (activity.isFinishing || activity.isDestroyed) return
                val distance = x / 2 + x * step / 16
                send(MotionEvent.ACTION_MOVE, 2, distance)
                if (step < 16) root.postOnAnimation { frame(step + 1) } else {
                    send(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, distance)
                    send(MotionEvent.ACTION_UP, 1, distance)
                    audit(activity, "native-multipointer-pinch")
                }
            }
            root.postOnAnimation { frame(1) }
        }, 2200)
    }
}
