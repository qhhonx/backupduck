package app.backupduck

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.drawable.GradientDrawable
import android.os.CancellationSignal
import android.text.TextUtils
import android.text.format.Formatter
import android.util.LruCache
import android.util.Size
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.R as M
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDragHandleView
import com.google.android.material.card.MaterialCardView
import com.google.android.material.progressindicator.CircularProgressIndicator
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Received photos (design/records.md): what needs the user, grouped by cause,
 * then every received photo as a grid grouped by the day of its latest change.
 * Material 3 roles; shown behind the catalog's design switch until migration
 * step 6 replaces [HistoryPage].
 */
internal class ReceivedPhotosPage(private val activity: MainActivity, private val actions: Actions) {
    class Actions(val more: () -> Unit, val reload: () -> Unit, val retryAll: (done: (Boolean) -> Unit) -> Unit,
        val retry: (item: HistoryItem, done: (Boolean) -> Unit) -> Unit, val connect: () -> Unit)

    private val images = PhotoImages(activity)
    private val adapter = PhotoAdapter(activity, images, ::cardAction, ::showDetail, actions)
    private val span = (activity.resources.displayMetrics.widthPixels / activity.dp(96)).coerceAtLeast(3)
    private val layout = GridLayoutManager(activity, span).apply {
        spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int) = if (adapter.currentList.getOrNull(position) is PhotoRow.Tile) 1 else span
        }
    }
    private var history = HistoryState()
    private var attention = HistoryState()

    val view: RecyclerView = RecyclerView(activity).apply {
        id = R.id.receiver_photos_list; layoutManager = layout; adapter = this@ReceivedPhotosPage.adapter; itemAnimator = null
        clipToPadding = false; setPadding(0, 0, 0, activity.dp(24))
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy > 0 && layout.findLastVisibleItemPosition() >= this@ReceivedPhotosPage.adapter.itemCount - span * 4) actions.more()
            }
        })
    }

    fun render(state: HistoryState) { history = state; rebuild() }
    fun attention(state: HistoryState) { attention = state; rebuild() }
    fun progress(values: Map<String, ReceiverByteProgress>) = adapter.progress(view, values)
    fun scrollToTop() = layout.scrollToPositionWithOffset(0, 0)

    /** The index in the loaded history of the first photo on screen, for refreshing the visible page. */
    fun firstVisible(): Int {
        val first = layout.findFirstVisibleItemPosition().coerceAtLeast(0)
        val tile = adapter.currentList.drop(first).firstOrNull { it is PhotoRow.Tile } as? PhotoRow.Tile ?: return 0
        return history.items.indexOfFirst { it.id == tile.item.id }.coerceAtLeast(0)
    }

    private fun rebuild() {
        // The failed filter returns attention items only; the check also keeps a stale page honest.
        val causes = needsYou(attention.items.filter { it.processing == "failed" }, attention.nextCursor != null)
        adapter.scope = photoScope(history.counts, history.items, history.total, activity.devicePanels.senderNames)
        adapter.hasSenders = activity.hasKnownSenders != false
        adapter.submitList(photoRows(history.items, causes, ReceiverEnvironment.now(), ZoneId.systemDefault(),
            history.loading, history.failed, history.nextCursor != null))
    }

    private fun cardAction(group: CauseGroup, button: View) = when (group.cause) {
        PhotoCause.LIVE_PHOTO -> showCause(group)
        PhotoCause.NOT_SAVED -> {
            button.isEnabled = false
            actions.retryAll { ok ->
                button.isEnabled = true
                activity.duckAcknowledge(activity.getString(if (ok) R.string.photos_trying_again else R.string.photos_retry_failed))
            }
        }
    }

    /** The photos of one cause, as the same tiles. */
    private fun showCause(group: CauseGroup) {
        val sheet = photoSheet(activity)
        val body = sheet.body
        body.addView(photoText(activity, causeTitle(activity, group), M.style.TextAppearance_Material3_TitleLarge).apply { isAccessibilityHeading = true },
            LinearLayout.LayoutParams(-1, -2).apply { setMargins(activity.dp(24), 0, activity.dp(24), 0) })
        body.addView(photoText(activity, activity.getString(causeNote(group.cause)), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
            LinearLayout.LayoutParams(-1, -2).apply { setMargins(activity.dp(24), activity.dp(4), activity.dp(24), activity.dp(16)) })
        val tiles = PhotoAdapter(activity, images, { _, _ -> }, { sheet.dismiss(); showDetail(it) }, actions)
        body.addView(RecyclerView(activity).apply {
            layoutManager = GridLayoutManager(activity, span); adapter = tiles; itemAnimator = null; isNestedScrollingEnabled = false
        }, LinearLayout.LayoutParams(-1, -2))
        tiles.submitList(group.items.map { PhotoRow.Tile(it) })
        sheet.show()
    }

    fun showDetail(item: HistoryItem) { PhotoDetail(activity, images, actions).show(adapter.live(item)) }
}

