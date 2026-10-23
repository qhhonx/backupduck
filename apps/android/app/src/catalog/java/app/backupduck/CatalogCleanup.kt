package app.backupduck

import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject
import java.io.File

/** Scripted host boundary: never launches settings or performs real account binding/cleanup. */
internal class CatalogCleanup(private val context: Context, private val script: JSONObject) : CleanupOperations {
    private val main = Handler(Looper.getMainLooper())
    private var generation = 0
    private var accessGranted = script.optBoolean("access", true)
    override val state = MutableStateFlow(PhotosProbeState(connected = accessGranted,
        running = script.optBoolean("running"), mode = script.optString("mode", "cleanup"), observation = script.optString("reason", "ready"), secondsLeft = script.optInt("seconds", 90),
        seen = script.optJSONArray("seen")?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()))
    init {
        ReceiverEnvironment.cleanupAccess = { accessGranted }
        val facts = PhotosCleanup(context)
        facts.enabled = script.optBoolean("enabled", false)
        facts.account = if (script.optBoolean("account", true)) "catalog-account-fingerprint" else ""
        facts.save(if (script.optBoolean("pending")) JSONObject().put("phase", "pending") else JSONObject(), script.optString("reason", "ready"))
        facts.journey = script.optString("journey"); facts.enableAfterBinding = facts.journey.isNotEmpty()
        context.getSharedPreferences("photos_probe", 0).edit().putBoolean("cleanup_disclosure_v2", true).commit()
        val prefs = context.getSharedPreferences("photos_cleanup", 0).edit()
        if (script.has("last_result")) prefs.putString("last_result", script.getString("last_result"))
        if (script.has("last_bytes")) prefs.putLong("last_freed_bytes", script.getLong("last_bytes"))
        if (script.has("last_at")) prefs.putLong("last_completed_at", script.getLong("last_at"))
        prefs.commit()
        if (CatalogTextAudit.enabled) main.post(object : Runnable {
            override fun run() {
                if (ReceiverEnvironment.cleanupOperations !== this@CatalogCleanup) return
                val saved = PhotosCleanup(context)
                File(context.getExternalFilesDir(null), "cleanup-state.json").writeText(JSONObject()
                    .put("enabled", saved.enabled).put("pending", saved.pending).put("accountConfirmed", saved.account.isNotEmpty())
                    .put("reason", saved.reason).put("journey", saved.journey).put("enableAfterBinding", saved.enableAfterBinding)
                    .put("running", state.value.running).put("lastResult", saved.lastResult).toString(2))
                main.postDelayed(this, 250)
            }
        })
    }
    private fun record(action: String) { File(context.getExternalFilesDir(null), "cleanup-actions.txt").appendText("$action\n") }
    override fun start(context: Context, bind: Boolean, route: String): Boolean {
        if (!accessGranted || state.value.running) return false
        record(if (bind) "bind" else if (PhotosCleanup(context).pending) "check-result" else "run")
        val token = ++generation
        state.value = PhotosProbeState(connected = true, running = true, mode = if (bind) "bind" else "cleanup", observation = "opening")
        main.postDelayed({
            if (token != generation || ReceiverEnvironment.cleanupOperations !== this) return@postDelayed
            val facts = PhotosCleanup(context)
            val reason = script.optString(if (bind) "bind_result" else "run_result", if (bind) "bound" else "nothing_to_free")
            if (reason == "bound") facts.account = "catalog-confirmed-fingerprint"
            if (reason == "nothing_to_free") facts.recordNothingToFree()
            facts.save(if (reason == "pending") JSONObject().put("phase", "pending") else if (reason == "nothing_to_free") JSONObject() else facts.state, reason)
            state.value = state.value.copy(running = false, observation = reason)
        }, script.optLong("operation_ms", 1600))
        return true
    }
    override fun observe(context: Context): Boolean {
        if (!accessGranted || state.value.running || script.optBoolean("photos_missing")) return false
        record("observe-only")
        state.value = state.value.copy(running = true, mode = "probe", observation = "waiting", secondsLeft = 120, seen = emptySet())
        return true
    }
    override fun stop() {
        ++generation; record("stop")
        val facts = PhotosCleanup(context); facts.report(if (facts.pending) "pending" else "stopped")
        state.value = state.value.copy(running = false, observation = facts.reason)
    }
    override fun access(context: Context, returned: () -> Unit) {
        record("access-handoff")
        main.postDelayed({
            if (ReceiverEnvironment.cleanupOperations !== this) return@postDelayed
            accessGranted = script.optBoolean("grant_access", true)
            state.value = state.value.copy(connected = accessGranted)
            returned()
        }, script.optLong("access_ms", 1200))
    }
    override fun photos(context: Context, returned: () -> Unit) {
        record("photos-handoff")
        if (script.optBoolean("photos_unavailable")) throw android.content.ActivityNotFoundException()
        main.postDelayed({ if (ReceiverEnvironment.cleanupOperations === this) returned() }, 700)
    }
}
