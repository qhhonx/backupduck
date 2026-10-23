package app.backupduck

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.LinearLayout
import android.widget.TextView
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

/** Preserves both existing export payloads, including unresolved publication receipts. */
internal fun Context.combinedDiagnostics(root: String): ByteArray = JSONObject()
    .put("schema_version", 1).put("source", "BackupDuck Pixel receiver")
    .put("exported_at_ms", ReceiverEnvironment.now())
    .put("receiver_log", ReceiverLogPolicy.read(root))
    .put("photos_saving_receipts", ReceiverEnvironment.diagnosticReceipts(this, root))
    .toString(2).toByteArray(Charsets.UTF_8)

internal class DiagnosticsScreen(private val activity: MainActivity, restored: Bundle, private val export: (DiagnosticsScreen) -> Unit) {
    val page = LookPage(activity, activity.getString(R.string.pref_diagnostics), "diagnostics")
    private val support: TextView
    init { with(activity) {
        page.state.putAll(restored)
        if (page.state.getString("export") == "busy") page.state.putString("export", "failure")
        ReceiverEnvironment.diagnosticInitialState?.let { if (restored.isEmpty) page.state.putAll(it) }
        page.body.addView(lookText(getString(R.string.diag_intro), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        val log = lookGroup(page.body)
        ((log.parent as android.view.View).layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_large)
        lookRow(log, R.drawable.ic_document, getString(R.string.diag_log)) {
            startActivity(Intent(this, ReceiverActivityLogActivity::class.java))
        }
        support = lookRow(log, R.drawable.ic_document, getString(R.string.diag_export), getString(R.string.diag_contents)) {
            if (page.state.getString("export") != "busy") export(this@DiagnosticsScreen)
        }
        lookSection(page.body, getString(R.string.diag_tools))
        val tools = lookGroup(page.body)
        lookRow(tools, R.drawable.ic_photo, getString(R.string.diag_probe), getString(R.string.diag_probe_note)) { probe("diagnostics") }
        lookRow(tools, R.drawable.ic_settings, getString(R.string.diag_cleanup)) { probe("cleanup") }
        lookRow(tools, R.drawable.ic_check, getString(R.string.diag_bind)) { probe("bind") }
        lookRow(tools, R.drawable.ic_clock, getString(R.string.diag_progress)) { probe("progress") }
        render()
    } }
    private fun probe(route: String) { activity.startActivity(Intent(activity, PhotosProbeActivity::class.java)
        .putExtra("route", route).putExtra("diagnostics", route == "diagnostics")) }
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
