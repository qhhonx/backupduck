package app.backupduck

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.android.material.R as M
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * First run on the Pixel (design/flows.md § First run, P6): one decision per
 * screen, the step mark of the journey on top, the primary action fixed at the
 * bottom (I2 guided flow) and system prompts explained first. Built from the
 * shared components; shown by the design catalog until migration step 6 opens
 * it on first launch.
 */
class ReceiverOnboardingActivity : BackupDuckActivity() {
    enum class Step { WELCOME, RUNNING, CODE, CONNECTED, GPHOTOS, SPACE }

    private lateinit var band: FrameLayout
    private lateinit var content: LinearLayout
    private lateinit var fine: TextView
    private lateinit var primary: MaterialButton
    private lateinit var secondary: MaterialButton
    private var step = Step.WELCOME
    private var watcher: Job? = null
    private var senderName: String? = null
    private var connectScan: ((String?) -> Unit)? = null
    private val scanner = registerForActivityResult(com.journeyapps.barcodescanner.ScanContract()) { result ->
        connectScan?.let { connectScan = null; it(result.contents) }
    }
    /** The same connect flow as the hub and the device page (design/pixel-connect.md), under the second step mark. */
    private val connect by lazy {
        ConnectFlow(this, content, primary, secondary, window, ::scanCode, {
            ReceiverPreferences.setEnabled(this, true); runCatching { ReceiverEnvironment.startService(this) }
        }, R.string.onb_next, { show(Step.GPHOTOS) }) { it.addView(marks(2)) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        val background = getColor(R.color.duck_role_background)
        step = intent.getStringExtra("step")?.let { name -> Step.values().firstOrNull { it.name.equals(name, true) } } ?: Step.WELCOME
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(background) }
        val page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        band = FrameLayout(this)
        // The band gives way to the words at large text sizes, so the welcome still fits one screen.
        page.addView(band, LinearLayout.LayoutParams(-1, dp(if (resources.configuration.fontScale > 1.15f) 140 else 200)))
        val margin = token(R.dimen.duck_space_large)
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(margin, margin, margin, token(R.dimen.duck_space_medium)) }
        page.addView(content, LinearLayout.LayoutParams(-1, -2))
        root.addView(ScrollView(this).apply { addView(page) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(margin, token(R.dimen.duck_space_x_small), margin, token(R.dimen.duck_space_medium)) }
        fine = lookText(getString(R.string.onb_fine_print), M.style.TextAppearance_Material3_BodySmall, secondary = true)
        actions.addView(fine, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = token(R.dimen.duck_space_small) })
        primary = lookButton("", LookButton.FILLED, large = true) {}
        secondary = lookButton("", LookButton.TEXT, large = true) {}
        actions.addView(primary, LinearLayout.LayoutParams(-1, -2))
        actions.addView(secondary, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_xx_small) })
        root.addView(actions)
        setContentView(root)
        show(step)
    }

    override fun onResume() {
        super.onResume()
        // Permissions and Smart Storage may have changed in Settings.
        if (step == Step.SPACE || step == Step.RUNNING) show(step)
    }

    override fun onDestroy() { watcher?.cancel(); connect.stop(); super.onDestroy() }

    private fun scanCode(done: (String?) -> Unit) {
        ReceiverEnvironment.scanOverride?.let { it(done); return }
        connectScan = done
        runCatching {
            scanner.launch(com.journeyapps.barcodescanner.ScanOptions().setDesiredBarcodeFormats(com.journeyapps.barcodescanner.ScanOptions.QR_CODE)
                .setPrompt(getString(R.string.connect_mac_title)).setBeepEnabled(false).setBarcodeImageEnabled(false)
                .setCaptureActivity(ReceiverScanActivity::class.java).setOrientationLocked(true))
        }.onFailure { connectScan = null; done(null) }
    }

    private fun show(next: Step) {
        step = next
        watcher?.cancel()
        connect.stop()
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        content.removeAllViews(); band.removeAllViews()
        band.visibility = if (next == Step.WELCOME) View.VISIBLE else View.GONE
        fine.visibility = if (next == Step.WELCOME) View.VISIBLE else View.GONE
        secondary.visibility = View.GONE
        primary.visibility = View.VISIBLE
        when (next) {
            Step.WELCOME -> {
                // The welcome's brand moment: the duck on duck yellow's tint (V1, V6); a quiet surface in dark mode.
                val night = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
                band.setBackgroundColor(getColor(if (night) R.color.duck_role_grouped_surface else R.color.duck_illustration_duck_yellow_tint))
                band.addView(ImageView(this).apply { setImageResource(R.drawable.duck_welcome); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                    FrameLayout.LayoutParams(dp(144), dp(144), Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM).apply { bottomMargin = token(R.dimen.duck_space_medium) })
                title(getString(R.string.onb_title))
                lead(getString(R.string.onb_subtitle))
                stepRow(1, R.string.onb_step_install)
                stepRow(2, R.string.onb_step_connect)
                stepRow(3, R.string.onb_step_backup)
                action(R.string.onb_start) { show(Step.RUNNING) }
            }
            Step.RUNNING -> {
                content.addView(marks(1))
                title(getString(R.string.onb_running_title))
                lead(getString(R.string.onb_running_lead))
                val group = lookGroup(content)
                (group.parent as View).let { (it.layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_large) }
                val notifying = Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                val unrestricted = getSystemService(android.os.PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
                lookRow(group, R.drawable.ic_bell, getString(R.string.onb_running_notify), getString(R.string.onb_running_notify_note), done(notifying))
                lookRow(group, R.drawable.ic_bolt, getString(R.string.onb_running_battery), getString(R.string.onb_running_battery_note), done(unrestricted))
                lookRow(group, R.drawable.ic_wifi, getString(R.string.onb_running_wifi), getString(R.string.onb_running_power))
                action(R.string.onb_allow) {
                    if (!notifying) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    if (!unrestricted) runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
                    ReceiverPreferences.setEnabled(this, true)
                    runCatching { ReceiverEnvironment.startService(this) }
                    show(Step.CODE)
                }
            }
            Step.CODE -> connect.showCode()
            Step.CONNECTED -> connect.showConnected(senderName, mac = false)
            Step.GPHOTOS -> {
                content.addView(marks(3))
                title(getString(R.string.onb_gphotos_title))
                lead(getString(R.string.onb_gphotos_body))
                val card = lookCard(content, params = LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_large) })
                card.orientation = LinearLayout.HORIZONTAL; card.gravity = Gravity.CENTER_VERTICAL
                card.addView(ImageView(this).apply {
                    setImageResource(R.drawable.ic_photo); imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.duck_role_accent))
                    token(R.dimen.duck_space_small).let { setPadding(it, it, it, it) }
                    background = android.graphics.drawable.GradientDrawable().apply { cornerRadius = token(R.dimen.duck_radius_feature).toFloat(); setColor(getColor(R.color.duck_role_elevated_surface)) }
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(dp(48), dp(48)).apply { marginEnd = token(R.dimen.duck_space_medium) })
                card.addView(lookText(getString(R.string.onb_gphotos_unknown), M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(0, -2, 1f))
                action(R.string.onb_gphotos_open) {
                    packageManager.getLaunchIntentForPackage("com.google.android.apps.photos")?.let { runCatching { startActivity(it) } }
                    show(Step.SPACE)
                }
                secondary(R.string.onb_gphotos_done) { show(Step.SPACE) }
            }
            Step.SPACE -> {
                content.addView(marks(3))
                title(getString(R.string.onb_space_title))
                val smart = Settings.Secure.getInt(contentResolver, "automatic_storage_manager_enabled", 0) == 1
                lead(getString(if (smart) R.string.onb_space_smart_lead_on else R.string.onb_space_smart_lead_off))
                if (!smart) {
                    val group = lookGroup(content)
                    (group.parent as View).let { (it.layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_medium) }
                    lookRow(group, R.drawable.ic_storage, getString(R.string.onb_space_smart), getString(R.string.onb_space_smart_off)) {
                        runCatching { startActivity(Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$AutomaticStorageManagerSettingsActivity"))) }
                    }
                }
                val card = lookCard(content, params = LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_medium) })
                val heading = FlowRow(this, token(R.dimen.duck_space_x_small))
                heading.addView(lookText(getString(R.string.onb_space_auto_title), M.style.TextAppearance_Material3_TitleMedium))
                heading.addView(lookPill(getString(R.string.onb_space_experiment), null))
                card.addView(heading)
                card.addView(lookText(getString(R.string.onb_space_auto_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
                    LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_x_small) })
                action(R.string.onb_space_enable) { startActivity(Intent(this, ExperimentsActivity::class.java)); finish() }
                secondary(R.string.onb_later) { finish() }
            }
        }
    }

    // ---- Building blocks ----

    private fun action(text: Int, onClick: () -> Unit) { primary.text = getString(text); primary.setOnClickListener { onClick() } }
    private fun secondary(text: Int, onClick: () -> Unit) { secondary.visibility = View.VISIBLE; secondary.text = getString(text); secondary.setOnClickListener { onClick() } }

    /** A check at the end of a row whose system permission is already granted. */
    private fun done(granted: Boolean): View? = if (!granted) null else ImageView(this).apply {
        setImageResource(R.drawable.ic_check); imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.duck_state_saved))
        contentDescription = getString(R.string.onb_allowed)
    }.also { it.layoutParams = LinearLayout.LayoutParams(dp(24), dp(24)) }

    /** Guided-flow title: Headline medium (V2). */
    private fun title(text: String) {
        content.addView(lookText(text, M.style.TextAppearance_Material3_HeadlineSmall).apply { isAccessibilityHeading = true },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_medium); bottomMargin = token(R.dimen.duck_space_small) })
    }

    private fun lead(text: String) = content.addView(lookText(text, M.style.TextAppearance_Material3_BodyLarge, secondary = true))

    /** One step of the journey beside its mark, in a single line so the welcome fits one screen. */
    private fun stepRow(number: Int, title: Int) {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        row.addView(mark(number), LinearLayout.LayoutParams(dp(48), dp(36)).apply { marginEnd = token(R.dimen.duck_space_small) })
        val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        words.addView(lookText(getString(title), M.style.TextAppearance_Material3_BodyLarge))
        row.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_x_small) })
    }

    /** One current step mark (V6: one at a time on later steps). */
    private fun marks(current: Int): View = LinearLayout(this).apply {
        gravity = Gravity.CENTER_VERTICAL
        contentDescription = getString(R.string.onb_step_of, current); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        listOf(Triple(R.drawable.mark_circle, 20, 20), Triple(R.drawable.mark_wing, 28, 14), Triple(R.drawable.mark_sparkle, 22, 22)).forEachIndexed { index, (drawable, w, h) ->
            if (index + 1 == current) addView(ImageView(context).apply { setImageResource(drawable); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                LinearLayout.LayoutParams(dp(w), dp(h)).apply { marginEnd = token(R.dimen.duck_space_small) })
        }
    }.also { it.layoutParams = LinearLayout.LayoutParams(-2, dp(28)) }

    /**
     * A step mark with its numeral, for the welcome's list: yellow circle, blue
     * wing, orange sparkle at the same visual weight. The wing is shifted so its
     * thick front carries the numeral.
     */
    private fun mark(number: Int): View {
        val frame = FrameLayout(this).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val (drawable, w, h) = when (number) { 1 -> Triple(R.drawable.mark_circle, 34, 34); 2 -> Triple(R.drawable.mark_wing, 42, 21); else -> Triple(R.drawable.mark_sparkle, 38, 38) }
        frame.addView(ImageView(this).apply { setImageResource(drawable); if (number == 2) translationX = dp(7).toFloat() },
            FrameLayout.LayoutParams(dp(w), dp(h), Gravity.CENTER))
        frame.addView(lookText(number.toString(), M.style.TextAppearance_Material3_TitleMedium,
            // Numerals on brand marks use the illustration ink on yellow and the paper color on the others, as on Apple.
            color = getColor(if (number == 1) R.color.duck_illustration_ink else R.color.duck_illustration_paper)).apply {
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            if (number == 2) translationY = dp(3).toFloat()
        }, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
        return frame
    }
}
