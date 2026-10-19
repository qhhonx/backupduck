package app.backupduck

import android.os.StatFs
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.R as M
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.progressindicator.LinearProgressIndicator

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
 * The proposed receive page: one state said once, a problem card with at most
 * two actions, device readings only when they matter, then recent items.
 * Material 3 type and color roles; shown in the design catalog until migration
 * step 6 replaces [ReceiverHome].
 */
internal class ReceiverHub(private val activity: MainActivity, private val actions: Actions) : ReceiverHomeSurface {
    class Actions(val start: () -> Unit, val connect: () -> Unit, val toggleReceive: () -> Unit, val records: (failed: Boolean) -> Unit,
        val retryRecent: () -> Unit, val openWifi: () -> Unit, val openPhotos: () -> Unit, val openCleanup: () -> Unit,
        val recovery: () -> Unit)

    private val hero = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val recent = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val recentStatus = text("", M.style.TextAppearance_Material3_BodyMedium, secondary = true)
    private val recentRetry = activity.duckLink(activity.getString(R.string.receiver_recent_retry), actions.retryRecent)
    // Recent rows open the proposed photo detail rather than the legacy item sheet.
    private val adapter = TransferAdapter(activity, activity::showPhoto)
    private lateinit var allRow: TextView
    private lateinit var attentionRow: LinearLayout
    private val attentionCount = text("", M.style.TextAppearance_Material3_BodyLarge, secondary = true)
    private var saved = 0; private var total = 0; private var failed = 0
    private var rendered: List<Any?>? = null

