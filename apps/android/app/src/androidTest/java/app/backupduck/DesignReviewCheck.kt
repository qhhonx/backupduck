package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.io.File

/** Current native page compositions on isolated synthetic emulator data. */
internal fun Instrumentation.checkDesignReview(args: Bundle): String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone") || android.os.Build.FINGERPRINT.contains("generic"))
    val dark = args.getString("dark") == "true"
    targetContext.getSharedPreferences("appearance", 0).edit().putInt("mode", if (dark) 2 else 1).commit()
    ReceiverPreferences.setEnabled(targetContext, false)
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun <T> main(action: () -> T): T { var result: Result<T>? = null; runOnMainSync { result = runCatching(action) }; return result!!.getOrThrow() }
    fun settle() { waitForIdleSync(); Thread.sleep(350) }
    fun shot(name: String) {
        settle(); val image = checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir, "review-${if (dark) "dark" else "light"}-$name.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }; image.recycle()
    }
    val items = (200 downTo 1).map { i -> HistoryItem(i.toLong(), "review-$i", "Sample_$i.HEIC", "photo", 100, 100, "received",
        if (i > 198) "failed" else "complete", if (i > 198) "storage" else null, false, senderNames = "Fixture phone", stateChangedAtMs = 1790917140000L) }
    try {
        settle(); shot("receive")
        val nav = main { activity.findViewById<BottomNavigationView>(R.id.main_navigation) }
        main { check(nav.menu.size() == 3 && nav.menu.findItem(3) == null); nav.selectedItemId = 2 }
        val page = main { activity.photosForCheck() }
        val state = HistoryState(items = items, total = 200, counts = HistoryCounts(200, 198, 2))
        main { page.render(state); page.attention(state.copy(items = items.take(2), filter = "failed")) }; shot("photos")
        val height = main { page.view.height }
        for (snapshot in listOf(ReceiverSnapshot(phase = "ready", received = 10, total = 200),
            ReceiverSnapshot(phase = "ready", thermalHeld = true, temperatureDeciCelsius = 430),
            ReceiverSnapshot(phase = "ready", failed = 2), ReceiverSnapshot(phase = "ready", published = 200), ReceiverSnapshot(phase = "waiting", error = "wifi_required"))) {
            main { activity.receiverHome.render(snapshot, "Fixture Pixel", false); page.progress(mapOf("review-200" to ReceiverByteProgress(50, 100, false))) }
            settle(); check(main { page.view.height == height }) { "Receiver feedback resized Photos" }
        }
        main { page.openNeedsYou() }; settle()
        check(main { (page.view.layoutManager as LinearLayoutManager).findFirstVisibleItemPosition() <= 1 })
        main { page.view.scrollToPosition(190) }; settle()
        check(main { page.view.childCount < 100 }) { "Photos did not virtualize 200 tiles" }
        main { activity.openStorage() }; shot("storage")
        main { check((activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!.route == "storage"); activity.onBackPressedDispatcher.onBackPressed() }; settle()
        main { nav.selectedItemId = 4 }; shot("settings")
        return "PASS: current Home/Photos/Storage/Settings; stable photo geometry through receiver states; Needs you; 200-photo virtualization; stable navigation IDs 1/2/4"
    } finally { main { activity.finish() } }
}
