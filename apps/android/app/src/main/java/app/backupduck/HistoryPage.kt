package app.backupduck

import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.CancellationSignal
import android.provider.MediaStore
import android.text.TextUtils
import android.text.format.Formatter
import android.util.LruCache
import android.util.Size
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

internal class HistoryPage(private val activity: MainActivity, private val model: HistoryModel, private val root: String) : LinearLayout(activity) {
    private val count: TextView
    private val countHeader:View
    private val filterHeader:View
    private val message: TextView
    private val emptyNote:TextView
    private val readFailure:LinearLayout
    private val emptyBox: LinearLayout
    private val emptyArt:View
    private val emptyScroll:ScrollView
    private val emptyAction: com.google.android.material.button.MaterialButton
    private val list: RecyclerView
    private val adapter=TransferAdapter(activity)
    private val layout=LinearLayoutManager(activity)
    private val chips=linkedMapOf<String,com.google.android.material.chip.Chip>()
    private var allCount=0; private var savedCount=0
    init {
        orientation=VERTICAL;setBackgroundColor(activity.getColor(R.color.duck_surface))
        val accessibleHeading=activity.resources.configuration.fontScale>1.3f
        val heading=LinearLayout(activity).apply {orientation=if(accessibleHeading)VERTICAL else HORIZONTAL;gravity=android.view.Gravity.CENTER_VERTICAL;minimumHeight=activity.dp(56);setPadding(activity.dp(16),if(accessibleHeading)activity.dp(8) else 0,activity.dp(16),if(accessibleHeading)activity.dp(8) else 0) }
        count=activity.duckText("",13,true);heading.addView(count,if(accessibleHeading)LayoutParams(-1,-2) else LayoutParams(0,-2,1f))
        heading.addView(activity.duckLink(activity.getString(R.string.duck_status_guide_link),::showStatusGuide).apply {contentDescription=activity.getString(R.string.duck_status_guide)},LayoutParams(-2,-2).apply {if(accessibleHeading)gravity=android.view.Gravity.END})
        countHeader=heading;addView(heading,LayoutParams(-1,if(accessibleHeading)-2 else activity.dp(56)))
        val filters=com.google.android.material.chip.ChipGroup(activity).apply { isSingleLine=true;isSingleSelection=true;isSelectionRequired=true;chipSpacingHorizontal=activity.dp(6);setPadding(activity.dp(12),0,activity.dp(12),activity.dp(8)) }
        listOf("all" to R.string.duck_all,"active" to R.string.duck_active,"failed" to R.string.duck_failed_chip,"published" to R.string.duck_saved_chip).forEach { (key,label) ->
            val chip=com.google.android.material.chip.Chip(activity).apply {
                id=View.generateViewId();setText(label);textSize=12f;isCheckable=true;isChecked=key==model.state.value.filter
                isCheckedIconVisible=false;chipMinHeight=activity.dp(30).toFloat();chipStartPadding=activity.dp(8).toFloat();chipEndPadding=activity.dp(8).toFloat();textStartPadding=0f;textEndPadding=0f
                chipCornerRadius=activity.dp(18).toFloat();ensureAccessibleTouchTarget(activity.dp(48))
                chipBackgroundColor=android.content.res.ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked),intArrayOf()),intArrayOf(activity.getColor(R.color.duck_action_background),activity.getColor(R.color.duck_surface)))
                chipStrokeColor=android.content.res.ColorStateList.valueOf(activity.getColor(R.color.duck_border));chipStrokeWidth=activity.dp(1).toFloat()
                setTextColor(android.content.res.ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked),intArrayOf()),intArrayOf(activity.getColor(R.color.duck_action),activity.getColor(R.color.duck_text_secondary))))
                setOnClickListener { if(key!=model.state.value.filter) activity.lifecycleScope.launch { model.select(root,filter=key) } }
            };chips[key]=chip;filters.addView(chip)
        }
        filterHeader=HorizontalScrollView(activity).apply {isHorizontalScrollBarEnabled=false;addView(filters)};addView(filterHeader,LayoutParams(-1,-2))
        readFailure=LinearLayout(activity).apply {orientation=VERTICAL;setPadding(activity.dp(16),0,activity.dp(16),0);visibility=View.GONE}
        activity.duckProblem(readFailure,activity.getString(R.string.duck_history_load_failed))
        readFailure.addView(activity.duckButton(activity.getString(R.string.duck_retry)) {activity.lifecycleScope.launch {model.refreshVisible(root,firstVisible())}})
        addView(readFailure,LayoutParams(-1,-2))
        val content=FrameLayout(activity);addView(content,LayoutParams(-1,0,1f))
        list=RecyclerView(activity).apply {
            id=R.id.receiver_history_list;layoutManager=layout;adapter=this@HistoryPage.adapter;itemAnimator=null
            setPadding(activity.dp(16),0,activity.dp(16),0);clipToPadding=false
            addOnScrollListener(object:RecyclerView.OnScrollListener() { override fun onScrolled(recyclerView:RecyclerView,dx:Int,dy:Int) {
                if(dy>0&&layout.findLastVisibleItemPosition()>=this@HistoryPage.adapter.itemCount-8) activity.lifecycleScope.launch { model.more(root) }
            } })
        };content.addView(list,FrameLayout.LayoutParams(-1,-1))
        emptyBox=LinearLayout(activity).apply {orientation=VERTICAL;gravity=android.view.Gravity.CENTER;setPadding(activity.dp(24),activity.dp(24),activity.dp(24),activity.dp(24))}
        emptyArt=ImageView(activity).apply {setImageResource(R.mipmap.ic_launcher);background=activity.duckBackground(R.color.duck_brand_accent,24,false);setPadding(activity.dp(10),activity.dp(10),activity.dp(10),activity.dp(10))}
        emptyBox.addView(emptyArt,LayoutParams(activity.dp(88),activity.dp(88)))
        message=activity.duckText("",22,bold=true).apply {gravity=android.view.Gravity.CENTER;setPadding(0,activity.dp(16),0,activity.dp(12))}
        emptyBox.addView(message)
        emptyNote=activity.duckParagraph(activity.getString(R.string.duck_history_empty_note)).apply {gravity=android.view.Gravity.CENTER}
        emptyBox.addView(emptyNote,LayoutParams(-1,-2).apply {bottomMargin=activity.dp(24)})
        emptyAction=activity.duckButton(activity.getString(R.string.design_connect_device),true,activity::openConnection)
        emptyBox.addView(emptyAction,LayoutParams(-1,-2))
        emptyScroll=ScrollView(activity).apply {isFillViewport=true;addView(emptyBox,LayoutParams(-1,-2))}
        content.addView(emptyScroll,FrameLayout.LayoutParams(-1,-1))

    }
    fun totals(total:Int,saved:Int) {allCount=total;savedCount=saved;count.text=activity.getString(R.string.duck_count,total,saved)}
    fun firstVisible()=layout.findFirstVisibleItemPosition().coerceAtLeast(0)
    fun progress(values:Map<String,ReceiverByteProgress>) {adapter.progress(list,values)}
    fun render(state:HistoryState) {
        state.counts?.let {totals(it.total,it.published)}
        val first=layout.findFirstVisibleItemPosition();val anchor=adapter.currentList.getOrNull(first)?.id;val top=layout.findViewByPosition(first)?.top ?: 0
        adapter.submitList(state.items) { if(first>0&&anchor!=null) { val index=adapter.currentList.indexOfFirst {it.id==anchor};if(index>=0&&!list.isComputingLayout&&list.scrollState==RecyclerView.SCROLL_STATE_IDLE) layout.scrollToPositionWithOffset(index,top) } }
        count.text=activity.getString(R.string.duck_count,if(allCount>0) allCount else state.total,savedCount)
        chips.forEach { (key,chip) -> chip.isChecked=key==state.filter }
        emptyBox.visibility=if(state.items.isEmpty()) View.VISIBLE else View.GONE
        emptyScroll.visibility=emptyBox.visibility
        countHeader.visibility=View.VISIBLE;filterHeader.visibility=View.VISIBLE
        readFailure.visibility=if(state.failed&&state.items.isNotEmpty())View.VISIBLE else View.GONE
        val filtered=state.filter!="all"||state.kind!="all"||state.sender!=null
        emptyArt.visibility=if(filtered)View.GONE else View.VISIBLE
        emptyNote.visibility=if(state.loading||state.failed||filtered)View.GONE else View.VISIBLE
        emptyNote.setText(if(state.filter=="all"&&state.kind=="all"&&state.sender==null)R.string.duck_history_empty_note else R.string.history_empty)
        emptyAction.visibility=if(!state.loading) View.VISIBLE else View.GONE
        emptyAction.setText(if(state.failed)R.string.duck_retry else if(filtered)R.string.receiver_refinement_clear_filters else R.string.design_connect_device)
        emptyAction.visibility=if(state.loading||(!state.failed&&!filtered&&(state.total>0||activity.hasKnownSenders!=false)))View.GONE else View.VISIBLE
        emptyAction.setOnClickListener {
            if(state.failed)activity.lifecycleScope.launch {model.refreshVisible(root,firstVisible())}
            else if(filtered)activity.lifecycleScope.launch {model.select(root,filter="all",kind="all",sender=null)}
            else activity.openConnection()
        }
        message.setText(when {state.loading -> R.string.history_loading;state.failed -> R.string.duck_history_load_failed;filtered -> R.string.receiver_refinement_filtered_empty;else -> R.string.duck_history_empty})
    }
    // This page already shows tasks. Status/control belongs on the receiving
    // home page; do not duplicate a no-op "view tasks" strip below this list.
    fun renderActivity(state:ReceiverSnapshot) {
        if(state.phase=="ready") totals(state.total,state.published)
    }
    fun showStatusGuide() {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_status_guide));val group=activity.duckGroup(sheet.body)
        listOf(R.string.duck_receiving to R.string.receiver_item_receiving,R.string.duck_waiting_short to R.string.receiver_item_received,R.string.duck_saved to R.string.receiver_item_published,R.string.duck_failed to R.string.receiver_item_failed).forEach { (title,note) -> activity.duckSetting(group,activity.getString(title),activity.getString(note),activity.duckText("",13),leadingIcon=when(title) {R.string.duck_receiving->R.drawable.ic_transfers;R.string.duck_waiting_short->R.drawable.ic_clock;R.string.duck_saved->R.drawable.ic_check;else->R.drawable.ic_alert}) }
        activity.duckNotice(sheet.body,activity.getString(R.string.duck_cloud_title),activity.getString(R.string.duck_cloud_unknown));sheet.show()
    }
    fun showFilters() {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_advanced_filters))
        val group=activity.duckGroup(sheet.body)
        activity.duckSetting(group,activity.getString(R.string.duck_type),activity.getString(R.string.duck_type),activity.duckText(activity.getString(when(model.state.value.kind) {"photo"->R.string.filter_photo;"video"->R.string.filter_video;"motion"->R.string.filter_motion;"burst"->R.string.filter_burst;else->R.string.filter_all}),13,true)) {sheet.dismiss();showKinds()}
        activity.duckSetting(group,activity.getString(R.string.history_sender),action={sheet.dismiss();showSenders()})
        sheet.body.addView(activity.duckButton(activity.getString(R.string.storage_refresh)) {sheet.dismiss();activity.lifecycleScope.launch {model.refreshVisible(root,firstVisible());if(!model.state.value.failed)activity.duckAcknowledge(activity.getString(R.string.duck_history_refreshed))}},LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(16)})
        val failure=activity.duckFailure(sheet.body,activity.getString(R.string.settings_start_first))
        lateinit var retry:com.google.android.material.button.MaterialButton
        retry=activity.duckButton(activity.getString(R.string.receiver_retry_processing)) {
            retry.isEnabled=false;failure.visibility=View.GONE
            activity.lifecycleScope.launch {
                val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","retry_processing"))}}
                retry.isEnabled=true
                result.onSuccess {activity.duckAcknowledge(activity.getString(R.string.design_retry_requested),sheet.body)}.onFailure {failure.visibility=View.VISIBLE}
            }
        };sheet.body.addView(retry,LinearLayout.LayoutParams(-1,-2));sheet.show()
    }
    private fun showKinds() {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_type));val group=activity.duckGroup(sheet.body)
        listOf("all" to R.string.filter_all,"photo" to R.string.filter_photo,"motion" to R.string.filter_motion,"video" to R.string.filter_video,"burst" to R.string.filter_burst).forEach {(key,label)->
            val selected=if(key==model.state.value.kind) activity.duckPill(activity.getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background) else activity.duckText("",13)
            activity.duckSetting(group,activity.getString(label),control=selected) {sheet.dismiss();activity.lifecycleScope.launch {model.select(root,kind=key)}}
        };sheet.show()
    }
    private fun showSenders() {
        val sheet=DuckSheet(activity,activity.getString(R.string.history_sender));sheet.show()
        fun load() {
            sheet.body.removeAllViews();activity.duckNotice(sheet.body,activity.getString(R.string.device_loading))
            activity.lifecycleScope.launch {
                val result=withContext(Dispatchers.IO) {runCatching {DeviceProfiles.read(activity).getJSONArray("peers")}}
                if(!sheet.isShowing)return@launch
                sheet.body.removeAllViews()
                result.onFailure {activity.duckProblem(sheet.body,activity.getString(R.string.device_load_failed));sheet.body.addView(activity.duckButton(activity.getString(R.string.duck_retry)) {load()})}
                result.onSuccess {peers ->
                    if(peers.length()==0)activity.duckNotice(sheet.body,activity.getString(R.string.device_no_senders))
                    val group=activity.duckGroup(sheet.body)
                    val senders=mutableListOf<String?>(null,"unknown");val labels=mutableListOf(activity.getString(R.string.history_sender_all),activity.getString(R.string.history_sender_unknown))
                    for(i in 0 until peers.length()) {val profile=peers.getJSONObject(i).getJSONObject("profile");senders+=profile.getString("id");labels+=profile.getString("name")}
                    senders.forEachIndexed {i,id->activity.duckSetting(group,labels[i],control=if(model.state.value.sender==id)activity.duckPill(activity.getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background) else activity.duckText("",13)) {sheet.dismiss();activity.lifecycleScope.launch {model.select(root,sender=id)}}}
                }
            }
        };load()
    }

}

