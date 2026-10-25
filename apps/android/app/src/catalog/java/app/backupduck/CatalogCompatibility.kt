package app.backupduck

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatDelegate
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomnavigation.BottomNavigationView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Opt-in synthetic compatibility fixtures, confined to the Catalog identity. */
internal object CatalogCompatibility : Application.ActivityLifecycleCallbacks {
    /** Only an explicit fixture text scale overrides the device's own setting. */
    private var textScale: Float? = null
    private var savedRoot: Int? = null
    private var lastCommand = ""
    private var active = false
    private var seededRoute: String? = null
    private var restoredRoutes = emptyList<String>()
    private fun file(context: Context, name: String) = File(context.getExternalFilesDir(null), "compat-$name.json")
    private fun fixture(context: Context) = File(context.filesDir, "catalog-restoration.json")

    fun install(application: Application) {
        check(application.packageName == "app.backupduck.catalog")
        application.registerActivityLifecycleCallbacks(this)
        val saved = fixture(application)
        if (saved.exists()) {
            val value = JSONObject(saved.readText())
            val scenario = CatalogRuntime.loadAll(application).first { it.id == value.getString("scenario") }
            CatalogRuntime.apply(application, scenario)
            val language = value.optString("language")
            application.getSharedPreferences("appearance", 0).edit().putInt("mode", value.getInt("mode")).putString("language", language).commit()
            AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(language))
            active = true
        }
        val transport = NativeBridge.transport
        NativeBridge.transport = { request ->
            if (active) {
                val query = JSONObject(request)
                Log.i("DuckCompatibility", JSONObject().put("event", "query").put("op", query.optString("op"))
                    .put("state", query.optString("state")).put("cursor", query.optString("cursor"))
                    .put("callers", JSONArray(Thread.currentThread().stackTrace.map { it.className }.filter { it.startsWith("app.backupduck.") }.distinct())).toString())
            }
            checkNotNull(transport).invoke(request)
        }
    }

    fun configure(context: Context, intent: Intent, scenario: CatalogScenario) {
        active = intent.getBooleanExtra("compatibilityProbe", false)
        savedRoot = null
        seededRoute = null
        restoredRoutes = emptyList()
        lastCommand = ""
        if (active) fixture(context).writeText(JSONObject().put("scenario", scenario.id)
            .put("mode", context.getSharedPreferences("appearance", 0).getInt("mode", 1))
            .put("language", AppCompatDelegate.getApplicationLocales().toLanguageTags()).toString())
        else fixture(context).delete()
        file(context, "command").delete()
    }

    @Suppress("DEPRECATION")
    override fun onActivityPreCreated(activity: Activity, state: Bundle?) {
        if (activity is CatalogActivity) textScale = activity.intent.takeIf { it.hasExtra("fontScale") }?.getFloatExtra("fontScale", 1f)?.coerceIn(1f, 2f)
        val scale = textScale ?: return
        val configuration = android.content.res.Configuration(activity.resources.configuration)
        configuration.fontScale = scale
        activity.resources.updateConfiguration(configuration, activity.resources.displayMetrics)
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) {
        if (!active || activity !is MainActivity || state == null) return
        restoredRoutes = activity.supportFragmentManager.fragments.filterIsInstance<PageFragment>().mapNotNull { it.arguments?.getString("route") }
        val pending = file(activity, "pending-result")
        if (!pending.exists()) return
        val code = JSONObject(pending.readText()).getString("contents")
        pending.delete()
        val registry = Bundle().also(activity.activityResultRegistry::onSaveInstanceState)
        val keys = checkNotNull(registry.getStringArrayList("KEY_COMPONENT_ACTIVITY_REGISTERED_KEYS"))
        val codes = checkNotNull(registry.getIntegerArrayList("KEY_COMPONENT_ACTIVITY_REGISTERED_RCS"))
        val requestCode = codes[keys.indexOf("activity_rq#0")]
        check(activity.activityResultRegistry.dispatchResult(requestCode, Activity.RESULT_OK,
            Intent().putExtra("SCAN_RESULT", code).putExtra("SCAN_RESULT_FORMAT", "QR_CODE")))
        Log.i("DuckCompatibility", "Queued camera Activity result before STARTED")
    }

    override fun onActivityResumed(activity: Activity) {
        if (!active || activity !is MainActivity) return
        val root = activity.window.decorView
        fun poll() {
            if (activity.isDestroyed || !root.isAttachedToWindow || !activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) return
            val command = file(activity, "command")
            if (command.exists()) {
                val value = JSONObject(command.readText())
                if (value.getString("id") != lastCommand) {
                    lastCommand = value.getString("id")
                    when (value.getString("action")) {
                        "seed-route" -> {
                            activity.supportFragmentManager.popBackStackImmediate(null, androidx.fragment.app.FragmentManager.POP_BACK_STACK_INCLUSIVE)
                            seededRoute = value.getString("route")
                            activity.pushPage(PageFragment().apply {
                            arguments = Bundle().apply { putString("route", value.getString("route")); putBundle("state", Bundle().apply { putBoolean("scan", value.optBoolean("scan")); putString("surface", "connect-mac") }) }
                            })
                        }
                        "saved-root" -> {
                            savedRoot = value.getInt("page")
                            activity.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId = if (savedRoot == 3) 4 else savedRoot!!
                        }
                        "snapshot" -> Unit
                        else -> error("Unknown compatibility fixture command")
                    }
                    root.postDelayed({ snapshot(activity) }, 700)
                }
            }
            root.postDelayed({ poll() }, 500)
        }
        root.postDelayed({ poll() }, 500)
        root.postDelayed({ snapshot(activity) }, 900)
    }

    private fun snapshot(activity: MainActivity) {
        if (activity.isDestroyed) return
        fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
            (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
        val top = activity.supportFragmentManager.primaryNavigationFragment as? PageFragment
        val list = activity.findViewById<RecyclerView>(R.id.receiver_photos_list)
        val rows = (list?.adapter as? ListAdapter<*, *>)?.currentList.orEmpty()
        val absent = listOf("ReceiverHome", "HistoryPage", "TransferAdapter", "StoragePage", "PairingUI", "PhotosProbeActivity", "DiagnosticRoutes", "OriginalArchive").associateWith {
            runCatching { Class.forName("app.backupduck.$it", false, activity.classLoader) }.isFailure
        }
        val result = JSONObject().put("command", lastCommand).put("pid", android.os.Process.myPid())
            .put("root", activity.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId)
            .put("route", top?.page?.route).put("savedRoute", top?.arguments?.getString("route"))
            .put("restoredRoutes", JSONArray(restoredRoutes))
            .put("stack", activity.supportFragmentManager.backStackEntryCount).put("oldTypesAbsent", JSONObject(absent))
            .put("photoIDs", JSONArray(rows.filterIsInstance<PhotoRow.Tile>().map { it.item.id }))
            .put("rowKeys", JSONArray(rows.filterIsInstance<PhotoRow>().map { it.key }))
            .put("needsYou", rows.any { it is PhotoRow.NeedsHeader })
            .put("firstVisible", (list?.layoutManager as? androidx.recyclerview.widget.LinearLayoutManager)?.findFirstVisibleItemPosition())
            .put("classes", JSONArray(views(activity.window.decorView).map { it.javaClass.simpleName }.distinct()))
        file(activity, "result").writeText(result.toString(2))
        Log.i("DuckCompatibility", result.toString())
    }

    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {
        if (active && activity is MainActivity) savedRoot?.let { state.putInt("page", it) }
    }
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {
        // Simulate arguments written by an older app before killing this Catalog process.
        if (active && activity is MainActivity) seededRoute?.let { route ->
            (activity.supportFragmentManager.primaryNavigationFragment as? PageFragment)?.arguments?.putString("route", route)
        }
    }
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
