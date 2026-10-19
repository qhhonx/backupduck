package app.backupduck

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.CancellationSignal
import android.os.StatFs
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import com.google.android.material.R as M
import com.google.android.material.progressindicator.LinearProgressIndicator
import kotlinx.coroutines.Job

/**
 * The receive hub in the proposed visual language (design/visual-language.md),
 * shown next to [ReceiverHub] while the owner decides it. Same states and
 * actions; only the look differs: received photos lead calm states, one card
 * style, neutral titles with one colored glyph, tonal actions in cards and
 * soft status pills.
 */
internal class ReceiverHubLook(private val activity: MainActivity, private val actions: ReceiverHub.Actions) : ReceiverHomeSurface {
    private val status = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val recent = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val pills = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
    private val images = PhotoImages(activity)
    private val mosaic = PhotoMosaic(activity)
    private var photos: List<HistoryItem> = emptyList()
    private var saved = 0; private var total = 0; private var failed = 0
    private var rendered: List<Any?>? = null

    override val view: View = activity.scrollPage { panel ->
        panel.setPadding(activity.dp(16), activity.dp(8), activity.dp(16), activity.dp(24))
        panel.addView(status, LinearLayout.LayoutParams(-1, -2))
        panel.addView(recent, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(24) })
        val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(activity.lookText(activity.getString(R.string.rhub_recent), M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true },
            LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(pills)
        recent.addView(header, LinearLayout.LayoutParams(-1, -2))
        recent.addView(mosaic, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(12) })
    }

    override fun history(state: HistoryState) {
        state.counts?.let { totals(it.published, it.total, it.failed) }
        // Only photos already in the Pixel's Photos have a picture to show.
        photos = state.items.filter { it.processing == "complete" }.take(6)
        mosaic.bind(photos, images) { activity.showPhoto(it) }
        mosaic.visibility = if (photos.isEmpty()) View.GONE else View.VISIBLE
        renderPills()
    }

    override fun progress(values: Map<String, ReceiverByteProgress>) { /* The mosaic shows settled photos only. */ }

    override fun totals(saved: Int, total: Int, failed: Int) {
        this.saved = saved; this.total = total; this.failed = failed
        renderPills(); rendered = null
    }

    private fun renderPills() = with(activity) {
        pills.removeAllViews()
        if (failed > 0) pills.addView(lookPill(resources.getQuantityString(R.plurals.look_needs_you, failed, String.format(java.util.Locale.getDefault(), "%,d", failed)),
            getColor(R.color.duck_state_attention)) { actions.records(true) }, LinearLayout.LayoutParams(-2, -2).apply { marginEnd = dp(8) })
        pills.addView(lookPill(getString(R.string.look_see_all), null) { actions.records(false) })
    }

    override fun render(state: ReceiverSnapshot, name: String?, pending: Boolean) { with(activity) {
        val enabled = ReceiverPreferences.enabled(this); val paused = ReceiverPreferences.paused(this)
        val senders = devicePanels.senderNames
        val hub = receiverHubState(enabled, paused, pending, state, senders.isNotEmpty(), saved)
        val key = listOf(hub, total, senders, state.published, state.total, state.failed, state.error, state.temperatureDeciCelsius.takeIf { state.thermalHeld }, saved)
        if (key == rendered) return@with
        rendered = key
        status.removeAllViews()
        recent.visibility = if (hub in setOf(ReceiverHubState.STOPPED, ReceiverHubState.NO_DEVICE) || (hub == ReceiverHubState.WAITING && total == 0)) View.GONE else View.VISIBLE
        val attention = getColor(R.color.duck_state_attention)
        when (hub) {
            ReceiverHubState.STOPPED -> duckCard(R.drawable.duck_empty, getString(R.string.rhub_stopped), getString(R.string.rhub_stopped_note), getString(R.string.rhub_start) to actions.start)
            ReceiverHubState.STARTING -> status.addView(lookPill(getString(R.string.rhub_starting), themeColor(M.attr.colorOutline)), LinearLayout.LayoutParams(-2, -2))
            ReceiverHubState.NO_DEVICE -> duckCard(R.drawable.duck_pairing, getString(R.string.rhub_no_device), getString(R.string.rhub_no_device_note), getString(R.string.rhub_connect) to actions.connect)
            ReceiverHubState.WAITING -> { duckCard(R.drawable.duck_waiting, getString(R.string.rhub_waiting), getString(R.string.rhub_waiting_note), null); pauseLink() }
            ReceiverHubState.PAUSED -> problem(R.drawable.ic_clock, themeColor(M.attr.colorPrimary), getString(R.string.rhub_paused), getString(R.string.rhub_paused_note),
                actions = listOf(getString(R.string.rhub_resume) to actions.toggleReceive))
            ReceiverHubState.CAUGHT_UP -> {
                status.addView(lookPill(getString(R.string.rhub_caught_up), getColor(R.color.duck_state_saved)), LinearLayout.LayoutParams(-2, -2))
                status.addView(lookText(getString(R.string.rhub_caught_up_note, String.format(java.util.Locale.getDefault(), "%,d", maxOf(saved, state.published))),
                    M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8); marginStart = dp(4) })
                pauseLink()
                spaceHint()
            }
            ReceiverHubState.RECEIVING -> {
                val card = lookCard(status)
                val title = if (senders.size == 1) getString(R.string.rhub_receiving_from, senders[0]) else getString(R.string.rhub_receiving)
                card.addView(lookText(title, M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true })
                val left = (state.total - state.published - state.failed).coerceAtLeast(0)
                card.addView(lookText(resources.getQuantityString(R.plurals.rhub_remaining, left, left), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
                    LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
                card.addView(LinearProgressIndicator(this).apply { max = state.total.coerceAtLeast(1); setProgressCompat(state.published + state.failed, false); trackCornerRadius = dp(2) },
                    LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
                card.addView(lookTonal(getString(R.string.rhub_pause), actions.toggleReceive), LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(12) })
            }
            ReceiverHubState.SPACE_FULL -> problem(R.drawable.ic_storage, attention, getString(R.string.rhub_space_full), getString(R.string.rhub_space_full_note),
                reading = getString(R.string.rhub_free_reading, Formatter.formatShortFileSize(this, StatFs(filesDir.path).availableBytes)),
                actions = listOfNotNull(if (PhotosCleanup(this).enabled) null else getString(R.string.rhub_auto_cleanup) to actions.openCleanup,
                    getString(R.string.rhub_free_up) to actions.openPhotos))
            ReceiverHubState.TOO_HOT -> problem(R.drawable.ic_thermostat, attention, getString(R.string.rhub_too_hot), null,
                reading = state.temperatureDeciCelsius?.let { getString(R.string.rhub_temperature, String.format(java.util.Locale.getDefault(), "%.1f °C", it / 10.0)) })
            ReceiverHubState.NO_WIFI -> problem(R.drawable.ic_globe, attention, getString(R.string.rhub_no_wifi), getString(R.string.rhub_no_wifi_note),
                actions = listOf(getString(R.string.rhub_wifi_settings) to actions.openWifi))
            ReceiverHubState.TROUBLE -> receiverProblem(state)?.let { p ->
                problem(R.drawable.ic_alert, attention, getString(R.string.rhub_trouble), getString(p.message), actions = listOf(getString(p.action) to actions.recovery))
            }
        }
    } }

    /** Empty states and setup: the duck, a neutral title, the note and the screen's one filled action. */
    private fun duckCard(duck: Int, title: String, note: String, action: Pair<String, () -> Unit>?) = with(activity) {
        val card = lookCard(status, padding = 24)
        card.gravity = Gravity.CENTER_HORIZONTAL
        card.addView(ImageView(this).apply { setImageResource(duck); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(dp(120), dp(120)).apply { gravity = Gravity.CENTER_HORIZONTAL })
        card.addView(lookText(title, M.style.TextAppearance_Material3_TitleLarge).apply { gravity = Gravity.CENTER; isAccessibilityHeading = true },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        card.addView(lookText(note, M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })
        action?.let { (label, run) -> card.addView(lookFilled(label, run), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(20) }) }
    }

    /** A problem: one colored glyph, a neutral title, the note, a reading pill and tonal actions. */
    private fun problem(icon: Int, tint: Int, title: String, note: String?, reading: String? = null, actions: List<Pair<String, () -> Unit>> = emptyList()) = with(activity) {
        val card = lookCard(status)
        card.addView(lookGlyphTitle(icon, tint, title))
        val indent = dp(36)
        note?.let { card.addView(lookText(it, M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6); marginStart = indent }) }
        reading?.let { card.addView(lookPill(it, null), LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(12); marginStart = indent }) }
        actions.forEach { (label, run) -> card.addView(lookTonal(label, run), LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(12); marginStart = indent }) }
    }

    /** Pausing is rare and calm states need no card for it: a Material text button. */
    private fun pauseLink() = with(activity) {
        status.addView(com.google.android.material.button.MaterialButton(this, null, M.attr.borderlessButtonStyle).apply {
            text = getString(R.string.rhub_pause); setOnClickListener { actions.toggleReceive() }
        }, LinearLayout.LayoutParams(-2, -2))
    }

    /** Space is a device reading: shown only when it runs low and cleanup could help. */
    private fun spaceHint() = with(activity) {
        val stat = StatFs(filesDir.path)
        if (PhotosCleanup(this).enabled || stat.totalBytes == 0L || stat.availableBytes * 100 / stat.totalBytes >= 15) return@with
        problem(R.drawable.ic_storage, getColor(R.color.duck_state_attention), getString(R.string.rhub_space_low, Formatter.formatShortFileSize(this, stat.availableBytes)),
            getString(R.string.rhub_space_low_note), actions = listOf(getString(R.string.rhub_auto_cleanup) to actions.openCleanup))
        (status.getChildAt(status.childCount - 1).layoutParams as LinearLayout.LayoutParams).topMargin = dp(16)
    }
}

