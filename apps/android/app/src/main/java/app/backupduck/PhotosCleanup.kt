package app.backupduck

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Receiver-local consent and crash fence. Never stores account text or page dumps. */
internal class PhotosCleanup(private val context: Context) : CleanupAccessStore {
    private val prefs = context.getSharedPreferences("photos_cleanup", Context.MODE_PRIVATE)
    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(value) { check(prefs.edit().putBoolean("enabled", value).commit()) }
    var account: String
        get() = prefs.getString("account", "").orEmpty()
        set(value) { check(prefs.edit().putString("account", value).commit()) }
    /** Durable setup intent; enabling follows a successful bounded account check only. */
    var journey: String
        get() = prefs.getString("journey", "").orEmpty()
        set(value) {
            val edit = prefs.edit().putString("journey", value)
            if (value != "access") edit.remove("access_route").remove("access_wait_started_at")
            check(edit.commit())
        }
    override var accessStep: CleanupAccessStep?
        get() = if (journey != "access") null else CleanupAccessStep(
            prefs.getString("access_route", "storage").orEmpty(),
            if (prefs.contains("access_wait_started_at")) prefs.getLong("access_wait_started_at", 0) else null)
        set(value) {
            val edit = prefs.edit()
            if (value == null) edit.putString("journey", "").remove("access_route").remove("access_wait_started_at")
            else {
                edit.putString("journey", "access").putString("access_route", value.route)
                if (value.waitingSince == null) edit.remove("access_wait_started_at")
                else edit.putLong("access_wait_started_at", value.waitingSince)
            }
            check(edit.commit())
        }
    val accessRecovery get() = CleanupAccessRecovery(this)
    var enableAfterBinding: Boolean
        get() = prefs.getBoolean("enable_after_binding", false)
        set(value) { check(prefs.edit().putBoolean("enable_after_binding", value).commit()) }
    val lastResult: String get() = prefs.getString("last_result", "").orEmpty()
    fun recordNothingToFree() {
        check(prefs.edit().putString("last_result", "nothing_to_free").putLong("last_completed_at", System.currentTimeMillis())
            .remove("last_freed_bytes").commit())
    }
    val state: JSONObject get() = runCatching { JSONObject(prefs.getString("state", "{}").orEmpty()) }.getOrDefault(JSONObject())
    val pending: Boolean get() = state.optString("phase") in setOf("pending", "returning")
    val held: Boolean get() = pending || PhotosProbeService.cleanupRunning
    val reason: String get() = prefs.getString("reason", "ready").orEmpty()
    val lastFreedBytes: Long? get() = prefs.getLong("last_freed_bytes", 0).takeIf { it > 0 }
    val lastCompletedAt: Long? get() = prefs.getLong("last_completed_at", 0).takeIf { it > 0 }
    fun recordCompletion(bytes: Long?) {
        val edit = prefs.edit().putString("last_result", "completed").putLong("last_completed_at", System.currentTimeMillis())
        if (bytes == null) edit.remove("last_freed_bytes") else edit.putLong("last_freed_bytes", bytes)
        check(edit.commit())
    }
    fun save(state: JSONObject, reason: String) {
        check(prefs.edit().putString("state", state.toString()).putString("reason", reason).commit())
    }
    fun report(reason: String) { check(prefs.edit().putString("reason", reason).commit()) }
    fun reviewed() { save(JSONObject(), "reviewed"); cooldown(15 * 60_000) }
    fun cooldown(delay: Long) { prefs.edit().putLong("next", System.currentTimeMillis() + delay).apply() }
    fun trigger(reserve: Long): Long = reserve + (1L shl 30)
    suspend fun tick(free: Long, reserve: Long) {
        if (enabled && account.isNotEmpty() && !PhotosProbeService.state.value.running &&
            (pending || free < trigger(reserve)) && System.currentTimeMillis() >= prefs.getLong("next", 0)) {
            cooldown(if (pending) 60_000 else 5 * 60_000)
            withContext(Dispatchers.Main) { PhotosProbeService.clean() }
        }
        ReceiverHolds.sync(context)
    }
}
