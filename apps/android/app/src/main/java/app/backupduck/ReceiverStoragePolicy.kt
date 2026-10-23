package app.backupduck

import android.content.Context
import org.json.JSONObject

/** The core caps acceptance by actual free space minus its existing safe reserve. */
internal object ReceiverStoragePolicy {
    private const val SAFE_RESERVE = 1L shl 30
    fun capacity(context: Context): Long = ReceiverEnvironment.deviceStorage(context).totalBytes.coerceIn(1L, 1L shl 40)
    fun apply(context: Context) {
        val root = "${context.filesDir}/receiver"
        val response = NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject
        val settings = response.getJSONObject("settings")
        val ceiling = capacity(context)
        if (settings.getLong("receiver_budget_bytes") == ceiling && settings.getLong("min_free_bytes") == SAFE_RESERVE) return
        val updated = JSONObject(settings.toString()).put("receiver_budget_bytes", ceiling).put("min_free_bytes", SAFE_RESERVE)
        NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root).put("settings", updated))
    }
}
