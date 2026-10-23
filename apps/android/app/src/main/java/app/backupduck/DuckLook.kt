package app.backupduck

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.CancellationSignal
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.DimenRes
import androidx.annotation.DrawableRes
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.NestedScrollView
import com.google.android.material.R as M
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDragHandleView
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.android.material.progressindicator.LinearProgressIndicator
import kotlinx.coroutines.Job

/**
 * The shared components of the Pixel receiver in Material 3 Views
 * (design/visual-language.md V1–V7, design/interaction.md I2–I4). Pages build
 * from these and never define a color, size or radius of their own: surfaces
 * are solid (V4), colors come from the generated scheme and `duck_*` tokens,
 * spacing and radius from the generated `duck_space_*` and `duck_radius_*`
 * dimensions, and text from the Material type scale (V2).
 */
internal object DuckLook {
    /** Applies the generated Material 3 scheme to an activity or dialog theme before its views are built. */
    fun applyScheme(context: Context) { context.theme.applyStyle(R.style.ThemeOverlay_BackupDuck_Scheme, true) }
}

/**
 * The same scheme in its dark variant, for surfaces that are dark in every
 * theme: the photo viewer, as photo viewers are.
 */
internal fun Context.darkLook(): Context {
    val night = android.content.res.Configuration(resources.configuration).apply {
        uiMode = (uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK.inv()) or android.content.res.Configuration.UI_MODE_NIGHT_YES
    }
    return androidx.appcompat.view.ContextThemeWrapper(this, R.style.AppTheme).apply {
        applyOverrideConfiguration(night); DuckLook.applyScheme(this)
    }
}

/** A spacing or radius token in pixels. */
internal fun Context.token(@DimenRes id: Int) = resources.getDimensionPixelSize(id)

/** Shared page composition metrics; row/card padding remains component-owned. */
internal object LookSectionMetrics {
    val gap = R.dimen.duck_space_large
    val headingGap = R.dimen.duck_space_x_small
    val footnoteGap = R.dimen.duck_space_small
    val inset = R.dimen.duck_space_medium
}

// ---- Text ----

/** Shared wrapping for body, supporting text and footnotes, including centered empty states. */
internal fun TextView.balanceLines() {
    breakStrategy = android.text.Layout.BREAK_STRATEGY_BALANCED
    hyphenationFrequency = android.text.Layout.HYPHENATION_FREQUENCY_NONE
}

/** Text in one role of the type scale: on-surface, or on-surface-variant when [secondary]. */
internal fun Context.lookText(value: CharSequence, appearance: Int, secondary: Boolean = false, color: Int? = null) = TextView(this).apply {
    text = value; setTextAppearance(appearance)
    balanceLines()
    setTextColor(color ?: getColor(if (secondary) R.color.duck_role_secondary_text else R.color.duck_role_primary_text))
}

/** A section header: Label large in the accent, aligned with the row content of the group below (V2). */
internal fun Context.lookSection(parent: LinearLayout, title: String, separated: Boolean = true): TextView = lookText(title, M.style.TextAppearance_Material3_LabelLarge,
    color = getColor(R.color.duck_role_accent)).apply {
    isAccessibilityHeading = true
    setPadding(token(LookSectionMetrics.inset), 0, token(LookSectionMetrics.inset), token(LookSectionMetrics.headingGap))
}.also { parent.addView(it, LinearLayout.LayoutParams(-1, -2).apply {
    if (separated) topMargin = token(LookSectionMetrics.gap)
}) }

/** One page section, including its heading, content and footnotes; hiding it removes its gap. */
internal fun Context.lookContentSection(parent: LinearLayout, title: String): LinearLayout = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
}.also { section ->
    parent.addView(section, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(LookSectionMetrics.gap) })
    lookSection(section, title, separated = false)
}

