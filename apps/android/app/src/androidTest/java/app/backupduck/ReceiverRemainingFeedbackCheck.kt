package app.backupduck
import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.*
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.io.File

/** Read-only navigation/layout check on the isolated validation emulator. */
internal fun Instrumentation.checkReceiverRemainingFeedback(args:Bundle):String {
 check(targetContext.packageName.endsWith(".validation")&&android.os.Build.MODEL.contains("sdk_gphone"))
 fun all(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {all(v.getChildAt(it))} else emptyList()
 fun <T> main(f:()->T):T {var r:Result<T>?=null;runOnMainSync {r=runCatching(f)};return r!!.getOrThrow()}
 fun root()=WindowInspector.getGlobalWindowViews().last {it.isShown&&it.hasWindowFocus()}
 fun ready(f:()->Boolean) {repeat(60){if(main {runCatching(f).getOrDefault(false)})return;Thread.sleep(100)};check(main(f))}
 val old=ReceiverPreferences.enabled(targetContext);ReceiverPreferences.setEnabled(targetContext,false)
 val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
 var probe:PhotosProbeActivity?=null
 val out=File(targetContext.cacheDir,"remaining-feedback").apply {mkdirs()}
 fun text(id:Int)=all(root()).filterIsInstance<TextView>().filter {it.isShown&&it.text.toString()==a.getString(id)}
 fun shot(name:String){waitForIdleSync();val b=checkNotNull(uiAutomation.takeScreenshot());File(out,"$name.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
 try {
  main {
   val nav=a.findViewById<BottomNavigationView>(R.id.main_navigation);nav.selectedItemId=1
   check(!all(a.window.decorView).filterIsInstance<MaterialToolbar>().single().menu.findItem(100).isVisible)
   nav.selectedItemId=2;check(all(a.window.decorView).filterIsInstance<MaterialToolbar>().single().menu.findItem(100).isVisible)
   nav.selectedItemId=3
  }
  ready {text(R.string.duck_storage_detail).isNotEmpty()}
  main {for(id in listOf(R.string.receiver_open_photos,R.string.gallery_receipts_export,R.string.originals_export))check(text(id).isEmpty())}
  shot("storage")
  main {a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=4}
  ready {text(R.string.receiver_records_exports).isNotEmpty()}
  main {
   for(id in listOf(R.string.logs_export,R.string.gallery_receipts_export,R.string.originals_export))check(text(id).size==1)
   fun y(id:Int):Int {val p=IntArray(2);text(id).single().getLocationOnScreen(p);return p[1]}
   check(y(R.string.receiver_help_title)>y(R.string.updates_title))
  }
  waitForIdleSync();Thread.sleep(200)
  main {all(root()).filterIsInstance<ScrollView>().first {it.isShown}.fullScroll(View.FOCUS_DOWN)}
  waitForIdleSync();Thread.sleep(200);shot("settings")
  main {a.showThermalSettings()}
  ready {text(R.string.receiver_thermal_explanation).isNotEmpty()}
  main {check(text(R.string.duck_automatic_resume).isEmpty())};shot("thermal")
  main {all(root()).filterIsInstance<ImageButton>().first {it.contentDescription==a.getString(R.string.receiver_close)}.performClick()}
  probe=startActivitySync(Intent(targetContext,PhotosProbeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as PhotosProbeActivity
  ready {text(R.string.photos_diagnostics_title).isNotEmpty()}
  main {
   val button=text(R.string.photos_diagnostics_title).single()
   val lp=button.layoutParams as LinearLayout.LayoutParams
   check(lp.topMargin==a.dp(16)&&lp.bottomMargin==a.dp(16))
   button.requestRectangleOnScreen(android.graphics.Rect(0,0,button.width,button.height),true)
  };shot("cleanup-spacing")
  return "PASS: no homepage help; transfer filters retained; storage no exports/gallery shortcut; exports unique in settings and help after update; thermal condition contextual; check-button margins balanced"
 } finally {main {probe?.finish();a.finish()};ReceiverPreferences.setEnabled(targetContext,old)}
}
