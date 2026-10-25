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
        CatalogIconReview.install()
        CatalogViewerProbe.install(this)
        CatalogCompatibility.install(this)
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
        // The historical `proposed` extra is intentionally ignored.
        ReceiverEnvironment.allowsPhotoMotion = !intent.getBooleanExtra("reduceMotion", false)
        CatalogViewerProbe.pending = intent.getStringExtra("viewerProbe")
        ReceiverEnvironment.stepMarkHighContrast = if (intent.hasExtra("highContrastText")) intent.getBooleanExtra("highContrastText", false) else null
        CatalogOverlay.showInfo = intent.getBooleanExtra("catalogInfo", false)
        CatalogOverlay.selectPhotos = intent.getBooleanExtra("selectPhotos", false)
        CatalogIconReview.pending = intent.getStringExtra("iconReview")
        CatalogIconReview.fault = intent.getStringExtra("iconFault")
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
        CatalogCompatibility.configure(this, intent, scenario)
        if (scenario.surface == "waking") {
            startActivity(Intent(this, CatalogWakeActivity::class.java))
        } else if (scenario.surface == "metadata") {
            val row = (CatalogMedia.history(scenario.core.getValue("receiver_history").first().value) as org.json.JSONObject).getJSONArray("items").getJSONObject(0)
            val item = HistoryItem(row.getLong("cursor"), row.getString("id"), row.getString("filename"), row.getString("kind"),
                row.getLong("total_bytes"), row.optLong("confirmed_bytes"), row.optString("receipt", "received"),
                row.optString("processing", "complete"),
                row.optString("processing_error").takeUnless { it.isBlank() || it == "null" },
                row.optBoolean("originals_released"),
                senderNames = row.optJSONArray("senders")?.let { peers ->
                    (0 until peers.length()).mapNotNull { peers.optJSONObject(it)?.optJSONObject("profile")?.optString("name")?.takeIf(String::isNotBlank) }.joinToString(SENDER_SEPARATOR)
                }.orEmpty(),
                capturedAtMs = CatalogMedia.captureTime(row.optString("id")) ?: row.optLong("captured_at_ms").takeIf { it > 0 },
                receivedAtMs = row.optLong("received_at_ms").takeIf { it > 0 },
                publishedAtMs = row.optLong("published_at_ms").takeIf { it > 0 })
            startActivity(Intent(this, NativePhotoViewerActivity::class.java).putExtra("photo", item.toBundle()))
        } else if (scenario.page == "onboarding") {
            startActivity(Intent(this, ReceiverOnboardingActivity::class.java).putExtra("step", scenario.step).putExtra("senderName", "Lin's iPhone"))
        } else {
            startActivity(Intent(this, MainActivity::class.java).putExtra("destination", scenario.page).putExtra("surface", scenario.launchSurface))
        }
    }
}

/** Scenario review is opt-in via Intent; the production view tree receives no controls or margins. */
internal object CatalogOverlay : Application.ActivityLifecycleCallbacks {
    var showInfo = false
    var selectPhotos = false
    private fun selectSyntheticPhotos(activity: MainActivity, attempt: Int = 0) {
        if (!selectPhotos || activity.isDestroyed) return
        val root = activity.window.decorView
        root.postDelayed({
            fun tiles(view: View): List<View> {
                if (view is androidx.recyclerview.widget.RecyclerView) {
                    return (0 until view.childCount).map { view.getChildAt(it) }.filter {
                        view.getChildViewHolder(it).javaClass.simpleName == "TileHolder"
                    }
                }
                return if (view is ViewGroup) (0 until view.childCount).flatMap { tiles(view.getChildAt(it)) } else emptyList()
            }
            val photos = tiles(root)
            if (photos.size >= 2 && photos[0].performLongClick()) {
                photos[1].performClick()
                selectPhotos = false
            } else if (attempt < 40) selectSyntheticPhotos(activity, attempt + 1)
        }, 100)
    }
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
        if (CatalogRuntime.current?.surface in setOf("action-failure", "action-failure-retry") && activity.window.decorView.tag != "catalog-action-failure") {
            activity.window.decorView.tag = "catalog-action-failure"
            activity.window.decorView.postDelayed({
                if (!activity.isDestroyed && activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) {
                    val retryable = CatalogRuntime.current?.surface == "action-failure-retry"
                    activity.showActionFailure(if (retryable) R.string.receiver_pause_failed else R.string.support_open_failed) {
                        java.io.File(activity.getExternalFilesDir(null), "action-retry.txt").writeText("retry invoked")
                    }
                }
            }, 500)
        }
        CatalogIconReview.attach(activity)
        selectSyntheticPhotos(activity)
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
            .setNeutralButton("Options") { _, _ -> options(activity) }
            .show()
    }

    private fun options(activity: MainActivity) {
        AlertDialog.Builder(activity).setTitle("Review").setItems(arrayOf("Dark / light")) { _, _ ->
            val prefs = activity.getSharedPreferences("appearance", Activity.MODE_PRIVATE)
            val dark = prefs.getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM) == AppCompatDelegate.MODE_NIGHT_YES
            prefs.edit().putInt("mode", if (dark) AppCompatDelegate.MODE_NIGHT_NO else AppCompatDelegate.MODE_NIGHT_YES).commit()
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

/** Preview only: no live cleanup request or keyguard operation. */
class CatalogWakeActivity : BackupDuckActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        setContentView(cleanupWakeContent(this))
    }
}
