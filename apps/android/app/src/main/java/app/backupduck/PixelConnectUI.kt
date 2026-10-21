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
    devicePeers(DeviceProfiles.read(activity).optJSONArray("peers"))
}

internal fun devicePeers(peers: org.json.JSONArray?): List<DevicePeer> =
    if (peers == null) emptyList() else (0 until peers.length()).mapNotNull { index ->
        val peer = peers.optJSONObject(index) ?: return@mapNotNull null
        val profile = peer.optJSONObject("profile") ?: return@mapNotNull null
        DevicePeer(profile.optString("id"), profile.optString("name"),
            peer.optString("device_type").takeUnless { it.isBlank() || it == "null" }, peer.optLong("last_seen"), peer.optBoolean("enabled", true))
    }

/** "Last connected today 10:42", or nothing when the device has not connected yet. */
internal fun lastConnected(context: android.content.Context, peer: DevicePeer): String? {
    if (peer.lastSeenSec <= 0) return null
    val time = shortTime(context, peer.lastSeenSec * 1000)
    // "Today" heads a day group; inside a sentence it reads "last connected today".
    val relative = listOf(R.string.photos_today, R.string.photos_yesterday).map { context.getString(it) }.any { time.startsWith(it) }
    val sentence = if (relative && context.resources.configuration.locales[0].language == "en") time.replaceFirstChar { it.lowercase() } else time
    return context.getString(R.string.devices_last, sentence)
}

/**
 * The one connect flow (design/pixel-connect.md), shared by first run, the hub
 * and the device page: the code an iPhone scans, the Mac direction, and the
 * connected screen. The host owns the screen and its two fixed buttons.
 */
