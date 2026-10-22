package app.backupduck

import android.app.Activity
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Opt-in native line-layout evidence alongside full-resolution Catalog screenshots. */
internal object CatalogTextAudit {
    var enabled = false
    var staticCapture = false
    private val attached = java.util.Collections.newSetFromMap(java.util.WeakHashMap<View, Boolean>())

    fun attach(activity: Activity) {
        if (!enabled || activity is CatalogActivity) return
        val root = activity.window.decorView
        if (!attached.add(root)) return
        val write = Runnable {
            if (!activity.isDestroyed && root.isAttachedToWindow && root.hasWindowFocus()) {
                // This source set only displays synthetic pairing credentials.
                val secure = android.view.WindowManager.LayoutParams.FLAG_SECURE
                if (staticCapture && activity.window.attributes.flags and secure != 0) activity.window.clearFlags(secure)
                val texts = JSONArray()
                val geometry = JSONArray()
                fun visit(view: View) {
                    val visible = Rect()
                    if (!view.isShown || !view.getGlobalVisibleRect(visible)) return
                    if (view is DuckStepMark || view is DuckStepProgress ||
                        view is com.google.android.material.appbar.MaterialToolbar ||
                        view is com.google.android.material.navigation.NavigationBarView) {
                        val entry = JSONObject().put("class", view.javaClass.simpleName)
                            .put("bounds", JSONArray(listOf(visible.left, visible.top, visible.right, visible.bottom)))
                            .put("description", view.contentDescription)
                        if (view is DuckStepMark) {
                            val mark = view.getChildAt(0) as android.widget.ImageView
                            val rect = Rect(); mark.getGlobalVisibleRect(rect)
                            entry.put("imageBounds", JSONArray(listOf(rect.left, rect.top, rect.right, rect.bottom)))
                                .put("alpha", mark.alpha).put("contrastTint", mark.imageTintList != null)
                        }
                        geometry.put(entry)
                    }
                    if (view is TextView) view.layout?.let { layout ->
                        val lines = JSONArray()
                        for (line in 0 until layout.lineCount) {
                            lines.put(layout.text.subSequence(layout.getLineStart(line), layout.getLineEnd(line)).toString().trimEnd())
                        }
                        texts.put(JSONObject().put("text", view.text.toString()).put("lines", lines)
                            .put("breakStrategy", view.breakStrategy).put("hyphenation", view.hyphenationFrequency)
                            .put("bounds", visible.toShortString()).put("class", view.javaClass.simpleName))
                    }
                    if (view is ViewGroup) for (index in 0 until view.childCount) visit(view.getChildAt(index))
                }
                // A pushed destination covers the root page, which remains attached beneath it.
                val page = (activity as? BackupDuckActivity)?.supportFragmentManager?.primaryNavigationFragment?.view
                visit(page ?: root)
                val result = JSONObject().put("scenario", CatalogRuntime.current?.id)
                    .put("capturedAt", System.currentTimeMillis()).put("texts", texts).put("geometry", geometry)
                val directory = activity.getExternalFilesDir(null) ?: return@Runnable
                val temporary = File(directory, "text-layout.tmp")
                temporary.writeText(result.toString(2))
                temporary.renameTo(File(directory, "text-layout.json"))
            }
        }
        fun schedule() { root.removeCallbacks(write); root.postDelayed(write, 200) }
        root.viewTreeObserver.addOnGlobalLayoutListener { schedule() }
        root.viewTreeObserver.addOnScrollChangedListener { schedule() }
        schedule()
    }
}