    override val view = activity.scrollPage { panel ->
        panel.setPadding(activity.dp(16), activity.dp(8), activity.dp(16), activity.dp(24))
        panel.addView(hero, LinearLayout.LayoutParams(-1, -2))
        panel.addView(recent, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(8) })
        recent.addView(text(activity.getString(R.string.rhub_recent), M.style.TextAppearance_Material3_TitleSmall, secondary = true).apply {
            isAccessibilityHeading = true; setPadding(activity.dp(4), activity.dp(16), 0, activity.dp(8))
        })
        val card = card(recent)
        card.addView(RecyclerView(activity).apply {
            layoutManager = LinearLayoutManager(activity); adapter = this@ReceiverHub.adapter; itemAnimator = null; isNestedScrollingEnabled = false
        }, LinearLayout.LayoutParams(-1, -2))
        card.addView(recentStatus.apply { setPadding(activity.dp(16), activity.dp(14), activity.dp(16), activity.dp(14)) })
        card.addView(recentRetry.apply { setPadding(activity.dp(16), 0, activity.dp(16), 0) }, LinearLayout.LayoutParams(-2, -2))
        val links = card(recent).apply { (parent as View).layoutParams = (parent as View).layoutParams.also { (it as LinearLayout.LayoutParams).topMargin = activity.dp(12) } }
        attentionRow = row(links, activity.getString(R.string.rhub_needs_attention), attentionCount) { actions.records(true) }
        links.addView(activity.duckRule().apply { tag = "rule.attention" })
        allRow = text("", M.style.TextAppearance_Material3_BodyLarge, secondary = true)
        row(links, activity.getString(R.string.rhub_all_records), allRow) { actions.records(false) }
    }

    override fun history(state: HistoryState) {
        state.counts?.let { totals(it.published, it.total, it.failed) }
        adapter.submitList(state.items.take(3))
        recentStatus.visibility = if (state.items.isEmpty() || state.failed) View.VISIBLE else View.GONE
        recentStatus.setText(when { state.failed -> R.string.receiver_recent_failed; state.loading && state.items.isEmpty() -> R.string.rhub_loading; else -> R.string.receiver_home_recent_empty })
        recentRetry.visibility = if (state.failed && !state.loading) View.VISIBLE else View.GONE
    }

    override fun progress(values: Map<String, ReceiverByteProgress>) { /* Recent rows show settled items only. */ }

    override fun totals(saved: Int, total: Int, failed: Int) {
        this.saved = saved; this.total = total; this.failed = failed
        allRow.text = String.format(java.util.Locale.getDefault(), "%,d", total)
        attentionCount.text = String.format(java.util.Locale.getDefault(), "%,d", failed)
        attentionRow.visibility = if (failed > 0) View.VISIBLE else View.GONE
        (attentionRow.parent as LinearLayout).findViewWithTag<View>("rule.attention")?.visibility = attentionRow.visibility
        rendered = null
    }

    override fun render(state: ReceiverSnapshot, name: String?, pending: Boolean) { with(activity) {
        val enabled = ReceiverPreferences.enabled(this); val paused = ReceiverPreferences.paused(this)
        val senders = devicePanels.senderNames
        val hub = receiverHubState(enabled, paused, pending, state, senders.isNotEmpty(), saved)
        val key = listOf(hub, total, senders, state.published, state.total, state.failed, state.error, state.temperatureDeciCelsius.takeIf { state.thermalHeld }, saved)
        if (key == rendered) return@with
        rendered = key
        hero.removeAllViews()
        // Nothing received yet: the hub line already says so, so recent items stay hidden.
        recent.visibility = if (hub in setOf(ReceiverHubState.STOPPED, ReceiverHubState.NO_DEVICE) || (hub == ReceiverHubState.WAITING && total == 0)) View.GONE else View.VISIBLE
        when (hub) {
            ReceiverHubState.STOPPED -> calm(R.drawable.duck_empty, getString(R.string.rhub_stopped), getString(R.string.rhub_stopped_note),
                getString(R.string.rhub_start) to actions.start)
            ReceiverHubState.STARTING -> calm(R.drawable.duck_waiting, getString(R.string.rhub_starting), null)
            ReceiverHubState.PAUSED -> calm(R.drawable.duck_waiting, getString(R.string.rhub_paused), getString(R.string.rhub_paused_note),
                getString(R.string.rhub_resume) to actions.toggleReceive)
            ReceiverHubState.NO_DEVICE -> calm(R.drawable.duck_pairing, getString(R.string.rhub_no_device), getString(R.string.rhub_no_device_note),
                getString(R.string.rhub_connect) to actions.connect)
            ReceiverHubState.WAITING -> { calm(R.drawable.duck_waiting, getString(R.string.rhub_waiting), getString(R.string.rhub_waiting_note)); spaceHint(); pauseLink() }
            ReceiverHubState.CAUGHT_UP -> {
                calm(R.drawable.duck_done, getString(R.string.rhub_caught_up),
                    getString(R.string.rhub_caught_up_note, String.format(java.util.Locale.getDefault(), "%,d", maxOf(saved, state.published))))
                spaceHint(); pauseLink()
            }
            ReceiverHubState.RECEIVING -> { receiving(state, senders); pauseLink() }
            ReceiverHubState.SPACE_FULL -> problem(R.drawable.ic_storage, getString(R.string.rhub_space_full), getString(R.string.rhub_space_full_note),
                reading = getString(R.string.rhub_free_reading, Formatter.formatShortFileSize(this, StatFs(filesDir.path).availableBytes)),
                primary = if (PhotosCleanup(this).enabled) null else getString(R.string.rhub_auto_cleanup) to actions.openCleanup,
                secondary = getString(R.string.rhub_free_up) to actions.openPhotos)
            ReceiverHubState.TOO_HOT -> problem(R.drawable.ic_thermostat, getString(R.string.rhub_too_hot), null,
                reading = state.temperatureDeciCelsius?.let { getString(R.string.rhub_temperature, String.format(java.util.Locale.getDefault(), "%.1f °C", it / 10.0)) })
            ReceiverHubState.NO_WIFI -> problem(R.drawable.ic_globe, getString(R.string.rhub_no_wifi), getString(R.string.rhub_no_wifi_note),
                primary = getString(R.string.rhub_wifi_settings) to actions.openWifi)
            ReceiverHubState.TROUBLE -> receiverProblem(state)?.let { p ->
                problem(R.drawable.ic_alert, getString(R.string.rhub_trouble), getString(p.message), primary = getString(p.action) to actions.recovery)
            }
        }
    } }

    private fun calm(duck: Int, title: String, note: String?, action: Pair<String, () -> Unit>? = null) = with(activity) {
        hero.addView(ImageView(this).apply { setImageResource(duck); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(dp(120), dp(120)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(16) })
        hero.addView(text(title, M.style.TextAppearance_Material3_HeadlineSmall).apply { gravity = Gravity.CENTER_HORIZONTAL; isAccessibilityHeading = true },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        note?.let { hero.addView(text(it, M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply { gravity = Gravity.CENTER_HORIZONTAL },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) }) }
        action?.let { (label, run) -> hero.addView(duckButton(label, true, run), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(20) }) }
    }

    private fun receiving(state: ReceiverSnapshot, senders: List<String>) = with(activity) {
        val box = card(hero, R.color.duck_subtle).apply { setPadding(dp(16), dp(16), dp(16), dp(16)) }
        val title = if (senders.size == 1) getString(R.string.rhub_receiving_from, senders[0]) else getString(R.string.rhub_receiving)
        box.addView(text(title, M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true })
        val left = (state.total - state.published - state.failed).coerceAtLeast(0)
        box.addView(text(resources.getQuantityString(R.plurals.rhub_remaining, left, left), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
        box.addView(LinearProgressIndicator(this).apply {
            max = state.total.coerceAtLeast(1); setProgressCompat(state.published + state.failed, false); trackCornerRadius = dp(2)
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
    }

    private fun problem(icon: Int, title: String, note: String?, reading: String? = null,
        primary: Pair<String, () -> Unit>? = null, secondary: Pair<String, () -> Unit>? = null) = with(activity) {
        val box = card(hero, R.color.duck_attention_background).apply { setPadding(dp(16), dp(16), dp(16), dp(12)) }
        val head = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        head.addView(ImageView(this).apply { setImageResource(icon); imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.duck_attention)); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = dp(12) })
        head.addView(text(title, M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true }, LinearLayout.LayoutParams(0, -2, 1f))
        box.addView(head)
        note?.let { box.addView(text(it, M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8); marginStart = dp(36) }) }
        reading?.let { box.addView(text(it, M.style.TextAppearance_Material3_LabelLarge, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8); marginStart = dp(36) }) }
        val buttons = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        primary?.let { (label, run) -> buttons.addView(duckButton(label, true, run), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) }) }
        secondary?.let { (label, run) -> buttons.addView(duckButton(label, false, run), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(if (primary == null) 16 else 8) }) }
        if (buttons.childCount > 0) box.addView(buttons, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(4) })
    }

    /** Space is a device reading: shown only when it runs low and cleanup could help. */
    private fun spaceHint() = with(activity) {
        val stat = StatFs(filesDir.path)
        if (PhotosCleanup(this).enabled || stat.totalBytes == 0L || stat.availableBytes * 100 / stat.totalBytes >= 15) return@with
        val box = card(hero).apply { setPadding(dp(16), dp(14), dp(16), dp(8)) }
        box.addView(text(getString(R.string.rhub_space_low, Formatter.formatShortFileSize(this, stat.availableBytes)), M.style.TextAppearance_Material3_TitleSmall))
        box.addView(text(getString(R.string.rhub_space_low_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
        box.addView(duckLink(getString(R.string.rhub_auto_cleanup), actions.openCleanup), LinearLayout.LayoutParams(-2, -2))
        (box.parent as View).layoutParams = (box.parent as View).layoutParams.also { (it as LinearLayout.LayoutParams).topMargin = dp(24) }
    }

    private fun pauseLink() = with(activity) {
        hero.addView(duckLink(getString(R.string.rhub_pause), actions.toggleReceive).apply { setTextColor(getColor(R.color.duck_action)) },
            LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(8) })
    }

    private fun card(parent: LinearLayout, color: Int = R.color.duck_surface): LinearLayout = with(activity) {
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        parent.addView(MaterialCardView(this).apply {
            radius = dp(16).toFloat(); cardElevation = 0f; setCardBackgroundColor(getColor(color)); strokeWidth = 0; addView(body)
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        body
    }

    private fun row(parent: LinearLayout, title: String, value: TextView, action: () -> Unit): LinearLayout = with(activity) {
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(56); setPadding(dp(16), 0, dp(12), 0)
            val out = android.util.TypedValue(); theme.resolveAttribute(android.R.attr.selectableItemBackground, out, true)
            foreground = getDrawable(out.resourceId); isFocusable = true; setOnClickListener { action() }
        }
        row.addView(text(title, M.style.TextAppearance_Material3_BodyLarge), LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(value)
        row.addView(ImageView(this).apply { setImageResource(R.drawable.ic_chevron); imageTintList = android.content.res.ColorStateList.valueOf(themeColor(M.attr.colorOnSurfaceVariant)) },
            LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginStart = dp(8) })
        parent.addView(row, LinearLayout.LayoutParams(-1, -2))
        row
    }

    private fun text(value: String, appearance: Int, secondary: Boolean = false) = TextView(activity).apply {
        text = value; setTextAppearance(appearance)
        setTextColor(activity.themeColor(if (secondary) M.attr.colorOnSurfaceVariant else M.attr.colorOnSurface))
    }
}
