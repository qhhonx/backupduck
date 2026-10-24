package app.backupduck

import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import com.google.android.material.R as M

/** What the receive page renders; the current page and the proposed hub both implement it. */
internal interface ReceiverHomeSurface {
    val view: View
    fun render(state: ReceiverSnapshot, name: String?, pending: Boolean)
    fun history(state: HistoryState)
    fun progress(values: Map<String, ReceiverByteProgress>)
    fun totals(saved: Int, total: Int, failed: Int)
}

/** The hub's single state (design/flows.md § Pixel hub states, § When something goes wrong). */
internal enum class ReceiverHubState { STOPPED, STARTING, PAUSED, SPACE_FULL, TOO_HOT, NO_WIFI, TROUBLE, NO_DEVICE, RECEIVING, CAUGHT_UP, WAITING }

internal fun receiverHubState(enabled: Boolean, paused: Boolean, pending: Boolean, state: ReceiverSnapshot,
    hasSenders: Boolean, savedTotal: Int): ReceiverHubState = when {
    !enabled -> ReceiverHubState.STOPPED
    pending || state.phase == "starting" -> ReceiverHubState.STARTING
    // Pausing is the user's choice and says so before any hold it hides.
    paused -> ReceiverHubState.PAUSED
    state.error in setOf("processing_low_space", "low_space", "capacity") -> ReceiverHubState.SPACE_FULL
    state.thermalHeld -> ReceiverHubState.TOO_HOT
    state.error in setOf("wifi_required", "receiver_interface_unavailable") -> ReceiverHubState.NO_WIFI
    state.error != null -> ReceiverHubState.TROUBLE
    state.phase != "ready" -> ReceiverHubState.STARTING
    !hasSenders -> ReceiverHubState.NO_DEVICE
    state.total > state.published + state.failed -> ReceiverHubState.RECEIVING
    state.published > 0 || savedTotal > 0 -> ReceiverHubState.CAUGHT_UP
    else -> ReceiverHubState.WAITING
}

/**
 * The receive hub (design/interaction.md I2 task center, design/flows.md §
 * Pixel hub states): one state card said once, recently saved photos as the
 * evidence, and the devices that send here while calm. Built from the shared
 * components (DuckLook.kt).
 */
internal class ReceiverHub(private val activity: MainActivity, private val actions: Actions) : ReceiverHomeSurface {
    class Actions(val start: () -> Unit, val connect: () -> Unit, val toggleReceive: () -> Unit, val records: (failed: Boolean) -> Unit,
        val openWifi: () -> Unit, val openPhotos: () -> Unit, val openCleanup: () -> Unit, val devices: () -> Unit,
        val recovery: () -> Unit)

    private val state = StateCard(activity)
    private val hint = StateCard(activity)
    private val empty = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val needsYou = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val recent = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val images = PhotoImages(activity)
    private val mosaic = PhotoMosaic(activity)
    private var photos: List<HistoryItem> = emptyList()
    private var saved = 0; private var total = 0; private var failed = 0
    private var rendered: List<Any?>? = null

    override val view: View = activity.scrollPage { panel ->
        with(activity) {
            panel.setPadding(token(R.dimen.duck_space_medium), token(R.dimen.duck_space_x_small), token(R.dimen.duck_space_medium), token(R.dimen.duck_space_large))
            panel.addView(state.view, LinearLayout.LayoutParams(-1, -2))
            panel.addView(empty, LinearLayout.LayoutParams(-1, -2))
            panel.addView(hint.view, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
            panel.addView(needsYou, LinearLayout.LayoutParams(-1, -2))
            panel.addView(recent, LinearLayout.LayoutParams(-1, -2))
            val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
            header.addView(lookText(getString(R.string.rhub_recent), M.style.TextAppearance_Material3_LabelLarge, color = getColor(R.color.duck_role_accent)).apply {
                isAccessibilityHeading = true; setPadding(token(R.dimen.duck_space_medium), 0, 0, 0)
            }, LinearLayout.LayoutParams(0, -2, 1f))
            header.addView(lookButton(getString(R.string.look_see_all), LookButton.TEXT) { actions.records(false) })
            recent.addView(header, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
            recent.addView(mosaic, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_xx_small) })

        }
    }

    override fun history(state: HistoryState) {
        state.counts?.let { totals(it.published, it.total, it.failed) }
        // Only photos already in the Pixel's Photos have a picture to show.
        photos = state.items.filter { it.processing == "complete" }.take(8)
        mosaic.bind(photos, images, { tileDescription(activity, it) }) { item, tile, collection ->
            NativePhotoViewerActivity.open(activity, item, tile, mosaic, collection)
        }
        rendered = null
        render(ReceiverState.snapshot.value, null, false)
    }

