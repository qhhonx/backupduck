package app.backupduck

import android.app.Instrumentation
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.os.CancellationSignal
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.*
import com.google.android.material.bottomnavigation.BottomNavigationView
import kotlinx.coroutines.runBlocking
import java.io.File

/** Real MediaStore photo/video + UI checks, only own synthetic emulator files. */
internal fun Instrumentation.checkReceiverRefinement(args:Bundle):String {
    check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun <T> main(block:()->T):T {var r:Result<T>?=null;runOnMainSync {r=runCatching(block)};return r!!.getOrThrow()}
    fun root()=WindowInspector.getGlobalWindowViews().last {it.isShown&&it.hasWindowFocus()}
    fun awaitReady(test:()->Boolean) {repeat(40) {if(main {runCatching(test).getOrDefault(false)})return;Thread.sleep(100)};check(main {runCatching(test).getOrDefault(false)}){"Expected native state did not appear"}}
    val preferences=targetContext.getSharedPreferences("appearance",0);val oldMode=preferences.getInt("mode",-1)
    preferences.edit().putInt("mode",if(args.getString("dark")=="true")2 else 1).commit()
    val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    val resolver=a.contentResolver;val own=mutableListOf<android.net.Uri>();var sheet:DuckSheet?=null
    val output=File(targetContext.cacheDir,"receiver-refinement").apply {mkdirs()};val suffix="${a.resources.configuration.screenWidthDp}-${args.getString("dark") ?: "false"}"
    fun shot(name:String){waitForIdleSync();Thread.sleep(180);val b=checkNotNull(uiAutomation.takeScreenshot());File(output,"$name-$suffix.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
    try {
        val scanIntent=com.journeyapps.barcodescanner.ScanOptions().setCaptureActivity(ReceiverScanActivity::class.java).setDesiredBarcodeFormats(com.journeyapps.barcodescanner.ScanOptions.QR_CODE).setBeepEnabled(false).setOrientationLocked(true).createScanIntent(a).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val capture=startActivitySync(scanIntent) as ReceiverScanActivity
        main {check(capture.resources.configuration.orientation==android.content.res.Configuration.ORIENTATION_PORTRAIT)}
        shot("scanner-portrait");main {capture.finish()};Thread.sleep(180)
        check(a.packageManager.getActivityInfo(android.content.ComponentName(a,ReceiverScanActivity::class.java),0).screenOrientation==ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)
        main {a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=4}
        waitForIdleSync();shot("settings")
        main {
            val visible=views(root()).filterIsInstance<TextView>().filter {it.isShown}
            check(visible.count {it.text.toString()==a.getString(R.string.device_known_senders)}==1)
            check(visible.any {it.text.toString()==a.getString(R.string.receiver_refinement_logs)})
            check(visible.any {it.text.toString()==a.getString(R.string.receiver_stop)})
        }
        main {views(root()).filterIsInstance<ScrollView>().single {it.isShown}.fullScroll(View.FOCUS_DOWN)};shot("settings-tail")
        main {check(views(root()).filterIsInstance<TextView>().count {it.isShown&&it.text.toString()==a.getString(R.string.gallery_receipts_export)}==0)}
        main {a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=3}
        awaitReady {views(root()).filterIsInstance<android.widget.Button>().any {it.text.toString()==a.getString(R.string.duck_storage_detail)}}
        main {views(root()).filterIsInstance<ScrollView>().single {it.isShown}.fullScroll(View.FOCUS_DOWN)}
        main {views(root()).filterIsInstance<android.widget.Button>().single {it.text.toString()==a.getString(R.string.duck_storage_detail)}.performClick()}
        awaitReady {views(root()).filterIsInstance<TextView>().any {it.text.toString()==a.getString(R.string.receiver_refinement_partial)}}
        shot("storage-details")
        main {
            val texts=views(root()).filterIsInstance<TextView>()
            for(title in listOf(R.string.storage_flow_originals_stat,R.string.receiver_refinement_partial,R.string.storage_flow_gallery_ready,R.string.storage_flow_gallery_pending)) {
                val name=texts.single {it.text.toString()==a.getString(title)}
                val row=generateSequence(name.parent as? View) {it.parent as? View}.first {it.tag=="duck.setting"}
                val amount=views(row).filterIsInstance<TextView>().last()
                check(amount.text.toString()!=name.text.toString())
                check(amount.gravity and android.view.Gravity.HORIZONTAL_GRAVITY_MASK==android.view.Gravity.RIGHT){"Size is not in the trailing column"}
            }
            check(texts.count {it.text.toString()==a.getString(R.string.gallery_receipts_export)}==0){"Pure statistics must not repeat the storage-home export"}
        }
        sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);Thread.sleep(180)
        // Genuine filtered-empty presentation; reset calls the real empty JNI catalog.
        val model=HistoryModel();val history=main {HistoryPage(a,model,"${a.filesDir}/receiver").also {a.setContentView(it);it.render(HistoryState(filter="failed",loading=false))}}
        shot("filtered-empty")
        main {
            val visible=views(history).filterIsInstance<TextView>().filter {it.isShown}
            check(visible.none {it.text.toString()==a.getString(R.string.design_connect_device)||it.text.toString()==a.getString(R.string.duck_view_tasks)})
            check(visible.any {it.text.toString()==a.getString(R.string.receiver_refinement_filtered_empty)})
            (visible.single {it.text.toString()==a.getString(R.string.receiver_refinement_clear_filters)} as View).performClick()
        }
        Thread.sleep(400);check(model.state.value.filter=="all"&&model.state.value.kind=="all"&&model.state.value.sender==null)
        fun insert(kind:String,id:String):android.net.Uri {
            val video=kind=="video";val uri=checkNotNull(resolver.insert(if(video)MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME,"BD_$id.${if(video)"mp4" else "jpg"}");put(MediaStore.MediaColumns.MIME_TYPE,if(video)"video/mp4" else "image/jpeg");put(MediaStore.MediaColumns.RELATIVE_PATH,"DCIM/BackupDuck/");put(MediaStore.MediaColumns.IS_PENDING,1)
            }));own+=uri
            resolver.openOutputStream(uri,"w")!!.use {out ->if(video) {
                val generated=args.getString("video_fixture")
                val input=if(generated==null)context.assets.open("motion.mp4") else {
                    check(generated=="/data/local/tmp/BackupDuck-generated-HD-video.mp4");File(generated).inputStream()
                }
                input.use {it.copyTo(out)}
            } else {
                val b=Bitmap.createBitmap(1200,900,Bitmap.Config.ARGB_8888);val c=Canvas(b);c.drawColor(Color.rgb(30,130,210));val paint=android.graphics.Paint().apply {color=Color.rgb(240,170,50)};c.drawRect(160f,180f,1000f,700f,paint);b.compress(Bitmap.CompressFormat.JPEG,96,out);b.recycle()
            }}
            resolver.update(uri,ContentValues().apply {put(MediaStore.MediaColumns.IS_PENDING,0)},null,null);return uri
        }
        val adapter=TransferAdapter(a)
        for(kind in listOf("photo","video")) {
            val id=(if(kind=="video")"b" else "a").repeat(64);val uri=insert(kind,id)
            val actualBytes=resolver.query(uri,arrayOf(MediaStore.MediaColumns.SIZE),null,null,null)!!.use {it.moveToFirst();it.getLong(0)}
            val item=HistoryItem(1,id,"Generated.$kind",kind,actualBytes,actualBytes,"received","complete",null,false)
            val copy=GalleryPreview.resolve(a,item,null,CancellationSignal());check(copy?.uri==uri){"$kind copy depended on an already-decoded row thumbnail"}
            val decoded=GalleryPreview.decode(a,copy!!,android.util.Size(1000,500),CancellationSignal());if(kind=="photo")check(decoded.width>=1000&&decoded.height>=500){"Photo detail reused a low-resolution list icon: ${decoded.width}x${decoded.height}"}
            else android.media.MediaMetadataRetriever().use {r ->r.setDataSource(a,uri);val w=r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt();val h=r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt();check(decoded.width>=minOf(w,1000)-2&&decoded.height>=minOf(h,500)-2){"Video frame ${decoded.width}x${decoded.height} below source ${w}x${h}"}}
            ;decoded.recycle()
            main {sheet=adapter.showDetails(item,null)}
            awaitReady {views(root()).any {it.tag=="receiver.detail.open-copy"&&it.isShown}}
            awaitReady {views(root()).filterIsInstance<ImageView>().any {it.tag=="receiver.detail.preview"&&it.drawable is BitmapDrawable}}
            shot("detail-$kind")
            main {check(views(root()).single {it.tag=="receiver.detail.open-copy"}.isEnabled);sheet!!.dismiss()};Thread.sleep(180)
        }
        val missing=HistoryItem(1,"c".repeat(64),"Missing.mp4","video",100,100,"received","complete",null,false)
        main {sheet=adapter.showDetails(missing,null)}
        awaitReady {views(root()).filterIsInstance<TextView>().any {it.text.toString()==a.getString(R.string.receiver_refinement_copy_missing)&&it.isShown}}
        main {check(views(root()).none {it.tag=="receiver.detail.open-copy"&&it.isShown})};shot("detail-missing-copy")
        main {sheet!!.dismiss()};Thread.sleep(150)
        return "PASS: portrait scanner contract; filtered-empty clear/reset without connect/no-op strip; unique settings responsibilities; independently resolved real photo/video MediaStore copies and high-resolution image and real frame without upscaling a small source; missing-copy recovery. Synthetic-only $suffix"
    } finally {
        main {sheet?.takeIf {it.window?.decorView?.isAttachedToWindow==true}?.dismissImmediately();a.finish()}
        own.forEach {runCatching {resolver.delete(it,null,null)}}
        preferences.edit().putInt("mode",oldMode).commit()
    }
}

