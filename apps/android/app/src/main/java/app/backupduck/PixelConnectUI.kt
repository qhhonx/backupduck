package app.backupduck

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDialog
import androidx.lifecycle.lifecycleScope
import com.google.android.material.R as M
import com.google.android.material.button.MaterialButton
import com.google.android.material.progressindicator.CircularProgressIndicator
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Reads the devices the core knows. `last_seen` is in seconds. */
internal suspend fun readDevicePeers(activity: AppCompatActivity): List<DevicePeer> = withContext(Dispatchers.IO) {
    val peers = DeviceProfiles.read(activity).optJSONArray("peers")
    if (peers == null) emptyList() else (0 until peers.length()).mapNotNull { index ->
        val peer = peers.optJSONObject(index) ?: return@mapNotNull null
        val profile = peer.optJSONObject("profile") ?: return@mapNotNull null
        DevicePeer(profile.optString("id"), profile.optString("name"),
            peer.optString("device_type").takeUnless { it.isBlank() || it == "null" }, peer.optLong("last_seen"), peer.optBoolean("enabled", true))
    }
}

/**
 * The one connect flow (design/pixel-connect.md), shared by first run, the hub
 * and the device page: the code an iPhone scans, the Mac direction, and the
 * connected screen. The host owns the screen and its two fixed buttons.
 */
