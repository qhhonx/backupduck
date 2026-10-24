package app.backupduck

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.LinearLayout
import android.widget.TextView
import android.view.View
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import com.google.android.material.R as M

/** Host policy uses the existing settings operation; the core still owns pruning. */
internal object ReceiverLogPolicy {
    @Synchronized fun apply(root: String) {
        val response = NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject
        val settings = response.getJSONObject("settings")
        if (settings.getInt("log_days") != 14) {
            val updated = JSONObject(settings.toString()).put("log_days", 14)
            NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root).put("settings", updated))
        }
    }
    fun read(root: String): JSONArray {
        apply(root)
        return NativeBridge.request(JSONObject().put("op", "receiver_logs").put("root", root)) as JSONArray
    }
}

internal fun Context.diagnosticFileName(uri: Uri, fallback: String): String = runCatching {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
        if (it.moveToFirst()) it.getString(0) else null
    }
}.getOrNull() ?: fallback

/** Read-only cleanup facts; identifiers and raw accessibility content never enter the export. */
internal fun Context.photosCleanupDiagnostics(): JSONObject {
    val facts = PhotosCleanup(this)
    val saved = getSharedPreferences("photos_cleanup", Context.MODE_PRIVATE)
    val observed = ReceiverEnvironment.cleanupOperations.state.value
    return JSONObject()
        .put("google_photos_app_version", ReceiverEnvironment.photosVersion(this) ?: JSONObject.NULL)
        .put("last_observation", observed.observation.takeUnless { it.isEmpty() || it == "idle" } ?: JSONObject.NULL)
        .put("screens_seen", observed.seen.takeIf { it.isNotEmpty() }?.let { JSONArray(it.sorted()) } ?: JSONObject.NULL)
        .put("enabled", facts.enabled)
        .put("pending", facts.pending)
        .put("last_result", facts.lastResult.takeIf { it.isNotEmpty() } ?: JSONObject.NULL)
        .put("last_reason", saved.getString("reason", null)?.takeIf { it.isNotEmpty() } ?: JSONObject.NULL)
        .put("last_freed_bytes", if (saved.contains("last_freed_bytes"))
            saved.getLong("last_freed_bytes", -1).takeIf { it >= 0 } ?: JSONObject.NULL else JSONObject.NULL)
        .put("last_completed_at_ms", facts.lastCompletedAt ?: JSONObject.NULL)
        .put("account_bound", facts.account.isNotEmpty())
        .put("cloud_backup_verified", false)
}

/** Preserves full log payloads and unresolved publication receipts alongside cleanup observations. */
internal fun Context.combinedDiagnostics(root: String): ByteArray = JSONObject()
    .put("schema_version", 1).put("source", "BackupDuck Pixel receiver")
    .put("exported_at_ms", ReceiverEnvironment.now())
    .put("receiver_log", ReceiverLogPolicy.read(root))
    .put("photos_saving_receipts", ReceiverEnvironment.diagnosticReceipts(this, root))
    .put("photos_cleanup", photosCleanupDiagnostics())
    .toString(2).toByteArray(Charsets.UTF_8)

internal class DiagnosticsScreen(private val activity: MainActivity, restored: Bundle, private val export: (DiagnosticsScreen) -> Unit) {
    val page = LookPage(activity, activity.getString(R.string.pref_diagnostics), "diagnostics")
    private val support: TextView
    private val recent = RecentActivityAdapter(activity)
    private val feedback = activity.lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true)
    private var loading: Job? = null
    init { with(activity) {
        page.state.putAll(restored)
        if (page.state.getString("export") == "busy") page.state.putString("export", "failure")
        ReceiverEnvironment.diagnosticInitialState?.let { if (restored.isEmpty) page.state.putAll(it) }
        page.body.addView(lookText(getString(R.string.diag_intro), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        val log = lookGroup(page.body)
        ((log.parent as android.view.View).layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_large)
        support = lookRow(log, R.drawable.ic_document, getString(R.string.diag_export), getString(R.string.diag_contents)) {
            if (page.state.getString("export") != "busy") export(this@DiagnosticsScreen)
        }
        lookSection(page.body, getString(R.string.diag_recent))
        page.body.addView(feedback)
        page.body.addView(RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@with)
            adapter = recent
            itemAnimator = null
            isNestedScrollingEnabled = false
        }, LinearLayout.LayoutParams(-1, -2))
        page.setOnDismissListener { loading?.cancel() }
        render()
        loadRecent()
    } }
    private fun loadRecent() {
        loading?.cancel()
        loading = activity.lifecycleScope.launch {
            feedback.setText(R.string.diag_loading)
            val result = withContext(Dispatchers.IO) { runCatching {
                val raw = ReceiverLogPolicy.read("${activity.filesDir}/receiver")
                (0 until raw.length()).map { DiagnosticEntry(raw.getJSONObject(it)) }
                    .sortedWith(compareByDescending<DiagnosticEntry> { it.timestamp }.thenByDescending { it.id })
                    .filter { it.known(activity) }.take(12)
            } }
            ensureActive()
            feedback.visibility = View.GONE
            result.onSuccess { entries ->
                recent.submit(entries)
                if (entries.isEmpty()) { feedback.setText(R.string.diag_empty); feedback.visibility = View.VISIBLE }
            }.onFailure {
                feedback.setText(R.string.diag_read_failed)
                feedback.visibility = View.VISIBLE
            }
        }
    }
    fun result(state: String, name: String? = null) {
        page.state.putString("export", state); name?.let { page.state.putString("file", it) }; render()
    }
    private fun render() { support.setSupporting(activity.getString(when(page.state.getString("export")) {
        "busy" -> R.string.diag_exporting
        "success" -> R.string.diag_saved
        "failure" -> R.string.diag_failed
        else -> R.string.diag_contents
    }, page.state.getString("file").orEmpty())) }
}
