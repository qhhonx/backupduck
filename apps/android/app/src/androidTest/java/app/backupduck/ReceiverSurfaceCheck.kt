package app.backupduck

import android.app.Instrumentation
import android.app.Notification
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.io.File

/** Synthetic native presentation checks. Never start a real receiver or change Wi-Fi. */
internal fun Instrumentation.checkReceiverSurface(args: Bundle): String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
    val enabled = ReceiverPreferences.enabled(targetContext)
    val paused = ReceiverPreferences.paused(targetContext)
    val previous = ReceiverState.snapshot.value
    val appearance = targetContext.getSharedPreferences("appearance", 0)
    val oldMode = appearance.getInt("mode", -1)
    ReceiverPreferences.setEnabled(targetContext, false)
    ReceiverPreferences.setPaused(targetContext, false)
    appearance.edit().putInt("mode", if (args.getString("dark") == "true") 2 else 1).commit()
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    fun screenshot(name: String, view: View) {
        var bitmap: Bitmap? = null
        val draw = { bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also {
            it.eraseColor(android.graphics.Color.WHITE)
            view.draw(android.graphics.Canvas(it))
        } }
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) draw() else runOnMainSync { draw() }
        File(targetContext.cacheDir, "receiver-surface-$name.png").outputStream().use { bitmap!!.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap!!.recycle()
    }
    try {
        waitForIdleSync()
        ReceiverPreferences.setEnabled(targetContext, true)
        val waiting = ReceiverSnapshot(phase = "waiting", error = "wifi_required")
        runOnMainSync { activity.receiverHome.render(waiting, "Synthetic Pixel", false) }
        waitForIdleSync()
        val root = activity.receiverHome.view
        val drawables = all(root).filter { it.background != null }.associateWith { it.background }
        runOnMainSync {
            repeat(12) { activity.receiverHome.render(waiting.startingIfRequested(false), "Synthetic Pixel", false) }
            check(all(root).filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.receiver_waiting) })
            check(drawables.all { (view, background) -> view.background === background }) { "Stable polling recreated visual surfaces" }
        }
        waitForIdleSync()
        val nav = activity.findViewById<BottomNavigationView>(R.id.main_navigation)
        var largestGap = 0
        var largestInkGap = 0
        fun ink(view: View): Rect {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            val bounds = Rect(view.width, view.height, 0, 0)
            for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                if (android.graphics.Color.alpha(bitmap.getPixel(x, y)) > 16) {
                    bounds.left = minOf(bounds.left, x); bounds.top = minOf(bounds.top, y)
                    bounds.right = maxOf(bounds.right, x + 1); bounds.bottom = maxOf(bounds.bottom, y + 1)
                }
            }
            bitmap.recycle()
            check(!bounds.isEmpty) { "Navigation glyph was not rendered" }
            return bounds
        }
        runOnMainSync {
            for (icon in all(nav).filter { it.id == com.google.android.material.R.id.navigation_bar_item_icon_view }) {
                var item = icon.parent as ViewGroup
                while (all(item).filterIsInstance<TextView>().none { it.isShown && it.text.isNotEmpty() } && item.parent is ViewGroup && item.parent !== nav) item = item.parent as ViewGroup
                val label = all(item).filterIsInstance<TextView>().first { it.isShown && it.text.isNotEmpty() }
                val iconRect = Rect(); val labelRect = Rect()
                icon.getGlobalVisibleRect(iconRect); label.getGlobalVisibleRect(labelRect)
                check(labelRect.top >= iconRect.bottom) { "Navigation icon overlaps label" }
                largestGap = maxOf(largestGap, labelRect.top - iconRect.bottom)
                check(labelRect.top - iconRect.bottom <= activity.dp(16)) { "Navigation gap is too large: ${labelRect.top - iconRect.bottom}px" }
                val inkGap = labelRect.top + ink(label).top - (iconRect.top + ink(icon).bottom)
                largestInkGap = maxOf(largestInkGap, inkGap)
                check(inkGap in 0..activity.dp(20)) { "Actual icon-label ink gap is too large: ${inkGap}px" }
            }
        }
        screenshot("home", activity.window.decorView)
        runOnMainSync {
            val readings = DuckReadings(activity, listOf("A long caption that wraps", "Short", "Another caption"))
            readings.render("5", "5", "0")
            readings.view.measure(View.MeasureSpec.makeMeasureSpec(activity.dp(288), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            readings.view.layout(0, 0, readings.view.measuredWidth, readings.view.measuredHeight)
            val baselines = (0 until readings.view.childCount).mapNotNull {
                val column = readings.view.getChildAt(it) as? android.widget.LinearLayout
                val value = column?.getChildAt(0) as? TextView
                if (column != null && value != null) column.top + value.top + value.baseline else null
            }
            check(baselines.max() - baselines.min() <= 1) { "Wrapping captions misalign value baselines" }
            screenshot("readings", readings.view)
            val button = activity.duckButton("Action", true) {}
            button.measure(View.MeasureSpec.makeMeasureSpec(activity.dp(240), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(activity.dp(48), View.MeasureSpec.EXACTLY))
            button.layout(0, 0, button.measuredWidth, button.measuredHeight)
            fun paintedBackground(): Int {
                val image = Bitmap.createBitmap(button.width, button.height, Bitmap.Config.ARGB_8888)
                button.draw(android.graphics.Canvas(image))
                val color = image.getPixel(activity.dp(30), button.height / 2)
                image.recycle()
                return color
            }
            val activeColor = paintedBackground()
            button.isEnabled = false
            check(paintedBackground() != activeColor) { "Disabled action still looks active" }
            screenshot("disabled", button)
        }
        check(ReceiverNotifications.text(activity, waiting) == activity.getString(R.string.receiver_waiting))
        val ready = ReceiverSnapshot(phase = "ready")
        check(ReceiverNotifications.text(activity, ready) == activity.getString(R.string.duck_wait_receive))
        check(ReceiverNotifications.text(activity, ready.copy(received = 1, total = 1)) == activity.getString(R.string.receiver_notification_processing))
        val receipt = RecentTransfer("synthetic", "synthetic.jpg", "photo", 100, 50, "receiving", "pending")
        check(ReceiverNotifications.text(activity, ready.copy(recent = listOf(receipt))) == activity.getString(R.string.receiver_notification))
        ReceiverPreferences.setPaused(activity, true)
        check(ReceiverNotifications.text(activity, ready) == activity.getString(R.string.duck_reception_paused))
        ReceiverPreferences.setPaused(activity, false)
        val notification = ReceiverNotifications.build(activity, waiting)
        check(notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() == activity.getString(R.string.receiver_waiting))
        check(notification.extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) == 0)
        check(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        val builder = Notification.Builder.recoverBuilder(activity, notification)
        val template = builder.createBigContentView() ?: builder.createContentView()
        var templateHeight = 0
        runOnMainSync {
            val view = template.apply(activity, FrameLayout(activity))
            val width = activity.resources.displayMetrics.widthPixels - activity.dp(32)
            view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(activity.dp(400), View.MeasureSpec.AT_MOST))
            view.layout(0, 0, width, view.measuredHeight)
            templateHeight = view.measuredHeight
            check(templateHeight in activity.dp(40)..activity.dp(240)) { "Notification template reserves a large blank area: ${templateHeight}px" }
            screenshot("notification", view)
        }
        return "PASS: stable recovery across 12 polls; unchanged surface identity; icon-label gap ${largestGap / activity.resources.displayMetrics.density}dp (ink ${largestInkGap / activity.resources.displayMetrics.density}dp); actual short notification template ${templateHeight / activity.resources.displayMetrics.density}dp; honest waiting/receiving/processing/pause; no fake progress"
    } finally {
        runOnMainSync { activity.finish() }
        ReceiverPreferences.setEnabled(targetContext, enabled)
        ReceiverPreferences.setPaused(targetContext, paused)
        ReceiverState.mutable.value = previous
        if (oldMode == -1) appearance.edit().remove("mode").commit() else appearance.edit().putInt("mode", oldMode).commit()
    }
}
