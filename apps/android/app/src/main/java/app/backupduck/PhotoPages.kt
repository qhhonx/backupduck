package app.backupduck

import android.content.Context
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs

/** At animation scale zero a horizontal choice adopts the next page immediately. */
internal class PhotoPager(context: Context) : RecyclerView(context) {
    var jump: (Int) -> Unit = {}
    private var startX = 0f
    private var startY = 0f
    private val slop = android.view.ViewConfiguration.get(context).scaledTouchSlop
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (context.photoAnimationsEnabled()) return super.onInterceptTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { startX = event.x; startY = event.y }
            MotionEvent.ACTION_MOVE -> if (abs(event.x-startX) > slop && abs(event.x-startX) > abs(event.y-startY)) return true
        }
        return false
    }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (context.photoAnimationsEnabled()) return super.onTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP && abs(event.x-startX) > slop) {
            jump(if (event.x < startX) 1 else -1)
        }
        return true
    }
}

/** A snapshot of the originating view's order, virtualized by the native pager. */
internal class PhotoPages(private val items: List<HistoryItem>,
    private val make: (HistoryItem, Int, () -> Boolean) -> PhotoDetail.Content) : RecyclerView.Adapter<PhotoPages.Page>() {
    private val mounted = mutableMapOf<Int, Page>()
    private val ids = items.map { it.id }.withIndex().associate { it.value to it.index.toLong() }
    init { setHasStableIds(true) }
    // Collision-free identities are assigned to media IDs for this immutable collection.
    override fun getItemId(position: Int) = ids.getValue(items[position].id)
    override fun getItemCount() = items.size
    class Page(val host: FrameLayout) : RecyclerView.ViewHolder(host) {
        var content: PhotoDetail.Content? = null
        var bound = -1
        var generation = 0
        fun clear() { generation++; content?.cancel?.invoke(); content = null; host.removeAllViews() }
    }
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Page(FrameLayout(parent.context).apply {
        layoutParams = RecyclerView.LayoutParams(-1, -1); isTransitionGroup = false
    })
    override fun onBindViewHolder(holder: Page, position: Int) {
        mounted.remove(holder.bound)
        holder.clear(); holder.bound = position
        val generation = holder.generation
        holder.content = make(items[position], position) { holder.generation == generation }
        holder.host.addView(holder.content!!.root, FrameLayout.LayoutParams(-1, -1))
        mounted[position] = holder
    }
    override fun onViewRecycled(holder: Page) {
        mounted.remove(holder.bound); holder.clear(); holder.bound = -1
    }
    fun contentAt(position: Int) = mounted[position]?.content
    fun cancelAll() { mounted.values.toList().forEach { it.clear() }; mounted.clear() }
}
