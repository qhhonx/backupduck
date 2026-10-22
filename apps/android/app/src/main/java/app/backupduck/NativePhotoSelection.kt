package app.backupduck

import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import androidx.appcompat.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.selection.ItemDetailsLookup
import androidx.recyclerview.selection.ItemKeyProvider
import androidx.recyclerview.selection.SelectionPredicates
import androidx.recyclerview.selection.SelectionTracker
import androidx.recyclerview.selection.StorageStrategy
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** D1 opt-in: each grid owns its stable media keys and a system contextual action mode. */
internal class NativePhotoSelection(
    private val activity: MainActivity,
    private val list: RecyclerView,
    private val stateKey: String,
    private val rows: () -> List<HistoryItem?>,
    private val open: (HistoryItem) -> Unit,
    private val retry: (HistoryItem, (Boolean) -> Unit) -> Unit,
) {
    private val tracker = SelectionTracker.Builder(
        stateKey, list, object : ItemKeyProvider<String>(SCOPE_MAPPED) {
            override fun getKey(position: Int) = rows().getOrNull(position)?.id
            override fun getPosition(key: String) = rows().indexOfFirst { it?.id == key }
        }, object : ItemDetailsLookup<String>() {
            override fun getItemDetails(event: MotionEvent): ItemDetails<String>? {
                val child = list.findChildViewUnder(event.x, event.y) ?: return null
                val position = list.getChildAdapterPosition(child)
                val key = rows().getOrNull(position)?.id ?: return null
                return object : ItemDetails<String>() {
                    override fun getPosition() = position
                    override fun getSelectionKey() = key
                }
            }
        }, StorageStrategy.createStringStorage()
    ).withSelectionPredicate(SelectionPredicates.createSelectAnything()).build()
    private var mode: ActionMode? = null
    private var pendingRestore: Bundle? = activity.savedStateRegistry.consumeRestoredStateForKey(stateKey)
    private var busy = false
    private var shareWork: Job? = null
    private var shareSignal: CancellationSignal? = null
    private var alive = true
    private var suspended = false
    private var resumeAfterViewer = false
    private val back = object : androidx.activity.OnBackPressedCallback(false) {
        override fun handleOnBackPressed() { tracker.clearSelection() }
    }
    private fun selected() = rows().filterNotNull().filter { tracker.isSelected(it.id) }

    init {
        activity.onBackPressedDispatcher.addCallback(activity, back)
        activity.savedStateRegistry.registerSavedStateProvider(stateKey) { Bundle().also(tracker::onSaveInstanceState) }
        tracker.addObserver(object : SelectionTracker.SelectionObserver<String>() {
            override fun onSelectionChanged() {
                updateMode()
                // Rebind only selection decoration. Image work keeps its revision key.
                for (i in 0 until list.childCount) {
                    val child = list.getChildAt(i)
                    rows().getOrNull(list.getChildAdapterPosition(child))?.let { bind(child, it.id) }
                }
            }
        })
        list.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {}
            override fun onViewDetachedFromWindow(v: View) { dispose() }
        })
        activity.lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) {
                if (resumeAfterViewer) { resumeAfterViewer = false; resumeMode() }
            }
            override fun onDestroy(owner: LifecycleOwner) { dispose() }
        })
    }

    private fun updateMode() {
        back.isEnabled = !suspended && tracker.hasSelection()
        if (suspended) return
        if (tracker.hasSelection()) {
            if (mode == null) mode = activity.startSupportActionMode(callback)
            mode?.title = activity.resources.getQuantityString(R.plurals.photos_selected, tracker.selection.size(), tracker.selection.size())
            mode?.invalidate()
        } else mode?.finish()
    }
    fun suspendMode() {
        suspended = true; back.isEnabled = false
        mode?.finish()
    }
    fun resumeMode() { if (alive) { suspended = false; updateMode() } }
    fun select(key: String): Boolean { tracker.select(key); return true }

    private fun dispose() {
        if (!alive) return
        alive = false; shareSignal?.cancel(); shareWork?.cancel(); mode?.finish(); back.remove()
        activity.savedStateRegistry.unregisterSavedStateProvider(stateKey)
    }
    fun rowsChanged() {
        if (!alive) return
        if (pendingRestore != null && rows().all { it == null }) return
        pendingRestore?.let { pendingRestore = null; tracker.onRestoreInstanceState(it) }
        val keys = rows().mapNotNull { it?.id }.toSet()
        tracker.selection.toList().filter { it !in keys }.forEach(tracker::deselect)
        updateMode()
    }
    fun toggleIfSelecting(key: String): Boolean {
        if (!tracker.hasSelection()) return false
        if (tracker.isSelected(key)) tracker.deselect(key) else tracker.select(key)
        return true
    }
    fun bind(view: View, key: String) {
        view.isActivated = tracker.isSelected(key); view.isSelected = tracker.isSelected(key)
        view.findViewWithTag<NativePhotoSelectionMark>("photo-selection")
            ?.bind(tracker.isSelected(key), tracker.hasSelection())
        androidx.core.view.ViewCompat.setStateDescription(view,
            if (tracker.isSelected(key)) activity.getString(R.string.photos_selection_selected) else null)
    }
    private val callback = object : ActionMode.Callback {
        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
            menu.add(0, 1, 0, R.string.photos_view).setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
            menu.add(0, 2, 1, R.string.photos_try_again).setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
            menu.add(0, 3, 2, R.string.photos_share).setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
            return true
        }
        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
            val items = selected()
            menu.findItem(1).apply { isVisible = items.size == 1; isEnabled = !busy }
            menu.findItem(2).apply { isVisible = items.any { it.cause == PhotoCause.NOT_SAVED }; isEnabled = !busy }
            menu.findItem(3).apply { isVisible = items.isNotEmpty(); isEnabled = !busy }
            return true
        }
        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            val items = selected()
            if (busy || items.isEmpty()) return true
            mode.subtitle = null
            when (item.itemId) {
                1 -> items.singleOrNull()?.let {
                    resumeAfterViewer = true; suspendMode(); open(it)
                }
                2 -> {
                    val retryable = items.filter { it.cause == PhotoCause.NOT_SAVED }
                    busy = true; mode.invalidate()
                    var remaining = retryable.size
                    var failed = false
                    retryable.forEach { photo -> retry(photo) { ok ->
                        if (alive) {
                            failed = failed || !ok
                            if (--remaining == 0) {
                                busy = false
                                mode.subtitle = activity.getString(if (failed) R.string.photos_retry_failed else R.string.photos_trying_again)
                                mode.invalidate()
                            }
                        }
                    } }
                }
                3 -> share(items, mode)
                else -> return false
            }
            return true
        }
        override fun onDestroyActionMode(mode: ActionMode) {
            this@NativePhotoSelection.mode = null
            shareSignal?.cancel(); shareWork?.cancel(); busy = false
            if (!suspended) tracker.clearSelection()
        }
    }
    private fun share(items: List<HistoryItem>, mode: ActionMode) {
        busy = true; mode.invalidate()
        val signal = CancellationSignal().also { shareSignal = it }
        shareWork = activity.lifecycleScope.launch {
            val copies = withContext(Dispatchers.IO) {
                items.map { photo -> runCatching { photoShareCopy(activity, photo, signal) }.getOrNull() }
            }
            if (!alive || signal.isCanceled) return@launch
            busy = false; mode.invalidate()
            if (copies.any { it == null }) {
                mode.subtitle = activity.getString(R.string.photos_share_unavailable)
                return@launch
            }
            val available = copies.filterNotNull()
            val uris = ArrayList(available.map { it.uri })
            val mime = available.map { it.mime }.distinct().singleOrNull() ?: "*/*"
            val intent = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
                type = mime
                if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris.single()) else putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                clipData = ClipData.newUri(activity.contentResolver, activity.getString(R.string.nav_photos), uris.first()).apply {
                    uris.drop(1).forEach { addItem(ClipData.Item(it)) }
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            runCatching { activity.startActivity(Intent.createChooser(intent, activity.getString(R.string.photos_share))) }
                .onFailure { mode.subtitle = activity.getString(R.string.photos_share_unavailable) }
        }
    }
}