/** Footnotes align with group content and grow with localized/accessibility text. */
internal fun Context.lookFootnote(parent: LinearLayout, text: String): TextView =
    lookText(text, M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
        breakStrategy = android.text.Layout.BREAK_STRATEGY_BALANCED
    }.also {
        parent.addView(it, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = token(LookSectionMetrics.footnoteGap)
            marginStart = token(LookSectionMetrics.inset); marginEnd = token(LookSectionMetrics.inset)
        })
    }

// ---- Cards ----

/**
 * The one card (V3, V4): a solid grouped surface with the card radius, no
 * border and no shadow. Returns the card's body, padded by default.
 */
internal fun Context.lookCard(parent: ViewGroup, padded: Boolean = true, params: ViewGroup.LayoutParams = LinearLayout.LayoutParams(-1, -2)): LinearLayout {
    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        if (padded) token(R.dimen.duck_space_medium).let { setPadding(it, it, it, it) }
    }
    parent.addView(MaterialCardView(this).apply {
        radius = token(R.dimen.duck_radius_card).toFloat(); cardElevation = 0f; strokeWidth = 0
        setCardBackgroundColor(getColor(R.color.duck_role_grouped_surface)); addView(body)
    }, params)
    return body
}

/** What a state card says (I3): one glyph in a state color, a neutral title, a note and at most one tonal action. */
internal class LookState(
    @DrawableRes val glyph: Int, val tint: Int, val title: String, val note: String? = null,
    /** A device reading shown as a neutral pill, only when it matters (flows.md § Pixel hub states). */
    val reading: String? = null,
    /** Real progress as done of total; the bar sits inside the card and never adds a row (I3 Working). */
    val progress: Pair<Int, Int>? = null,
    val action: Pair<String, () -> Unit>? = null,
    /** A quieter alternative beside the action, as a text button. */
    val secondary: Pair<String, () -> Unit>? = null,
) {
    /** What decides whether the card changed; progress alone updates the bar in place. */
    val key get() = listOf(glyph, tint, title, note, reading, progress != null, action?.first, secondary?.first)
}

/**
 * The state card used for every hub state and problem (V1, I3): the glyph
 * carries the state color, the title stays neutral. A new state replaces the
 * content in place with a short fade; progress moves the bar without
 * rebuilding. Problems never show the duck (V6).
 */
