package app.backupduck

import android.app.Activity
import android.app.AlertDialog
import android.app.Application
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate

/** Installs the scenario providers before any receiver page is created. */
class CatalogApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CatalogRuntime.install()
        CatalogViewerProbe.install(this)
        registerActivityLifecycleCallbacks(CatalogOverlay)
    }
}

/**
 * Lists scenarios and opens the production [MainActivity] on one of them.
 * `adb shell am start -n app.backupduck.catalog/app.backupduck.CatalogActivity --es scenario <id>`
 * opens a scenario directly; `--es appearance dark|light` sets the appearance and
 * `--es language zh-CN` the language.
 */
class CatalogActivity : BackupDuckActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CatalogRuntime.referenceUri = intent.data?.takeIf { it.scheme == "content" && it.authority == "media" }
        val scenarios = runCatching { CatalogRuntime.loadAll(this) }
        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(24), dp(16), dp(24)) }
        list.addView(TextView(this).apply { text = "Design catalog"; textSize = 24f; setTypeface(typeface, Typeface.BOLD) })
        scenarios.exceptionOrNull()?.let { list.addView(TextView(this).apply { text = it.message; setTextColor(0xFFB3261E.toInt()) }) }
        val all = scenarios.getOrDefault(emptyList())
        for (page in listOf("onboarding", "receive", "transfers", "storage", "settings")) {
            val items = all.filter { it.page == page }
            if (items.isEmpty()) continue
            list.addView(TextView(this).apply { text = page; textSize = 14f; setPadding(0, dp(20), 0, dp(4)); setTypeface(typeface, Typeface.BOLD) })
            for (scenario in items) list.addView(TextView(this).apply {
                text = "${scenario.title}\n${scenario.id}"; textSize = 16f
                setPadding(0, dp(10), 0, dp(10))
                setOnClickListener { open(scenario, null) }
            })
        }
        setContentView(ScrollView(this).apply { addView(list) })
        // `--ez proposed true` shows the proposed redesign instead of the current page.
        ReceiverEnvironment.proposedDesign = intent.getBooleanExtra("proposed", ReceiverEnvironment.proposedDesign)
        ReceiverEnvironment.allowsPhotoMotion = !intent.getBooleanExtra("reduceMotion", false)
        CatalogViewerProbe.pending = intent.getStringExtra("viewerProbe")
        ReceiverEnvironment.stepMarkHighContrast = if (intent.hasExtra("highContrastText")) intent.getBooleanExtra("highContrastText", false) else null
        CatalogOverlay.showInfo = intent.getBooleanExtra("catalogInfo", false)
        CatalogTextAudit.enabled = intent.getBooleanExtra("auditText", false)
        CatalogTextAudit.staticCapture = intent.getBooleanExtra("staticCapture", false)
        // `--es language zh-CN` shows the pages in that language for this process.
        intent.getStringExtra("language")?.let { AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(it)) }
        intent.getStringExtra("scenario")?.let { id -> all.firstOrNull { it.id == id }?.let { open(it, intent.getStringExtra("appearance")) } }
        intent.removeExtra("scenario")
    }

    private fun open(scenario: CatalogScenario, appearance: String?) {
        CatalogRuntime.apply(this, scenario)
        appearance?.let {
            val mode = if (it == "dark") AppCompatDelegate.MODE_NIGHT_YES else AppCompatDelegate.MODE_NIGHT_NO
            getSharedPreferences("appearance", MODE_PRIVATE).edit().putInt("mode", mode).commit()
        }
        if (scenario.surface == "metadata") {
            val row = (CatalogMedia.history(scenario.core.getValue("receiver_history").first().value) as org.json.JSONObject).getJSONArray("items").getJSONObject(0)
            val item = HistoryItem(row.getLong("cursor"), row.getString("id"), row.getString("filename"), row.getString("kind"),
                row.getLong("total_bytes"), 0, "received", "complete", null, false,
                senderNames = row.optJSONArray("senders")?.let { peers ->
                    (0 until peers.length()).mapNotNull { peers.optJSONObject(it)?.optJSONObject("profile")?.optString("name")?.takeIf(String::isNotBlank) }.joinToString(" · ")
                }.orEmpty(),
                capturedAtMs = row.optLong("captured_at_ms").takeIf { it > 0 },
                receivedAtMs = row.optLong("received_at_ms").takeIf { it > 0 },
                publishedAtMs = row.optLong("published_at_ms").takeIf { it > 0 })
            startActivity(Intent(this, NativePhotoViewerActivity::class.java).putExtra("photo", item.toBundle()))
        } else if (scenario.page == "onboarding") {
            startActivity(Intent(this, ReceiverOnboardingActivity::class.java).putExtra("step", scenario.step))
        } else {
            startActivity(Intent(this, MainActivity::class.java).putExtra("destination", scenario.page).putExtra("surface", scenario.launchSurface))
        }
    }
}