internal class ConnectFlow(private val activity: AppCompatActivity, private val content: LinearLayout,
    private val primary: MaterialButton, private val secondary: MaterialButton, private val secureWindow: Window,
    private val scan: ((String?) -> Unit) -> Unit, private val startReceiving: () -> Unit,
    private val doneLabel: Int, private val done: () -> Unit) {
    private var work: Job? = null
    /** Which direction is showing, so a recreated screen can reopen it. */
    var surface = "pairing"
        private set

    fun stop() { work?.cancel(); work = null; secureWindow.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }

    private fun reset() {
        stop(); content.removeAllViews()
        primary.visibility = View.GONE; secondary.visibility = View.GONE
    }

    fun showCode(): Unit = with(activity) {
        reset(); surface = "pairing"
        heading(getString(R.string.connect_code_title))
        step(1, R.string.connect_step_open); step(2, R.string.connect_step_scan)
        val boxShape = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(themeColor(M.attr.colorSurfaceContainerHigh)) }
        val box = FrameLayout(this).apply { background = boxShape; setPadding(dp(8), dp(8), dp(8), dp(8)) }
        content.addView(box, LinearLayout.LayoutParams(dp(248), dp(248)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(20) })
        val code = ImageView(this).apply { contentDescription = getString(R.string.connect_code_description); visibility = View.GONE }
        box.addView(code, FrameLayout.LayoutParams(-1, -1))
        val spinner = CircularProgressIndicator(this).apply { isIndeterminate = true; contentDescription = getString(R.string.connect_getting_ready) }
        box.addView(spinner, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
        val status = line(getString(R.string.connect_getting_ready), M.style.TextAppearance_Material3_BodyMedium, center = true).apply {
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        line(getString(R.string.connect_code_note), M.style.TextAppearance_Material3_BodySmall, center = true)
        secondary(R.string.connect_mac_instead) { showMac(null) }
        val state = ReceiverState.snapshot.value
        if (state.phase != "ready" || ReceiverState.pairing == null) startReceiving()
        val opened = SystemClock.elapsedRealtime()
        work = lifecycleScope.launch {
            var before: Set<String>? = null
            var shown: String? = null
            var lastPoll = 0L
            while (isActive) {
                val snapshot = ReceiverState.snapshot.value
                val payload = ReceiverState.pairing
                when (codePhase(snapshot.phase, snapshot.error, payload != null, SystemClock.elapsedRealtime() - opened)) {
                    CodePhase.GETTING_READY -> Unit
                    CodePhase.CODE -> if (payload != shown && payload != null) {
                        shown = payload
                        secureWindow.addFlags(WindowManager.LayoutParams.FLAG_SECURE) // The code lets a device send to this Pixel.
                        boxShape.setColor(Color.WHITE) // design-exception: the code sits on white in every theme so cameras can read it.
                        code.setImageBitmap(qr(payload)); code.visibility = View.VISIBLE; spinner.visibility = View.GONE
                        status.setText(R.string.connect_code_auto)
                    }
                    CodePhase.FAILED -> { failed(snapshot); return@launch }
                }
                val now = SystemClock.elapsedRealtime()
                if (now - lastPoll >= 2_000) {
                    lastPoll = now
                    runCatching { readDevicePeers(activity) }.onSuccess { peers ->
                        val known = before
                        if (known == null) before = peers.map { it.id }.toSet()
                        else newlyConnected(known, peers)?.let { showConnected(it.name, mac = false); return@launch }
                    }
                }
                delay(400)
            }
        }
    }

    private fun failed(snapshot: ReceiverSnapshot): Unit = with(activity) {
        reset()
        heading(getString(R.string.connect_code_title))
        val wifi = snapshot.error in setOf("wifi_required", "receiver_interface_unavailable")
        problem(getString(if (wifi) R.string.connect_ready_failed else receiverProblem(snapshot)?.message ?: R.string.connect_ready_failed))
        primary(R.string.connect_try_again) { showCode() }
        secondary(R.string.connect_mac_instead) { showMac(null) }
        // Receiving retries by itself; the code comes back as soon as it is ready.
        work = lifecycleScope.launch {
            while (isActive) {
                if (ReceiverState.snapshot.value.phase == "ready" && ReceiverState.pairing != null) { showCode(); return@launch }
                delay(1_000)
            }
        }
    }

    fun showMac(message: Int?): Unit = with(activity) {
        reset(); surface = "connect-mac"
        content.addView(ImageView(this).apply {
            setImageResource(R.drawable.ic_scan); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            imageTintList = ColorStateList.valueOf(themeColor(M.attr.colorOnSecondaryContainer))
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(themeColor(M.attr.colorSecondaryContainer)) }
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }, LinearLayout.LayoutParams(dp(96), dp(96)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(20) })
        heading(getString(R.string.connect_mac_title))
        line(getString(R.string.connect_mac_body), M.style.TextAppearance_Material3_BodyLarge, center = true)
        line(getString(R.string.connect_mac_camera), M.style.TextAppearance_Material3_BodySmall, center = true)
        message?.let { problem(getString(it)) }
        val cameraOff = message == R.string.connect_camera_off
        if (cameraOff) primary(R.string.connect_open_settings) {
            runCatching { startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))) }
        } else primary(if (message == null) R.string.connect_scan else R.string.connect_scan_again) { scan(::scanned) }
        secondary(R.string.connect_iphone_instead) { showCode() }
    }

    private fun scanned(contents: String?): Unit = with(activity) {
        when (macScan(contents)) {
            MacScan.CANCELLED -> {
                val denied = androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED
                showMac(if (denied && ReceiverEnvironment.scanOverride == null) R.string.connect_camera_off else null)
            }
            MacScan.UNREADABLE -> showMac(R.string.connect_mac_unreadable)
            MacScan.CODE -> connectMac(contents!!)
        }
    }

    private fun connectMac(invite: String): Unit = with(activity) {
        reset()
        content.addView(CircularProgressIndicator(this).apply { isIndeterminate = true }, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(48) })
        line(getString(R.string.connect_mac_connecting), M.style.TextAppearance_Material3_BodyLarge, center = true).apply {
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        if (ReceiverState.snapshot.value.phase != "ready" || ReceiverState.pairing == null) startReceiving()
        val opened = SystemClock.elapsedRealtime()
        work = lifecycleScope.launch {
            // The Mac needs this Pixel's own code, so receiving has to be ready first.
            while (isActive && (ReceiverState.snapshot.value.phase != "ready" || ReceiverState.pairing == null)) {
                if (SystemClock.elapsedRealtime() - opened > CODE_READY_TIMEOUT_MS) { showMac(R.string.connect_mac_failed); return@launch }
                delay(400)
            }
            val pairing = ReceiverState.pairing ?: return@launch
            val result = withContext(Dispatchers.IO) { runCatching {
                NativeBridge.request(JSONObject().put("op", "submit_desktop_pairing").put("invite", JSONObject(invite)).put("pairing", JSONObject(pairing)))
            } }
            if (!isActive) return@launch
            if (result.isSuccess) showConnected(null, mac = true) else showMac(R.string.connect_mac_failed)
        }
    }

    fun showConnected(name: String?, mac: Boolean): Unit = with(activity) {
        reset()
        content.addView(ImageView(this).apply { setImageResource(R.drawable.duck_pairing); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(dp(150), dp(150)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(24); bottomMargin = dp(8) })
        heading(if (mac || name.isNullOrBlank()) getString(if (mac) R.string.connect_connected_mac else R.string.connect_connected_device) else getString(R.string.connect_connected, name))
        line(getString(R.string.connect_connected_body), M.style.TextAppearance_Material3_BodyLarge, center = true)
        primary(doneLabel) { done() }
    }

    // ---- Building blocks ----

    private fun heading(text: String) = content.addView(photoText(activity, text, M.style.TextAppearance_Material3_HeadlineSmall).apply {
        gravity = Gravity.CENTER_HORIZONTAL; isAccessibilityHeading = true
    }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(16) })

    private fun line(text: String, appearance: Int, center: Boolean = false): TextView =
        photoText(activity, text, appearance, secondary = true).apply { if (center) gravity = Gravity.CENTER_HORIZONTAL }
            .also { content.addView(it, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(12) }) }

    private fun problem(text: String) = if (DuckLook.on) {
        // The proposed look: one colored glyph beside neutral text (visual-language.md).
        content.addView(LinearLayout(activity).apply {
            gravity = Gravity.CENTER_VERTICAL; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            setPadding(activity.dp(16), activity.dp(14), activity.dp(16), activity.dp(14))
            background = GradientDrawable().apply { cornerRadius = activity.dp(DuckLook.RADIUS_DP).toFloat(); setColor(activity.themeColor(M.attr.colorSurfaceContainer)) }
            addView(ImageView(activity).apply { setImageResource(R.drawable.ic_alert); imageTintList = ColorStateList.valueOf(activity.getColor(R.color.duck_state_attention)); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                LinearLayout.LayoutParams(activity.dp(24), activity.dp(24)).apply { marginEnd = activity.dp(12) })
            addView(photoText(activity, text, M.style.TextAppearance_Material3_BodyLarge), LinearLayout.LayoutParams(0, -2, 1f))
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(20) })
    } else content.addView(photoText(activity, text, M.style.TextAppearance_Material3_BodyLarge,
        color = activity.getColor(R.color.duck_state_attention)).apply { gravity = Gravity.CENTER_HORIZONTAL; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE },
        LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(20) })

    /** A numbered instruction: the numeral in a tonal circle. */
    private fun step(number: Int, text: Int): Unit = with(activity) {
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        row.addView(photoText(this, number.toString(), M.style.TextAppearance_Material3_LabelLarge, color = themeColor(M.attr.colorOnSecondaryContainer)).apply {
            gravity = Gravity.CENTER; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(themeColor(M.attr.colorSecondaryContainer)) }
        }, LinearLayout.LayoutParams(dp(28), dp(28)).apply { marginEnd = dp(12) })
        row.addView(photoText(this, getString(text), M.style.TextAppearance_Material3_BodyLarge), LinearLayout.LayoutParams(0, -2, 1f))
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    private fun primary(label: Int, action: () -> Unit) { primary.visibility = View.VISIBLE; primary.setText(label); primary.setOnClickListener { action() } }
    private fun secondary(label: Int, action: () -> Unit) { secondary.visibility = View.VISIBLE; secondary.setText(label); secondary.setOnClickListener { action() } }

    private fun qr(payload: String): Bitmap {
        val size = 512
        val matrix = MultiFormatWriter().encode(payload, BarcodeFormat.QR_CODE, size, size)
        // design-exception: QR modules stay pure black on white in every theme so scanners can read them.
        val pixels = IntArray(size * size) { if (matrix[it % size, it / size]) Color.BLACK else Color.WHITE }
        return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
    }
}