internal class StateCard(private val context: Context) {
    private val body: LinearLayout
    val view: MaterialCardView
    private val glyph = ImageView(context).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
    private val title = context.lookText("", M.style.TextAppearance_Material3_TitleMedium).apply {
        isAccessibilityHeading = true; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
    }
    private val note = context.lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true)
    private val reading = context.lookPill("", null)
    private val bar = LinearProgressIndicator(context).apply {
        trackThickness = context.dp(3); trackCornerRadius = context.dp(2); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val actions = FlowRow(context, context.token(R.dimen.duck_space_x_small))
    private val media = FrameLayout(context).apply { visibility = View.GONE }
    /** The card's tonal action, for disabling it while the action runs. */
    var actionButton: MaterialButton? = null
        private set
    private val words = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private var shown: List<Any?>? = null
    private var identity: List<Any?>? = null

    init {
        val padding = context.token(R.dimen.duck_space_medium)
        body = LinearLayout(context).apply { setPadding(padding, padding, padding, padding) }
        view = MaterialCardView(context).apply {
            radius = context.token(R.dimen.duck_radius_card).toFloat(); cardElevation = 0f; strokeWidth = 0
            setCardBackgroundColor(context.getColor(R.color.duck_role_grouped_surface)); addView(body)
        }
        body.addView(glyph, LinearLayout.LayoutParams(context.dp(24), context.dp(24)).apply { marginEnd = context.token(R.dimen.duck_space_medium) })
        body.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
        words.addView(title)
        words.addView(note, LinearLayout.LayoutParams(-1, -2).apply { topMargin = context.token(R.dimen.duck_space_xx_small) })
        words.addView(reading, LinearLayout.LayoutParams(-2, -2).apply { topMargin = context.token(R.dimen.duck_space_x_small) })
        // I3 Working: progress updates inside one fixed slot; absent content reserves no rows.
        words.addView(bar, LinearLayout.LayoutParams(-1, context.dp(3)).apply { topMargin = context.token(R.dimen.duck_space_small) })
        words.addView(media, LinearLayout.LayoutParams(-1, -2).apply { topMargin = context.token(R.dimen.duck_space_small) })
        words.addView(actions, LinearLayout.LayoutParams(-1, -2).apply { topMargin = context.token(R.dimen.duck_space_small) })
    }

    /** Optional fixed-size photo evidence, before the single problem action. */
    fun media(content: View?) {
        if (media.getChildAt(0) !== content) {
            media.removeAllViews()
            content?.let { media.addView(it) }
        }
        media.visibility = if (content == null) View.GONE else View.VISIBLE
    }

    fun actionFeedback(message: String, failed: Boolean) {
        note.text = message; note.visibility = View.VISIBLE
        if (failed) {
            glyph.setImageResource(R.drawable.ic_alert)
            glyph.imageTintList = ColorStateList.valueOf(context.getColor(R.color.duck_state_failure))
        }
    }

    fun show(state: LookState) {
        state.progress?.let { (done, total) -> bar.max = total.coerceAtLeast(1); bar.setProgressCompat(done.coerceIn(0, bar.max), shown == state.key) }
        if (shown == state.key) return
        // Counts change the note in place; only a different state fades.
        val replacing = shown != null && identity != listOf(state.glyph, state.title)
        shown = state.key; identity = listOf(state.glyph, state.title)
        glyph.setImageResource(state.glyph); glyph.imageTintList = ColorStateList.valueOf(state.tint)
        title.text = state.title
        note.text = state.note; note.visibility = if (state.note.isNullOrEmpty()) View.GONE else View.VISIBLE
        reading.text = state.reading; reading.visibility = if (state.reading.isNullOrEmpty()) View.GONE else View.VISIBLE
        bar.visibility = if (state.progress == null) View.GONE else View.VISIBLE
        actions.removeAllViews()
        actionButton = state.action?.let { (label, run) -> context.lookButton(label, LookButton.TONAL, action = run).also { it.tag = this; actions.addView(it) } }
        state.secondary?.let { (label, run) -> actions.addView(context.lookButton(label, LookButton.TEXT, action = run)) }
        actions.visibility = if (actions.childCount == 0) View.GONE else View.VISIBLE
        // I7: a state change fades in place over the text duration; Reduce Motion adopts it at once.
        if (replacing && ValueAnimator.areAnimatorsEnabled()) {
            words.alpha = 0f
            words.animate().alpha(1f).setDuration(context.resources.getInteger(R.integer.duck_motion_text_ms).toLong()).start()
        }
    }
}

/** An empty state (I3): the duck, a neutral title, one sentence and at most one action. Never used for problems (V6). */
internal fun Context.lookEmpty(parent: ViewGroup, @DrawableRes duck: Int, title: String, note: String?,
    action: Pair<String, () -> Unit>? = null, card: Boolean = true, centered: Boolean = false): LinearLayout {
    val box = if (card) lookCard(parent) else object : LinearLayout(this) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            if (centered) {
                val viewport = generateSequence(parent as? View) { it.parent as? View }.firstOrNull {
                    it is androidx.recyclerview.widget.RecyclerView || it is NestedScrollView
                }
                minimumHeight = viewport?.let { maxOf(it.height, it.measuredHeight) - it.paddingTop - it.paddingBottom }?.coerceAtLeast(0) ?: 0
            }
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        }
    }.apply { orientation = LinearLayout.VERTICAL }.also { parent.addView(it, LinearLayout.LayoutParams(-1, -2)) }
    box.gravity = if (centered) Gravity.CENTER else Gravity.CENTER_HORIZONTAL
    token(R.dimen.duck_space_large).let { box.setPadding(box.paddingLeft, it, box.paddingRight, it) }
    box.addView(ImageView(this).apply { setImageResource(duck); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
        LinearLayout.LayoutParams(dp(112), dp(112)))
    box.addView(lookText(title, M.style.TextAppearance_Material3_TitleMedium).apply { gravity = Gravity.CENTER; isAccessibilityHeading = true },
        LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
    note?.let { box.addView(lookText(it, M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply { gravity = Gravity.CENTER },
        LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_xx_small) }) }
    action?.let { (label, run) -> box.addView(lookButton(label, LookButton.FILLED, action = run),
        LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_medium) }) }
    return box
}

