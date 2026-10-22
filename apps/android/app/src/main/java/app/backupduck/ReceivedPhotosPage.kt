package app.backupduck

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import androidx.core.view.doOnPreDraw
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
import java.io.File
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
    private val adapter = PhotoAdapter(activity, images, ::cardAction, { item, source -> open(item, source) }, actions)
    private val span = (activity.resources.displayMetrics.widthPixels / activity.dp(96)).coerceAtLeast(3)
    private val layout = GridLayoutManager(activity, span).apply {
        spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int) = if (adapter.currentList.getOrNull(position) is PhotoRow.Tile) 1 else span
        }
    }
    private var history = HistoryState()
    private var attention = HistoryState()
    private var needsYouRequested = false

    val view: RecyclerView = RecyclerView(activity).apply {
        id = R.id.receiver_photos_list; layoutManager = layout; adapter = this@ReceivedPhotosPage.adapter; itemAnimator = null
        clipToPadding = false; setPadding(0, 0, 0, activity.dp(24))
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) needsYouRequested = false
            }
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy > 0 && layout.findLastVisibleItemPosition() >= this@ReceivedPhotosPage.adapter.itemCount - span * 4) actions.more()
            }
        })
    }

    init { if (ReceiverEnvironment.nativeLibraryChrome) adapter.enableSelection(view, "received-photos") }

    private fun open(item: HistoryItem, source: ImageView?, list: RecyclerView = view) {
        if (ReceiverEnvironment.nativeLibraryChrome) NativePhotoViewerActivity.open(activity, adapter.live(item), source, list)
        else showDetail(item, source?.photoPoster(item.id))
    }

    fun render(state: HistoryState) { history = state; rebuild() }
    fun attention(state: HistoryState) { attention = state; rebuild() }
    fun progress(values: Map<String, ReceiverByteProgress>) = adapter.progress(view, values)
    fun scrollToTop() = layout.scrollToPositionWithOffset(0, 0)

    fun openNeedsYou() {
        needsYouRequested = true
        scrollToTop()
        rebuild()
    }

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
            history.loading, history.failed, history.nextCursor != null)) {
            if (needsYouRequested) {
                val section = adapter.currentList.indexOf(PhotoRow.NeedsHeader)
                if (section >= 0) {
                    layout.scrollToPositionWithOffset(section, 0)
                    needsYouRequested = false
                } else if (attention.filter == "failed" && !attention.loading && causes.isEmpty()) {
                    // The notification may outlive the problem; stay at the current Photos page.
                    needsYouRequested = false
                }
            }
        }
    }

    private fun cardAction(group: CauseGroup, button: View) = when (group.cause) {
        PhotoCause.LIVE_PHOTO -> showCause(group)
        PhotoCause.NOT_SAVED -> {
            button.isEnabled = false
            actions.retryAll { ok ->
                button.isEnabled = true
                (button.tag as? StateCard)?.actionFeedback(activity.getString(if (ok) R.string.photos_trying_again else R.string.photos_retry_failed), !ok)
            }
        }
    }

    /** The photos of one cause, as the same tiles. */
    private fun showCause(group: CauseGroup) {
        val sheet = LookSheet(activity)
        val body = sheet.body
        body.addView(activity.lookText(causeTitle(activity, group), M.style.TextAppearance_Material3_TitleLarge).apply { isAccessibilityHeading = true },
            LinearLayout.LayoutParams(-1, -2).apply { setMargins(activity.dp(24), 0, activity.dp(24), 0) })
        body.addView(activity.lookText(activity.getString(causeNote(group.cause)), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
            LinearLayout.LayoutParams(-1, -2).apply { setMargins(activity.dp(24), activity.dp(4), activity.dp(24), activity.dp(16)) })
        lateinit var grid: RecyclerView
        val tiles = PhotoAdapter(activity, images, { _, _ -> }, { item, source ->
            if (ReceiverEnvironment.nativeLibraryChrome) open(item, source, grid)
            else { val poster = source?.photoPoster(item.id); sheet.dismiss(); showDetail(item, poster) }
        }, actions)
        grid = RecyclerView(activity).apply {
            layoutManager = GridLayoutManager(activity, span); adapter = tiles; itemAnimator = null; isNestedScrollingEnabled = false
        }
        body.addView(grid, LinearLayout.LayoutParams(-1, -2))
        if (ReceiverEnvironment.nativeLibraryChrome) tiles.enableSelection(grid, "cause-${group.cause}")
        tiles.submitList(group.items.map { PhotoRow.Tile(it) })
        if (ReceiverEnvironment.nativeLibraryChrome) {
            adapter.suspendSelection()
            sheet.setOnDismissListener { adapter.resumeSelection() }
        }
        sheet.show()
    }

    fun showDetail(item: HistoryItem, poster: Bitmap? = null) { PhotoDetail(activity, images, actions).show(adapter.live(item), poster) }
}

