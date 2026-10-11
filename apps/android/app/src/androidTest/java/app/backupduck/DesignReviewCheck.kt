package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.io.File

/** Real native layouts, isolated emulator and synthetic data. Never runs against a user's Pixel. */
internal fun Instrumentation.checkDesignReview(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone")||android.os.Build.FINGERPRINT.contains("generic"))
    val dark=args.getString("dark")=="true"
    targetContext.getSharedPreferences("appearance",0).edit().putInt("mode",if(dark) AppCompatDelegate.MODE_NIGHT_YES else AppCompatDelegate.MODE_NIGHT_NO).commit()
    ReceiverPreferences.setEnabled(targetContext,false);ReceiverPreferences.setPaused(targetContext,false)
    DeviceProfiles.read(targetContext,"Pixel XL")
    if(android.os.Build.VERSION.SDK_INT>=33) targetContext.getSystemService(android.app.LocaleManager::class.java).applicationLocales=android.os.LocaleList.forLanguageTags("zh-CN")
    else runOnMainSync {AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("zh-CN"))}
    uiAutomation.executeShellCommand("input keyevent 224").close()
    uiAutomation.executeShellCommand("wm dismiss-keyguard").close()
    val activity=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup) (0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun shot(name:String,root:View=activity.window.decorView) {
        waitForIdleSync();Thread.sleep(450)
        var image:Bitmap?=uiAutomation.takeScreenshot()
        if(image==null) runOnMainSync {check(root.width>0&&root.height>0);image=Bitmap.createBitmap(root.width,root.height,Bitmap.Config.ARGB_8888);root.draw(android.graphics.Canvas(checkNotNull(image)))}
        File(targetContext.cacheDir,"review-${if(dark) "dark" else "light"}-$name.png").outputStream().use {checkNotNull(image).compress(Bitmap.CompressFormat.PNG,100,it)}
        image?.recycle()
    }
    val items=(0 until 200).map {i -> HistoryItem(i.toLong()+1,"review-$i","Sample_${String.format("%04d",5442-i)}.${if(i%5==2) "MOV" else "HEIC"}",
        if(i%5==2) "video" else if(i%3==0) "motion" else "photo",8500000,if(i in 2..4) 2200000 else 8500000,
        if(i in 2..4) "receiving" else "received",if(i<2) "failed" else if(i<8) "pending" else "complete",if(i<2) "conversion_required" else null,
        false,senderNames="验收示例 iPhone",capturedAtMs=1790917140000-i*60000L,burstPrimary=if(i==3) true else null,receivedAtMs=if(i>4) 1790920000000 else null,publishedAtMs=if(i>=8) 1790920300000 else null)}
    try {
        Thread.sleep(800);shot("receive")
        val active=ReceiverSnapshot(phase="ready",total=200,published=192,failed=2,recent=listOf(RecentTransfer("fixture","Sample.MOV","video",8500000,2200000,"receiving","pending")))
        runOnMainSync {ReceiverPreferences.setEnabled(targetContext,true);ReceiverState.mutable.value=active;activity.receiverHome.history(HistoryState(items=items.drop(2),total=200));activity.receiverHome.render(active,"Pixel XL",false)}
        shot("receive-active")
        val nav=views(activity.window.decorView).filterIsInstance<BottomNavigationView>().single()
        runOnMainSync {nav.selectedItemId=2};waitForIdleSync()
        val page=views(activity.window.decorView).filterIsInstance<HistoryPage>().single()
        val list=views(page).filterIsInstance<RecyclerView>().single()
        val adapter=list.adapter as TransferAdapter
        // Synthetic thumbnail pixels are supplied through the same bounded cache used by gallery rows.
        runOnMainSync {
            (0..12).forEach {i ->
                val bitmap=Bitmap.createBitmap(84,84,Bitmap.Config.ARGB_8888)
                val canvas=android.graphics.Canvas(bitmap);canvas.drawColor(android.graphics.Color.rgb(70+i*9,120+i*5,165-i*5))
                val paint=android.graphics.Paint().apply {color=android.graphics.Color.rgb(210-i*8,190-i*5,110+i*6)}
                canvas.drawCircle(60f,22f,13f,paint);canvas.drawRect(0f,57f,84f,84f,paint)
                adapter.cacheThumbnail(items[i].id,bitmap)
            }
            page.totals(200,192);page.render(HistoryState(items=items,total=200))
        }
        waitForIdleSync();shot("transfers")
        var baseline=0
        runOnMainSync {baseline=list.height}
        for((label,snapshot) in listOf(
            "active" to ReceiverSnapshot(phase="ready",total=200,published=192,failed=2,recent=listOf(RecentTransfer("fixture","Sample.MOV","video",8500000,2200000,"receiving","pending"))),
            "thermal" to ReceiverSnapshot(phase="ready",thermalHeld=true,temperatureDeciCelsius=430,total=200,published=192,failed=2),
            "failed" to ReceiverSnapshot(phase="ready",total=200,published=192,failed=2),
            "done" to ReceiverSnapshot(phase="ready",total=200,published=200),
            "offline" to ReceiverSnapshot(phase="waiting",error="wifi_required",total=200,published=192))) {
            runOnMainSync {ReceiverPreferences.setEnabled(targetContext,label!="offline");ReceiverState.mutable.value=snapshot;page.renderActivity(snapshot)}
            waitForIdleSync();Thread.sleep(350)
            runOnMainSync {check(list.height==baseline) {"Activity strip resized for $label: ${list.height} vs $baseline"}}
        }
        var sheet:DuckSheet?=null
        runOnMainSync {sheet=adapter.showDetails(items[0],null)};waitForIdleSync();shot("detail",checkNotNull(sheet).body.rootView)
        runOnMainSync {sheet?.dismiss()};Thread.sleep(250)
        runOnMainSync {list.scrollToPosition(190)};waitForIdleSync();Thread.sleep(200)
        check(list.childCount<20) {"RecyclerView failed to virtualize 200 rows"}
        runOnMainSync {nav.selectedItemId=3};Thread.sleep(1800);shot("storage")
        runOnMainSync {nav.selectedItemId=4};shot("settings")
        return "PASS: 4 native pages + bottom sheet; 200-row virtualization; activity height stable across active/thermal/failure/done/offline; ${activity.resources.configuration.screenWidthDp}dp, ${if(dark) "dark" else "light"}"
    } finally {
        runOnMainSync {ReceiverPreferences.setEnabled(targetContext,false);ReceiverPreferences.setPaused(targetContext,false);ReceiverState.mutable.value=ReceiverSnapshot();activity.finish()}
    }
}