/** Unavailable content uses a system glyph, a sentence and the existing recovery action. */
internal fun Context.lookUnavailable(parent: LinearLayout, title: String, note: String, action: Pair<String, () -> Unit>) {
    lookEmpty(parent, R.drawable.ic_alert, title, note, action, card = false, centered = true)
}

// ---- Buttons and pills ----

internal enum class LookButton { FILLED, TONAL, OUTLINED, TEXT }

/**
 * Native Material button roles (A1). FILLED is the primary action,
 * TONAL an action inside a card. The legacy OUTLINED role now resolves to TEXT.
 * [large] is the fixed bottom action of a guided flow.
 */
internal fun Context.lookButton(text: String, kind: LookButton, large: Boolean = false, @DrawableRes icon: Int? = null, action: () -> Unit): MaterialButton {
    val style = when (kind) {
        LookButton.FILLED -> R.style.DuckButtonFilled
        LookButton.TONAL -> R.style.DuckButtonTonal
        LookButton.OUTLINED, LookButton.TEXT -> R.style.DuckButtonText
    }
    return MaterialButton(androidx.appcompat.view.ContextThemeWrapper(this, style)).apply {
        this.text = text; setOnClickListener { action() }
        if (large) minimumHeight = dp(56)
        icon?.let { setIconResource(it) }
    }
}

/** A soft status pill: an optional colored dot and neutral text on a container, optionally tappable. */
internal fun Context.lookPill(text: String, dot: Int?, action: (() -> Unit)? = null): TextView = lookText(text, M.style.TextAppearance_Material3_LabelLarge).apply {
    gravity = Gravity.CENTER_VERTICAL; minHeight = dp(32)
    setPadding(token(R.dimen.duck_space_small), token(R.dimen.duck_space_xx_small),
        token(R.dimen.duck_space_small), token(R.dimen.duck_space_xx_small))
    background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(getColor(R.color.duck_role_elevated_surface)) }
    dot?.let { color ->
        setCompoundDrawablesRelativeWithIntrinsicBounds(GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setSize(dp(8), dp(8)) }, null, null, null)
        compoundDrawablePadding = token(R.dimen.duck_space_x_small)
    }
    action?.let { run ->
        isClickable = true; isFocusable = true; setOnClickListener { run() }
        foreground = selectableBackground(); minHeight = dp(40)
    }
}

/** Children in a row that wraps to the next line instead of clipping, for actions and pills at large text sizes. */
internal class FlowRow(context: Context, private val gap: Int) : ViewGroup(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        var x = 0; var y = 0; var line = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            child.measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.AT_MOST), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
            if (x > 0 && x + child.measuredWidth > width) { x = 0; y += line + gap; line = 0 }
            x += child.measuredWidth + gap; line = maxOf(line, child.measuredHeight)
        }
        setMeasuredDimension(width, resolveSize(maxOf(suggestedMinimumHeight, y + line), heightMeasureSpec))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val width = r - l; val rtl = layoutDirection == LAYOUT_DIRECTION_RTL
        var x = 0; var y = 0; var line = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue
            if (x > 0 && x + child.measuredWidth > width) { x = 0; y += line + gap; line = 0 }
            val left = if (rtl) width - x - child.measuredWidth else x
            child.layout(left, y, left + child.measuredWidth, y + child.measuredHeight)
            x += child.measuredWidth + gap; line = maxOf(line, child.measuredHeight)
        }
    }
}

// ---- Lists ----

