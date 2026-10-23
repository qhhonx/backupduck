package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.material.materialswitch.MaterialSwitch
import org.json.JSONObject

/** Current Storage retains persisted relay control and cancellable cleanup consent. */
internal fun Instrumentation.checkReceiverStorageFlow(args: Bundle): String {
    val policy = checkStorageUI(args)
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun <T> main(action: () -> T): T { var result: Result<T>? = null; runOnMainSync { result = runCatching(action) }; return result!!.getOrThrow() }
    fun views(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
    val root = "${activity.filesDir}/receiver"
    fun relay() = (NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject).getJSONObject("settings").getBoolean("receiver_relay")
    val old = relay()
    try {
        main { activity.openStorage() }; waitForIdleSync(); Thread.sleep(700)
        val toggle = main { views(activity.window.decorView).filterIsInstance<MaterialSwitch>().single { it.contentDescription == activity.getString(R.string.storage_relay) } }
        main { check(toggle.isEnabled); toggle.performClick() }; Thread.sleep(700); check(relay() != old)
        main { toggle.performClick() }; Thread.sleep(700); check(relay() == old)
        main {
            val cleanup = views(activity.window.decorView).filterIsInstance<MaterialSwitch>().single { it.contentDescription == activity.getString(R.string.storage_cleanup) }
            check(!cleanup.isChecked); cleanup.performClick()
        }
        waitForIdleSync(); Thread.sleep(250)
        sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); waitForIdleSync()
        main { check((activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!.route == "storage") }
        check(!PhotosCleanup(activity).enabled && PhotosCleanup(activity).journey.isEmpty())
        return "$policy; current relay switch persisted on/off; cancelling cleanup returns to Storage without enabling it"
    } finally {
        NativeBridge.request(JSONObject().put("op", "set_receiver_relay").put("root", root).put("enabled", old).put("include_history", true))
        main { activity.finish() }
    }
}

/** Version metadata lives in the current About destination. */
internal fun Instrumentation.checkReceiverSettingsRevision(): String {
    check(targetContext.packageName == "app.backupduck.validation" && android.os.Build.MODEL.contains("sdk_gphone"))
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("destination", "settings").putExtra("surface", "about")) as MainActivity
    try {
        waitForIdleSync(); Thread.sleep(300)
        runOnMainSync {
            val page = (activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!
            check(page.route == "about")
            fun views(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
            check(views(page.root).filterIsInstance<TextView>().any { it.text.toString().contains(activity.receiverAppVersion()) })
        }
        return "PASS: current About exposes the installed app version"
    } finally { runOnMainSync { activity.finish() } }
}