    override fun progress(values: Map<String, ReceiverByteProgress>) { /* The mosaic shows settled photos only. */ }

    override fun totals(saved: Int, total: Int, failed: Int) {
        if (saved == this.saved && total == this.total && failed == this.failed) return
        this.saved = saved; this.total = total; this.failed = failed
        rendered = null
    }

    override fun render(state: ReceiverSnapshot, name: String?, pending: Boolean) { with(activity) {
        val enabled = ReceiverPreferences.enabled(this); val paused = ReceiverPreferences.paused(this)
        val names = devicePanels.senderNames
        val hub = receiverHubState(enabled, paused, pending, state, names.isNotEmpty(), saved)
        val storage = ReceiverEnvironment.deviceStorage(this)
        val cleanup = PhotosCleanup(this).enabled
        val cleanupState = currentCleanupStatus()
        val key = listOf(hub, total, failed, names, state.published, state.total, state.failed, state.error,
            state.temperatureDeciCelsius.takeIf { state.thermalHeld }, saved, photos.size, storage.low, cleanup, cleanupState, devicePanels.peers)
        if (key == rendered) { if (hub == ReceiverHubState.RECEIVING) this@ReceiverHub.state.show(withLastConnection(receiving(state, names))); return@with }
        rendered = key
        val noDevice = hub == ReceiverHubState.NO_DEVICE
        val first = hub == ReceiverHubState.WAITING && total == 0
        val emptyState = first || noDevice
        empty.removeAllViews()
        if (first) lookEmpty(empty, R.drawable.duck_empty, getString(R.string.rhub_waiting_first),
            if (names.size == 1) getString(R.string.rhub_waiting_first_from, names[0]) else getString(R.string.rhub_waiting_note),
            getString(R.string.pref_devices) to actions.devices, card = false, centered = true)
        if (noDevice) lookEmpty(empty, R.drawable.duck_empty, getString(R.string.rhub_no_device),
            getString(R.string.rhub_no_device_note), getString(R.string.rhub_connect) to actions.connect, card = false, centered = true)
        this@ReceiverHub.state.view.visibility = if (emptyState) View.GONE else View.VISIBLE
        empty.visibility = if (emptyState) View.VISIBLE else View.GONE
        if (!emptyState) this@ReceiverHub.state.show(withLastConnection(card(hub, state, names, storage, cleanup)))
        // A space hint only while calm or receiving, and only when auto cleanup could help.
        val hinted = hub in setOf(ReceiverHubState.CAUGHT_UP, ReceiverHubState.WAITING, ReceiverHubState.RECEIVING) && storage.low && !cleanup
        hint.view.visibility = if (hinted) View.VISIBLE else View.GONE
        if (hinted) hint.show(LookState(R.drawable.ic_storage, getColor(R.color.duck_role_attention_glyph),
            getString(R.string.rhub_space_low, Formatter.formatShortFileSize(this, storage.freeBytes)), getString(R.string.rhub_space_low_note),
            action = getString(R.string.rhub_auto_cleanup) to actions.openCleanup))
        needsYou.visibility = if (cleanupState.needsAttention) View.VISIBLE else View.GONE
        needsYou.removeAllViews()
        if (cleanupState.needsAttention) {
            lookSection(needsYou, getString(R.string.photos_needs_you))
            lookRow(lookGroup(needsYou), R.drawable.ic_storage, getString(R.string.pref_storage),
                cleanupStatusText(cleanupState), trailing = duckDiscoveryDot().apply { setDuckEntryMark(true) }) { openStorage() }
        }
        // Recent photos appear once something is saved, and stay hidden while receiving is off or no device is connected.
        recent.visibility = if (hub in setOf(ReceiverHubState.STOPPED, ReceiverHubState.NO_DEVICE) || photos.isEmpty()) View.GONE else View.VISIBLE

    } }

    /** Retain the core's latest observed connection without a second device section. */
    private fun withLastConnection(card: LookState): LookState {
        val peer = activity.devicePanels.peers.filter { it.enabled && it.lastSeenSec > 0 }.maxByOrNull { it.lastSeenSec }
        val connection = peer?.let { lastConnected(activity, it)?.let { time -> "${it.name} · $time" } }
        return LookState(card.glyph, card.tint, card.title, card.note,
            reading = listOfNotNull(card.reading, connection).joinToString("\n").takeIf { it.isNotEmpty() },
            progress = card.progress, action = card.action, secondary = card.secondary)
    }