/** A group of list rows in one card; rows are added with [lookRow] or [lookSwitchRow]. */
internal fun Context.lookGroup(parent: LinearLayout): LinearLayout = lookCard(parent, padded = false)

/**
 * A Material list row (V5, V7): a monochrome leading icon, a headline and
 * optional supporting text, an optional trailing control and no chevron. 56dp
 * with one line and 72dp with two, growing with the text. Returns the
 * supporting text so callers can refresh the value with [setSupporting].
 * Native balanced wrapping keeps enlarged labels from leaving an orphaned word.
 */
internal fun Context.lookRow(group: LinearLayout, @DrawableRes icon: Int?, title: String, supporting: String? = null,
    trailing: View? = null, badge: String? = null, action: (() -> Unit)? = null): TextView {
    val support = lookText(supporting.orEmpty(), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
        visibility = if (supporting.isNullOrEmpty()) View.GONE else View.VISIBLE
        breakStrategy = android.text.Layout.BREAK_STRATEGY_BALANCED
    }
    val row = LinearLayout(this).apply {
        // Center each complete child; font baselines must not shift icons or text blocks.
        isBaselineAligned = false
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(if (supporting.isNullOrEmpty()) 56 else 72)
        setPadding(token(R.dimen.duck_space_medium), token(R.dimen.duck_space_x_small), token(R.dimen.duck_space_medium), token(R.dimen.duck_space_x_small))
        if (action != null) { isClickable = true; isFocusable = true; background = selectableBackground(); setOnClickListener { action() } }
    }
    icon?.let {
        row.addView(ImageView(this).apply {
            setImageResource(it); imageTintList = ColorStateList.valueOf(getColor(R.color.duck_role_secondary_text))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = token(R.dimen.duck_space_medium) })
    }
    val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    fun titleText() = lookText(title, M.style.TextAppearance_Material3_BodyLarge).apply {
        breakStrategy = android.text.Layout.BREAK_STRATEGY_BALANCED
    }
    if (badge == null) words.addView(titleText())
    else words.addView(FlowRow(this, token(R.dimen.duck_space_x_small)).apply {
        addView(titleText())
        addView(lookPill(badge, null).apply {
            minHeight = 0
            setTextAppearance(M.style.TextAppearance_Material3_LabelSmall)
            setTextColor(getColor(R.color.duck_role_secondary_text))
        })
    })
    words.addView(support)
    row.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
    trailing?.let { row.addView(it, LinearLayout.LayoutParams(it.layoutParams?.width ?: -2, it.layoutParams?.height ?: -2).apply { marginStart = token(R.dimen.duck_space_medium) }) }
    if (group.childCount > 0) group.addView(View(this).apply { setBackgroundColor(getColor(R.color.duck_role_separator)) }, LinearLayout.LayoutParams(-1, dp(1)))
    group.addView(row, LinearLayout.LayoutParams(-1, -2))
    return support
}

internal class LookSwitch(val toggle: MaterialSwitch, val supporting: TextView)

/** A row whose switch applies at once (I4); tapping anywhere on the row flips it. */
internal fun Context.lookSwitchRow(group: LinearLayout, @DrawableRes icon: Int?, title: String, supporting: String?,
    checked: Boolean, badge: String? = null, changed: (Boolean) -> Unit): LookSwitch {
    val toggle = MaterialSwitch(this).apply { isChecked = checked; contentDescription = title }
    val support = lookRow(group, icon, title, supporting, toggle, badge) { if (toggle.isEnabled) toggle.toggle() }
    toggle.setOnCheckedChangeListener { view, value -> if (view.tag != "restoring") changed(value) }
    return LookSwitch(toggle, support)
}

/** Sets a switch without reporting a change, for showing a stored value. */
internal fun MaterialSwitch.restore(value: Boolean) { tag = "restoring"; isChecked = value; tag = null }

internal fun TextView.setSupporting(value: String?) {
    text = value
    visibility = if (value.isNullOrEmpty()) View.GONE else View.VISIBLE
}