/** The connect flow as a full screen over the app, closed with its close button or Back. */
internal class ConnectPage(private val activity: MainActivity, scan: ((String?) -> Unit) -> Unit, startReceiving: () -> Unit,
    private val closed: () -> Unit) : AppCompatDialog(activity, R.style.DuckFullPage) {
    private val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(activity.dp(24), activity.dp(8), activity.dp(24), activity.dp(16)) }
    private val primary = MaterialButton(activity).apply { minimumHeight = activity.dp(52) }
    private val secondary = MaterialButton(activity, null, M.attr.borderlessButtonStyle)
    val flow: ConnectFlow

    init {
        val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(activity.themeColor(M.attr.colorSurface)) }
        root.addView(ImageButton(activity).apply {
            setImageResource(R.drawable.ic_close); contentDescription = activity.getString(R.string.connect_close)
            imageTintList = ColorStateList.valueOf(activity.themeColor(M.attr.colorOnSurfaceVariant))
            val out = android.util.TypedValue(); activity.theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, out, true)
            setBackgroundResource(out.resourceId); setOnClickListener { dismiss() }
        }, LinearLayout.LayoutParams(activity.dp(48), activity.dp(48)).apply { setMargins(activity.dp(4), activity.dp(4), 0, 0) })
        root.addView(ScrollView(activity).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(activity.dp(24), activity.dp(8), activity.dp(24), activity.dp(16)) }
        actions.addView(primary, LinearLayout.LayoutParams(-1, -2)); actions.addView(secondary, LinearLayout.LayoutParams(-1, -2))
        root.addView(actions)
        setContentView(root)
        flow = ConnectFlow(activity, content, primary, secondary, window!!, scan, startReceiving, R.string.connect_done) { dismiss() }
        setOnDismissListener { flow.stop(); closed() }
    }

    override fun show() {
        super.show(); window?.setLayout(-1, -1)
        if (DuckLook.on) window?.let { it.statusBarColor = activity.themeColor(M.attr.colorSurface); it.navigationBarColor = activity.themeColor(M.attr.colorSurface) }
    }
}