private data class Thumbnail(val bitmap: Bitmap, val uri: Uri?,val durationMs:Long?=null)
internal class TransferAdapter(private val activity: MainActivity, private val open: ((HistoryItem) -> Unit)? = null) : ListAdapter<HistoryItem, TransferAdapter.Holder>(object : DiffUtil.ItemCallback<HistoryItem>() {
    override fun areItemsTheSame(old: HistoryItem, new: HistoryItem) = old.id == new.id
    override fun areContentsTheSame(old: HistoryItem, new: HistoryItem) = old == new
    override fun getChangePayload(old:HistoryItem,new:HistoryItem):Any? =
        if(old.copy(confirmedBytes=new.confirmedBytes,receipt=new.receipt)==new) "bytes" else null
}) {
    private var liveProgress:Map<String,ReceiverByteProgress> = emptyMap()
    fun progress(list:RecyclerView,values:Map<String,ReceiverByteProgress>) {
        liveProgress=if(values.isEmpty())emptyMap() else LinkedHashMap(liveProgress).apply {
            values.forEach {(id,value)->remove(id);put(id,value)}
            while(size>256)remove(keys.first())
        }
        for(i in 0 until list.childCount) {
            val holder=list.getChildViewHolder(list.getChildAt(i)) as? Holder ?: continue
            val position=holder.bindingAdapterPosition
            if(position!=RecyclerView.NO_POSITION&&position<itemCount) applyProgress(holder,getItem(position))
        }
    }
    private fun liveItem(item:HistoryItem):HistoryItem {
        val live=liveProgress[item.id] ?: return item
        val phase=if(item.processing=="complete") "complete" else live.processing ?: item.processing
        return item.copy(receipt=if(item.receipt=="received"||live.received) "received" else item.receipt,
            confirmedBytes=maxOf(item.confirmedBytes,live.confirmed).coerceAtMost(item.totalBytes),processing=phase,
            processingError=if(phase=="complete")null else if(live.processing!=null)live.error else item.processingError)
    }
    private fun bindStatus(holder:Holder,item:HistoryItem) {
        val key="${item.receipt}|${item.processing}|${item.processingError}"
        if(holder.statusKey==key)return
        holder.statusKey=key
        holder.status.text=activity.getString(when {
            item.processing=="failed" -> R.string.duck_gallery_failed
            item.processing=="complete" -> R.string.duck_saved
            item.receipt=="received" -> R.string.duck_waiting_short
            else -> R.string.duck_receiving
        })
        val color=when {item.processing=="failed" -> R.color.duck_failure;item.processing=="complete" -> R.color.duck_saved;item.receipt=="received" -> R.color.duck_attention;else -> R.color.duck_action}
        val background=when {item.processing=="failed" -> R.color.duck_failure_background;item.processing=="complete" -> R.color.duck_saved_background;item.receipt=="received" -> R.color.duck_attention_background;else -> R.color.duck_action_background}
        holder.status.setTextColor(activity.getColor(color));holder.status.background=activity.duckBackground(background,6,false)
        val symbol=activity.getDrawable(when {item.processing=="failed" -> R.drawable.ic_alert;item.processing=="complete" -> R.drawable.ic_check;item.receipt=="received" -> R.drawable.ic_clock;else -> R.drawable.ic_transfers})?.mutate()
        symbol?.setTint(activity.getColor(color));symbol?.setBounds(0,0,activity.dp(13),activity.dp(13));holder.status.compoundDrawablePadding=activity.dp(4);holder.status.setCompoundDrawables(symbol,null,null,null)
        holder.row.contentDescription=item.filename+", "+holder.sender.text+", "+holder.status.text
    }
    private fun applyProgress(holder:Holder,item:HistoryItem) {
        val live=liveProgress[item.id]
        val received=item.receipt=="received"||live?.received==true
        val total=item.totalBytes.coerceAtLeast(1)
        val confirmed=maxOf(item.confirmedBytes,live?.confirmed ?: 0).coerceAtMost(total)
        bindStatus(holder,liveItem(item))
        holder.progress.visibility=if(received) View.GONE else View.VISIBLE
        holder.progress.progress=(confirmed.toDouble()/total*1000).toInt()
        holder.size.text=if(received) Formatter.formatFileSize(activity,item.totalBytes)
            else "${Formatter.formatFileSize(activity,confirmed)} / ${Formatter.formatFileSize(activity,item.totalBytes)}"
    }
    private val permits = Semaphore(2)
    private val cache = object : LruCache<String, Thumbnail>(12 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Thumbnail) = value.bitmap.allocationByteCount
    }
    private val previewCache=object:LruCache<String,Bitmap>(8*1024*1024) {
        override fun sizeOf(key:String,value:Bitmap)=value.allocationByteCount
    }
    init { stateRestorationPolicy = RecyclerView.Adapter.StateRestorationPolicy.PREVENT_WHEN_EMPTY }
    inner class Holder(val row: LinearLayout, val image: ImageView, val name: TextView, val status: TextView,
        val progress: ProgressBar, val size: TextView, val sender: TextView, outer: FrameLayout) : RecyclerView.ViewHolder(outer) {
        var work: Job? = null
        var signal: CancellationSignal? = null
        var itemID: String? = null
        var statusKey:String?=null
        fun cancel() { signal?.cancel(); work?.cancel(); signal = null; itemID = null;statusKey=null }
    }
    internal fun cacheThumbnail(id:String,bitmap:Bitmap) {cache.put(id,Thumbnail(bitmap,null))}
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val large=activity.resources.configuration.fontScale>1.3f
        val row = LinearLayout(activity).apply {orientation=if(large) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL;gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(0,activity.dp(8),0,activity.dp(8))}
        val line=if(large) LinearLayout(activity).apply {gravity=android.view.Gravity.CENTER_VERTICAL;row.addView(this,LinearLayout.LayoutParams(-1,-2))} else row
        val outer = FrameLayout(activity)
        outer.layoutParams = RecyclerView.LayoutParams(-1, -2)
        outer.addView(row, FrameLayout.LayoutParams(-1, -2))
        row.minimumHeight = activity.dp(64)
        val image = ImageView(activity).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            background=activity.duckBackground(R.color.duck_subtle,6,false);clipToOutline=true
        }
        line.addView(image, LinearLayout.LayoutParams(activity.dp(44), activity.dp(44)).apply { marginEnd = activity.dp(12) })
        val body = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        line.addView(body, LinearLayout.LayoutParams(0, -2, 1f))
        val name = activity.duckText("",16,bold=true).apply { maxLines=1;ellipsize=TextUtils.TruncateAt.END }
        body.addView(name)
        val sender = activity.duckText("",13,true).apply {maxLines=1;ellipsize=TextUtils.TruncateAt.END;setPadding(0,activity.dp(6),0,0)}
        body.addView(sender)
        val status=activity.duckPill("").apply { maxLines=if(activity.resources.configuration.fontScale>1.3f) 2 else 1;ellipsize=TextUtils.TruncateAt.END;maxWidth=if(large) Int.MAX_VALUE else activity.dp(126) }
        row.addView(status,LinearLayout.LayoutParams(-2,-2).apply {marginStart=activity.dp(if(large)56 else 8);if(large)topMargin=activity.dp(8)})
        val size=activity.duckText("",12,true).apply {visibility=View.GONE}
        outer.addView(activity.duckRule(),FrameLayout.LayoutParams(-1,activity.dp(1),android.view.Gravity.BOTTOM))
        val progress = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply { max = 1000 }
        outer.addView(progress, FrameLayout.LayoutParams(-1, activity.dp(2), android.view.Gravity.BOTTOM))
        return Holder(row, image, name, status, progress, size, sender, outer)
    }
    override fun onBindViewHolder(holder: Holder, position: Int) {
        val item = getItem(position)
        holder.cancel(); holder.itemID = item.id
        holder.name.text = item.filename
        val captured = item.capturedAtMs?.let { java.text.SimpleDateFormat("MM/dd HH:mm",java.util.Locale.getDefault()).format(java.util.Date(it)) }
            ?: activity.getString(R.string.design_capture_unknown)
        holder.sender.text = captured + " · " + activity.getString(when { item.burstPrimary != null && item.kind != "motion" -> R.string.filter_burst; item.kind == "motion" -> R.string.filter_motion; item.kind == "video" -> R.string.filter_video; else -> R.string.filter_photo })
        bindStatus(holder,item)
        holder.row.isFocusable=true
        applyProgress(holder,item)
        holder.image.setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
        holder.image.background=activity.duckBackground(R.color.duck_subtle,6,false)
        holder.image.setImageResource(if (item.kind == "video") R.drawable.ic_video else if (item.kind == "motion") R.drawable.ic_motion else R.drawable.ic_photo)
        holder.row.setOnClickListener { open?.invoke(liveItem(item)) ?: showDetails(liveItem(item), null) }
        cache.get(item.id)?.let {thumbnail ->
            holder.image.setPadding(0,0,0,0);holder.image.setImageBitmap(thumbnail.bitmap)
            holder.row.setOnClickListener {open?.invoke(liveItem(item)) ?: showDetails(liveItem(item),thumbnail.uri)}
            thumbnail.durationMs?.let {holder.sender.text=holder.sender.text.toString()+" · "+android.text.format.DateUtils.formatElapsedTime(it/1000)}
            return
        }
        if (item.processing != "complete") return
        val signal = CancellationSignal()
        holder.signal = signal
        holder.work = activity.lifecycleScope.launch {
            val thumbnail = cache.get(item.id) ?: withContext(Dispatchers.IO) {
                permits.withPermit {
                    currentCoroutineContext().ensureActive()
                    runCatching {
                        val copy=GalleryPreview.resolve(activity,item,null,signal) ?: return@withPermit null
                        val pixels=activity.dp(80).coerceIn(160,384)
                        Thumbnail(GalleryPreview.decode(activity,copy,Size(pixels,pixels),signal),copy.uri,copy.durationMs).also {cache.put(item.id,it)}
                    }.getOrNull()
                }
            }
            if (holder.itemID == item.id && thumbnail != null) {
                holder.image.setPadding(0, 0, 0, 0)
                holder.image.setImageBitmap(thumbnail.bitmap)
                holder.row.setOnClickListener { open?.invoke(liveItem(item)) ?: showDetails(item, thumbnail.uri) }
                thumbnail.durationMs?.let {holder.sender.text=holder.sender.text.toString()+" · "+android.text.format.DateUtils.formatElapsedTime(it/1000)}
            }
        }
    }
    override fun onBindViewHolder(holder:Holder,position:Int,payloads:MutableList<Any>) {
        if(payloads.isNotEmpty()&&payloads.all {it=="bytes"}) {
            applyProgress(holder,getItem(position))
        } else onBindViewHolder(holder,position)
    }
    internal fun showDetails(item:HistoryItem,gallery:Uri?):DuckSheet {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_detail))
        val preview=ImageView(activity).apply {
            scaleType=ImageView.ScaleType.CENTER_CROP;background=activity.duckBackground(R.color.duck_subtle,10,false);clipToOutline=true
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO;tag="receiver.detail.preview"
        }
        cache.get(item.id)?.bitmap?.let {preview.setImageBitmap(it)} ?: run {
            preview.setImageResource(if(item.kind=="video") R.drawable.ic_video else if(item.kind=="motion") R.drawable.ic_motion else R.drawable.ic_photo)
            preview.scaleType=ImageView.ScaleType.FIT_CENTER;preview.setPadding(activity.dp(56),activity.dp(56),activity.dp(56),activity.dp(56))
        }
        sheet.body.addView(preview,LinearLayout.LayoutParams(-1,activity.dp(170)).apply {bottomMargin=activity.dp(18)})
        val header=LinearLayout(activity).apply {gravity=android.view.Gravity.CENTER_VERTICAL}
        val large=activity.resources.configuration.fontScale>1.3f
        header.orientation=if(large)LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
        header.addView(activity.duckText(item.filename,18,bold=true),if(large)LinearLayout.LayoutParams(-1,-2) else LinearLayout.LayoutParams(0,-2,1f))
        val result=when {item.processing=="failed" -> R.string.duck_gallery_failed;item.processing=="complete" -> R.string.duck_saved;item.receipt=="received" -> R.string.duck_waiting_short;else -> R.string.duck_receiving}
        header.addView(activity.duckPill(activity.getString(result),if(item.processing=="failed") R.color.duck_failure else if(item.processing=="complete") R.color.duck_saved else R.color.duck_action,
            if(item.processing=="failed") R.color.duck_failure_background else if(item.processing=="complete") R.color.duck_saved_background else R.color.duck_action_background),LinearLayout.LayoutParams(-2,-2).apply {if(large)topMargin=activity.dp(8) else marginStart=activity.dp(8)})
        sheet.body.addView(header,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(12)})
        val captured=item.capturedAtMs?.let {java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it))} ?: activity.getString(R.string.design_capture_unknown)
        val kind=activity.getString(when {item.burstPrimary!=null&&item.kind!="motion" -> R.string.filter_burst;item.kind=="motion" -> R.string.filter_motion;item.kind=="video" -> R.string.filter_video;else -> R.string.filter_photo})
        val kindValue=activity.duckDefinition(sheet.body,activity.getString(R.string.duck_type),kind)
        activity.duckDefinition(sheet.body,activity.getString(R.string.duck_capture),captured)
        activity.duckDefinition(sheet.body,activity.getString(R.string.duck_source),item.senderNames.ifBlank {activity.getString(R.string.history_sender_unknown)})
        activity.duckDefinition(sheet.body,activity.getString(R.string.duck_size),Formatter.formatFileSize(activity,item.totalBytes))
        activity.duckDefinition(sheet.body,activity.getString(R.string.duck_original),activity.getString(when {
            item.originalsReleased&&item.releaseReason=="gallery" -> R.string.history_relay_reclaimed
            item.originalsReleased -> R.string.history_archived
            item.receipt=="received" -> R.string.duck_original_retained
            else -> R.string.receiver_item_receiving
        }))
        val stages=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;setPadding(0,activity.dp(20),0,0)}
        sheet.body.addView(stages)
        activity.duckTimeline(stages,activity.getString(if(item.receipt=="received") R.string.duck_received_short else R.string.duck_receiving),
            item.receivedAtMs?.let {java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it))} ?: activity.getString(R.string.duck_time_unknown),item.receipt=="received")
        val reason=item.processingError?.let {activity.getString(when(it) {"conversion_required" -> R.string.receiver_item_conversion_required;"unsupported" -> R.string.receiver_item_failed_unsupported;else -> R.string.receiver_item_failed})+" ("+it+")"}
        activity.duckTimeline(stages,activity.getString(if(item.processing=="complete") R.string.duck_saved else if(item.processing=="failed") R.string.duck_gallery_failed else R.string.duck_gallery_wait),
            item.publishedAtMs?.let {java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it))} ?: reason ?: activity.getString(R.string.duck_time_unknown),item.processing=="complete"||item.processing=="failed",if(item.processing=="failed") R.color.duck_failure else R.color.duck_saved)
        activity.duckTimeline(stages,activity.getString(R.string.duck_cloud_title),activity.getString(R.string.duck_cloud_unknown),false,last=true)
        val previewNotice=activity.duckText("",13,true).apply {visibility=View.GONE;tag="receiver.detail.preview-status"}
        sheet.body.addView(previewNotice,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(12)})
        var resolvedCopy:GalleryPreviewCopy?=null
        val openCopy=activity.duckButton(activity.getString(R.string.design_open_gallery)) {
            resolvedCopy?.let {copy ->runCatching {activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(copy.uri,copy.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))}
                .onFailure {previewNotice.setText(R.string.history_view_unavailable);previewNotice.visibility=View.VISIBLE}}
        }.apply {visibility=View.GONE;tag="receiver.detail.open-copy"}
        val signal=CancellationSignal()
        val previewWork=activity.lifecycleScope.launch {
            val copy=withContext(Dispatchers.IO) {runCatching {GalleryPreview.resolve(activity,item,gallery,signal)}.getOrNull()}
            if(!isActive||!sheet.isShowing)return@launch
            resolvedCopy=copy
            if(copy==null) {
                if(item.processing=="complete") {previewNotice.setText(R.string.receiver_refinement_copy_missing);previewNotice.visibility=View.VISIBLE}
                return@launch
            }
            openCopy.visibility=View.VISIBLE
            copy.durationMs?.let {kindValue.text=kind+" · "+android.text.format.DateUtils.formatElapsedTime(it/1000)}
            val width=(activity.resources.displayMetrics.widthPixels-activity.dp(40)).coerceIn(320,1440)
            val previewKey="${copy.uri}:$width:${activity.dp(170)}"
            val image=previewCache.get(previewKey) ?: withContext(Dispatchers.IO) {runCatching {GalleryPreview.decode(activity,copy,Size(width,activity.dp(170)),signal).also {previewCache.put(previewKey,it)}}.getOrNull()}
            if(!isActive||!sheet.isShowing)return@launch
            if(image!=null) {preview.setPadding(0,0,0,0);preview.scaleType=ImageView.ScaleType.CENTER_CROP;preview.setImageBitmap(image)}
            else {previewNotice.setText(R.string.receiver_refinement_preview_failed);previewNotice.visibility=View.VISIBLE}
        }
        sheet.setOnDismissListener {signal.cancel();previewWork.cancel()}
        if(item.processing=="failed") {
            activity.duckWarning(sheet.body,activity.getString(R.string.duck_gallery_failed),activity.getString(R.string.duck_retry_failed_note))
            val failure=activity.duckFailure(sheet.body,activity.getString(R.string.settings_start_first))
            lateinit var retry:com.google.android.material.button.MaterialButton
            retry=activity.duckButton(activity.getString(R.string.duck_retry_processing),true) {
                retry.isEnabled=false;failure.visibility=View.GONE
                activity.lifecycleScope.launch {
                    val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","retry_processing").put("id",item.id))}}
                    retry.isEnabled=true
                    result.onSuccess {activity.duckAcknowledge(activity.getString(R.string.design_retry_requested),sheet.body)}.onFailure {failure.visibility=View.VISIBLE}
                }
            }
            sheet.body.addView(retry,LinearLayout.LayoutParams(-1,-2))
            sheet.body.addView(activity.duckButton(activity.getString(R.string.duck_conversion)) {
                val child=activity.showConversionSettings()
                child.setOnDismissListener {if(!activity.isFinishing&&!activity.isDestroyed)sheet.show()}
                sheet.hide()
            })
        }
        sheet.body.addView(openCopy,LinearLayout.LayoutParams(-1,activity.dp(48)))
        sheet.show();return sheet
    }
    override fun onViewRecycled(holder: Holder) { holder.cancel(); holder.image.setImageDrawable(null) }
}