internal fun Context.selectableBackground(): Drawable? = TypedValue().let { value ->
    theme.resolveAttribute(android.R.attr.selectableItemBackground, value, true)
    getDrawable(value.resourceId)
}

// ---- Pages and sheets ----

/**
 * A page one level down (I1 push): a top app bar with Back and the title,
 * then a scrolling body with the page margin, on the page background.
 */
internal class LookPage(activity: BackupDuckActivity, title: String, route: String) : PageDestination(activity, route, title) {
    init {
        body.setPadding(activity.token(R.dimen.duck_space_medium), activity.token(R.dimen.duck_space_x_small),
            activity.token(R.dimen.duck_space_medium), activity.token(R.dimen.duck_space_large))
    }
}

/** A Material 3 modal bottom sheet (I1 detail and chooser) with a drag handle, the sheet radius and a scrolling body. */
internal class LookSheet(context: Context) : BottomSheetDialog(context) {
    init { context.trackNotificationWindow(this) }
    val body = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(0, 0, 0, context.token(R.dimen.duck_space_medium)) }
    init {
        val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        content.addView(BottomSheetDragHandleView(context), LinearLayout.LayoutParams(-1, -2))
        content.addView(NestedScrollView(context).apply { addView(body) }, LinearLayout.LayoutParams(-1, -2))
        setContentView(content)
    }
    override fun onStart() {
        super.onStart()
        behavior.state = BottomSheetBehavior.STATE_EXPANDED; behavior.skipCollapsed = true
    }
}

// ---- Photos ----

/**
 * Recently received photos in one rounded group (V3: 2dp gaps, the card
 * radius outside): four columns, two rows when there are eight, one row
 * otherwise, never an empty cell.
 */
internal class PhotoMosaic(context: Context) : ViewGroup(context) {
    private val gap = context.dp(2)
    private var jobs = emptyList<Pair<Job, CancellationSignal>>()

    init {
        background = GradientDrawable().apply { cornerRadius = context.token(R.dimen.duck_radius_card).toFloat(); setColor(context.getColor(R.color.duck_role_grouped_surface)) }
        clipToOutline = true
    }

    fun bind(items: List<HistoryItem>, images: PhotoImages, describe: (HistoryItem) -> String, open: (HistoryItem, ImageView, List<HistoryItem>) -> Unit) {
        val shown = items.take(if (items.size >= 8) 8 else if (items.size >= 4) 4 else items.size)
        val ids = shown.map { it.id }
        if (ids == tag) return
        tag = ids
        jobs.forEach { (job, signal) -> signal.cancel(); job.cancel() }
        removeAllViews()
        val size = (resources.displayMetrics.widthPixels / 3).coerceIn(160, 480)
        jobs = shown.map { item ->
            val image = ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP; contentDescription = describe(item)
                setBackgroundColor(context.getColor(R.color.duck_role_elevated_surface)); foreground = context.selectableBackground()
                transitionName = photoTransitionName(item.id)
                setOnClickListener { open(item, this, shown) }
            }
            addView(image)
            val signal = CancellationSignal()
            images.load(item, size, size, signal) { bitmap -> if (bitmap != null) {
                image.setImageBitmap(bitmap); image.setTag(R.id.photo_transition_ready, item.id)
            } } to signal
        }
        requestLayout()
    }

    private val columns get() = if (childCount >= 4) 4 else childCount.coerceAtLeast(1)

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val cell = (width - gap * (columns - 1)) / columns
        val side = if (childCount >= 4) cell else (width - gap * 3) / 4
        val rows = (childCount + columns - 1) / columns
        for (i in 0 until childCount) getChildAt(i).measure(MeasureSpec.makeMeasureSpec(cell, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(side, MeasureSpec.EXACTLY))
        setMeasuredDimension(width, if (rows == 0) 0 else rows * side + (rows - 1) * gap)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val x = (i % columns) * (child.measuredWidth + gap); val y = (i / columns) * (child.measuredHeight + gap)
            val left = if (layoutDirection == LAYOUT_DIRECTION_RTL) (r - l) - x - child.measuredWidth else x
            child.layout(left, y, left + child.measuredWidth, y + child.measuredHeight)
        }
    }
}

