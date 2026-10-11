package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Mutable native-response fixture; never modifies the physical receiver's catalog. */
internal fun Instrumentation.checkHistoryLive(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation")&&android.os.Build.MODEL.contains("sdk_gphone"))
    val prefs=targetContext.getSharedPreferences("appearance",0);val oldMode=prefs.getInt("mode",-1)
    val dark=args.getString("dark")=="true";prefs.edit().putInt("mode",if(dark)2 else 1).commit()
    val enabled=ReceiverPreferences.enabled(targetContext);ReceiverPreferences.setEnabled(targetContext,false)
    val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun <T> main(f:()->T):T {var r:Result<T>?=null;runOnMainSync {r=runCatching(f)};return r!!.getOrThrow()}
    var rows=(1..40).map {i -> JSONObject().put("cursor",i).put("id","generated-$i").put("filename","Generated_$i.jpg")
        .put("kind","photo").put("total_bytes",100).put("confirmed_bytes",100).put("receipt","received")
        .put("processing",if(i>38)"pending" else "complete").put("processing_error",JSONObject.NULL).put("originals_released",false)}
    val model=HistoryModel {query ->
        val matching=rows.filter {query.getString("state")!="active"||it.getString("processing")=="pending"}
        val page=matching.filter {query.isNull("before")||it.getLong("cursor")<query.getLong("before")}.sortedByDescending {it.getLong("cursor")}
        JSONObject().put("items",JSONArray(page)).put("total",matching.size).put("next_cursor",JSONObject.NULL)
            .put("counts",JSONObject().put("total",rows.size).put("published",rows.count {it.getString("processing")=="complete"}).put("failed",0))
    }
    try {
        rows.last().put("receipt","receiving").put("confirmed_bytes",0)
        runBlocking {model.select("synthetic-response")}
        val page=main {HistoryPage(a,model,"synthetic-response").also {a.setContentView(it);it.totals(7,7);it.render(model.state.value)}}
        fun count(total:Int,saved:Int)=main {views(page).filterIsInstance<TextView>().any {it.text.toString()==a.getString(R.string.duck_count,total,saved)}}
        waitForIdleSync();check(count(40,38)) {"Old storage counts override live history counts"}
        val list=main {views(page).filterIsInstance<RecyclerView>().single()}
        val adapter=list.adapter as TransferAdapter
        val holder=main {list.findViewHolderForAdapterPosition(0) as TransferAdapter.Holder}
        val thumbnail=main {holder.work}
        for(confirmed in listOf(25L,50L,75L)) {
            main {page.progress(mapOf("generated-40" to ReceiverByteProgress(confirmed,100,false)))}
            check(main {holder.progress.progress==(confirmed*10).toInt()&&holder.progress.visibility==View.VISIBLE})
            check(main {holder.work===thumbnail}) {"Byte update restarted thumbnail work"}
        }
        main {adapter.notifyItemChanged(0,"bytes")};waitForIdleSync()
        check(main {holder.progress.progress==750}) {"Old history snapshot rewound new byte progress"}
        val byteImage=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir,"history-bytes-${if(dark)"dark" else "light"}.png").outputStream().use {byteImage.compress(Bitmap.CompressFormat.PNG,100,it)};byteImage.recycle()
        main {page.progress(mapOf("generated-40" to ReceiverByteProgress(100,100,true)))}
        check(main {holder.progress.visibility==View.GONE&&holder.status.text.toString()==a.getString(R.string.duck_waiting_short)}) {"Receipt must wait for gallery outcome"}
        main {page.progress(mapOf("generated-40" to ReceiverByteProgress(100,100,true,"complete")))}
        check(main {holder.status.text.toString()==a.getString(R.string.duck_saved)}) {"Gallery event did not update transfer row immediately"}
        main {adapter.notifyItemChanged(0,"bytes")};waitForIdleSync()
        check(main {holder.status.text.toString()==a.getString(R.string.duck_saved)}) {"Old metadata rewound gallery result"}
        main {(list.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(8,0)};waitForIdleSync();Thread.sleep(150)
        val anchor=main {adapter.currentList[page.firstVisible()].id}
        rows=rows.map {JSONObject(it.toString()).put("processing","complete").put("receipt","received")}
        runBlocking {model.refreshVisible("synthetic-response",page.firstVisible())};main {page.render(model.state.value)}
        waitForIdleSync();Thread.sleep(150);check(count(40,40))
        check(main {adapter.currentList[page.firstVisible()].id==anchor}) {"Refresh lost scroll anchor"}
        rows=rows+JSONObject(rows.last().toString()).put("cursor",41).put("id","generated-41").put("filename","Generated_41.jpg").put("processing","pending")
        runBlocking {model.refreshVisible("synthetic-response",0)};main {page.render(model.state.value)}
        waitForIdleSync();Thread.sleep(150);check(count(41,40));check(adapter.currentList.first().id=="generated-41")
        main {ReceiverPreferences.setEnabled(a,true);a.receiverHome.render(ReceiverSnapshot(phase="ready"),"Generated Pixel",false);a.receiverHome.history(model.state.value)}
        waitForIdleSync();Thread.sleep(150)
        val recent=main {views(a.receiverHome.view).filterIsInstance<RecyclerView>().single().adapter as TransferAdapter}
        check(recent.currentList.first().id=="generated-41") {"Homepage recent records did not update"}
        main {
            val phase=mapOf("generated-41" to ReceiverByteProgress(100,100,true,"complete"))
            a.receiverHome.progress(phase);page.progress(phase)
            (a.receiverHome.view.parent as? ViewGroup)?.removeView(a.receiverHome.view)
            a.setContentView(a.receiverHome.view)
        }
        waitForIdleSync();Thread.sleep(200)
        val recentList=main {views(a.receiverHome.view).filterIsInstance<RecyclerView>().single()}
        val recentHolder=main {checkNotNull(recentList.findViewHolderForAdapterPosition(0) as? TransferAdapter.Holder)}
        check(main {recentHolder.status.text.toString()==a.getString(R.string.duck_saved)}) {"Homepage lagged the same item's gallery event"}
        main {a.setContentView(page)};waitForIdleSync()
        runBlocking {model.select("synthetic-response",filter="active")};main {page.render(model.state.value)};waitForIdleSync()
        check(model.state.value.items.size==1&&model.state.value.counts?.total==41)
        rows=rows.map {JSONObject(it.toString()).put("processing","complete")}
        runBlocking {model.refreshVisible("synthetic-response",0)};main {page.render(model.state.value)};waitForIdleSync()
        check(model.state.value.filter=="active"&&model.state.value.items.isEmpty()&&count(41,41))
        runBlocking {model.select("synthetic-response",filter="all")};main {page.render(model.state.value)};waitForIdleSync();Thread.sleep(150)
        check(adapter.currentList.first().processing=="complete")
        val image=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir,"history-live-${if(dark)"dark" else "light"}.png").outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)};image.recycle()
        return "PASS: byte progress updates without thumbnail restart or old-history rewind; receipt waits for gallery; counts replace stale storage values; new rows/homepage/filter/scroll preserved. Synthetic responses only."
    } finally {main {a.finish()};ReceiverPreferences.setEnabled(targetContext,enabled);if(oldMode<0)prefs.edit().remove("mode").commit() else prefs.edit().putInt("mode",oldMode).commit()}
}
