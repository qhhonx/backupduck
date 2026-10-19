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
import android.widget.Button
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
        registerActivityLifecycleCallbacks(CatalogOverlay)
    }
}

/**
 * Lists scenarios and opens the production [MainActivity] on one of them.
 * `adb shell am start -n app.backupduck.catalog/app.backupduck.CatalogActivity --es scenario <id>`
 * opens a scenario directly; `--es appearance dark|light` sets the appearance.
 */
class CatalogActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        // `--ez look true` shows the proposed visual language on the proposed pages.
        ReceiverEnvironment.proposedLook = intent.getBooleanExtra("look", ReceiverEnvironment.proposedLook)
        intent.getStringExtra("scenario")?.let { id -> all.firstOrNull { it.id == id }?.let { open(it, intent.getStringExtra("appearance")) } }
        intent.removeExtra("scenario")
    }

    private fun open(scenario: CatalogScenario, appearance: String?) {
        CatalogRuntime.apply(this, scenario)
        appearance?.let {
            val mode = if (it == "dark") AppCompatDelegate.MODE_NIGHT_YES else AppCompatDelegate.MODE_NIGHT_NO
            getSharedPreferences("appearance", MODE_PRIVATE).edit().putInt("mode", mode).commit()
        }
        if (scenario.page == "onboarding") {
            startActivity(Intent(this, ReceiverOnboardingActivity::class.java).putExtra("step", scenario.step))
        } else {
            startActivity(Intent(this, MainActivity::class.java).putExtra("destination", scenario.page).putExtra("surface", scenario.surface))
        }
    }
}

/** A small scenario button over the production page: details, restart and close. */
internal object CatalogOverlay : Application.ActivityLifecycleCallbacks {
    override fun onActivityResumed(activity: Activity) {
        if (activity !is MainActivity) return
        val content = activity.findViewById<FrameLayout>(android.R.id.content)
        if (content.findViewWithTag<View>("catalog") != null) return
        val scenario = CatalogRuntime.current ?: return
        val button = Button(activity).apply {
            tag = "catalog"; text = "ⓘ"; textSize = 16f; alpha = 0.85f
            minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0
            setPadding(activity.dp(12), activity.dp(6), activity.dp(12), activity.dp(6))
            contentDescription = "Scenario"
            setOnClickListener { details(activity, scenario) }
        }
        content.addView(button, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { setMargins(0, activity.dp(10), 0, 0) })
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
                activity.startActivity(Intent(activity, MainActivity::class.java).putExtra("destination", scenario.page).putExtra("surface", scenario.surface)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP))
                activity.finish()
            }
            .setNegativeButton("Close") { _, _ -> activity.finish() }
            .setNeutralButton("Options") { _, _ -> options(activity, scenario) }
            .show()
    }

    private fun options(activity: MainActivity, scenario: CatalogScenario) {
        val design = if (ReceiverEnvironment.proposedDesign) "Design: show current" else "Design: show proposed"
        val look = if (ReceiverEnvironment.proposedLook) "Look: show current" else "Look: show proposed"
        AlertDialog.Builder(activity).setTitle("Review").setItems(arrayOf(design, look, "Dark / light")) { _, which ->
            if (which == 0) {
                ReceiverEnvironment.proposedDesign = !ReceiverEnvironment.proposedDesign
            } else if (which == 1) {
                ReceiverEnvironment.proposedLook = !ReceiverEnvironment.proposedLook
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