/**
 * Prefer the published copy, falling back to the core's disposable preview of
 * the received original. Neither a picture nor its absence is publication evidence.
 */
internal class PhotoImages(private val activity: androidx.appcompat.app.AppCompatActivity) {
    companion object {
        private fun imageCache() = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
            override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
        }
        private val nativeCache = imageCache()
        private val nativePermits = Semaphore(2)
        fun clearCache() = nativeCache.evictAll()
    }
    private val cache = if (ReceiverEnvironment.nativeLibraryChrome) nativeCache else imageCache()
    private val permits = if (ReceiverEnvironment.nativeLibraryChrome) nativePermits else Semaphore(2)
    fun cached(item: HistoryItem, width: Int, height: Int): Bitmap? = cache.get(key(item, width, height))
    private fun key(item: HistoryItem, width: Int, height: Int) = "${item.id}:${item.receipt}:${item.processing}:${width}x$height"

    /** Loads off the main thread; the caller checks the result still belongs to its view. */
    fun load(item: HistoryItem, width: Int, height: Int, signal: CancellationSignal, done: (Bitmap?) -> Unit): Job =
        activity.lifecycleScope.launch {
            val key = key(item, width, height)
            val image = cache.get(key) ?: withContext(Dispatchers.IO) {
                permits.withPermit {
                    currentCoroutineContext().ensureActive()
                    signal.throwIfCanceled()
                    val image = runCatching {
                        val published = if (item.processing == "complete") runCatching {
                            ReceiverEnvironment.previewImage?.let { return@runCatching it(item, width, height) }
                            GalleryPreview.resolve(activity, item, null, signal)?.let {
                                GalleryPreview.decode(activity, it, Size(width, height), signal)
                            }
                        }.getOrNull() else null
                        signal.throwIfCanceled()
                        published ?: receivedPreview(item, signal)
                    }.getOrNull()
                    currentCoroutineContext().ensureActive()
                    signal.throwIfCanceled()
                    image?.also { cache.put(key, it) }
                }
            }
            if (isActive && !signal.isCanceled) done(image)
        }

    private fun receivedPreview(item: HistoryItem, signal: CancellationSignal): Bitmap? {
        if (item.receipt != "received") return null
        return loadReceiverPreviewFile(request = {
            val reply = NativeBridge.request(JSONObject().put("op", "receiver_preview")
                .put("root", "${activity.filesDir}/receiver").put("cache_dir", activity.cacheDir.absolutePath)
                .put("id", item.id)) as JSONObject
            reply.optString("path").takeIf { reply.optString("status") == "available" && it.isNotBlank() && !reply.isNull("path") }?.let(::File)
        }, decode = { BitmapFactory.decodeFile(it.absolutePath) }, checkCancelled = signal::throwIfCanceled)
    }
}

private class SquareFrame(context: android.content.Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) = super.onMeasure(widthMeasureSpec, widthMeasureSpec)
}

