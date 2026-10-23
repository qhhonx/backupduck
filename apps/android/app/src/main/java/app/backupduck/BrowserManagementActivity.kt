package app.backupduck

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.lifecycleScope
import com.google.android.material.R as M
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Preferences and credentials are separate from sender pairing and receiving tasks. */
class BrowserManagementActivity : BackupDuckActivity() {
    private lateinit var toggle: com.google.android.material.materialswitch.MaterialSwitch
    private lateinit var content: LinearLayout
    private lateinit var status: TextView
    private var codeView: TextView? = null
    private var reveal: View? = null
    private var secret = ""
    private var address = ""
    private var reading: Job? = null
    private var changing = false
    private var generation = 0
    private var ready = false
    private val captureFixture get() = packageName.endsWith(".catalog") || packageName.endsWith(".validation")

    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        // Real credentials keep the entire window secure. Catalog captures only masked fixtures.
        if (!captureFixture) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        nativeDetailPage(R.string.pref_browser) { panel ->
            toggle = lookSwitchRow(lookGroup(panel), R.drawable.ic_computer, getString(R.string.browser_enable),
                getString(R.string.browser_enable_note), ReceiverDashboardSettings.enabled(this)) { setEnabled(it) }.toggle
            content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            panel.addView(content, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_large) })
            status = lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
                accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
                visibility = View.GONE
            }
            panel.addView(status, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        }
        render(if (ReceiverDashboardSettings.enabled(this)) "starting" else "off")
        lifecycleScope.launch {
            ReceiverState.snapshot.map { it.phase to it.error }.distinctUntilChanged().collect { (phase, error) ->
                if (!changing && ReceiverDashboardSettings.enabled(this@BrowserManagementActivity)) {
                    when (phase) {
                        "ready" -> load()
                        "starting" -> { cancelRead(); render("starting") }
                        "waiting" -> { cancelRead(); render("failed", error) }
                        else -> { cancelRead(); render("failed", "receiver_stopped") }
                    }
                }
            }
        }
    }

    private suspend fun request(op: String) = withContext(Dispatchers.IO) {
        NativeBridge.request(JSONObject().put("op", op)) as JSONObject
    }
    private fun feedback(text: String) { status.setSupporting(text) }
    private fun cancelRead() { generation++; reading?.cancel(); reading = null }
    private fun setEnabled(on: Boolean) {
        if (changing) return
        feedback(""); hideCode(); cancelRead()
        if (on) {
            ReceiverDashboardSettings.setEnabled(this, true)
            begin()
        } else {
            changing = true; toggle.isEnabled = false
            render("starting")
            lifecycleScope.launch {
                try {
                    if (ReceiverState.snapshot.value.phase == "ready") request("stop_dashboard")
                    ReceiverDashboardSettings.setEnabled(this@BrowserManagementActivity, false)
                    render("off")
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) {
                    toggle.restore(true); render("failed", "disable_failed")
                } finally { changing = false; toggle.restore(ReceiverDashboardSettings.enabled(this@BrowserManagementActivity)); toggle.isEnabled = true }
            }
        }
    }
    private fun begin() {
        feedback(""); render("starting")
        if (ReceiverState.snapshot.value.phase == "ready") load()
        else {
            ReceiverPreferences.setEnabled(this, true)
            ReceiverState.mutable.value = ReceiverState.snapshot.value.copy(phase = "starting", error = null)
            runCatching { ReceiverEnvironment.startService(this) }.onFailure { render("failed") }
        }
    }
    private fun load() {
        cancelRead(); val ticket = generation
        render("starting")
        reading = lifecycleScope.launch {
            try {
                request("start_dashboard")
                val info = request("dashboard_info")
                if (ticket != generation || !ReceiverDashboardSettings.enabled(this@BrowserManagementActivity)) return@launch
                address = info.getString("url"); secret = info.getString("code")
                render("ready")
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { if (ticket == generation) render("failed") }
        }
    }
    private fun render(state: String, error: String? = null) {
        hideCode(); ready = state == "ready"
        if (!ready) { secret = ""; address = "" }
        codeView = null; reveal = null; content.removeAllViews()
        when (state) {
            "off" -> Unit
            "starting" -> content.addView(lookText(getString(R.string.duck_browser_starting), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
            "failed" -> {
                val message = when (error) {
                    "receiver_port_in_use" -> R.string.duck_start_port_busy
                    "receiver_interface_unavailable", "wifi_required", "receiver_address_changed" -> R.string.duck_start_network_failed
                    "receiver_stopped" -> R.string.browser_receiver_stopped
                    "disable_failed" -> R.string.browser_disable_failed
                    else -> R.string.dashboard_unavailable
                }
                content.addView(lookText(getString(message), M.style.TextAppearance_Material3_BodyMedium))
                content.addView(lookButton(getString(R.string.duck_retry), LookButton.TEXT) { if (error == "disable_failed") setEnabled(false) else begin() })
            }
            "ready" -> readyRows()
        }
    }
    @SuppressLint("ClickableViewAccessibility")
    private fun readyRows() {
        val access = DashboardAccessUI(this, changed = { feedback(it); load() })
        val group = lookGroup(content)
        val copy = lookButton(getString(R.string.browser_copy), LookButton.TEXT) {
            runCatching {
                (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("BackupDuck", address))
            }.onSuccess { feedback(getString(R.string.duck_address_copied)) }
                .onFailure { feedback(getString(R.string.browser_copy_failed)) }
        }
        lookRow(group, null, getString(R.string.duck_management_address), address, trailing = copy)
        val held = lookButton(getString(R.string.browser_hold_reveal), LookButton.TEXT) {}.apply {
            contentDescription = getString(R.string.browser_hold_reveal_description)
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        view.parent.requestDisallowInterceptTouchEvent(true)
                        view.isPressed = true
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        // Adopt the secure window before exposing even the synthetic fixture.
                        view.post { if (view.isPressed && ready && hasWindowFocus()) codeView?.text = secret }
                    }
                    MotionEvent.ACTION_MOVE -> if (event.x !in 0f..view.width.toFloat() || event.y !in 0f..view.height.toFloat()) hideCode()
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { view.parent.requestDisallowInterceptTouchEvent(false); hideCode() }
                }
                true
            }
            setOnKeyListener { view, key, event ->
                if (key != android.view.KeyEvent.KEYCODE_DPAD_CENTER && key != android.view.KeyEvent.KEYCODE_ENTER) false
                else {
                    if (event.action == android.view.KeyEvent.ACTION_DOWN) {
                        view.isPressed = true; window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        view.post { if (view.isPressed && ready && hasWindowFocus()) codeView?.text = secret }
                    } else hideCode()
                    true
                }
            }
        }
        reveal = held
        codeView = lookRow(group, null, getString(R.string.duck_access_code), "••••••••••", trailing = held).apply {
            tag = "browser.code"
            typeface = android.graphics.Typeface.MONOSPACE
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            isSaveEnabled = false
        }
        lookRow(group, null, getString(R.string.dashboard_manage_code)) { hideCode(); access.code() }
        lookRow(group, null, getString(R.string.duck_reset_random_code)) { hideCode(); access.reset() }
        lookRow(group, null, getString(R.string.dashboard_revoke)) { hideCode(); access.revoke() }
        content.addView(lookText(getString(R.string.browser_private_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
    }
    private fun hideCode() {
        reveal?.isPressed = false
        codeView?.text = "••••••••••"
        // Clear only after a masked frame, and only for isolated synthetic Catalog captures.
        if (captureFixture) window.decorView.postOnAnimation {
            if (reveal?.isPressed != true) window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) { super.onWindowFocusChanged(hasFocus); if (!hasFocus) hideCode() }
    override fun onPause() { hideCode(); super.onPause() }
    override fun onDestroy() { cancelRead(); hideCode(); secret = ""; address = ""; super.onDestroy() }
}
