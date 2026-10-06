package app.backupduck

import android.os.SystemClock
import android.text.format.Formatter
import android.view.View
import android.widget.*
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import org.json.JSONObject

/** The prototype's storage summary, with real accounting and secondary controls in a sheet. */
internal class StoragePage(private val activity:MainActivity,private val receiverRoot:String,private val export:()->Unit,private val totals:(JSONObject)->Unit) {
    private val device=activity.duckText(activity.getString(R.string.duck_local_storage,activity.receiverDeviceName),13,true)
    private val heading=activity.duckText(activity.getString(R.string.duck_storage_intro),18,bold=true)
    private val free=activity.duckText("—",32,bold=true).apply {fontFeatureSettings="tnum"}
    private val capacity=activity.duckText("",13,true)
    private val originals=activity.duckText(activity.getString(R.string.duck_originals)+" —",12,true)
    private val copies=activity.duckText(activity.getString(R.string.duck_working)+" —",12,true)
    private val other=activity.duckText(activity.getString(R.string.duck_other)+" —",12,true)
    private val budget=activity.duckText("—",13,true)
    private val keep=activity.duckPill("",R.color.duck_saved,R.color.duck_saved_background)
    private val failures=activity.duckPill("—",R.color.duck_attention,R.color.duck_attention_background)
    private val pendingNote=activity.duckText("",13,true)
    private val bar=StorageBar(activity)
    private var config:JSONObject?=null
    private var originalBytes:Long?=null;private var partialBytes:Long?=null;private var gallery:GalleryUsage?=null
    private var settings:JSONObject?=null
    private var work:Job?=null;private var lastRefresh=0L;private var pendingDetails=false
    val view:View=with(activity) {scrollPage {panel ->
        panel.setPadding(dp(16),dp(16),dp(16),dp(24))
        panel.addView(heading)
        panel.addView(device,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8);bottomMargin=dp(24)})
        val summary=duckGroup(panel)
        summary.setPadding(dp(20),dp(20),dp(20),dp(20))
        summary.background=android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TL_BR,intArrayOf(getColor(R.color.duck_action_background),getColor(R.color.duck_surface),getColor(R.color.duck_surface)))
        summary.addView(duckText(getString(R.string.duck_free),18,bold=true))
        val amount=LinearLayout(activity).apply {gravity=android.view.Gravity.BOTTOM}
        amount.addView(free);amount.addView(capacity,LinearLayout.LayoutParams(-2,-2).apply {marginStart=dp(6);bottomMargin=dp(5)})
        summary.addView(amount,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(24);bottomMargin=dp(24)})
        summary.addView(bar,LinearLayout.LayoutParams(-1,dp(8)))
        summary.addView(originals,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(12)})
        summary.addView(copies,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8)})
        summary.addView(other,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8)})
        val retention=duckGroup(panel,getString(R.string.duck_retention))
        duckSetting(retention,getString(R.string.duck_keep),getString(R.string.duck_keep_note),keep) {showRetention()}
        duckSetting(retention,getString(R.string.duck_limit),getString(R.string.duck_limit_note),budget) {showStorageControls(StorageSection.LIMITS) {refresh(force=true)}}
        val row=duckSetting(retention,getString(R.string.duck_pending),null,failures) {openTransfers(failed=true)}
        val words=row.parent as LinearLayout
        words.addView(pendingNote,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(5)})
        duckWarning(panel,getString(R.string.duck_cleanup_title),getString(R.string.duck_cleanup_note))
        panel.addView(duckButton(getString(R.string.duck_storage_detail),action=::showDetails),LinearLayout.LayoutParams(-1,dp(48)))
    }}
    internal fun showRetention() {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_retention))
        val controls=RetentionControls(activity,sheet.body,changed={refresh(force=true)},owner=sheet);controls.render(config?.optBoolean("receiver_relay",false) ?: false)
        sheet.show()
    }
    private fun showDetails() {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_storage_detail));sheet.show()
        var task:Job?=null
        fun load() {
            sheet.body.removeAllViews();activity.duckNotice(sheet.body,activity.getString(R.string.history_loading))
            task=activity.lifecycleScope.launch {
                val usage=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_storage_usage").put("root",receiverRoot)) as JSONObject}}
                val configuration=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",receiverRoot)) as JSONObject}}
                val inventory=withContext(Dispatchers.IO) {runCatching {GalleryInventory.read(activity)}}
                if(!sheet.isShowing)return@launch
                sheet.body.removeAllViews()
                if(usage.isFailure||configuration.isFailure) {
                    activity.duckProblem(sheet.body,activity.getString(R.string.storage_unavailable))
                    sheet.body.addView(activity.duckButton(activity.getString(R.string.duck_retry)) {load()});return@launch
                }
                val group=activity.duckGroup(sheet.body)
                activity.duckSetting(group,activity.getString(R.string.storage_originals_title),size(usage.getOrThrow().getLong("ready_bytes")),activity.duckText("",13))
                activity.duckSetting(group,activity.getString(R.string.storage_partial,size(usage.getOrThrow().getLong("partial_bytes"))),control=activity.duckText("",13))
                inventory.onSuccess {value ->
                    activity.duckSetting(group,activity.getString(R.string.storage_gallery_title),activity.getString(R.string.storage_gallery_amount,size(value.readyBytes),value.readyCount),activity.duckText("",13))
                    activity.duckSetting(group,activity.getString(R.string.storage_gallery_pending,size(value.pendingBytes),value.pendingCount),control=activity.duckText("",13))
                }.onFailure {activity.duckProblem(sheet.body,activity.getString(R.string.storage_unavailable))}
                val config=configuration.getOrThrow().getJSONObject("settings")
                activity.duckSetting(group,activity.getString(R.string.storage_limits),size(config.getLong("receiver_budget_bytes"))) {sheet.dismiss();activity.showStorageControls(StorageSection.LIMITS) {refresh(force=true)}}
                activity.duckSetting(group,activity.getString(R.string.relay_check_history)) {sheet.dismiss();activity.checkHistoricalOriginals {refresh(force=true)}}
                activity.duckSetting(group,activity.getString(R.string.originals_export),activity.getString(R.string.originals_export_note)) {sheet.dismiss();export()}
                activity.duckSetting(group,activity.getString(R.string.receiver_open_photos)) {activity.openPhotos()}
                RelayMaintenance.status.value?.let {activity.duckNotice(sheet.body,activity.getString(it))}
                activity.duckNotice(sheet.body,activity.getString(R.string.storage_snapshot_note))
            }
        }
        sheet.setOnDismissListener {task?.cancel()};load()
    }
    fun refresh(force:Boolean=false,includeDetails:Boolean=true) {
        if(work?.isActive==true) {if(force&&includeDetails) pendingDetails=true;return}
        if(!force&&SystemClock.elapsedRealtime()-lastRefresh<10_000) return
        lastRefresh=SystemClock.elapsedRealtime()
        device.text=activity.getString(R.string.duck_local_storage,activity.receiverDeviceName)
        work=activity.lifecycleScope.launch {
            val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",receiverRoot)) as JSONObject}}
            result.onSuccess {data ->
                settings=data;totals(data.getJSONObject("counts"));config=data.getJSONObject("settings")
                heading.setText(if(data.getLong("free_bytes")<=config!!.getLong("min_free_bytes")) R.string.duck_low_storage else R.string.duck_storage_intro)
                free.text=size(data.getLong("free_bytes"));capacity.text="/ "+size(android.os.StatFs(activity.filesDir.path).totalBytes)
                budget.text=size(config!!.getLong("receiver_budget_bytes"))
                keep.text=activity.getString(if(config!!.optBoolean("receiver_relay",false)) R.string.duck_relay_keep else R.string.duck_safe_keep)
                val failed=data.getJSONObject("counts").optInt("failed");failures.text=activity.getString(R.string.duck_items,failed);pendingNote.text=activity.getString(R.string.duck_pending_note,failed)
            }.onFailure {free.setText(R.string.storage_unavailable);capacity.text="";budget.text="—";failures.text="—";pendingNote.text=""}
            if(includeDetails) {
                val usage=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_storage_usage").put("root",receiverRoot)) as JSONObject}}
                usage.onSuccess {data ->originalBytes=data.getLong("ready_bytes");partialBytes=data.getLong("partial_bytes")}.onFailure {originalBytes=null;partialBytes=null}
                gallery=withContext(Dispatchers.IO) {runCatching {GalleryInventory.read(activity)}.getOrNull()}
                val original=originalBytes;val partial=partialBytes;val inventory=gallery
                originals.text="● "+activity.getString(R.string.duck_originals)+" "+(original?.let(::size) ?: "—");originals.setTextColor(activity.getColor(R.color.duck_action))
                val delivery=if(inventory!=null&&partial!=null)inventory.readyBytes+inventory.pendingBytes+partial else null
                copies.text="● "+activity.getString(R.string.duck_working)+" "+(delivery?.let(::size) ?: "—");copies.setTextColor(activity.getColor(R.color.duck_text_secondary))
                if(original!=null&&delivery!=null) {
                    val stat=android.os.StatFs(activity.filesDir.path)
                    val otherBytes=(stat.totalBytes-stat.availableBytes-original-delivery).coerceAtLeast(0)
                    other.text="● "+activity.getString(R.string.duck_other)+" "+size(otherBytes)
                    bar.render(original,delivery,otherBytes,stat.totalBytes)
                } else {other.text="● "+activity.getString(R.string.duck_other)+" —";bar.render(0,0,0,1)}
            }
        }
        work?.invokeOnCompletion {if(pendingDetails&&activity.lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) {pendingDetails=false;activity.lifecycleScope.launch {refresh(force=true)}}}
    }
    private fun size(bytes:Long)=Formatter.formatShortFileSize(activity,bytes)
}
private class StorageBar(context:android.content.Context):View(context) {
    private val paint=android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    private var amounts=doubleArrayOf(0.0,0.0,0.0)
    fun render(original:Long,copies:Long,other:Long,total:Long) {amounts=doubleArrayOf(original.toDouble(),copies.toDouble(),other.toDouble()).map {it/total.coerceAtLeast(1)}.toDoubleArray();invalidate()}
    override fun onDraw(canvas:android.graphics.Canvas) {
        val rect=android.graphics.RectF(0f,0f,width.toFloat(),height.toFloat());val path=android.graphics.Path().apply {addRoundRect(rect,height/2f,height/2f,android.graphics.Path.Direction.CW)}
        canvas.save();canvas.clipPath(path);paint.color=context.getColor(R.color.duck_border);canvas.drawRect(rect,paint)
        var x=0f;val colors=listOf(R.color.duck_action,R.color.duck_brand_accent,R.color.duck_text_secondary)
        amounts.forEachIndexed {i,amount ->paint.color=context.getColor(colors[i]);val end=(x+width*amount).toFloat().coerceAtMost(width.toFloat());canvas.drawRect(x,0f,end,height.toFloat(),paint);x=end};canvas.restore()
    }
}