private class PhotoAdapter(private val activity: MainActivity, private val images: PhotoImages,
    private val cardAction: (CauseGroup, View) -> Unit, private val open: (HistoryItem, ImageView?) -> Unit,
    private val actions: ReceivedPhotosPage.Actions) : ListAdapter<PhotoRow, RecyclerView.ViewHolder>(object : DiffUtil.ItemCallback<PhotoRow>() {
    override fun areItemsTheSame(old: PhotoRow, new: PhotoRow) = old.key == new.key
    override fun areContentsTheSame(old: PhotoRow, new: PhotoRow) = old == new
}), PhotoTransitionItems {
    override fun positionOfPhoto(id: String) = currentList.indexOfFirst { it is PhotoRow.Tile && it.item.id == id }
    private var selection: NativePhotoSelection? = null
    private var selectionSource: List<PhotoRow>? = null
    private var selectionRows: List<HistoryItem?> = emptyList()
    private fun selectedRows(): List<HistoryItem?> {
        // ListAdapter publishes its new list before dispatching diff notifications.
        // Key lookups during those notifications must already see the new positions.
        if (selectionSource !== currentList) {
            selectionSource = currentList
            selectionRows = currentList.map { (it as? PhotoRow.Tile)?.item?.let(::live) }
        }
        return selectionRows
    }
    fun enableSelection(list: RecyclerView, key: String) {
        selection = NativePhotoSelection(activity, list, key,
            rows = ::selectedRows,
            open = { item ->
                val position = currentList.indexOfFirst { it is PhotoRow.Tile && it.item.id == item.id }
                open(live(item), (list.findViewHolderForAdapterPosition(position) as? TileHolder)?.image)
            }, retry = actions.retry)
    }
    fun suspendSelection() { selection?.suspendMode() }
    fun resumeSelection() { selection?.resumeMode() }
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
        if (selection != null) {
            selectionSource = null
            selection?.rowsChanged()
        }
        for (i in 0 until list.childCount) {
            val holder = list.getChildViewHolder(list.getChildAt(i)) as? TileHolder ?: continue
            val position = holder.bindingAdapterPosition
            (currentList.getOrNull(position) as? PhotoRow.Tile)?.let { holder.mark(live(it.item)) }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder = with(activity) {
        when (viewType) {
            0 -> Plain(lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
                setPadding(dp(16), dp(4), dp(16), dp(8))
            })
            1 -> Plain(lookText(getString(R.string.photos_needs_you), M.style.TextAppearance_Material3_TitleMedium).apply {
                isAccessibilityHeading = true; setPadding(dp(16), dp(12), dp(16), dp(4))
            })
            2 -> CauseHolder(this@PhotoAdapter.activity)
            3 -> Plain(View(this).apply { minimumHeight = dp(8) })
            4 -> DayHolder(this@PhotoAdapter.activity)
            5 -> TileHolder(this@PhotoAdapter.activity)
            7 -> Plain(lookText(getString(R.string.photos_cloud_footer), M.style.TextAppearance_Material3_BodySmall, secondary = true).apply {
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

    override fun onCurrentListChanged(previousList: MutableList<PhotoRow>, currentList: MutableList<PhotoRow>) {
        selection?.rowsChanged()
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        (holder as? TileHolder)?.cancel()
        (holder as? CauseHolder)?.cancel()
    }

    override fun onViewDetachedFromWindow(holder: RecyclerView.ViewHolder) {
        (holder as? TileHolder)?.cancel()
        (holder as? CauseHolder)?.cancel()
    }

    override fun onViewAttachedToWindow(holder: RecyclerView.ViewHolder) {
        val row = currentList.getOrNull(holder.bindingAdapterPosition)
        if (holder is TileHolder && row is PhotoRow.Tile) holder.bind(live(row.item))
        if (holder is CauseHolder && row is PhotoRow.Cause) holder.bind(row.group)
    }

    private class Plain(view: View) : RecyclerView.ViewHolder(view)

    private inner class DayHolder(activity: MainActivity) : RecyclerView.ViewHolder(LinearLayout(activity)) {
        private val day = activity.lookText("", M.style.TextAppearance_Material3_TitleSmall).apply { isAccessibilityHeading = true }
        private val senders = activity.lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true)
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
        val image = ImageView(activity).apply {
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
                if (ReceiverEnvironment.nativeLibraryChrome) addView(android.widget.CheckBox(activity).apply {
                    tag = "photo-selection"; isClickable = false; isFocusable = false
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO; visibility = View.GONE
                }, FrameLayout.LayoutParams(activity.dp(48), activity.dp(48), Gravity.TOP or Gravity.END))
                addView(badge, FrameLayout.LayoutParams(activity.dp(28), activity.dp(28), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, activity.dp(2), activity.dp(2)) })
                isFocusable = true; isClickable = true
                val out = android.util.TypedValue(); activity.theme.resolveAttribute(android.R.attr.selectableItemBackground, out, true)
                foreground = activity.getDrawable(out.resourceId)
                if (ReceiverEnvironment.nativeLibraryChrome) setOnLongClickListener {
                    item?.let { selection?.select(it.id) } == true
                }
                setOnClickListener {
                    item?.let { current ->
                        if (selection?.toggleIfSelecting(current.id) != true) open(current, image)
                    }
                }
            }
        }
        fun cancel() { signal?.cancel(); work?.cancel(); signal = null; work = null; bound = null }
        fun bind(item: HistoryItem) {
            this.item = item
            image.transitionName = photoTransitionName(item.id)
            selection?.bind(itemView, item.id)
            mark(item)
            val size = (activity.resources.displayMetrics.widthPixels / 4).coerceIn(160, 384)
            val key = "${item.id}:${item.receipt}:${item.processing}"
            if (bound == key) return
            cancel(); bound = key
            image.setTag(R.id.photo_transition_ready, null)
            pictured = false
            images.cached(item, size, size)?.let { show(it); return }
            placeholder(image, loading = true); mark(item)
            val next = CancellationSignal(); signal = next
            work = images.load(item, size, size, next) { bitmap ->
                if (bound == key) {
                    if (bitmap != null) show(bitmap) else placeholder(image)
                }
            }
        }
        private var pictured = false
        private fun show(bitmap: Bitmap) {
            image.setPadding(0, 0, 0, 0); image.imageTintList = null; image.scaleType = ImageView.ScaleType.CENTER_CROP; image.setImageBitmap(bitmap)
            image.setTag(R.id.photo_transition_ready, item?.id)
            pictured = true; item?.let { photoMark(activity, badge, it.mark, onPhoto = true) }
        }
        fun mark(item: HistoryItem) {
            this.item = item
            photoMark(activity, badge, item.mark, onPhoto = pictured)
            itemView.contentDescription = activity.getString(R.string.photos_tile_description, kindLabel(activity, item), stateLabel(activity, item))
        }
    }

    /** The shared problem card reserves photo slots before any asynchronous loading. */
    private inner class CauseHolder(private val activity: MainActivity) : RecyclerView.ViewHolder(FrameLayout(activity)) {
        private val card = StateCard(activity)
        private val row = LinearLayout(activity)
        private val slots = List(3) { ImageView(activity) }
        private val tileSize = activity.token(R.dimen.duck_space_xx_large) + activity.token(R.dimen.duck_space_x_small)
        private val work = mutableListOf<Job>()
        private val signals = mutableListOf<CancellationSignal>()
        private var bound: List<HistoryItem>? = null
        private var currentGroup: CauseGroup? = null
        init {
            val size = tileSize
            row.layoutParams = FrameLayout.LayoutParams(-1, size)
            slots.forEachIndexed { index, image ->
                image.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                image.background = GradientDrawable().apply {
                    setColor(activity.getColor(R.color.duck_m3_surface_container_highest))
                    cornerRadius = activity.token(R.dimen.duck_radius_control).toFloat()
                }
                image.clipToOutline = true
                row.addView(image, LinearLayout.LayoutParams(size, size).apply {
                    if (index > 0) marginStart = activity.token(R.dimen.duck_space_xx_small)
                })
            }
            (itemView as FrameLayout).apply {
                setPadding(activity.token(R.dimen.duck_space_medium), activity.token(R.dimen.duck_space_xx_small), activity.token(R.dimen.duck_space_medium), activity.token(R.dimen.duck_space_xx_small))
                addView(card.view, FrameLayout.LayoutParams(-1, -2))
            }
        }
        fun cancel() {
            signals.forEach { it.cancel() }; work.forEach { it.cancel() }
            signals.clear(); work.clear(); bound = null
        }
        fun bind(group: CauseGroup) {
            currentGroup = group
            card.show(LookState(R.drawable.ic_alert, activity.getColor(R.color.duck_state_attention), causeTitle(activity, group), activity.getString(causeNote(group.cause)),
                action = activity.getString(if (group.cause == PhotoCause.LIVE_PHOTO) R.string.photos_view else R.string.photos_try_again) to {
                    currentGroup?.let { current -> card.actionButton?.let { cardAction(current, it) } }
                }))
            val items = group.items.take(slots.size)
            card.media(row.takeIf { items.isNotEmpty() })
            if (bound == items) return
            cancel(); bound = items
            val size = tileSize
            slots.forEachIndexed { index, image ->
                val item = items.getOrNull(index)
                image.visibility = if (item == null) View.GONE else View.VISIBLE
                if (item != null) {
                    fun placeholder(loading: Boolean) {
                        placeholder(image, loading)
                        image.contentDescription = if (loading) null else activity.getString(R.string.photos_preview_unavailable)
                        image.importantForAccessibility = if (loading) View.IMPORTANT_FOR_ACCESSIBILITY_NO else View.IMPORTANT_FOR_ACCESSIBILITY_YES
                    }
                    placeholder(loading = true)
                    fun show(bitmap: Bitmap) {
                        image.imageTintList = null; image.scaleType = ImageView.ScaleType.CENTER_CROP; image.setImageBitmap(bitmap)
                        image.contentDescription = null
                        image.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                    }
                    val cached = images.cached(item, size, size)
                    if (cached != null) show(cached) else {
                        val signal = CancellationSignal(); signals += signal
                        work += images.load(item, size, size, signal) { bitmap ->
                            if (bound == items) {
                                if (bitmap != null) show(bitmap) else placeholder(loading = false)
                            }
                        }
                    }
                }
            }
        }
    }

    private inner class StatusHolder(private val activity: MainActivity) : RecyclerView.ViewHolder(LinearLayout(activity)) {
        private val box = itemView as LinearLayout
        fun bind(kind: StatusKind) = with(activity) {
            box.removeAllViews(); box.orientation = LinearLayout.VERTICAL; box.gravity = Gravity.CENTER_HORIZONTAL
            val margin = token(R.dimen.duck_space_medium)
            when (kind) {
                StatusKind.LOADING -> {
                    box.setPadding(margin, token(R.dimen.duck_space_large), margin, token(R.dimen.duck_space_large))
                    box.addView(CircularProgressIndicator(this).apply { isIndeterminate = true; contentDescription = getString(R.string.rhub_loading) })
                }
                StatusKind.FAILED -> {
                    box.setPadding(margin, token(R.dimen.duck_space_x_small), margin, 0)
                    lookUnavailable(box, getString(R.string.nav_photos), getString(R.string.photos_load_failed),
                        getString(R.string.photos_try_again) to actions.reload)
                }
                StatusKind.EMPTY -> {
                    box.setPadding(margin, token(R.dimen.duck_space_xx_large), margin, token(R.dimen.duck_space_large))
                    lookEmpty(box, R.drawable.duck_empty, getString(R.string.photos_empty_title), getString(R.string.photos_empty_note),
                        getString(R.string.rhub_connect) to actions.connect, card = false)
                }
            }
        }
    }
}

/**
 * One photo (I1 full-screen viewer, I2 detail; P7): the photo on a dark page in
 * every theme, then when it was taken, received and saved to Photos with their
 * times, at most one action, the file, and one line on Google Photos, whose
 * backup BackupDuck cannot see.
 */
internal class PhotoDetail(private val activity: androidx.appcompat.app.AppCompatActivity, private val images: PhotoImages, private val actions: ReceivedPhotosPage.Actions) {
    fun show(item: HistoryItem, poster: Bitmap? = null): Unit = with(activity) {
        val dark = darkLook()
        val page = androidx.appcompat.app.AppCompatDialog(dark, R.style.DuckFullPage)
        trackNotificationWindow(page)
        val content = content(item, dismiss = { page.dismiss() }, isShowing = { page.isShowing }, poster = poster)
        page.setContentView(content.root)
        page.setOnDismissListener { content.cancel() }
        if (!photoAnimationsEnabled()) page.window?.setWindowAnimations(0)
        page.show()
        page.window?.let { window ->
            window.setLayout(-1, -1)
            androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
            window.statusBarColor = dark.getColor(android.R.color.transparent)
            window.navigationBarColor = dark.getColor(android.R.color.transparent)
            if (android.os.Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
            androidx.core.view.WindowCompat.getInsetsController(window, content.root).apply {
                isAppearanceLightStatusBars = false
                isAppearanceLightNavigationBars = false
            }
            androidx.core.view.ViewCompat.requestApplyInsets(content.root)
        }
    }

    internal class Content(val root: View, val preview: ImageView, val cancel: () -> Unit)

    fun content(item: HistoryItem, dismiss: () -> Unit, isShowing: () -> Boolean,
        sharedName: String? = null, poster: Bitmap? = null, ready: (Boolean) -> Unit = {},
        afterEnter: (() -> Unit) -> Unit = { it() }): Content = with(activity) {
        val dark = darkLook()
        val canvas = dark.getColor(R.color.duck_role_background)
        val root = LinearLayout(dark).apply {
            orientation = LinearLayout.VERTICAL; setBackgroundColor(canvas)
            if (sharedName != null) isTransitionGroup = false
        }
        if (sharedName != null) {
            root.addView(com.google.android.material.appbar.MaterialToolbar(dark).apply {
                setNavigationIcon(R.drawable.ic_close)
                setNavigationContentDescription(R.string.connect_close)
                setNavigationOnClickListener { dismiss() }
            }, LinearLayout.LayoutParams(-1, resources.getDimensionPixelSize(M.dimen.m3_appbar_size_compact)))
        } else root.addView(android.widget.ImageButton(dark).apply {
            setImageResource(R.drawable.ic_close); contentDescription = getString(R.string.connect_close)
            imageTintList = ColorStateList.valueOf(dark.getColor(R.color.duck_role_primary_text))
            val out = android.util.TypedValue(); dark.theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, out, true)
            setBackgroundResource(out.resourceId); setOnClickListener { dismiss() }
        }, LinearLayout.LayoutParams(dp(48), dp(48)).apply { setMargins(token(R.dimen.duck_space_xx_small), token(R.dimen.duck_space_xx_small), 0, 0) })
        val width = resources.displayMetrics.widthPixels.coerceIn(320, 1440)
        val height = (resources.displayMetrics.heightPixels * .6f).toInt()
        val preview = ImageView(dark).apply {
            contentDescription = kindLabel(activity, item); transitionName = sharedName
        }
        root.addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
        // Keep the same space when neither the published copy nor a received preview is available.
        placeholder(preview, loading = true)
        var hasPreview = false
        (poster ?: images.cached(item, (resources.displayMetrics.widthPixels / 4).coerceIn(160, 384),
            (resources.displayMetrics.widthPixels / 4).coerceIn(160, 384)))?.let {
            preview.background = null; preview.imageTintList = null
            preview.setPadding(0, 0, 0, 0)
            preview.scaleType = ImageView.ScaleType.FIT_CENTER; preview.setImageBitmap(it)
            hasPreview = true
        }
        // A retained tile poster can start the flight immediately. Do not replace its
        // drawable mid-flight; publish the full rendition once Android settles it.
        if (hasPreview) preview.doOnPreDraw { ready(true) }
        val signal = CancellationSignal()
        val work = images.load(item, width, height, signal) { bitmap ->
            if (bitmap != null && isShowing()) {
                fun publish() {
                    if (!isShowing()) return
                    preview.background = null; preview.imageTintList = null
                    if (sharedName != null) preview.setPadding(0, 0, 0, 0)
                    preview.scaleType = ImageView.ScaleType.FIT_CENTER; preview.setImageBitmap(bitmap)
                }
                if (sharedName != null && hasPreview) afterEnter(::publish) else publish()
            } else if (isShowing() && !hasPreview) placeholder(preview)
            if (!hasPreview) {
                if (sharedName != null) preview.doOnPreDraw { ready(bitmap != null) } else ready(bitmap != null)
            }
        }
        val panel = LinearLayout(dark).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(token(R.dimen.duck_space_medium), token(R.dimen.duck_space_large), token(R.dimen.duck_space_medium), token(R.dimen.duck_space_medium))
        }
        val information = BoundedScroll(dark, .6f).apply {
            addView(panel)
            background = GradientDrawable().apply {
                val r = dp(28).toFloat(); cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
                setColor(dark.getColor(R.color.duck_m3_surface_container_low))
            }
        }
        root.addView(information, LinearLayout.LayoutParams(-1, -2))
        // A8: the panel background reaches the window edge; only content avoids system bars.
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars() or
                androidx.core.view.WindowInsetsCompat.Type.displayCutout())
            root.setPadding(bars.left, bars.top, bars.right, 0)
            information.setPadding(0, 0, 0, bars.bottom)
            insets
        }
        panel.addView(dark.lookText(item.capturedAtMs?.let { getString(R.string.photos_taken, fullDate(this, it)) } ?: getString(R.string.photos_taken_unknown),
            M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true; setPadding(token(R.dimen.duck_space_xx_small), 0, 0, 0) })
        val facts = dark.lookGroup(panel)
        (facts.parent as View).let { (it.layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_small) }
        val sender = item.senders.joinToString(getString(R.string.photos_list_separator)).ifEmpty { null }
        if (item.receipt == "received") fact(dark, facts, R.drawable.ic_clock, dark.getColor(R.color.duck_state_received),
            sender?.let { getString(R.string.photos_received_from, it) } ?: getString(R.string.photos_received), item.receivedAtMs?.let { shortTime(this, it) })
        else fact(dark, facts, R.drawable.ic_clock, dark.getColor(R.color.duck_role_accent),
            sender?.let { getString(R.string.photos_receiving_from, it) } ?: getString(R.string.photos_receiving),
            java.text.NumberFormat.getPercentInstance().format(item.confirmedBytes.toDouble() / item.totalBytes.coerceAtLeast(1)))
        val attention = dark.getColor(R.color.duck_state_attention)
        when {
            item.processing == "complete" -> fact(dark, facts, R.drawable.ic_check, dark.getColor(R.color.duck_state_saved), getString(R.string.photos_in_photos), item.publishedAtMs?.let { shortTime(this, it) })
            item.cause == PhotoCause.LIVE_PHOTO -> fact(dark, facts, R.drawable.ic_alert, attention, getString(R.string.photos_live_cause), null)
            item.cause == PhotoCause.NOT_SAVED -> fact(dark, facts, R.drawable.ic_alert, attention, getString(R.string.photos_not_saved), null)
            item.receipt == "received" -> fact(dark, facts, R.drawable.ic_clock, dark.getColor(R.color.duck_role_accent), getString(R.string.photos_saving), null)
            else -> fact(dark, facts, R.drawable.ic_photo, dark.getColor(R.color.duck_role_secondary_text), getString(R.string.photos_after_arrival), null)
        }
        val failure = dark.lookText(getString(R.string.photos_retry_failed), M.style.TextAppearance_Material3_BodyMedium, color = dark.getColor(R.color.duck_state_failure)).apply {
            visibility = View.GONE; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        panel.addView(failure, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        val action = LinearLayout(dark).apply { orientation = LinearLayout.VERTICAL }
        panel.addView(action, LinearLayout.LayoutParams(-1, -2))
        if (item.cause == PhotoCause.NOT_SAVED) {
            lateinit var retry: View
            retry = dark.lookButton(getString(R.string.photos_try_again), LookButton.TONAL) {
                retry.isEnabled = false; failure.visibility = View.GONE
                actions.retry(item) { ok ->
                    retry.isEnabled = true
                    if (ok) { dismiss() } else failure.visibility = View.VISIBLE
                }
            }
            action.addView(retry, LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        }
        // Open the photo only once its copy in Photos is found; never offer a dead button.
        val lookup = if (item.processing == "complete") lifecycleScope.launch {
            val copy = withContext(Dispatchers.IO) { runCatching { GalleryPreview.resolve(activity, item, null, signal) }.getOrNull() } ?: return@launch
            if (!isShowing()) return@launch
            action.addView(dark.lookButton(getString(R.string.photos_open), LookButton.TONAL) {
                runCatching { startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(copy.uri, copy.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                    .onFailure { failure.setText(R.string.photos_open_failed); failure.visibility = View.VISIBLE }
            }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        } else null
        val quiet = LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) }
        panel.addView(dark.lookText(listOf(item.filename, Formatter.formatFileSize(this, item.totalBytes), kindLabel(activity, item)).joinToString(" · "),
            M.style.TextAppearance_Material3_BodySmall, secondary = true).apply { setPadding(token(R.dimen.duck_space_xx_small), 0, 0, 0) }, quiet)
        panel.addView(dark.lookText(getString(R.string.photos_detail_cloud), M.style.TextAppearance_Material3_BodySmall, secondary = true).apply {
            setPadding(token(R.dimen.duck_space_xx_small), 0, 0, 0)
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_xx_small) })
        Content(root, preview) { signal.cancel(); work.cancel(); lookup?.cancel() }
    }

    /** One fact: its glyph in the state color, the sentence, and its time below when known. */
    private fun fact(dark: android.content.Context, group: LinearLayout, icon: Int, tint: Int, text: String, time: String?) {
        val support = dark.lookRow(group, icon, text, time)
        val row = support.parent.parent as LinearLayout
        (row.getChildAt(0) as ImageView).imageTintList = ColorStateList.valueOf(tint)
    }
}

/** A scroll view no taller than [fraction] of the screen, so the photo above keeps its room at any text size. */
private class BoundedScroll(context: android.content.Context, private val fraction: Float) : NestedScrollView(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val limit = (resources.displayMetrics.heightPixels * fraction).toInt()
        val size = MeasureSpec.getSize(heightMeasureSpec)
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) limit else minOf(size, limit), MeasureSpec.AT_MOST))
    }
}