/**
 * Connected devices (design/pixel-connect.md § 3): a sentence, one Connect
 * button, then the devices that send here and the ones the user stopped.
 */
internal class DevicesPage(private val activity: MainActivity, private val connect: () -> Unit, private val changed: () -> Unit) {
    private val page = DuckPage(activity, activity.getString(R.string.pref_devices))
    private var load: Job? = null

    fun show() { page.body.setPadding(0, activity.dp(8), 0, activity.dp(24)); page.setOnDismissListener { load?.cancel() }; page.show(); reload() }
    val isShowing: Boolean get() = page.isShowing
    fun dismiss() = page.dismiss()

    fun reload(): Unit = with(activity) {
        load?.cancel()
        load = lifecycleScope.launch {
            val result = runCatching { readDevicePeers(activity) }
            if (!page.isShowing) return@launch
            val body = page.body; body.removeAllViews()
            result.onFailure {
                body.addView(photoText(activity, getString(R.string.devices_load_failed), M.style.TextAppearance_Material3_TitleMedium).apply { gravity = Gravity.CENTER },
                    LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(24), dp(32), dp(24), 0) })
                body.addView(duckButton(getString(R.string.connect_try_again), false) { reload() }, LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(24), dp(16), dp(24), 0) })
            }.onSuccess { peers -> render(deviceGroups(peers)) }
        }
    }

    private fun render(groups: DeviceGroups): Unit = with(activity) {
        val body = page.body
        if (groups.sending.isEmpty() && groups.stopped.isEmpty()) {
            body.addView(ImageView(this).apply { setImageResource(R.drawable.duck_empty); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                LinearLayout.LayoutParams(dp(120), dp(120)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(32) })
            body.addView(photoText(this, getString(R.string.devices_empty_title), M.style.TextAppearance_Material3_HeadlineSmall).apply { gravity = Gravity.CENTER; isAccessibilityHeading = true },
                LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(24), dp(12), dp(24), 0) })
        }
        body.addView(photoText(this, getString(R.string.devices_intro), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
            if (groups.sending.isEmpty() && groups.stopped.isEmpty()) gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(16), dp(8), dp(16), 0) })
        body.addView(duckButton(getString(R.string.rhub_connect), true) { connect() }, LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(16), dp(16), dp(16), dp(8)) })
        if (groups.sending.isNotEmpty()) {
            val section = settingsSection(body, getString(R.string.devices_sending))
            groups.sending.forEach { peer ->
                settingsItem(section, if (peer.computer) R.drawable.ic_computer else R.drawable.ic_receiver, peer.name, lastConnected(peer)) { device(peer) }
            }
        }
        if (groups.stopped.isNotEmpty()) {
            val section = settingsSection(body, getString(R.string.devices_stopped))
            groups.stopped.forEach { peer ->
                settingsItem(section, if (peer.computer) R.drawable.ic_computer else R.drawable.ic_receiver, peer.name, getString(R.string.devices_stopped_row)) { device(peer) }
            }
        }
    }

    private fun lastConnected(peer: DevicePeer): String? {
        if (peer.lastSeenSec <= 0) return null
        val time = shortTime(activity, peer.lastSeenSec * 1000)
        // "Today" heads a day group; inside a sentence it reads "last connected today".
        val sentence = if (activity.resources.configuration.locales[0].language == "en") time.replaceFirstChar { it.lowercase() } else time
        return activity.getString(R.string.devices_last, sentence)
    }

    /** One device: what it is, when it last connected, and the one thing the user can change. */
    private fun device(peer: DevicePeer): Unit = with(activity) {
        val sheet = PhotoSheet(this)
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), 0, dp(24), dp(8)) }
        sheet.body.addView(body)
        body.addView(photoText(this, peer.name, M.style.TextAppearance_Material3_TitleLarge).apply { isAccessibilityHeading = true })
        listOfNotNull(peer.kind, lastConnected(peer)).joinToString(" · ").takeIf { it.isNotEmpty() }?.let {
            body.addView(photoText(this, it, M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
        }
        body.addView(photoText(this, getString(if (peer.enabled) R.string.devices_stop_note else R.string.devices_stopped_note), M.style.TextAppearance_Material3_BodyMedium),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        val failure = photoText(this, getString(R.string.devices_save_failed), M.style.TextAppearance_Material3_BodyMedium, color = getColor(R.color.duck_state_failure)).apply {
            visibility = View.GONE; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        body.addView(failure, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        lateinit var button: View
        button = duckButton(getString(if (peer.enabled) R.string.devices_stop else R.string.devices_resume), !peer.enabled) {
            button.isEnabled = false; failure.visibility = View.GONE
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) { runCatching {
                    NativeBridge.request(JSONObject().put("op", "set_sender_enabled").put("root", "$filesDir/receiver/store").put("id", peer.id).put("enabled", !peer.enabled))
                } }
                button.isEnabled = true
                result.onSuccess {
                    sheet.dismiss(); reload(); changed()
                    duckAcknowledge(getString(if (peer.enabled) R.string.devices_stopped_ack else R.string.devices_resumed_ack, peer.name), page.body)
                }.onFailure { failure.visibility = View.VISIBLE }
            }
        }
        body.addView(button, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        sheet.show()
    }
}