/**
 * A media mark (V5): a white glyph with a soft shadow, no badge, in a fixed
 * corner of a photo. Cached per glyph and size.
 */
internal object PhotoGlyphs {
    private val cache = HashMap<String, Bitmap>()
    fun drawable(context: Context, @DrawableRes icon: Int, sizeDp: Int): Drawable {
        val key = "$icon:$sizeDp:${context.resources.displayMetrics.density}"
        val bitmap = cache.getOrPut(key) {
            val size = context.dp(sizeDp); val pad = context.dp(4)
            val glyph = Bitmap.createBitmap(size + pad * 2, size + pad * 2, Bitmap.Config.ARGB_8888)
            context.getDrawable(icon)!!.mutate().apply {
                // design-exception: media marks are white over photos in every theme (visual-language.md V5).
                setTint(android.graphics.Color.WHITE); setBounds(pad, pad, pad + size, pad + size); draw(Canvas(glyph))
            }
            val shadowPaint = Paint().apply { maskFilter = BlurMaskFilter(context.dp(3).toFloat(), BlurMaskFilter.Blur.NORMAL) }
            val offset = IntArray(2)
            val shadow = glyph.extractAlpha(shadowPaint, offset)
            Bitmap.createBitmap(glyph.width, glyph.height, Bitmap.Config.ARGB_8888).also { out ->
                val canvas = Canvas(out)
                // design-exception: the soft shadow under a media mark is black at 45% so the glyph reads on light photos.
                canvas.drawBitmap(shadow, offset[0].toFloat(), offset[1].toFloat() + context.dp(1), Paint().apply { color = android.graphics.Color.BLACK; alpha = 115 })
                canvas.drawBitmap(glyph, 0f, 0f, null)
                shadow.recycle(); glyph.recycle()
            }
        }
        return BitmapDrawable(context.resources, bitmap)
    }
}

/** Application consent uses the shared Material sheet, wrapping content and native actions. */
internal fun Context.lookConsentSheet(title: String, lines: List<String>, note: String,
    cancel: String, confirm: String, action: () -> Unit): LookSheet {
    val sheet = LookSheet(this)
    val inset = token(R.dimen.duck_space_medium)
    sheet.body.setPadding(inset, 0, inset, inset)
    sheet.body.addView(lookText(title, M.style.TextAppearance_Material3_HeadlineSmall).apply { isAccessibilityHeading = true })
    lines.forEach { line ->
        sheet.body.addView(lookText(line, M.style.TextAppearance_Material3_BodyLarge).apply {
            breakStrategy = android.text.Layout.BREAK_STRATEGY_BALANCED
        }, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = token(R.dimen.duck_space_medium)
        })
    }
    sheet.body.addView(lookText(note, M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
        breakStrategy = android.text.Layout.BREAK_STRATEGY_BALANCED
    }, LinearLayout.LayoutParams(-1, -2).apply {
        topMargin = token(R.dimen.duck_space_medium)
    })
    val stacked = resources.configuration.fontScale > 1.3f || resources.configuration.screenWidthDp < 360
    sheet.body.addView(LinearLayout(this).apply {
        orientation = if (stacked) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
        gravity = Gravity.END
        addView(lookButton(cancel, LookButton.TEXT) { sheet.dismiss() }, LinearLayout.LayoutParams(if (stacked) -1 else -2, -2))
        addView(lookButton(confirm, LookButton.FILLED) { sheet.dismiss(); action() }, LinearLayout.LayoutParams(if (stacked) -1 else -2, -2).apply {
            if (stacked) topMargin = token(R.dimen.duck_space_small) else marginStart = token(R.dimen.duck_space_small)
        })
    }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_medium) })
    return sheet
}
