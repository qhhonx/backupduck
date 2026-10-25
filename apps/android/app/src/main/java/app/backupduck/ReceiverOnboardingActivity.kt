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
import androidx.activity.OnBackPressedCallback
import androidx.lifecycle.lifecycleScope
import app.backupduck.FirstRunStep as Step
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
 * shared components, retained until the final space choice is made.
 */
class ReceiverOnboardingActivity : BackupDuckActivity() {
    private lateinit var band: FrameLayout
    private lateinit var progress: FrameLayout
    private lateinit var pageScroll: ScrollView
    private lateinit var content: LinearLayout
    private lateinit var fine: TextView
    private lateinit var primary: MaterialButton
    private lateinit var secondary: MaterialButton
    private var step = Step.WELCOME
    private var askedNotify = false
    private var askedBattery = false
    private var watcher: Job? = null
    private var senderName: String? = null
    private var connectScan: ((String?) -> Unit)? = null
    private val cameraPermission = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchScanner() else finishScan(null)
    }
    private fun finishScan(contents: String?) {
        val owner = connectScan; connectScan = null; owner?.invoke(contents)
    }
    private val scanner = registerForActivityResult(com.journeyapps.barcodescanner.ScanContract()) { result ->
        finishScan(if (result.originalIntent?.getBooleanExtra(ReceiverScanActivity.CAMERA_UNAVAILABLE, false) == true)
            ReceiverScanActivity.CAMERA_UNAVAILABLE else result.contents)
    }
    /** The same connect flow as the hub and the device page (design/pixel-connect.md), under the second step mark. */
    private val connect by lazy {
        ConnectFlow(this, content, primary, secondary, window, ::scanCode, {
            ReceiverPreferences.setEnabled(this, true); runCatching { ReceiverEnvironment.startService(this) }
        }, R.string.onb_next, { show(Step.GPHOTOS) }) { showProgress(2) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        val background = getColor(R.color.duck_role_background)
        step = Step.restore(savedInstanceState?.getString("step") ?: intent.getStringExtra("step"))
        if (packageName.endsWith(".catalog")) {
            val scripted = savedInstanceState?.getString("step") ?: intent.getStringExtra("step")
            step = Step.entries.firstOrNull { it.name.equals(scripted, true) } ?: Step.WELCOME
        }
        askedNotify = savedInstanceState?.getBoolean("askedNotify") ?: false
        askedBattery = savedInstanceState?.getBoolean("askedBattery") ?: false
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(background) }
        val margin = token(R.dimen.duck_space_large)
        progress = FrameLayout(this).apply { setPadding(margin, margin, margin, 0) }
        root.addView(progress, LinearLayout.LayoutParams(-1, -2))
        val page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        band = FrameLayout(this)
        // The band gives way to the words at large text sizes, so the welcome still fits one screen.
        page.addView(band, LinearLayout.LayoutParams(-1, DuckFirstRunMetrics.heroHeight(this)))
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(margin, margin, margin, token(R.dimen.duck_space_medium)) }
        page.addView(content, LinearLayout.LayoutParams(-1, -2))
        pageScroll = ScrollView(this).apply { addView(page) }
        root.addView(pageScroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(margin, token(R.dimen.duck_space_x_small), margin, token(R.dimen.duck_space_medium)) }
        fine = lookText(getString(R.string.onb_fine_print), M.style.TextAppearance_Material3_BodySmall, secondary = true).apply { gravity = Gravity.CENTER_HORIZONTAL }
        actions.addView(fine, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = token(R.dimen.duck_space_small) })
        primary = lookButton("", LookButton.FILLED, large = true) {}
        secondary = lookButton("", LookButton.TEXT, large = true) {}
        actions.addView(primary, LinearLayout.LayoutParams(-1, -2))
        actions.addView(secondary, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_xx_small) })
        root.addView(actions)
        setContentView(root)
        show(step)
        if (step == Step.CODE) savedInstanceState?.getBundle("connect")?.let { state ->
            connect.restore(state)
            if (state.getBoolean("scan")) connectScan = connect::scanned
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (step == Step.CODE && connect.back()) return
                val previous = step.previous
                if (previous == null) moveTaskToBack(true) else show(previous)
            }
        })
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("step", if (packageName.endsWith(".catalog")) step.name else step.resumable.name)
        outState.putBoolean("askedNotify", askedNotify)
        outState.putBoolean("askedBattery", askedBattery)
        if (step == Step.CODE) outState.putBundle("connect", connect.snapshot())
        super.onSaveInstanceState(outState)
    }

    override fun onResume() {
        super.onResume()
        // Permissions and Smart Storage may have changed in Settings.
        if (step == Step.SPACE || step == Step.RUNNING) show(step)
        if (step == Step.CODE) connect.resume()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (step == Step.RUNNING) show(Step.RUNNING)
    }

    override fun onDestroy() { watcher?.cancel(); connect.stop(); super.onDestroy() }

    private val firstRun get() = getSharedPreferences("first_run", MODE_PRIVATE)
    private fun complete() { firstRun.edit().putBoolean("done", true).remove("step").apply() }

    private fun scanCode(done: (String?) -> Unit) {
        ReceiverEnvironment.scanOverride?.let { it(done); return }
        connectScan = done
        if (androidx.core.content.ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            launchScanner()
        } else cameraPermission.launch(Manifest.permission.CAMERA)
    }
    private fun launchScanner() {
        if (connectScan == null) return
        runCatching {
            scanner.launch(com.journeyapps.barcodescanner.ScanOptions().setDesiredBarcodeFormats(com.journeyapps.barcodescanner.ScanOptions.QR_CODE)
                .setPrompt(getString(R.string.connect_mac_title)).setBeepEnabled(false).setBarcodeImageEnabled(false)
                .addExtra(com.google.zxing.client.android.Intents.Scan.SHOW_MISSING_CAMERA_PERMISSION_DIALOG, false)
                .setCaptureActivity(ReceiverScanActivity::class.java).setOrientationLocked(true))
        }.onFailure { finishScan(null) }
    }

    private fun show(next: Step) {
        step = next
        // The connected screen needs the live sender, so an interruption resumes after it.
        // Catalog scenarios open single steps and must not leave a flow to resume.
        if (!packageName.endsWith(".catalog")) firstRun.edit().putString("step", next.resumable.name).apply()
        watcher?.cancel()
        connect.stop()
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        content.removeAllViews(); band.removeAllViews()
        progress.removeAllViews()
        progress.visibility = if (next == Step.WELCOME) View.GONE else View.VISIBLE
        content.setPadding(content.paddingLeft, if (next == Step.WELCOME) token(R.dimen.duck_space_large) else 0,
            content.paddingRight, content.paddingBottom)
        pageScroll.scrollTo(0, 0)
        band.visibility = if (next == Step.WELCOME) View.VISIBLE else View.GONE
        fine.visibility = if (next == Step.WELCOME) View.VISIBLE else View.GONE
        secondary.visibility = View.GONE
        primary.visibility = View.VISIBLE
        when (next) {
            Step.WELCOME -> {
                // V1: brand colour belongs to the illustration, never the canvas.
                band.setBackgroundColor(getColor(R.color.duck_role_background))
                band.addView(ImageView(this).apply { setImageResource(R.drawable.duck_welcome); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                    FrameLayout.LayoutParams(DuckFirstRunMetrics.heroSize(this), DuckFirstRunMetrics.heroSize(this), Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM).apply { bottomMargin = token(R.dimen.duck_space_medium) })
                title(getString(R.string.onb_title), centered = true)
                lead(getString(R.string.onb_subtitle))
                stepRow(1, R.string.onb_step_install)
                stepRow(2, R.string.onb_step_connect)
                stepRow(3, R.string.onb_step_backup)
                action(R.string.onb_start) { show(Step.RUNNING) }
            }
            Step.RUNNING -> {
                showProgress(1)
                title(getString(R.string.onb_running_title))
                lead(getString(R.string.onb_running_lead))
                val group = lookGroup(content)
                (group.parent as View).let { (it.layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_large) }
                val notifying = androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()
                val unrestricted = getSystemService(android.os.PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
                lookRow(group, R.drawable.ic_bell, getString(R.string.onb_running_notify), getString(R.string.onb_running_notify_note), done(notifying))
                lookRow(group, R.drawable.ic_bolt, getString(R.string.onb_running_battery), getString(R.string.onb_running_battery_note), done(unrestricted))
                lookRow(group, R.drawable.ic_wifi, getString(R.string.onb_running_wifi), getString(R.string.onb_running_power))
                // One system confirmation at a time; the step re-renders when each
                // returns, and moves on once each missing item has been asked once.
                val pending = (!notifying && !askedNotify) || (!unrestricted && !askedBattery)
                action(if (pending) R.string.onb_allow else R.string.onb_next) {
                    when {
                        !notifying && !askedNotify -> {
                            askedNotify = true
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                            } else {
                                runCatching { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)) }
                            }
                        }
                        !unrestricted && !askedBattery -> {
                            askedBattery = true
                            runCatching { startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, android.net.Uri.parse("package:$packageName"))) }
                                .onFailure { runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } }
                        }
                        else -> {
                            ReceiverPreferences.setEnabled(this, true)
                            runCatching { ReceiverEnvironment.startService(this) }
                            show(Step.CODE)
                        }
                    }
                }
            }
            Step.CODE -> connect.showCode()
            Step.CONNECTED -> connect.showConnected(intent.getStringExtra("senderName") ?: senderName, mac = false)
            Step.GPHOTOS -> {
                showProgress(3)
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
                showProgress(3)
                title(getString(R.string.onb_space_title))
                lead(getString(R.string.onb_space_smart_lead))
                val group = lookGroup(content)
                lookRow(group, R.drawable.ic_storage, getString(R.string.onb_space_smart), smartStorageLabel())
                val details = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    val inset = token(R.dimen.duck_space_medium)
                    setPadding(inset + dp(24) + inset, token(R.dimen.duck_space_x_small), inset, 0)
                }
                details.addView(lookText(getString(R.string.storage_free_up_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
                details.addView(lookButton(getString(R.string.onb_space_try_auto), LookButton.TEXT) {
                    complete()
                    startActivity(Intent(this, MainActivity::class.java).putExtra("destination", "storage").putExtra("surface", "auto-cleanup"))
                    finish()
                }.apply { setPadding(0, paddingTop, 0, paddingBottom) },
                    LinearLayout.LayoutParams(-2, -2))
                content.addView(details, LinearLayout.LayoutParams(-1, -2))
                val openSmartStorage = {
                    runCatching { startActivity(smartStorageIntent()) }
                        .recoverCatching { startActivity(Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)) }
                        .onSuccess { complete(); finish() }
                        .onFailure { lead(getString(R.string.storage_smart_unavailable)) }
                    Unit
                }
                if (ReceiverEnvironment.smartStorage(this) == true) {
                    action(R.string.onb_next) { complete(); finish() }
                    secondary(R.string.onb_space_open_smart, openSmartStorage)
                } else {
                    action(R.string.onb_space_open_smart, openSmartStorage)
                    secondary(R.string.onb_later) { complete(); finish() }
                }
            }
        }
    }

    // ---- Building blocks ----

    private fun action(text: Int, onClick: () -> Unit) { primary.text = getString(text); primary.setOnClickListener { onClick() } }
    private fun secondary(text: Int, onClick: () -> Unit) { secondary.visibility = View.VISIBLE; secondary.text = getString(text); secondary.setOnClickListener { onClick() } }

    /** Permission rows use the same explicit state for granted and denied access. */
    private fun done(granted: Boolean): View = lookText(getString(if (granted) R.string.onb_allowed else R.string.onb_not_allowed),
        M.style.TextAppearance_Material3_BodySmall, secondary = true)

    /** Guided-flow title: balanced wrapping preserves explicit paragraph breaks in the copy. */
    private fun title(text: String, centered: Boolean = true) {
        content.addView(lookText(text, M.style.TextAppearance_Material3_HeadlineSmall).apply {
            isAccessibilityHeading = true
            typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
            if (centered) gravity = Gravity.CENTER_HORIZONTAL
        },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_medium); bottomMargin = token(R.dimen.duck_space_small) })
    }

    private fun lead(text: String) = content.addView(lookText(text, M.style.TextAppearance_Material3_BodyLarge, secondary = true).apply { gravity = Gravity.CENTER_HORIZONTAL })

    /** A fixed square optical column, no taller than two body lines. */
    private fun stepRow(number: Int, title: Int) {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        row.addView(DuckStepMark(this, number, compact = true), LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginEnd = token(R.dimen.duck_space_small) })
        val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        words.addView(lookText(getString(title), M.style.TextAppearance_Material3_BodyLarge))
        val note = when (number) { 1 -> R.string.onb_step_install_note; 2 -> R.string.onb_step_connect_note; else -> R.string.onb_step_backup_note }
        words.addView(lookText(getString(note), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        row.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_x_small) })
    }

    /** A fixed header shared by every screen in the first-run flow. */
    private fun showProgress(current: Int) {
        progress.removeAllViews()
        progress.addView(DuckStepProgress(this, current), FrameLayout.LayoutParams(-2, dp(36)))
    }
}