internal class ConnectFlow(private val activity: AppCompatActivity, private val content: LinearLayout,
    private val primary: MaterialButton, private val secondary: MaterialButton, private val secureWindow: Window,
    private val scan: ((String?) -> Unit) -> Unit, private val startReceiving: () -> Unit,
    private val doneLabel: Int, private val done: () -> Unit,
    /** What the host shows above every screen of the flow, such as first run's step marks. */
    private val decorate: (LinearLayout) -> Unit = {}) {
    private var work: Job? = null
    /** Which direction is showing, so a recreated screen can reopen it. */
    var surface = "pairing"
        private set

    fun stop() { work?.cancel(); work = null; secureWindow.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }

    private fun reset() {
        stop(); content.removeAllViews()
        primary.visibility = View.GONE; secondary.visibility = View.GONE
        decorate(content)
    }

    fun showCode(): Unit = with(activity) {
        reset(); surface = "pairing"
        heading(getString(R.string.connect_code_title))
        // The code is the subject of the screen (P6 step 3): one line under the title, then the code itself.
        val status = line(getString(R.string.connect_getting_ready), M.style.TextAppearance_Material3_BodyMedium, center = true).apply {
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            (layoutParams as LinearLayout.LayoutParams).topMargin = 0
        }
        val boxShape = GradientDrawable().apply { cornerRadius = token(R.dimen.duck_radius_card).toFloat(); setColor(getColor(R.color.duck_role_grouped_surface)) }
        val box = FrameLayout(this).apply { background = boxShape; token(R.dimen.duck_space_small).let { setPadding(it, it, it, it) } }
        content.addView(box, LinearLayout.LayoutParams(dp(264), dp(264)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = token(R.dimen.duck_space_large) })
        val code = ImageView(this).apply { contentDescription = getString(R.string.connect_code_description); visibility = View.GONE }
        box.addView(code, FrameLayout.LayoutParams(-1, -1))
        val spinner = CircularProgressIndicator(this).apply { isIndeterminate = true; contentDescription = getString(R.string.connect_getting_ready) }
        box.addView(spinner, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
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
            token(R.dimen.duck_space_large).let { setPadding(it, it, it, it) }
        }, LinearLayout.LayoutParams(dp(96), dp(96)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = token(R.dimen.duck_space_large); bottomMargin = token(R.dimen.duck_space_large) })
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
            LinearLayout.LayoutParams(dp(150), dp(150)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = token(R.dimen.duck_space_xx_large); bottomMargin = token(R.dimen.duck_space_medium) })
        heading(if (mac || name.isNullOrBlank()) getString(if (mac) R.string.connect_connected_mac else R.string.connect_connected_device) else getString(R.string.connect_connected, name))
        line(getString(R.string.connect_connected_body), M.style.TextAppearance_Material3_BodyLarge, center = true)
        primary(doneLabel) { done() }
    }

    // ---- Building blocks ----

    private fun heading(text: String) = content.addView(activity.lookText(text, M.style.TextAppearance_Material3_HeadlineSmall).apply {
        gravity = Gravity.CENTER_HORIZONTAL; isAccessibilityHeading = true
    }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.token(R.dimen.duck_space_medium); bottomMargin = activity.token(R.dimen.duck_space_x_small) })

    private fun line(text: String, appearance: Int, center: Boolean = false): TextView =
        activity.lookText(text, appearance, secondary = true).apply { if (center) gravity = Gravity.CENTER_HORIZONTAL }
            .also { content.addView(it, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.token(R.dimen.duck_space_small) }) }

    /** What went wrong, in the shared state card: one glyph, a neutral sentence (V1, I3 Problem). */
    private fun problem(text: String) {
        val card = StateCard(activity)
        card.show(LookState(R.drawable.ic_alert, activity.getColor(R.color.duck_state_attention), text))
        card.view.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        content.addView(card.view, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.token(R.dimen.duck_space_large) })
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
    private val content = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.token(R.dimen.duck_space_large), 0, activity.token(R.dimen.duck_space_large), activity.token(R.dimen.duck_space_medium))
    }
    private val primary = activity.lookButton("", LookButton.FILLED, large = true) {}
    private val secondary = activity.lookButton("", LookButton.TEXT, large = true) {}
    val flow: ConnectFlow

    init {
        val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(activity.getColor(R.color.duck_role_background)) }
        root.addView(com.google.android.material.appbar.MaterialToolbar(activity).apply {
            setNavigationIcon(R.drawable.ic_close)
            setNavigationContentDescription(R.string.connect_close)
            setNavigationOnClickListener { dismiss() }
        }, LinearLayout.LayoutParams(-1, -2))
        root.addView(ScrollView(activity).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.token(R.dimen.duck_space_large), activity.token(R.dimen.duck_space_x_small), activity.token(R.dimen.duck_space_large), activity.token(R.dimen.duck_space_medium))
        }
        actions.addView(primary, LinearLayout.LayoutParams(-1, -2)); actions.addView(secondary, LinearLayout.LayoutParams(-1, -2))
        root.addView(actions)
        setContentView(root)
        flow = ConnectFlow(activity, content, primary, secondary, window!!, scan, startReceiving, R.string.connect_done, { dismiss() })
        setOnDismissListener { flow.stop(); closed() }
    }

    override fun show() {
        super.show(); window?.setLayout(-1, -1)
    }
}

/**
 * Connected devices (design/pixel-connect.md § 3, P7): a sentence, one Connect
 * button, then the devices that send here and, apart, the ones the user stopped.
 */
internal class DevicesPage(private val activity: MainActivity, private val connect: () -> Unit, private val changed: () -> Unit) {
    private val page = LookPage(activity, activity.getString(R.string.pref_devices))
    private var load: Job? = null

    fun show() { page.setOnDismissListener { load?.cancel() }; page.show(); reload() }
    val isShowing: Boolean get() = page.isShowing
    fun dismiss() = page.dismiss()

    fun reload(): Unit = with(activity) {
        load?.cancel()
        load = lifecycleScope.launch {
            val result = runCatching { readDevicePeers(activity) }
            if (!page.isShowing) return@launch
            val body = page.body; body.removeAllViews()
            result.onFailure {
                lookUnavailable(body, getString(R.string.pref_devices), getString(R.string.devices_load_failed),
                    getString(R.string.connect_try_again) to { reload() })
            }.onSuccess { peers -> render(deviceGroups(peers)) }
        }
    }