/** Minimal final-JNI policy check. Never starts receiving or reclaims originals. */
internal fun Instrumentation.checkReceiverDefaultPolicy():String {
    check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
    val fresh=File(targetContext.cacheDir,"receiver-default-"+java.util.UUID.randomUUID())
    check(!fresh.exists());fresh.mkdirs()
    fun read()=NativeBridge.request(org.json.JSONObject().put("op","receiver_settings").put("root",fresh.path)) as org.json.JSONObject
    try {
        val value=read().getJSONObject("settings")
        check(value.getBoolean("receiver_relay")){"Fresh final JNI did not enable verified-copy relay reclamation"}
        value.put("receiver_relay",false)
        NativeBridge.request(org.json.JSONObject().put("op","receiver_settings").put("root",fresh.path).put("settings",value))
        check(!read().getJSONObject("settings").getBoolean("receiver_relay")){"Explicit retention preference was overwritten"}
        check(!read().getJSONObject("settings").getBoolean("receiver_relay")){"Reload changed retained preference"}
        return "PASS: final JNI fresh receiver_relay=true; explicit false persisted and reread false; no receive service, publication or reclamation was started"
    } finally {fresh.deleteRecursively()}
}

/** Focused real MainActivity host, not a full-size replacement content view. */
internal fun Instrumentation.checkReceiverEmptyAccessibility():String {
    check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun <T> main(block:()->T):T {var r:Result<T>?=null;runOnMainSync {r=runCatching(block)};return r!!.getOrThrow()}
    val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    val output=File(targetContext.cacheDir,"receiver-refinement").apply {mkdirs()}
    try {
        main {a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=2}
        val page=main {views(a.window.decorView).filterIsInstance<HistoryPage>().single()}
        for(filter in listOf("active","failed")) {
            main {page.render(HistoryState(filter=filter,loading=false))}
            waitForIdleSync()
            main {
                val count=views(page).filterIsInstance<TextView>().first {it.text.toString()==a.getString(R.string.duck_count,0,0)}
                val guide=views(page).filterIsInstance<TextView>().first {it.text.toString()==a.getString(R.string.duck_status_guide)}
                val chips=views(page).filterIsInstance<com.google.android.material.chip.ChipGroup>().single()
                val cr=android.graphics.Rect();val gr=android.graphics.Rect();val hr=android.graphics.Rect()
                check(count.getGlobalVisibleRect(cr)&&guide.getGlobalVisibleRect(gr)&&chips.getGlobalVisibleRect(hr))
                check(cr.bottom<=hr.top&&gr.bottom<=hr.top){"AX header overlaps chips"}
                val reset=views(page).filterIsInstance<android.widget.Button>().single {it.text.toString()==a.getString(R.string.receiver_refinement_clear_filters)}
                val scroll=generateSequence(reset.parent as? View) {it.parent as? View}.filterIsInstance<ScrollView>().first()
                scroll.fullScroll(View.FOCUS_DOWN)
                check(views(page).filterIsInstance<TextView>().none {it.isShown&&it.text.toString()==a.getString(R.string.history_empty)}){"Filtered empty repeats introduction"}
            }
            waitForIdleSync();Thread.sleep(100)
            main {
                val reset=views(page).filterIsInstance<android.widget.Button>().single {it.text.toString()==a.getString(R.string.receiver_refinement_clear_filters)}
                val r=android.graphics.Rect();check(reset.getGlobalVisibleRect(r)&&r.height()>=reset.height){"Reset is clipped by MainActivity toolbar/navigation"}
                check(reset.isEnabled)
            }
            val shot=checkNotNull(uiAutomation.takeScreenshot());File(output,"filtered-$filter-main-320-ax.png").outputStream().use {shot.compress(Bitmap.CompressFormat.PNG,100,it)};shot.recycle()
        }
        return "PASS: real MainActivity 320AX active/failed empty states; natural header clears chips; reset fully reachable within scroll host; no repeated first-use guidance"
    } finally {main {a.finish()}}
}
