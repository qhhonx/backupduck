package app.backupduck

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Instrumentation
import android.view.accessibility.AccessibilityManager
import org.json.JSONArray
import org.json.JSONObject

/** Runs without enabling accessibility or touching Google Photos/user files. */
internal fun Instrumentation.checkPhotosProbe(): String {
    fun snapshot(locked: Boolean = false, complete: Boolean = true, packageName: String = PhotosProbeService.PHOTOS_PACKAGE,
        entries: List<Triple<String, String, Boolean>>): JSONObject = JSONObject()
        .put("package", packageName).put("locked", locked).put("complete", complete).put("nodes", JSONArray().apply {
            entries.forEach { (id, text, actionable) -> put(JSONObject().put("id", "${PhotosProbeService.PHOTOS_PACKAGE}:id/$id").put("text", text).put("actionable", actionable)) }
        })
    fun classify(snapshot: JSONObject) = NativeBridge.request(JSONObject().put("op", "photos_probe").put("snapshot", snapshot)) as String
    val confirmed = listOf(Triple("safetyTip", "These items have been safely backed up.", false), Triple("free_up_button", "Free up 2 GB", true))
    check(classify(snapshot(entries = confirmed)) == "confirmation")
    check(classify(snapshot(locked = true, entries = confirmed)) == "locked")
    check(classify(snapshot(complete = false, entries = confirmed)) == "incomplete")
    check(classify(snapshot(packageName = "com.example.other", entries = confirmed)) == "other_app")
    check(classify(snapshot(entries = confirmed + confirmed)) == "unknown")
    check(classify(snapshot(entries = listOf(Triple("og_bento_card_title", "", false), Triple("og_bento_card_title", "释放此设备的空间", false)))) == "cleanup_entry")
    val safe = snapshot(entries = confirmed).put("account", "bound")
    val pending = JSONObject().put("phase", "pending").put("backs", 0).put("actions", 3)
    val resumed = NativeBridge.request(JSONObject().put("op", "photos_cleanup_step").put("state", pending).put("snapshot", safe).put("expected", "bound")) as JSONObject
    check(resumed.getString("action") == "wait")
    check(resumed.getJSONObject("state").getString("phase") == "pending")
    val storage = PhotosCleanup(targetContext)
    check(!storage.enabled)
    storage.save(pending, "pending")
    check(PhotosCleanup(targetContext).pending)
    storage.reviewed()
    check(!PhotosCleanup(targetContext).pending)
    val manager = targetContext.getSystemService(AccessibilityManager::class.java)
    val service = manager.installedAccessibilityServiceList.single { it.resolveInfo.serviceInfo.packageName == targetContext.packageName && it.resolveInfo.serviceInfo.name.endsWith("PhotosProbeService") }
    check(service.resolveInfo.serviceInfo.permission == "android.permission.BIND_ACCESSIBILITY_SERVICE")
    check(service.packageNames.toList() == listOf(PhotosProbeService.PHOTOS_PACKAGE))
    check(service.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_RETRIEVE_WINDOW_CONTENT != 0)
    check(service.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_PERFORM_GESTURES == 0)
    check(manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).none { it.id == service.id }) { "isolated_probe_service_already_enabled" }
    check(!PhotosProbeService.state.value.running)
    checkPhotosCleanupDiagnostics()
    return "PASS: native classifier and pending fence; package-restricted service; no permissions or user media changed"
}
