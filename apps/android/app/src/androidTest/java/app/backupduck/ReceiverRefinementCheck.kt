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
    val resolver=a.contentResolver;val own=mutableListOf<android.net.Uri>();var detail:PhotoDetail.Content?=null
    val gallery=ReceiverEnvironment.openGalleryPhoto
    val output=File(targetContext.cacheDir,"receiver-refinement").apply {mkdirs()};val suffix="${a.resources.configuration.screenWidthDp}-${args.getString("dark") ?: "false"}"
    fun shot(name:String){waitForIdleSync();Thread.sleep(180);val b=checkNotNull(uiAutomation.takeScreenshot());File(output,"$name-$suffix.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
    try {
        val scanIntent=com.journeyapps.barcodescanner.ScanOptions().setCaptureActivity(ReceiverScanActivity::class.java).setDesiredBarcodeFormats(com.journeyapps.barcodescanner.ScanOptions.QR_CODE).setBeepEnabled(false).setOrientationLocked(true).createScanIntent(a).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val capture=startActivitySync(scanIntent) as ReceiverScanActivity
        main {check(capture.resources.configuration.orientation==android.content.res.Configuration.ORIENTATION_PORTRAIT)}
        shot("scanner-portrait");main {capture.finish()};Thread.sleep(180)
        check(a.packageManager.getActivityInfo(android.content.ComponentName(a,ReceiverScanActivity::class.java),0).screenOrientation==ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)
        main {a.openSettings()};waitForIdleSync();shot("settings")
        main {
            val visible=views(root()).filterIsInstance<TextView>().filter {it.isShown}
            check(visible.count {it.text.toString()==a.getString(R.string.pref_devices)}==1)
            a.openStorage()
        }
        awaitReady {(a.supportFragmentManager.primaryNavigationFragment as? PageFragment)?.page?.route=="storage"}
        shot("storage")
        main {a.onBackPressedDispatcher.onBackPressed()};waitForIdleSync()
        // Core filters still apply before paging even though current Photos has no filter controls.
        val model=HistoryModel()
        runBlocking {model.select("${a.cacheDir}/filtered-empty",filter="failed",kind="video",sender="fixture")}
        check(!model.state.value.failed&&model.state.value.items.isEmpty()&&model.state.value.filter=="failed"&&model.state.value.kind=="video"&&model.state.value.sender=="fixture")
        runBlocking {model.select("${a.cacheDir}/filtered-empty",filter="all",kind="all",sender=null)}
        check(model.state.value.filter=="all"&&model.state.value.kind=="all"&&model.state.value.sender==null)
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
        var retries=0
        val actions=ReceivedPhotosPage.Actions({}, {}, {it(false)}, {_,done->retries++;done(false)}, {})
        fun open(item:HistoryItem) = main {
            detail?.cancel?.invoke()
            detail=PhotoDetail(a,PhotoImages(a),actions).content(item,{}, {true})
            a.setContentView(detail!!.root)
        }
        for(kind in listOf("photo","video")) {
            val id=(if(kind=="video")"b" else "a").repeat(64);val uri=insert(kind,id)
            val actualBytes=resolver.query(uri,arrayOf(MediaStore.MediaColumns.SIZE),null,null,null)!!.use {it.moveToFirst();it.getLong(0)}
            val item=HistoryItem(1,id,"Generated.$kind",kind,actualBytes,actualBytes,"received","complete",null,false)
            val copy=GalleryPreview.resolve(a,item,null,CancellationSignal());check(copy?.uri==uri){"$kind copy depended on an already-decoded row thumbnail"}
            val decoded=GalleryPreview.decode(a,copy!!,android.util.Size(1000,500),CancellationSignal());if(kind=="photo")check(decoded.width>=1000&&decoded.height>=500){"Photo detail reused a low-resolution list icon: ${decoded.width}x${decoded.height}"}
            else android.media.MediaMetadataRetriever().use {r ->r.setDataSource(a,uri);val w=r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt();val h=r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt();check(decoded.width>=minOf(w,1000)-2&&decoded.height>=minOf(h,500)-2){"Video frame ${decoded.width}x${decoded.height} below source ${w}x${h}"}}
            ;decoded.recycle()
            open(item)
            awaitReady {views(root()).any {it.contentDescription==a.getString(R.string.viewer_open_photos)&&it.isShown}}
            awaitReady {detail!!.preview.drawable is BitmapDrawable}
            shot("detail-$kind")
            main {check(views(root()).single {it.contentDescription==a.getString(R.string.viewer_open_photos)}.isEnabled);detail!!.cancel()};Thread.sleep(180)
        }
        val missing=HistoryItem(1,"c".repeat(64),"Missing.mp4","video",100,100,"received","complete",null,false)
        open(missing)
        awaitReady {detail!!.preview.contentDescription==a.getString(R.string.photos_preview_unavailable)}
        ReceiverEnvironment.openGalleryPhoto={_,_->throw android.content.ActivityNotFoundException("Synthetic missing gallery")}
        main {views(root()).single {it.contentDescription==a.getString(R.string.viewer_open_photos)}.performClick()}
        awaitReady {views(root()).filterIsInstance<TextView>().any {it.text.toString()==a.getString(R.string.photos_open_failed)&&it.isShown}}
        shot("detail-missing-copy")
        main {detail!!.cancel()};Thread.sleep(150)
        val failed=missing.copy(processing="failed",processingError="storage")
        open(failed)
        main {views(root()).filterIsInstance<TextView>().first {it.text.toString()==a.getString(R.string.viewer_save_failed)}.performClick()}
        check(retries==1)
        main {views(root()).first {it.contentDescription==a.getString(R.string.viewer_details)}.performClick()}
        awaitReady {views(root()).filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==a.getString(R.string.photos_retry_failed)}}
        shot("publication-retry-failed")
        return "PASS: portrait scanner; core state/kind/sender filters and reset; current Settings/Storage; independently resolved real photo/video MediaStore copies and high-resolution image and real frame without upscaling a small source; current viewer missing-copy failure/recovery. Synthetic-only $suffix"
    } finally {
        main {detail?.cancel?.invoke();a.finish()}
        ReceiverEnvironment.openGalleryPhoto=gallery
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

/** Current Photos empty and failed states remain reachable in the native host. */
internal fun Instrumentation.checkReceiverEmptyAccessibility():String {
    check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    try {
        runOnMainSync {a.openTransfers()}
        val page=a.photosForCheck()
        for(failed in listOf(false,true)) {
            runOnMainSync {page.render(HistoryState(failed=failed))}
            waitForIdleSync();Thread.sleep(250)
            runOnMainSync {
                val action=views(page.view).filterIsInstance<android.widget.Button>().single {it.isShown}
                action.requestRectangleOnScreen(android.graphics.Rect(0,0,action.width,action.height),true)
            }
            waitForIdleSync()
            runOnMainSync {
                val action=views(page.view).filterIsInstance<android.widget.Button>().single {it.isShown}
                val rect=android.graphics.Rect();check(action.getGlobalVisibleRect(rect)&&rect.height()==action.height&&action.isEnabled)
                check(views(page.view).filterIsInstance<TextView>().count {it.text.toString()==a.getString(if(failed)R.string.photos_load_failed else R.string.photos_empty_title)}==1)
            }
        }
        return "PASS: current Photos empty Connect and failed Retry are visible, unique and fully reachable inside MainActivity"
    } finally {runOnMainSync {a.finish()}}
}
