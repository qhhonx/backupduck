package app.backupduck

import android.app.Activity
import android.app.Application
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.inspector.WindowInspector
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.bottomnavigation.BottomNavigationView
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference

/** Navigation/lifecycle regression checks on disposable emulator data only. */
internal fun Instrumentation.checkPageNavigation(): String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
    val transport = NativeBridge.transport
    val start = ReceiverEnvironment.startService
    val checksUpdates = ReceiverEnvironment.checksUpdates
    val enabled = ReceiverPreferences.enabled(targetContext)
    val latest = AtomicReference<MainActivity>()
    val application = targetContext.applicationContext as Application
    val observer = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, state: Bundle?) { if (activity is MainActivity) latest.set(activity) }
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityResumed(activity: Activity) {}
        override fun onActivityPaused(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }
    application.registerActivityLifecycleCallbacks(observer)
    fun settle() { waitForIdleSync(); Thread.sleep(350); waitForIdleSync() }
    try {
        ReceiverPreferences.setEnabled(targetContext, false)
        ReceiverEnvironment.startService = {}
        ReceiverEnvironment.checksUpdates = false
        NativeBridge.transport = { raw ->
            if (JSONObject(raw).getString("op") == "device_status")
                """{"ok":true,"value":{"device":{"id":"fixture","name":"Fixture Pixel"},"peers":[{"profile":{"id":"fixture-phone","name":"Fixture phone"},"last_seen":0,"enabled":true}]}}"""
            else """{"ok":false,"error":"navigation_fixture"}"""
        }
        var activity = startActivitySync(Intent(targetContext, MainActivity::class.java)
            .putExtra("destination", "settings").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        settle()
        for (route in listOf("devices", "storage", "advanced", "diagnostics", "logs-report", "gallery-report", "connect", "legacy-devices", "legacy-scan")) {
            var page: PageDestination? = null
            val windows = WindowInspector.getGlobalWindowViews().size
            runOnMainSync { page = activity.restorePage(route, Bundle()); page!!.show() }
            settle()
            runOnMainSync {
                check(activity.supportFragmentManager.backStackEntryCount == 1) { route }
                check(page!!.root.isShown && page!!.root.windowToken == activity.window.decorView.windowToken)
                if(route=="legacy-devices") check(page!!.route=="devices")
                if(route=="legacy-scan") check(page!!.route=="connect" && page!!.saveState!!.invoke().getString("surface")=="connect-mac" && !page!!.saveState!!.invoke().getBoolean("scan"))
                check(WindowInspector.getGlobalWindowViews().size == windows) { "Page created a dialog window: $route" }
                val toolbar = page!!.root.getChildAt(0) as MaterialToolbar
                check(toolbar.navigationContentDescription == activity.getString(R.string.nav_back))
                activity.onBackPressedDispatcher.onBackPressed()
            }
            settle()
            runOnMainSync {
                check(!page!!.isShowing && activity.supportFragmentManager.backStackEntryCount == 0)
                check(activity.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId == 4)
            }
        }
        var parent: PageDestination? = null
        runOnMainSync { parent = activity.restorePage("diagnostics", Bundle()); parent!!.show() }
        settle()
        runOnMainSync { activity.restorePage("logs-report", Bundle().apply { putString("result", "success") }).show() }
        settle()
        runOnMainSync { check(!parent!!.root.isShown); activity.onBackPressedDispatcher.onBackPressed() }
        settle()
        runOnMainSync {
            check(parent!!.root.isShown) // The caller's original view survives a child and Back.
            activity.restorePage("logs-report", Bundle().apply { putString("result", "success") }).show()
        }
        settle()
        val before = activity
        runOnMainSync { activity.recreate() }
        repeat(30) { if (latest.get() === before) Thread.sleep(100) }
        activity = checkNotNull(latest.get())
        check(activity !== before)
        settle()
        runOnMainSync {
            check(activity.supportFragmentManager.backStackEntryCount == 2)
            val top = activity.supportFragmentManager.primaryNavigationFragment as PageFragment
            check(top.page!!.route == "diagnostics" && top.page!!.state.getString("export") == "failure")
            activity.onBackPressedDispatcher.onBackPressed()
        }
        settle()
        runOnMainSync {
            check((activity.supportFragmentManager.primaryNavigationFragment as PageFragment).page!!.route == "diagnostics")
            val host = activity.findViewById<android.view.ViewGroup>(R.id.page_destinations).parent as android.view.ViewGroup
            check(host.getChildAt(0).importantForAccessibility == View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS)
        }
        return "PASS: nine native routes, no page windows, system Back to caller, nested parent continuity, restored stack/report state"
    } finally {
        runOnMainSync { latest.get()?.finish() }
        settle()
        application.unregisterActivityLifecycleCallbacks(observer)
        NativeBridge.transport = transport
        ReceiverEnvironment.startService = start
        ReceiverEnvironment.checksUpdates = checksUpdates
        ReceiverPreferences.setEnabled(targetContext, enabled)
    }
}