/**
 * Thumbnails and previews come from the photo's copy in the Pixel's Photos
 * (synthetic in the catalog). A photo still arriving or not saved has no copy
 * yet, so it shows its kind instead; the core offers no thumbnail of the
 * received file.
 */
internal class PhotoImages(private val activity: MainActivity) {
    private val permits = Semaphore(2)
    private val cache = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    fun cached(item: HistoryItem, width: Int, height: Int): Bitmap? = cache.get(key(item, width, height))
    private fun key(item: HistoryItem, width: Int, height: Int) = "${item.id}:${width}x$height"

    /** Loads off the main thread; the caller checks the result still belongs to its view. */
    fun load(item: HistoryItem, width: Int, height: Int, signal: CancellationSignal, done: (Bitmap?) -> Unit): Job =
        activity.lifecycleScope.launch {
            val key = key(item, width, height)
            val image = cache.get(key) ?: withContext(Dispatchers.IO) {
                permits.withPermit {
                    currentCoroutineContext().ensureActive()
                    if (item.processing != "complete") return@withPermit null
                    runCatching {
                        ReceiverEnvironment.previewImage?.let { return@runCatching it(item, width, height) }
                        val copy = GalleryPreview.resolve(activity, item, null, signal) ?: return@runCatching null
                        GalleryPreview.decode(activity, copy, Size(width, height), signal)
                    }.getOrNull()?.also { cache.put(key, it) }
                }
            }
            if (isActive) done(image)
        }
}

private class SquareFrame(context: android.content.Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) = super.onMeasure(widthMeasureSpec, widthMeasureSpec)
}