/**
 * Recent photos in one rounded group: one large and five small for six photos,
 * otherwise a single row of up to three, never an empty cell.
 */
internal class PhotoMosaic(context: Context) : ViewGroup(context) {
    private val gap = context.dp(3)
    private var jobs = emptyList<Pair<Job, CancellationSignal>>()

    init {
        background = GradientDrawable().apply { cornerRadius = context.dp(DuckLook.RADIUS_DP).toFloat(); setColor(context.themeColor(M.attr.colorSurfaceContainer)) }
        clipToOutline = true
    }

    fun bind(items: List<HistoryItem>, images: PhotoImages, open: (HistoryItem) -> Unit) {
        val ids = items.map { it.id }
        if (ids == tag) return
        tag = ids
        jobs.forEach { (job, signal) -> signal.cancel(); job.cancel() }
        removeAllViews()
        val size = (resources.displayMetrics.widthPixels / 2).coerceIn(240, 720)
        jobs = items.map { item ->
            val image = ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP; contentDescription = item.filename
                setBackgroundColor(context.themeColor(M.attr.colorSurfaceContainerHigh)); setOnClickListener { open(item) }
            }
            addView(image)
            val signal = CancellationSignal()
            images.load(item, size, size, signal) { bitmap -> if (bitmap != null) image.setImageBitmap(bitmap) } to signal
        }
        requestLayout()
    }

    private val large get() = childCount >= 6

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val small = (width - gap * 2) / 3
        val height = when { childCount == 0 -> 0; large -> small * 3 + gap * 2; else -> context.dp(120) }
        for (i in 0 until childCount) {
            val (w, h) = cell(i, width, small)
            getChildAt(i).measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        }
        setMeasuredDimension(width, height)
    }

    private fun cell(i: Int, width: Int, small: Int): Pair<Int, Int> = when {
        large && i == 0 -> (small * 2 + gap) to (small * 2 + gap)
        large -> small to small
        else -> { val count = childCount.coerceAtMost(3); ((width - gap * (count - 1)) / count) to context.dp(120) }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val width = r - l; val small = (width - gap * 2) / 3
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val (x, y) = if (large) when (i) {
                0 -> 0 to 0
                1 -> (small * 2 + gap * 2) to 0
                2 -> (small * 2 + gap * 2) to (small + gap)
                else -> ((i - 3) * (small + gap)) to (small * 2 + gap * 2)
            } else (i * (child.measuredWidth + gap)) to 0
            if (!large && i >= 3) { child.layout(0, 0, 0, 0); continue }
            child.layout(x, y, x + child.measuredWidth, y + child.measuredHeight)
        }
    }
}
