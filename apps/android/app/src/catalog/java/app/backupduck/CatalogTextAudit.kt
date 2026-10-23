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
                if (staticCapture && activity !is BrowserManagementActivity && activity.window.attributes.flags and secure != 0) activity.window.clearFlags(secure)
                val texts = JSONArray()
                val geometry = JSONArray()
                fun visit(view: View) {
                    val visible = Rect()
                    if (!view.isShown || !view.getGlobalVisibleRect(visible)) return
                    if (view is DuckStepMark || view is DuckStepProgress ||
                        view is com.google.android.material.appbar.MaterialToolbar ||
                        view is com.google.android.material.navigation.NavigationBarView ||
                        view.tag in listOf("duck.discovery", "duck.attention")) {
                        val entry = JSONObject().put("class", view.javaClass.simpleName)
                            .put("bounds", JSONArray(listOf(visible.left, visible.top, visible.right, visible.bottom)))
                            .put("description", view.contentDescription).put("tag", view.tag)
                        if (view is DuckStepMark) {
                            val mark = view.getChildAt(0) as android.widget.ImageView
                            val rect = Rect(); mark.getGlobalVisibleRect(rect)
                            entry.put("imageBounds", JSONArray(listOf(rect.left, rect.top, rect.right, rect.bottom)))
                                .put("alpha", mark.alpha).put("contrastTint", mark.imageTintList != null)
                        }
                        geometry.put(entry)
                    }
                    if (view is androidx.recyclerview.widget.RecyclerView && view.id == R.id.receiver_photos_list) {
                        val adapter = view.adapter as? androidx.recyclerview.widget.ListAdapter<*, *>
                        val rows = JSONArray()
                        adapter?.currentList?.forEach { row -> when (row) {
                            is PhotoRow.Day -> rows.put(JSONObject().put("day", row.epochDay))
                            is PhotoRow.Tile -> rows.put(JSONObject().put("id", row.item.id).put("cursor", row.item.cursor).put("changed", row.item.latestChangeMs))
                            else -> rows.put(JSONObject().put("role", row?.javaClass?.simpleName))
                        } }
                        val manager = view.layoutManager as? androidx.recyclerview.widget.LinearLayoutManager
                        geometry.put(JSONObject().put("class", "PhotoRows").put("rows", rows)
                            .put("firstVisible", manager?.findFirstVisibleItemPosition()).put("lastVisible", manager?.findLastVisibleItemPosition()))
                    }
                    if (view is TextView) view.layout?.let { layout ->
                        val lines = JSONArray()
                        for (line in 0 until layout.lineCount) {
                            lines.put(layout.text.subSequence(layout.getLineStart(line), layout.getLineEnd(line)).toString().trimEnd())
                        }
                        val protectedText = view.transformationMethod is android.text.method.PasswordTransformationMethod || view.tag == "browser.code"
                        texts.put(JSONObject().put("text", if (protectedText) "•".repeat(view.text.length) else view.text.toString())
                            .put("credentialVisible", view.tag == "browser.code" && view.text.any { it.isDigit() }).put("lines", if (protectedText) JSONArray().put("•".repeat(view.text.length)) else lines)
                            .put("breakStrategy", view.breakStrategy).put("hyphenation", view.hyphenationFrequency)
                            .put("bounds", visible.toShortString()).put("class", view.javaClass.simpleName))
                    }
                    if (view is ViewGroup) for (index in 0 until view.childCount) visit(view.getChildAt(index))
                }
                // A pushed destination covers the root page, which remains attached beneath it.
                val page = (activity as? BackupDuckActivity)?.supportFragmentManager?.primaryNavigationFragment?.view
                visit(page ?: root)
                val result = JSONObject().put("scenario", CatalogRuntime.current?.id)
                    .put("capturedAt", System.currentTimeMillis()).put("windowSecure", activity.window.attributes.flags and secure != 0).put("texts", texts).put("geometry", geometry)
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