private class PhotoAdapter(private val activity: MainActivity, private val images: PhotoImages,
    private val cardAction: (CauseGroup, View) -> Unit, private val open: (HistoryItem) -> Unit,
    private val actions: ReceivedPhotosPage.Actions) : ListAdapter<PhotoRow, RecyclerView.ViewHolder>(object : DiffUtil.ItemCallback<PhotoRow>() {
    override fun areItemsTheSame(old: PhotoRow, new: PhotoRow) = old.key == new.key
    override fun areContentsTheSame(old: PhotoRow, new: PhotoRow) = old == new
}) {
    var scope = PhotoScope(0, 0, null)
        set(value) { if (field != value) { field = value; currentList.indexOf(PhotoRow.Scope).takeIf { it >= 0 }?.let(::notifyItemChanged) } }
    var hasSenders = true
    private var liveProgress: Map<String, ReceiverByteProgress> = emptyMap()

    init { setHasStableIds(true); stateRestorationPolicy = StateRestorationPolicy.PREVENT_WHEN_EMPTY }
    override fun getItemId(position: Int) = getItem(position).key
    override fun getItemViewType(position: Int) = when (getItem(position)) {
        PhotoRow.Scope -> 0; PhotoRow.NeedsHeader -> 1; is PhotoRow.Cause -> 2; PhotoRow.TimelineHeader -> 3
        is PhotoRow.Day -> 4; is PhotoRow.Tile -> 5; is PhotoRow.Status -> 6; PhotoRow.CloudFooter -> 7
    }

    fun live(item: HistoryItem) = item.withLive(liveProgress[item.id])

    fun progress(list: RecyclerView, values: Map<String, ReceiverByteProgress>) {
        liveProgress = if (values.isEmpty()) emptyMap() else LinkedHashMap(liveProgress).apply {
            values.forEach { (id, value) -> remove(id); put(id, value) }
            while (size > 256) remove(keys.first())
        }
        for (i in 0 until list.childCount) {
            val holder = list.getChildViewHolder(list.getChildAt(i)) as? TileHolder ?: continue
            val position = holder.bindingAdapterPosition
            (currentList.getOrNull(position) as? PhotoRow.Tile)?.let { holder.mark(live(it.item)) }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder = with(activity) {
        when (viewType) {
            0 -> Plain(photoText(this, "", M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
                setPadding(dp(16), dp(4), dp(16), dp(8))
            })
            1 -> Plain(photoText(this, getString(R.string.photos_needs_you), M.style.TextAppearance_Material3_TitleMedium).apply {
                isAccessibilityHeading = true; setPadding(dp(16), dp(12), dp(16), dp(4))
            })
            2 -> CauseHolder(this@PhotoAdapter.activity)
            3 -> Plain(View(this).apply { minimumHeight = dp(8) })
            4 -> DayHolder(this@PhotoAdapter.activity)
            5 -> TileHolder(this@PhotoAdapter.activity)
            7 -> Plain(photoText(this, getString(R.string.photos_cloud_footer), M.style.TextAppearance_Material3_BodySmall, secondary = true).apply {
                gravity = Gravity.CENTER; setPadding(dp(32), dp(24), dp(32), dp(8))
            })
            else -> StatusHolder(this@PhotoAdapter.activity)
        }.also { it.itemView.layoutParams = RecyclerView.LayoutParams(-1, -2) }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = getItem(position)) {
            PhotoRow.Scope -> (holder.itemView as TextView).text = scopeLine(activity, scope)
            is PhotoRow.Cause -> (holder as CauseHolder).bind(row.group)
            is PhotoRow.Day -> (holder as DayHolder).bind(row)
            is PhotoRow.Tile -> (holder as TileHolder).bind(live(row.item))
            is PhotoRow.Status -> (holder as StatusHolder).bind(row.kind)
            else -> {}
        }
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        (holder as? TileHolder)?.cancel()
    }

    private class Plain(view: View) : RecyclerView.ViewHolder(view)

    private inner class DayHolder(activity: MainActivity) : RecyclerView.ViewHolder(LinearLayout(activity)) {
        private val day = photoText(activity, "", M.style.TextAppearance_Material3_TitleSmall).apply { isAccessibilityHeading = true }
        private val senders = photoText(activity, "", M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
            maxLines = 1; ellipsize = TextUtils.TruncateAt.END
        }
        init {
            (itemView as LinearLayout).apply {
                gravity = Gravity.CENTER_VERTICAL; setPadding(activity.dp(16), activity.dp(20), activity.dp(16), activity.dp(8))
                addView(day); addView(senders, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = activity.dp(8) })
            }
        }
        fun bind(row: PhotoRow.Day) {
            day.text = dayLabel(activity, row.epochDay)
            senders.text = row.senders.joinToString(activity.getString(R.string.photos_list_separator))
            senders.visibility = if (row.senders.isEmpty()) View.GONE else View.VISIBLE
        }
    }

    inner class TileHolder(private val activity: MainActivity) : RecyclerView.ViewHolder(SquareFrame(activity)) {
        private val image = ImageView(activity).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private val badge = ImageView(activity).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        private var work: Job? = null
        private var signal: CancellationSignal? = null
        private var bound: String? = null
        private var item: HistoryItem? = null
        init {
            (itemView as FrameLayout).apply {
                setPadding(activity.dp(1), activity.dp(1), activity.dp(1), activity.dp(1))
                addView(image, FrameLayout.LayoutParams(-1, -1))
                val mark = if (DuckLook.on) 28 else 22
                addView(badge, FrameLayout.LayoutParams(activity.dp(mark), activity.dp(mark), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, activity.dp(if (DuckLook.on) 2 else 5), activity.dp(if (DuckLook.on) 2 else 5)) })
                isFocusable = true; isClickable = true
                val out = android.util.TypedValue(); activity.theme.resolveAttribute(android.R.attr.selectableItemBackground, out, true)
                foreground = activity.getDrawable(out.resourceId)
                setOnClickListener { item?.let(open) }
            }
        }
        fun cancel() { signal?.cancel(); work?.cancel(); signal = null; work = null; bound = null }
        fun bind(item: HistoryItem) {
            this.item = item
            mark(item)
            val size = (activity.resources.displayMetrics.widthPixels / 4).coerceIn(160, 384)
            val key = "${item.id}:${item.processing}"
            if (bound == key) return
            cancel(); bound = key
            pictured = false
            images.cached(item, size, size)?.let { show(it); return }
            placeholder(image, item); mark(item)
            val next = CancellationSignal(); signal = next
            work = images.load(item, size, size, next) { bitmap -> if (bound == key && bitmap != null) show(bitmap) }
        }
        private var pictured = false
        private fun show(bitmap: Bitmap) {
            image.setPadding(0, 0, 0, 0); image.imageTintList = null; image.scaleType = ImageView.ScaleType.CENTER_CROP; image.setImageBitmap(bitmap)
            pictured = true; item?.let { photoMark(activity, badge, it.mark, onPhoto = true) }
        }
        fun mark(item: HistoryItem) {
            this.item = item
            photoMark(activity, badge, item.mark, onPhoto = pictured)
            itemView.contentDescription = activity.getString(R.string.photos_tile_description, kindLabel(activity, item), stateLabel(activity, item))
        }
    }

    private inner class CauseHolder(private val activity: MainActivity) : RecyclerView.ViewHolder(FrameLayout(activity)) {
        // The proposed look: a neutral card and title with one colored glyph and a tonal action (visual-language.md).
        private val look = DuckLook.on
        private val title = photoText(activity, "", M.style.TextAppearance_Material3_TitleMedium,
            color = if (look) activity.themeColor(M.attr.colorOnSurface) else activity.getColor(R.color.duck_state_on_attention_container))
        private val note = photoText(activity, "", M.style.TextAppearance_Material3_BodyMedium,
            color = if (look) activity.themeColor(M.attr.colorOnSurfaceVariant) else activity.getColor(R.color.duck_state_on_attention_container))
        private val button = if (look) activity.lookTonal("") {} else activity.duckButton("", false) {}
        init {
            val body = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(activity.dp(16), activity.dp(16), activity.dp(16), activity.dp(12)) }
            val head = LinearLayout(activity)
            head.addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_alert); imageTintList = ColorStateList.valueOf(activity.getColor(R.color.duck_state_attention))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(activity.dp(24), activity.dp(24)).apply { marginEnd = activity.dp(12) })
            val words = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            words.addView(title); words.addView(note, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(4) })
            head.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
            body.addView(head)
            body.addView(button, LinearLayout.LayoutParams(-2, -2).apply {
                topMargin = activity.dp(12); if (look) marginStart = activity.dp(36) else gravity = Gravity.END
            })
            (itemView as FrameLayout).apply {
                setPadding(activity.dp(16), activity.dp(4), activity.dp(16), activity.dp(4))
                addView(MaterialCardView(activity).apply {
                    radius = activity.dp(if (look) DuckLook.RADIUS_DP else 16).toFloat(); cardElevation = 0f; strokeWidth = 0
                    setCardBackgroundColor(if (look) activity.themeColor(M.attr.colorSurfaceContainer) else activity.getColor(R.color.duck_state_attention_container)); addView(body)
                }, FrameLayout.LayoutParams(-1, -2))
            }
        }
        // No thumbnails: photos that need the user have no copy in Photos, and the core offers none of the received file.
        fun bind(group: CauseGroup) {
            title.text = causeTitle(activity, group)
            note.setText(causeNote(group.cause))
            button.setText(if (group.cause == PhotoCause.LIVE_PHOTO) R.string.photos_view else R.string.photos_try_again)
            button.setOnClickListener { cardAction(group, button) }
        }
    }

    private inner class StatusHolder(private val activity: MainActivity) : RecyclerView.ViewHolder(LinearLayout(activity)) {
        private val box = itemView as LinearLayout
        fun bind(kind: StatusKind) = with(activity) {
            box.removeAllViews(); box.orientation = LinearLayout.VERTICAL; box.gravity = Gravity.CENTER_HORIZONTAL
            when (kind) {
                StatusKind.LOADING -> {
                    box.setPadding(dp(16), dp(24), dp(16), dp(24))
                    box.addView(CircularProgressIndicator(this).apply { isIndeterminate = true; contentDescription = getString(R.string.rhub_loading) })
                }
                StatusKind.FAILED -> {
                    box.setPadding(dp(24), dp(32), dp(24), dp(24))
                    box.addView(photoText(this, getString(R.string.photos_load_failed), M.style.TextAppearance_Material3_TitleMedium).apply { gravity = Gravity.CENTER })
                    box.addView(duckButton(getString(R.string.photos_try_again), false, actions.reload), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
                }
                StatusKind.EMPTY -> {
                    box.setPadding(dp(24), dp(48), dp(24), dp(24))
                    box.addView(ImageView(this).apply { setImageResource(R.drawable.duck_empty); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                        LinearLayout.LayoutParams(dp(120), dp(120)))
                    box.addView(photoText(this, getString(R.string.photos_empty_title), M.style.TextAppearance_Material3_HeadlineSmall).apply {
                        gravity = Gravity.CENTER; isAccessibilityHeading = true
                    }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
                    box.addView(photoText(this, getString(R.string.photos_empty_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply { gravity = Gravity.CENTER },
                        LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
                    if (!hasSenders) box.addView(duckButton(getString(R.string.rhub_connect), true, actions.connect), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(20) })
                }
            }
        }
    }
}

/**
 * One photo's detail: the photo, when it was taken, received and saved to
 * Photos, at most one action, then the file. Google Photos' state is the same
 * for every photo, so the page says it once in its footer instead.
 */
private class PhotoDetail(private val activity: MainActivity, private val images: PhotoImages, private val actions: ReceivedPhotosPage.Actions) {
    fun show(item: HistoryItem) = with(activity) {
        val sheet = photoSheet(this)
        val body = sheet.body
        val width = (resources.displayMetrics.widthPixels - dp(32)).coerceIn(320, 1440)
        val height = (width * 3 / 4).coerceAtMost((resources.displayMetrics.heightPixels * .45f).toInt())
        val preview = ImageView(this).apply {
            clipToOutline = true; maxHeight = height
            background = GradientDrawable().apply { cornerRadius = dp(12).toFloat(); setColor(themeColor(M.attr.colorSurfaceContainerHigh)) }
            contentDescription = kindLabel(activity, item)
        }
        body.addView(preview, LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(16), 0, dp(16), 0) })
        // Only a photo in the Pixel's Photos has a picture; the rest keep a small kind placeholder.
        placeholder(preview, item); preview.minimumHeight = if (item.processing == "complete") height else dp(120)
        val signal = CancellationSignal()
        val work = images.load(item, width, height, signal) { bitmap ->
            if (bitmap != null && sheet.isShowing) { preview.minimumHeight = 0; preview.adjustViewBounds = true; preview.setPadding(0, 0, 0, 0); preview.imageTintList = null; preview.scaleType = ImageView.ScaleType.FIT_CENTER; preview.setImageBitmap(bitmap) }
        }
        val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(16), dp(24), 0) }
        body.addView(words)
        words.addView(photoText(this, item.capturedAtMs?.let { getString(R.string.photos_taken, fullDate(this, it)) } ?: getString(R.string.photos_taken_unknown),
            M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true })
        val facts = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        words.addView(facts, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        val sender = item.senders.joinToString(getString(R.string.photos_list_separator)).ifEmpty { null }
        if (item.receipt == "received") fact(facts, R.drawable.ic_receiver, getColor(R.color.duck_state_received),
            sender?.let { getString(R.string.photos_received_from, it) } ?: getString(R.string.photos_received), item.receivedAtMs?.let { shortTime(this, it) })
        else fact(facts, R.drawable.ic_clock, themeColor(M.attr.colorPrimary),
            sender?.let { getString(R.string.photos_receiving_from, it) } ?: getString(R.string.photos_receiving),
            java.text.NumberFormat.getPercentInstance().format(item.confirmedBytes.toDouble() / item.totalBytes.coerceAtLeast(1)))
        when {
            item.processing == "complete" -> fact(facts, R.drawable.ic_check, getColor(R.color.duck_state_saved), getString(R.string.photos_in_photos), item.publishedAtMs?.let { shortTime(this, it) })
            item.cause == PhotoCause.LIVE_PHOTO -> fact(facts, R.drawable.ic_alert, getColor(R.color.duck_state_attention), getString(R.string.photos_live_cause), null)
            item.cause == PhotoCause.NOT_SAVED -> fact(facts, R.drawable.ic_alert, getColor(R.color.duck_state_attention), getString(R.string.photos_not_saved), null)
            item.receipt == "received" -> fact(facts, R.drawable.ic_clock, themeColor(M.attr.colorPrimary), getString(R.string.photos_saving), null)
            else -> fact(facts, R.drawable.ic_photo, themeColor(M.attr.colorOnSurfaceVariant), getString(R.string.photos_after_arrival), null)
        }
        val failure = photoText(this, getString(R.string.photos_retry_failed), M.style.TextAppearance_Material3_BodyMedium, color = getColor(R.color.duck_state_failure)).apply {
            visibility = View.GONE; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        words.addView(failure, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        val action = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        words.addView(action, LinearLayout.LayoutParams(-1, -2))
        if (item.cause == PhotoCause.NOT_SAVED) {
            lateinit var retry: View
            retry = duckButton(getString(R.string.photos_try_again), true) {
                retry.isEnabled = false; failure.visibility = View.GONE
                actions.retry(item) { ok ->
                    retry.isEnabled = true
                    if (ok) { sheet.dismiss(); duckAcknowledge(getString(R.string.photos_trying_again)) } else failure.visibility = View.VISIBLE
                }
            }
            action.addView(retry, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        }
        // Open the photo only once its copy in Photos is found; never offer a dead button.
        val lookup = if (item.processing == "complete") lifecycleScope.launch {
            val copy = withContext(Dispatchers.IO) { runCatching { GalleryPreview.resolve(activity, item, null, signal) }.getOrNull() } ?: return@launch
            if (!sheet.isShowing) return@launch
            action.addView(duckButton(getString(R.string.photos_open), false) {
                runCatching { startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(copy.uri, copy.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                    .onFailure { failure.setText(R.string.photos_open_failed); failure.visibility = View.VISIBLE }
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        } else null
        words.addView(photoText(this, listOf(item.filename, Formatter.formatFileSize(this, item.totalBytes), kindLabel(activity, item))
            .joinToString(" · "), M.style.TextAppearance_Material3_BodySmall, secondary = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(24); bottomMargin = dp(8) })
        sheet.setOnDismissListener { signal.cancel(); work.cancel(); lookup?.cancel() }
        sheet.show()
    }

    private fun fact(parent: LinearLayout, icon: Int, tint: Int, text: String, time: String?) = with(activity) {
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(48) }
        row.addView(ImageView(this).apply { setImageResource(icon); imageTintList = ColorStateList.valueOf(tint); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(16) })
        row.addView(photoText(this, text, M.style.TextAppearance_Material3_BodyLarge), LinearLayout.LayoutParams(0, -2, 1f).apply { topMargin = dp(6); bottomMargin = dp(6) })
        time?.let { row.addView(photoText(this, it, M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(12) }) }
        parent.addView(row, LinearLayout.LayoutParams(-1, -2))
    }
}

/** A Material 3 modal sheet with a drag handle and a scrolling body. */
internal class PhotoSheet(context: android.content.Context) : BottomSheetDialog(context, R.style.DuckBottomSheetDialog) {
    val body = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(0, 0, 0, context.dp(16)) }
    init {
        val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        content.addView(BottomSheetDragHandleView(context), LinearLayout.LayoutParams(-1, -2))
        content.addView(NestedScrollView(context).apply { addView(body) }, LinearLayout.LayoutParams(-1, -2))
        setContentView(content)
    }
    override fun onStart() {
        super.onStart()
        findViewById<FrameLayout>(M.id.design_bottom_sheet)?.let { sheet ->
            sheet.backgroundTintList = null
            sheet.background = GradientDrawable().apply {
                val r = context.dp(28).toFloat(); cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
                setColor(context.themeColor(M.attr.colorSurfaceContainerLow))
            }
        }
        behavior.state = BottomSheetBehavior.STATE_EXPANDED; behavior.skipCollapsed = true
    }
}
private fun photoSheet(activity: MainActivity) = PhotoSheet(activity)

internal fun photoText(context: android.content.Context, value: String, appearance: Int, secondary: Boolean = false, color: Int? = null) = TextView(context).apply {
    text = value; setTextAppearance(appearance)
    setTextColor(color ?: context.themeColor(if (secondary) M.attr.colorOnSurfaceVariant else M.attr.colorOnSurface))
}

/** The kind's icon on a neutral tile while there is no picture (still arriving, or no copy in Photos). */
private fun placeholder(view: ImageView, item: HistoryItem) = with(view.context) {
    view.setImageResource(when (item.kind) { "video" -> R.drawable.ic_video; "motion" -> R.drawable.ic_motion; else -> R.drawable.ic_photo })
    view.imageTintList = ColorStateList.valueOf(themeColor(M.attr.colorOnSurfaceVariant))
    view.scaleType = ImageView.ScaleType.CENTER
    view.background = view.background ?: GradientDrawable().apply { setColor(themeColor(M.attr.colorSurfaceContainerHigh)) }
    view.setPadding(0, 0, 0, 0)
}

/** A tile's mark: none when in the Pixel's Photos, a clock while receiving or saving, an alert when it needs the user. */
private fun photoMark(context: android.content.Context, badge: ImageView, mark: PhotoMark, onPhoto: Boolean) = with(context) {
    if (mark == PhotoMark.NONE) { badge.visibility = View.GONE; return@with }
    badge.visibility = View.VISIBLE
    val pending = mark == PhotoMark.PENDING
    if (DuckLook.on) {
        // The proposed look (visual-language.md § Marks): over a photo, a white glyph with a soft shadow and no badge.
        // A tile still arriving or not saved has no picture yet, so its glyph takes the text color, or attention when it needs the user.
        badge.background = null; badge.setPadding(0, 0, 0, 0); badge.scaleType = ImageView.ScaleType.CENTER
        val icon = if (pending) R.drawable.ic_clock else R.drawable.ic_alert
        if (onPhoto) { badge.imageTintList = null; badge.setImageDrawable(PhotoGlyphs.drawable(this, icon, 18)) }
        else {
            badge.setImageResource(icon)
            badge.imageTintList = ColorStateList.valueOf(if (pending) themeColor(M.attr.colorOnSurfaceVariant) else getColor(R.color.duck_state_attention))
            badge.scaleType = ImageView.ScaleType.FIT_CENTER; val pad = dp(5); badge.setPadding(pad, pad, pad, pad)
        }
        return@with
    }
    badge.setImageResource(if (pending) R.drawable.ic_clock else R.drawable.ic_alert)
    badge.imageTintList = ColorStateList.valueOf(if (pending) themeColor(M.attr.colorOnPrimaryContainer) else getColor(R.color.duck_state_on_attention_container))
    badge.background = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(if (pending) themeColor(M.attr.colorPrimaryContainer) else getColor(R.color.duck_state_attention_container))
        setStroke(dp(2), themeColor(M.attr.colorSurface))
    }
    val pad = dp(4); badge.setPadding(pad, pad, pad, pad)
}

private fun count(group: CauseGroup) = String.format(java.util.Locale.getDefault(), "%,d", group.items.size) + if (group.more) "+" else ""
private fun causeTitle(context: android.content.Context, group: CauseGroup) = context.resources.getQuantityString(
    if (group.cause == PhotoCause.LIVE_PHOTO) R.plurals.photos_cause_live else R.plurals.photos_cause_not_saved, group.items.size, count(group))
private fun causeNote(cause: PhotoCause) = if (cause == PhotoCause.LIVE_PHOTO) R.string.photos_cause_live_note else R.string.photos_cause_not_saved_note

private fun scopeLine(context: android.content.Context, scope: PhotoScope): String = with(context) {
    val total = String.format(java.util.Locale.getDefault(), "%,d", scope.total)
    val photos = scope.sender?.let { resources.getQuantityString(R.plurals.photos_scope_from, scope.total, total, it) }
        ?: resources.getQuantityString(R.plurals.photos_scope, scope.total, total)
    val saved = if (scope.allSaved) getString(R.string.photos_scope_all_saved)
        else getString(R.string.photos_scope_saved, String.format(java.util.Locale.getDefault(), "%,d", scope.saved))
    "$photos · $saved"
}

private fun kindLabel(context: android.content.Context, item: HistoryItem) = context.getString(when {
    item.kind == "motion" -> R.string.photos_kind_live
    item.kind == "video" -> R.string.photos_kind_video
    item.burstPrimary != null -> R.string.photos_kind_burst
    else -> R.string.photos_kind_photo
})

private fun stateLabel(context: android.content.Context, item: HistoryItem) = context.getString(when (item.mark) {
    PhotoMark.NONE -> R.string.photos_in_photos
    PhotoMark.PENDING -> R.string.photos_state_pending
    PhotoMark.NEEDS_YOU -> R.string.photos_needs_you
})

private fun dayLabel(context: android.content.Context, epochDay: Long): String {
    val today = epochDay(ReceiverEnvironment.now(), ZoneId.systemDefault())
    return when (epochDay) {
        today -> context.getString(R.string.photos_today)
        today - 1 -> context.getString(R.string.photos_yesterday)
        else -> {
            val date = LocalDate.ofEpochDay(epochDay)
            val ms = date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            formatted(context, if (date.year != LocalDate.ofEpochDay(today).year) "yMMMEd" else "MMMEd", ms)
        }
    }
}

/** Dates in the app's own language, which can differ from the system's. */
private fun formatted(context: android.content.Context, skeleton: String, ms: Long): String =
    android.icu.text.DateFormat.getInstanceForSkeleton(skeleton, context.resources.configuration.locales[0]).format(java.util.Date(ms))

internal fun shortTime(context: android.content.Context, ms: Long): String =
    dayLabel(context, epochDay(ms, ZoneId.systemDefault())) + " " + formatted(context, "jm", ms)

private fun fullDate(context: android.content.Context, ms: Long): String = formatted(context, "yMMMMEEEEdjm", ms)