/** Native D1 tile decoration; selection never resizes the grid or reloads its image. */
internal class NativePhotoSelectionMark(private val image: android.widget.ImageView) : android.widget.ImageView(image.context) {
    private val inset = context.token(R.dimen.duck_space_xx_small)
    private val circle = android.graphics.drawable.GradientDrawable().apply {
        shape = android.graphics.drawable.GradientDrawable.OVAL
    }
    init {
        tag = "photo-selection"
        isClickable = false; isFocusable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        visibility = View.GONE
        background = circle
        setPadding(inset, inset, inset, inset)
        image.outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(view: View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, view.width, view.height,
                    context.token(R.dimen.duck_radius_control).toFloat())
            }
        }
    }
    fun bind(selected: Boolean, selecting: Boolean) {
        visibility = if (selecting) View.VISIBLE else View.GONE
        circle.setColor(context.getColor(if (selected) R.color.duck_role_accent else R.color.duck_role_background))
        circle.setStroke(if (selected) 0 else inset / 2, context.getColor(R.color.duck_role_secondary_text))
        setImageResource(if (selected) R.drawable.ic_check else 0)
        imageTintList = android.content.res.ColorStateList.valueOf(context.getColor(R.color.duck_m3_on_primary))
        val margin = if (selected) inset else 0
        val params = image.layoutParams as android.widget.FrameLayout.LayoutParams
        if (params.leftMargin != margin) {
            params.setMargins(margin, margin, margin, margin)
            image.layoutParams = params
        }
        image.clipToOutline = selected
        image.invalidateOutline()
    }
}
