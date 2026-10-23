package app.backupduck

import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.TextView
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

/** Retargeted recovery assertions use the ordinary page and synthetic host operations. */
internal fun Instrumentation.checkOrdinaryCleanupRecovery() {
    val prefs = targetContext.getSharedPreferences("photos_cleanup", Context.MODE_PRIVATE)
    val previous = prefs.all
    val previousOperations = ReceiverEnvironment.cleanupOperations
    val previousAccess = ReceiverEnvironment.cleanupAccess
    val snapshots = MutableStateFlow(PhotosProbeState(connected = true, mode = "cleanup"))
    val facts = PhotosCleanup(targetContext)
    var stops = 0
    ReceiverEnvironment.cleanupAccess = { true }
    ReceiverEnvironment.cleanupOperations = object : CleanupOperations {
        override val state = snapshots
        override fun start(context: Context, bind: Boolean, route: String): Boolean = error("unexpected cleanup")
        override fun stop() { stops++; snapshots.value = snapshots.value.copy(running = false, observation = "stopped") }
        override fun access(context: Context, returned: () -> Unit) = error("unexpected settings handoff")
        override fun photos(context: Context, returned: () -> Unit) = returned()
    }
    fun <T> main(action: () -> T): T {
        var result: Result<T>? = null
        runOnMainSync { result = runCatching(action) }
        return result!!.getOrThrow()
    }
    fun settle() { waitForIdleSync(); Thread.sleep(400) }
    fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    var page: AutoCleanupScreen? = null
    fun show(reason: String, pending: Boolean = false, running: Boolean = false) {
        main {
            activity.supportFragmentManager.popBackStackImmediate(null, androidx.fragment.app.FragmentManager.POP_BACK_STACK_INCLUSIVE)
            facts.account = "synthetic-account-fingerprint"
            facts.enabled = true
            facts.journey = ""
            facts.enableAfterBinding = false
            facts.save(if (pending) JSONObject().put("phase", "pending") else JSONObject(), reason)
            snapshots.value = snapshots.value.copy(running = running, observation = reason)
            page = AutoCleanupScreen(activity).also { it.page.show() }
        }
        settle()
    }
    fun labels(id: Int) = views(page!!.page.root).filterIsInstance<TextView>()
        .filter { it.isShown && it.text.toString() == activity.getString(id) }
    fun click(id: Int) { main { labels(id).single().performClick() }; settle() }
    try {
        show("bound")
        main { check(labels(R.string.auto_cleanup_account_confirmed).size == 1) }
        show("opening_cleanup", running = true)
        main {
            check(labels(R.string.auto_cleanup_stop).size == 1)
            check(labels(R.string.auto_cleanup_run).isEmpty())
        }
        click(R.string.auto_cleanup_stop)
        check(stops == 1 && facts.reason == "stopped" && !snapshots.value.running)
        show("account_changed")
        main {
            check(labels(R.string.auto_cleanup_account).size == 1)
            check(labels(R.string.auto_cleanup_account_confirmed).isEmpty())
        }
        show("pending", pending = true)
        main {
            check(labels(R.string.auto_cleanup_review).size == 1)
            check(labels(R.string.auto_cleanup_reviewed).isEmpty())
            check(labels(R.string.auto_cleanup_check_result).size == 1)
        }
        click(R.string.auto_cleanup_open_photos)
        click(R.string.auto_cleanup_reviewed)
        fun confirm(positive: Boolean) = main {
            val root = WindowInspector.getGlobalWindowViews().last { it.isShown && it.hasWindowFocus() }
            root.findViewById<View>(if (positive) android.R.id.button1 else android.R.id.button2).performClick()
        }
        confirm(false); settle(); check(facts.pending)
        click(R.string.auto_cleanup_reviewed)
        confirm(true); settle(); check(!facts.pending && facts.reason == "reviewed")
        facts.recordNothingToFree()
        show("nothing_to_free")
        main {
            check(labels(R.string.auto_cleanup_nothing).size == 1)
            check(labels(R.string.auto_cleanup_reviewed).isEmpty())
        }
    } finally {
        main { activity.finish() }
        ReceiverEnvironment.cleanupOperations = previousOperations
        ReceiverEnvironment.cleanupAccess = previousAccess
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
