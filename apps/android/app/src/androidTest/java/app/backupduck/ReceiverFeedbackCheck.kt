package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import kotlinx.coroutines.runBlocking
import java.io.File

/** Real empty/failing history reads and current Home/Settings/Diagnostics presentation. */
internal fun Instrumentation.checkReceiverFeedback(args: Bundle): String {
    check(targetContext.packageName == "app.backupduck.validation" && android.os.Build.MODEL.contains("sdk_gphone"))
    val enabled = ReceiverPreferences.enabled(targetContext); ReceiverPreferences.setEnabled(targetContext, false)
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun <T> main(action: () -> T): T { var result: Result<T>? = null; runOnMainSync { result = runCatching(action) }; return result!!.getOrThrow() }
    fun views(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
    val root = File(targetContext.cacheDir, "feedback-${System.nanoTime()}").apply { mkdirs() }
    try {
        val empty = HistoryModel(); runBlocking { empty.select(File(root, "empty").path) }
        check(!empty.state.value.failed && empty.state.value.items.isEmpty())
        val broken = File(root, "broken/store").apply { mkdirs() }; File(broken, "receiver.sqlite3").writeText("Invalid synthetic database")
        val failed = HistoryModel(); runBlocking { failed.select(broken.parentFile!!.path) }; check(failed.state.value.failed)
        val items = listOf(
            HistoryItem(3, "saved", "Saved.jpg", "photo", 100, 100, "received", "complete", null, false),
            HistoryItem(2, "pending", "Pending.jpg", "photo", 100, 100, "received", "pending", null, false),
            HistoryItem(1, "failed", "Failed.jpg", "photo", 100, 100, "received", "failed", "storage", false))
        main {
            activity.receiverHome.history(HistoryState(items = items, total = 3, counts = HistoryCounts(3, 1, 1)))
            val mosaic = views(activity.receiverHome.view).filterIsInstance<PhotoMosaic>().single()
            check(mosaic.tag == listOf("saved")) { "Home treated a pending or failed save as a published photo" }
            activity.openSettings()
        }
        waitForIdleSync()
        main {
            val texts = views(activity.window.decorView).filterIsInstance<TextView>().filter { it.isShown }.map { it.text.toString() }
            check(texts.count { it == activity.getString(R.string.pref_devices) } == 1)
            check(texts.count { it == activity.getString(R.string.pref_storage) } == 1)
            activity.showDiagnostics()
        }
        waitForIdleSync(); Thread.sleep(350)
        main {
            val page = (activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!
            check(page.route == "diagnostics")
            check(views(page.root).filterIsInstance<TextView>().none { it.text.toString() == activity.getString(R.string.logs_retention_settings) })
        }
        return "PASS: actual JNI empty/read failure; current Home includes only published photos; unique current Settings destinations; automatic Diagnostics retention"
    } finally { main { activity.finish() }; ReceiverPreferences.setEnabled(targetContext, enabled); root.deleteRecursively() }
}
