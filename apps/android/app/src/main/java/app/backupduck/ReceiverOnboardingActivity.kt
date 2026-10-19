package app.backupduck

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
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
 * First run on the Pixel (design/flows.md § First run): one decision per screen,
 * the primary action in a fixed place, and system prompts explained first.
 * Shown by the design catalog until migration step 6 opens it on first launch.
 */
class ReceiverOnboardingActivity : AppCompatActivity() {
    enum class Step { WELCOME, RUNNING, CODE, CONNECTED, GPHOTOS, SPACE }

    private lateinit var content: LinearLayout
    private lateinit var primary: MaterialButton
    private lateinit var secondary: MaterialButton
    private var step = Step.WELCOME
    private var watcher: Job? = null
    private var senderName: String? = null
    private var connectScan: ((String?) -> Unit)? = null
    private val scanner = registerForActivityResult(com.journeyapps.barcodescanner.ScanContract()) { result ->
        connectScan?.let { connectScan = null; it(result.contents) }
    }
    /** The same connect flow as the hub and the device page (design/pixel-connect.md). */
    private val connect by lazy {
        ConnectFlow(this, content, primary, secondary, window, ::scanCode, {
            ReceiverPreferences.setEnabled(this, true); runCatching { ReceiverEnvironment.startService(this) }
        }, R.string.onb_next) { show(Step.GPHOTOS) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        step = intent.getStringExtra("step")?.let { name -> Step.values().firstOrNull { it.name.equals(name, true) } } ?: Step.WELCOME
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(themeColor(com.google.android.material.R.attr.colorSurface)) }
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(32), dp(24), dp(16)) }
        root.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(8), dp(24), dp(16)) }
        primary = MaterialButton(this).apply { minimumHeight = dp(52) }
        secondary = MaterialButton(this, null, com.google.android.material.R.attr.borderlessButtonStyle)
        actions.addView(primary, LinearLayout.LayoutParams(-1, -2))
        actions.addView(secondary, LinearLayout.LayoutParams(-1, -2))
        root.addView(actions)
        setContentView(root)
        show(step)
    }

    override fun onResume() {
        super.onResume()
        if (step == Step.SPACE) show(Step.SPACE) // Smart Storage may have changed in Settings.
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
        content.removeAllViews()
        secondary.visibility = View.GONE
        primary.visibility = View.VISIBLE
        when (next) {
            Step.WELCOME -> {
                duck(R.drawable.duck_welcome, 120)
                title(getString(R.string.onb_title), display = true)
                body(getString(R.string.onb_subtitle))
                stepRow(1, R.string.onb_step_install, R.string.onb_step_install_note)
                stepRow(2, R.string.onb_step_connect, R.string.onb_step_connect_note)
                stepRow(3, R.string.onb_step_backup, R.string.onb_step_backup_note)
                caption(getString(R.string.onb_fine_print))
                action(R.string.onb_start) { show(Step.RUNNING) }
            }
            Step.RUNNING -> {
                content.addView(mark(2, 1.25f), LinearLayout.LayoutParams(-2, -2).apply { bottomMargin = dp(12) })
                title(getString(R.string.onb_running_title))
                bullet(R.string.onb_running_wifi); bullet(R.string.onb_running_notify); bullet(R.string.onb_running_battery)
                caption(getString(R.string.onb_running_power))
                action(R.string.onb_allow) {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
                    ReceiverPreferences.setEnabled(this, true)
                    runCatching { ReceiverEnvironment.startService(this) }
                    show(Step.CODE)
                }
            }
            Step.CODE -> connect.showCode()
            Step.CONNECTED -> connect.showConnected(senderName, mac = false)
            Step.GPHOTOS -> {
                content.addView(mark(3, 1.25f), LinearLayout.LayoutParams(-2, -2).apply { bottomMargin = dp(12) })
                title(getString(R.string.onb_gphotos_title))
                body(getString(R.string.onb_gphotos_body))
                action(R.string.onb_gphotos_open) {
                    packageManager.getLaunchIntentForPackage("com.google.android.apps.photos")?.let { runCatching { startActivity(it) } }
                    show(Step.SPACE)
                }
                secondary(R.string.onb_gphotos_done) { show(Step.SPACE) }
            }
            Step.SPACE -> {
                title(getString(R.string.onb_space_title))
                val smart = Settings.Secure.getInt(contentResolver, "automatic_storage_manager_enabled", 0) == 1
                val smartRow = settingsItem(content, R.drawable.ic_storage, getString(R.string.onb_space_smart),
                    getString(if (smart) R.string.onb_space_smart_on else R.string.onb_space_smart_off)) {
                    runCatching { startActivity(Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$AutomaticStorageManagerSettingsActivity"))) }
                }
                smartRow.setTextColor(themeColor(if (smart) com.google.android.material.R.attr.colorPrimary else com.google.android.material.R.attr.colorOnSurfaceVariant))
                settingsItem(content, R.drawable.ic_flask, getString(R.string.onb_space_auto), getString(R.string.onb_space_auto_note))
                action(R.string.onb_space_enable) { startActivity(Intent(this, ExperimentsActivity::class.java)); finish() }
                secondary(R.string.onb_later) { finish() }
            }
        }
    }

    // ---- Building blocks ----

    private fun action(text: Int, onClick: () -> Unit) { primary.text = getString(text); primary.setOnClickListener { onClick() } }
    private fun secondary(text: Int, onClick: () -> Unit) { secondary.visibility = View.VISIBLE; secondary.text = getString(text); secondary.setOnClickListener { onClick() } }

    private fun duck(drawable: Int, size: Int) {
        content.addView(ImageView(this).apply { setImageResource(drawable); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(dp(size), dp(size)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(8) })
    }

    private fun title(text: String, display: Boolean = false, center: Boolean = false) {
        content.addView(TextView(this).apply {
            this.text = text
            setTextAppearance(if (display) com.google.android.material.R.style.TextAppearance_Material3_HeadlineLarge else com.google.android.material.R.style.TextAppearance_Material3_HeadlineSmall)
            setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurface))
            if (center) gravity = Gravity.CENTER_HORIZONTAL
            isAccessibilityHeading = true
        }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(12) })
    }

    private fun body(text: String) {
        content.addView(TextView(this).apply {
            this.text = text
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge)
            setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurfaceVariant))
        }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(16) })
    }

    private fun caption(text: String, center: Boolean = false): TextView = TextView(this).apply {
        this.text = text
        setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall)
        setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurfaceVariant))
        if (center) gravity = Gravity.CENTER_HORIZONTAL
    }.also { content.addView(it, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) }) }

    private fun bullet(text: Int) {
        content.addView(TextView(this).apply {
            this.text = "•  " + getString(text)
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge)
            setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurface))
        }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(8) })
    }

    private fun stepRow(number: Int, title: Int, note: Int) {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        row.addView(mark(number), LinearLayout.LayoutParams(dp(54), dp(40)).apply { marginEnd = dp(12) })
        val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        words.addView(TextView(this).apply { text = getString(title); setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleMedium); setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurface)) })
        words.addView(TextView(this).apply { text = getString(note); setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium); setTextColor(themeColor(com.google.android.material.R.attr.colorOnSurfaceVariant)) })
        row.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(12) })
    }

    /**
     * Step marks: yellow circle, blue wing, orange sparkle at the same visual weight.
     * Numerals share one axis; the wing is shifted so its thick front carries the numeral.
     */
    private fun mark(number: Int, scale: Float = 1f): View {
        fun px(v: Float) = (v * scale * resources.displayMetrics.density).toInt()
        val frame = FrameLayout(this).apply { minimumWidth = px(54f); minimumHeight = px(40f); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val (drawable, w, h) = when (number) { 1 -> Triple(R.drawable.mark_circle, 36f, 36f); 2 -> Triple(R.drawable.mark_wing, 44f, 22f); else -> Triple(R.drawable.mark_sparkle, 40f, 40f) }
        frame.addView(ImageView(this).apply { setImageResource(drawable); if (number == 2) translationX = px(7.8f).toFloat() },
            FrameLayout.LayoutParams(px(w), px(h), Gravity.CENTER))
        frame.addView(TextView(this).apply {
            text = number.toString()
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleMedium)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            // design-exception: numerals on brand marks use the illustration ink and white, as on Apple.
            setTextColor(if (number == 1) Color.parseColor("#102346") else Color.WHITE)
            if (number == 2) translationY = px(3f).toFloat()
        }, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
        return frame
    }
}