/** Scenario review is opt-in via Intent; the production view tree receives no controls or margins. */
internal object CatalogOverlay : Application.ActivityLifecycleCallbacks {
    var showInfo = false
    override fun onActivityResumed(activity: Activity) {
        CatalogTextAudit.attach(activity)
        if (activity is NativePhotoViewerActivity) CatalogViewerProbe.attach(activity)
        if (activity is NativePhotoViewerActivity && CatalogRuntime.current?.surface == "metadata") {
            val root = activity.window.decorView
            if (root.tag != "metadata-opened") {
                root.tag = "metadata-opened"
                root.post {
                    fun find(view: View): View? {
                        if (view.contentDescription == activity.getString(R.string.viewer_details)) return view
                        if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
                        return null
                    }
                    find(root)?.performClick()
                }
            }
        }
        if (activity !is MainActivity) return
        if (!showInfo) return
        val scenario = CatalogRuntime.current ?: return
        showInfo = false
        activity.window.decorView.post { if (!activity.isFinishing) details(activity, scenario) }
    }

    private fun details(activity: MainActivity, scenario: CatalogScenario) {
        val text = buildString {
            append(scenario.title).append("\n").append(scenario.id).append("\n")
            if (scenario.expect.isNotEmpty()) { append("\nExpected\n"); scenario.expect.forEach { append("• ").append(it).append("\n") } }
            if (scenario.actions.isNotEmpty()) { append("\nActions\n"); scenario.actions.forEach { (a, r) -> append("• ").append(a).append(" → ").append(r).append("\n") } }
            append("\nUnscripted core commands\n")
            val missing = CatalogRuntime.unscripted
            append(if (missing.isEmpty()) "None" else missing.joinToString("\n"))
        }
        AlertDialog.Builder(activity).setTitle("Scenario").setMessage(text)
            .setPositiveButton("Restart") { _, _ ->
                CatalogRuntime.apply(activity, scenario)
                activity.startActivity(Intent(activity, MainActivity::class.java).putExtra("destination", scenario.page).putExtra("surface", scenario.launchSurface)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP))
                activity.finish()
            }
            .setNegativeButton("Close") { _, _ -> activity.finish() }
            .setNeutralButton("Options") { _, _ -> options(activity, scenario) }
            .show()
    }

    private fun options(activity: MainActivity, scenario: CatalogScenario) {
        val design = if (ReceiverEnvironment.proposedDesign) "Design: show current" else "Design: show proposed"
        AlertDialog.Builder(activity).setTitle("Review").setItems(arrayOf(design, "Dark / light")) { _, which ->
            if (which == 0) {
                ReceiverEnvironment.proposedDesign = !ReceiverEnvironment.proposedDesign
            } else {
                val prefs = activity.getSharedPreferences("appearance", Activity.MODE_PRIVATE)
                val dark = prefs.getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM) == AppCompatDelegate.MODE_NIGHT_YES
                prefs.edit().putInt("mode", if (dark) AppCompatDelegate.MODE_NIGHT_NO else AppCompatDelegate.MODE_NIGHT_YES).commit()
            }
            activity.recreate()
        }.show()
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