/** Loading is a quiet neutral tile; only an unavailable preview shows the photo glyph. */
private fun placeholder(view: ImageView, loading: Boolean = false) = with(view.context) {
    if (loading) view.setImageDrawable(null) else view.setImageResource(R.drawable.ic_photo)
    view.imageTintList = if (loading) null else ColorStateList.valueOf(getColor(R.color.duck_m3_on_surface_variant))
    view.scaleType = ImageView.ScaleType.CENTER
    val background = view.background as? GradientDrawable ?: GradientDrawable()
    background.setColor(getColor(R.color.duck_m3_surface_container_highest))
    view.background = background
    view.setPadding(0, 0, 0, 0)
}

/** A tile's mark: none when in the Pixel's Photos, a clock while receiving or saving, an alert when it needs the user. */
private fun photoMark(context: android.content.Context, badge: ImageView, mark: PhotoMark, onPhoto: Boolean) = with(context) {
    if (mark == PhotoMark.NONE) { badge.visibility = View.GONE; return@with }
    badge.visibility = View.VISIBLE
    val pending = mark == PhotoMark.PENDING
    // V5: over a photo, a white glyph with a soft shadow and no badge. On a placeholder,
    // use secondary text color, or attention when the photo needs the user.
    badge.background = null; badge.setPadding(0, 0, 0, 0); badge.scaleType = ImageView.ScaleType.CENTER
    val icon = if (pending) R.drawable.ic_clock else R.drawable.ic_alert
    if (onPhoto) { badge.imageTintList = null; badge.setImageDrawable(PhotoGlyphs.drawable(this, icon, 18)) }
    else {
        badge.setImageResource(icon)
        badge.imageTintList = ColorStateList.valueOf(getColor(if (pending) R.color.duck_role_secondary_text else R.color.duck_state_attention))
        badge.scaleType = ImageView.ScaleType.FIT_CENTER; val pad = dp(5); badge.setPadding(pad, pad, pad, pad)
    }
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

/** What a tile says to a screen reader: its kind and where it is. */
internal fun tileDescription(context: android.content.Context, item: HistoryItem) = context.getString(R.string.photos_tile_description, kindLabel(context, item), stateLabel(context, item))

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
