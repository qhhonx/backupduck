package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.io.File

/** Current feedback and preference responsibilities on isolated emulator data. */
internal fun Instrumentation.checkReceiverRemainingFeedback(args: Bundle): String {
    check(targetContext.packageName.endsWith(".validation") && android.os.Build.MODEL.contains("sdk_gphone"))
    val enabled = ReceiverPreferences.enabled(targetContext); ReceiverPreferences.setEnabled(targetContext, false)
    val thermal = ReceiverThermalSettings.enabled(targetContext); val threshold = ReceiverThermalSettings.threshold(targetContext)
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun <T> main(action: () -> T): T { var result: Result<T>? = null; runOnMainSync { result = runCatching(action) }; return result!!.getOrThrow() }
    fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    fun settle() { waitForIdleSync(); Thread.sleep(400) }
    try {
        main {
            val nav = activity.findViewById<BottomNavigationView>(R.id.main_navigation)
            for (id in listOf(1, 2, 4)) {
                nav.selectedItemId = id
                check(all(activity.window.decorView).filterIsInstance<MaterialToolbar>().single().menu.size() == 0)
            }
            check(nav.menu.findItem(3) == null)
            activity.openStorage()
        }; settle()
        main {
            val page = (activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!
            check(page.route == "storage" && page.root.isShown)
            check(all(page.root).filterIsInstance<TextView>().none { it.text.toString() in listOf(activity.getString(R.string.gallery_receipts_export), activity.getString(R.string.originals_export)) })
            activity.onBackPressedDispatcher.onBackPressed()
        }; settle()
        main { activity.restorePage("advanced", Bundle()).show() }; settle()
        main {
            val page = (activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!
            val texts = all(page.root).filterIsInstance<TextView>().map { it.text.toString() }
            check(texts.count { it == activity.getString(R.string.pref_conversion) } == 1)
            check(texts.count { it == activity.getString(R.string.pref_browser) } == 1)
            check(texts.count { it == activity.getString(R.string.receiver_stop) } == 1)
            check(activity.getString(R.string.duck_thermal) !in texts)
            activity.onBackPressedDispatcher.onBackPressed()
        }; settle()
        check(ReceiverThermalSettings.enabled(targetContext) == thermal && ReceiverThermalSettings.threshold(targetContext) == threshold)
        main { activity.showDiagnostics() }; settle()
        main {
            val page = (activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!
            check(page.route == "diagnostics" && page.root.isShown)
            check(all(page.root).filterIsInstance<TextView>().count { it.text.toString() == activity.getString(R.string.diag_export) } == 1)
        }
        val image = checkNotNull(uiAutomation.takeScreenshot()); File(targetContext.cacheDir, "remaining-current.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }; image.recycle()
        return "PASS: current Photos has no retired filters menu; Storage is secondary; Advanced has one conversion/browser/stop row; hidden thermal values retained; one Diagnostics export"
    } finally { main { activity.finish() }; ReceiverPreferences.setEnabled(targetContext, enabled) }
}