    private fun render(groups: DeviceGroups): Unit = with(activity) {
        val body = page.body
        if (groups.sending.isEmpty() && groups.stopped.isEmpty()) {
            lookEmpty(body, R.drawable.duck_empty, getString(R.string.devices_empty_title), getString(R.string.devices_intro),
                getString(R.string.devices_connect) to connect)
            return@with
        }
        body.addView(lookText(getString(R.string.devices_intro), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
            setPadding(token(R.dimen.duck_space_xx_small), 0, token(R.dimen.duck_space_xx_small), 0)
        }, LinearLayout.LayoutParams(-1, -2))
        body.addView(lookButton(getString(R.string.devices_connect), LookButton.FILLED, icon = R.drawable.ic_plus) { connect() },
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_small); bottomMargin = token(R.dimen.duck_space_small) })
        if (groups.sending.isNotEmpty()) {
            lookSection(body, getString(R.string.devices_sending))
            val group = lookGroup(body)
            groups.sending.forEach { peer -> lookRow(group, icon(peer), peer.name, lastConnected(this, peer)) { device(peer) } }
        }
        if (groups.stopped.isNotEmpty()) {
            lookSection(body, getString(R.string.devices_stopped))
            val group = lookGroup(body)
            groups.stopped.forEach { peer ->
                lookRow(group, icon(peer), peer.name, listOfNotNull(getString(R.string.devices_stopped_row), lastConnected(this, peer)).joinToString(" · ")) { device(peer) }
            }
        }
    }

    private fun icon(peer: DevicePeer) = if (peer.computer) R.drawable.ic_computer else R.drawable.ic_receiver

    /** One device: what it is, when it last connected, and the one thing the user can change. */
    private fun device(peer: DevicePeer): Unit = with(activity) {
        val sheet = LookSheet(this)
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(token(R.dimen.duck_space_large), 0, token(R.dimen.duck_space_large), token(R.dimen.duck_space_x_small)) }
        sheet.body.addView(body)
        body.addView(lookText(peer.name, M.style.TextAppearance_Material3_TitleLarge).apply { isAccessibilityHeading = true })
        listOfNotNull(peer.kind, lastConnected(this, peer)).joinToString(" · ").takeIf { it.isNotEmpty() }?.let {
            body.addView(lookText(it, M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_xx_small) })
        }
        body.addView(lookText(getString(if (peer.enabled) R.string.devices_stop_note else R.string.devices_stopped_note), M.style.TextAppearance_Material3_BodyMedium),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_medium) })
        val failure = duckFailure(body, getString(R.string.devices_save_failed))
        var resumeButton: com.google.android.material.button.MaterialButton? = null
        fun change(confirmation: DuckConfirmation? = null) {
            failure.visibility = View.GONE
            confirmation?.busy(true)
            sheet.setCancelable(false)
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) { runCatching {
                    NativeBridge.request(JSONObject().put("op", "set_sender_enabled").put("root", "$filesDir/receiver/store").put("id", peer.id).put("enabled", !peer.enabled))
                } }
                confirmation?.busy(false);sheet.setCancelable(true);resumeButton?.isEnabled=true
                result.onSuccess {
                    confirmation?.dismiss(); sheet.dismiss(); reload(); changed()
                    if (peer.enabled) {
                        com.google.android.material.snackbar.Snackbar.make(page.body, getString(R.string.devices_stopped_ack, peer.name),
                            com.google.android.material.snackbar.Snackbar.LENGTH_LONG)
                            .setAction(R.string.action_undo) {
                                lifecycleScope.launch {
                                    val restored = withContext(Dispatchers.IO) { runCatching {
                                        NativeBridge.request(JSONObject().put("op", "set_sender_enabled").put("root", "$filesDir/receiver/store").put("id", peer.id).put("enabled", true))
                                    } }
                                    restored.onSuccess { reload(); changed() }
                                        .onFailure { duckProblem(page.body, getString(R.string.devices_save_failed)) }
                                }
                            }.show()
                    }
                }.onFailure {
                    if (confirmation != null) confirmation.showFailure(R.string.devices_save_failed) else failure.visibility = View.VISIBLE
                }
            }
        }
        if (peer.enabled) {
            val toolbar = com.google.android.material.appbar.MaterialToolbar(this)
            toolbar.menu.add(R.string.devices_stop).setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_NEVER)
            toolbar.setOnMenuItemClickListener {
                duckConfirm(R.string.devices_stop, R.string.devices_stop_note, R.string.devices_stop) { change(it) }
                true
            }
            body.addView(toolbar, 0, LinearLayout.LayoutParams(-1, -2))
        } else {
            val resume = lookButton(getString(R.string.devices_resume), LookButton.TONAL) {}
            resumeButton = resume
            resume.setOnClickListener { resume.isEnabled=false;change() }
            body.addView(resume, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_medium) })
        }
        sheet.show()
    }
}
