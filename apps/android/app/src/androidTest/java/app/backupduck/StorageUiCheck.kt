package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.material.bottomnavigation.BottomNavigationView
import org.json.JSONObject
import java.io.File

/** Current Storage and retired-entry compatibility preserve exact stored policy. */
internal fun Instrumentation.checkStorageUI(args: Bundle): String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone") || android.os.Build.FINGERPRINT.contains("generic"))
    targetContext.getSharedPreferences("appearance", 0).edit().putInt("mode", if (args.getString("dark") == "true") 2 else 1).commit()
    val enabled = ReceiverPreferences.enabled(targetContext); ReceiverPreferences.setEnabled(targetContext, false)
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun <T> main(action: () -> T): T { var result: Result<T>? = null; runOnMainSync { result = runCatching(action) }; return result!!.getOrThrow() }
    fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    fun settle() { waitForIdleSync(); Thread.sleep(500) }
    val root = "${targetContext.filesDir}/receiver"
    fun config() = (NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject).getJSONObject("settings")
    fun save(value: JSONObject) { NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root).put("settings", value)) }
    val previous = config()
    try {
        save(JSONObject(previous.toString()).put("receiver_budget_bytes", 123456789L).put("min_free_bytes", 456789L).put("receiver_relay", false))
        main { activity.openSettings() }; settle()
        for (route in listOf("storage", "storage-limits", "retention", "reclaim-originals", "relay-history")) {
            main { activity.restorePage(route, Bundle()).show() }; settle()
            main {
                val current = (activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!
                check(current.route == "storage")
                check(activity.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId == 4)
                check(current.root.isShown)
                check(views(current.root).filterIsInstance<TextView>().none { it.text.toString() == activity.getString(R.string.duck_storage_detail) })
            }
            check(config().getLong("receiver_budget_bytes") == 123456789L && config().getLong("min_free_bytes") == 456789L && !config().getBoolean("receiver_relay")) { "Storage changed a retained policy" }
            main { activity.onBackPressedDispatcher.onBackPressed() }; settle()
        }
        main { activity.openStorage() }; settle()
        val image = checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir, "storage-current.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }; image.recycle()
        return "PASS: current secondary Storage with Back to Settings; retired aliases; exact quota/reserve/retention preferences survive navigation"
    } finally { save(previous); main { activity.finish() }; ReceiverPreferences.setEnabled(targetContext, enabled) }
}