    private fun card(hub: ReceiverHubState, state: ReceiverSnapshot, names: List<String>, storage: DeviceStorage, cleanup: Boolean): LookState = with(activity) {
        val attention = getColor(R.color.duck_role_attention_glyph)
        val quiet = getColor(R.color.duck_role_secondary_text)
        val accent = getColor(R.color.duck_role_accent)
        val count = { value: Int -> String.format(java.util.Locale.getDefault(), "%,d", value) }
        when (hub) {
            ReceiverHubState.STOPPED -> LookState(R.drawable.ic_receiver, quiet, getString(R.string.rhub_stopped), getString(R.string.rhub_stopped_note),
                action = getString(R.string.rhub_start) to actions.start)
            ReceiverHubState.STARTING -> LookState(R.drawable.ic_clock, quiet, getString(R.string.rhub_starting))
            ReceiverHubState.NO_DEVICE -> LookState(R.drawable.ic_qr, accent, getString(R.string.rhub_no_device), getString(R.string.rhub_no_device_note),
                action = getString(R.string.rhub_connect) to actions.connect)
            ReceiverHubState.PAUSED -> LookState(R.drawable.ic_clock, accent, getString(R.string.rhub_paused), getString(R.string.rhub_paused_note),
                action = getString(R.string.rhub_resume) to actions.toggleReceive)
            ReceiverHubState.WAITING -> LookState(R.drawable.ic_clock, quiet, getString(R.string.rhub_waiting), getString(R.string.rhub_waiting_note))
            ReceiverHubState.RECEIVING -> receiving(state, names)
            // "All in Photos" only when every received photo is saved there (flows.md § Hub rules).
            ReceiverHubState.CAUGHT_UP -> if (failed > 0) LookState(R.drawable.ic_alert, attention,
                resources.getQuantityString(R.plurals.rhub_received_some, failed, count(failed)), getString(R.string.rhub_received_some_note),
                action = getString(R.string.photos_view) to { actions.records(true) })
            else LookState(R.drawable.ic_check, getColor(R.color.duck_state_saved), getString(R.string.rhub_caught_up),
                getString(R.string.rhub_caught_up_note, count(maxOf(saved, state.published))))
            ReceiverHubState.SPACE_FULL -> LookState(R.drawable.ic_storage, attention, getString(R.string.rhub_space_full), getString(R.string.rhub_space_full_note),
                reading = getString(R.string.rhub_free_reading, Formatter.formatShortFileSize(this, storage.freeBytes)),
                action = if (cleanup) getString(R.string.rhub_free_up) to actions.openPhotos else getString(R.string.rhub_auto_cleanup) to actions.openCleanup,
                secondary = if (cleanup) null else getString(R.string.rhub_free_up) to actions.openPhotos)
            ReceiverHubState.TOO_HOT -> LookState(R.drawable.ic_thermostat, attention, getString(R.string.rhub_too_hot), null,
                reading = state.temperatureDeciCelsius?.let { getString(R.string.rhub_temperature, String.format(java.util.Locale.getDefault(), "%.1f °C", it / 10.0)) })
            ReceiverHubState.NO_WIFI -> LookState(R.drawable.ic_wifi, attention, getString(R.string.rhub_no_wifi), getString(R.string.rhub_no_wifi_note),
                action = getString(R.string.rhub_wifi_settings) to actions.openWifi)
            ReceiverHubState.TROUBLE -> receiverProblem(state)?.let { p ->
                LookState(R.drawable.ic_alert, attention, getString(R.string.rhub_trouble), getString(p.message), action = getString(p.action) to actions.recovery)
            } ?: LookState(R.drawable.ic_alert, attention, getString(R.string.rhub_trouble))
        }
    }

    /** Receiving: who sends, how many are left and real progress; pausing is the card's one action. */
    private fun receiving(state: ReceiverSnapshot, names: List<String>): LookState = with(activity) {
        val left = (state.total - state.published - state.failed).coerceAtLeast(0)
        LookState(R.drawable.ic_arrow_up, getColor(R.color.duck_role_accent),
            if (names.size == 1) getString(R.string.rhub_receiving_from, names[0]) else getString(R.string.rhub_receiving),
            resources.getQuantityString(R.plurals.rhub_remaining, left, left),
            progress = (state.published + state.failed) to state.total,
            action = getString(R.string.rhub_pause) to actions.toggleReceive)
    }
}
