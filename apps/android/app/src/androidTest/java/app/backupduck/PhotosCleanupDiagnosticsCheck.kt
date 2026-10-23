package app.backupduck

import android.app.Instrumentation
import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

/** Synthetic export facts only: no service, account handoff or cleanup is started. */
internal fun Instrumentation.checkPhotosCleanupDiagnostics() {
    val prefs = targetContext.getSharedPreferences("photos_cleanup", Context.MODE_PRIVATE)
    val previous = prefs.all
    val previousOperations = ReceiverEnvironment.cleanupOperations
    val previousVersion = ReceiverEnvironment.photosVersion
    val snapshots = MutableStateFlow(PhotosProbeState(observation = "completed",
        seen = setOf("confirmation", "completed")))
    ReceiverEnvironment.cleanupOperations = object : CleanupOperations {
        override val state = snapshots
        override fun start(context: Context, bind: Boolean, route: String): Boolean = error("unexpected cleanup")
        override fun stop() = error("unexpected cleanup")
        override fun access(context: Context, returned: () -> Unit) = error("unexpected handoff")
        override fun photos(context: Context, returned: () -> Unit) = error("unexpected handoff")
    }
    try {
        ReceiverEnvironment.photosVersion = { "7.2.0 (synthetic)" }
        prefs.edit().clear().putBoolean("enabled", true).putString("account", "private-synthetic-fingerprint")
            .putString("state", JSONObject().put("phase", "pending").toString()).putString("reason", "pending")
            .putString("last_result", "completed").putLong("last_freed_bytes", 1234)
            .putLong("last_completed_at", 1792360800000).commit()
        val known = targetContext.photosCleanupDiagnostics()
        check(known.getString("google_photos_app_version") == "7.2.0 (synthetic)")
        check(known.getString("last_observation") == "completed")
        check(known.getJSONArray("screens_seen").let { it.length() == 2 && it.getString(0) == "completed" && it.getString(1) == "confirmation" })
        check(known.getBoolean("enabled") && known.getBoolean("pending") && known.getBoolean("account_bound"))
        check(known.getString("last_result") == "completed" && known.getString("last_reason") == "pending")
        check(known.getLong("last_freed_bytes") == 1234L && known.getLong("last_completed_at_ms") == 1792360800000)
        check(!known.getBoolean("cloud_backup_verified"))
        check(!known.toString().contains("private-synthetic-fingerprint"))
        // A recorded zero is known. A missing value remains an explicit JSON null.
        prefs.edit().putLong("last_freed_bytes", 0).commit()
        check(targetContext.photosCleanupDiagnostics().getLong("last_freed_bytes") == 0L)
        prefs.edit().clear().commit()
        snapshots.value = PhotosProbeState()
        ReceiverEnvironment.photosVersion = { null }
        val unknown = targetContext.photosCleanupDiagnostics()
        listOf("google_photos_app_version", "last_observation", "screens_seen", "last_result", "last_reason",
            "last_freed_bytes", "last_completed_at_ms").forEach { check(unknown.has(it) && unknown.isNull(it)) }
        listOf("enabled", "pending", "account_bound", "cloud_backup_verified").forEach { check(!unknown.getBoolean(it)) }
    } finally {
        ReceiverEnvironment.cleanupOperations = previousOperations
        ReceiverEnvironment.photosVersion = previousVersion
        prefs.edit().clear().apply {
            previous.forEach { (key, value) -> when (value) {
                is String -> putString(key, value)
                is Boolean -> putBoolean(key, value)
                is Int -> putInt(key, value)
                is Long -> putLong(key, value)
                is Float -> putFloat(key, value)
            } }
        }.commit()
    }
}
