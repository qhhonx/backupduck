package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView

/** Current Material preference rows own their padding and trailing controls. */
internal fun Instrumentation.checkReceiverRowContract(args: Bundle): String {
    check(targetContext.packageName.endsWith(".validation") && android.os.Build.MODEL.contains("sdk_gphone"))
    val enabled = ReceiverPreferences.enabled(targetContext); ReceiverPreferences.setEnabled(targetContext, false)
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    var page: LookPage? = null
    fun descendants(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { descendants(v.getChildAt(it)) } else emptyList()
    try {
        runOnMainSync {
            page = LookPage(activity, "Preference rows", "row-contract")
            val group = activity.lookGroup(page!!.body)
            activity.lookRow(group, R.drawable.ic_storage, "Storage", "A supporting value that wraps across several lines in a narrow layout") {}
            activity.lookSwitchRow(group, R.drawable.ic_motion, "Live Photo conversion", "Conversion applies to future saves", false) {}
            page!!.show()
        }
        waitForIdleSync(); Thread.sleep(250)
        runOnMainSync {
            val root = checkNotNull(page).root
            val toggle = descendants(root).filterIsInstance<com.google.android.material.materialswitch.MaterialSwitch>().single()
            val title = descendants(root).filterIsInstance<TextView>().single { it.text.toString() == "Live Photo conversion" }
            val tr = Rect(); val sr = Rect()
            check(title.getGlobalVisibleRect(tr) && toggle.getGlobalVisibleRect(sr))
            check(tr.right <= sr.left && sr.width() == toggle.width) { "Preference label overlaps or clips the trailing switch" }
            check(toggle.width < root.width / 2) { "Switch stretched into the content column" }
            val storage = descendants(root).filterIsInstance<TextView>().single { it.text.toString() == "Storage" }
            val rr = Rect(); check(storage.getGlobalVisibleRect(rr)); check(rr.left == tr.left) { "Shared rows disagree on the label inset" }
            check(!toggle.isChecked)
        }
        return "PASS: current shared Material row label alignment, wrapped support, trailing switch bounds and unchanged Boolean"
    } finally { runOnMainSync { page?.dismiss(); activity.finish() }; ReceiverPreferences.setEnabled(targetContext, enabled) }
}
