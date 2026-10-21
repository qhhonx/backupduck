package app.backupduck
import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.*
import com.google.android.material.bottomnavigation.BottomNavigationView
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.io.File

/** BD24/25 real models + synthetic presentation fields; disposable validation emulator only. */
internal fun Instrumentation.checkReceiverFeedback(args:Bundle):String {
 check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
 val oldEnabled=ReceiverPreferences.enabled(targetContext);ReceiverPreferences.setEnabled(targetContext,false)
 val oldName=DeviceProfiles.read(targetContext).getJSONObject("device").getString("name");DeviceProfiles.read(targetContext,"Generated receiver name 1234567890")
 val prefs=targetContext.getSharedPreferences("appearance",0);val previousMode=prefs.getInt("mode",-1);val dark=args.getString("dark")=="true";prefs.edit().putInt("mode",if(dark)2 else 1).commit()
 fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
 fun <T> main(block:()->T):T {var result:Result<T>?=null;runOnMainSync {result=runCatching(block)};return result!!.getOrThrow()}
 fun root()=WindowInspector.getGlobalWindowViews().last {it.isShown&&it.hasWindowFocus()}
 val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
 val output=File(targetContext.cacheDir,"feedback-check").apply {mkdirs()};val suffix="${a.resources.configuration.screenWidthDp}-${if(dark)"dark" else "light"}"
 fun shot(name:String){waitForIdleSync();Thread.sleep(180);val b=checkNotNull(uiAutomation.takeScreenshot());File(output,"$name-$suffix.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
 var sheet:DuckSheet?=null
 var editDialog:DuckEditDialog?=null
 try {
  Thread.sleep(700)
  val empty=HistoryModel();runBlocking {empty.select(File(targetContext.cacheDir,"empty-history-${System.nanoTime()}").path)};check(!empty.state.value.failed&&empty.state.value.items.isEmpty()){"Real empty history did not read"}
  val bad=File(targetContext.cacheDir,"invalid-history-${System.nanoTime()}").apply {mkdirs()};File(bad,"store").mkdirs();File(bad,"store/receiver.sqlite3").writeText("Invalid isolated test catalog");val unreadable=HistoryModel();runBlocking {unreadable.select(bad.path)};check(unreadable.state.value.failed){"Real isolated catalog failure did not surface"}
  main {ReceiverPreferences.setEnabled(a,true);a.receiverHome.render(ReceiverSnapshot(phase="ready"),"Generated Pixel",false);a.receiverHome.history(empty.state.value)}
  waitForIdleSync();val home=a.receiverHome.view
  main {val all=views(home);check(all.filterIsInstance<TextView>().none {it.text.toString()==a.getString(R.string.duck_cloud_title)||it.text.toString()==a.getString(R.string.duck_cloud_unknown)}){"Duplicate cloud card on Home"};val device=all.single {it.tag=="receiver.device-state"};val recent=all.filterIsInstance<TextView>().single {it.text.toString()==a.getString(R.string.receiver_recent_records)};val dr=IntArray(2);val rr=IntArray(2);device.getLocationOnScreen(dr);recent.getLocationOnScreen(rr);check(dr[1]<rr[1]){"Telemetry is below recent records"};check(all.filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==a.getString(R.string.receiver_home_recent_empty)})}
  shot("home-empty")
  main {a.receiverHome.history(unreadable.state.value)};shot("home-read-failure");main {check(views(home).single {it.tag=="receiver.recent-retry"}.isShown)}
  val items=listOf(HistoryItem(3,"generated-3","Generated_003.jpg","photo",100,100,"received","complete",null,false),HistoryItem(2,"generated-2","Generated_002.jpg","photo",100,100,"received","failed","generated_error",false),HistoryItem(1,"generated-1","Generated_001.mp4","video",100,50,"receiving","pending",null,false))
  main {a.receiverHome.totals(1,3,1);a.receiverHome.history(HistoryState(items=items,total=3))};shot("home-records");main { (home as ScrollView).fullScroll(View.FOCUS_DOWN)};shot("home-records-tail");main {check(!views(home).single {it.tag=="receiver.recent-status"}.isShown)}
  // First-tier rows have actual values, not duplicate feature paragraphs.
  main {ReceiverPreferences.setEnabled(a,false);a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=4};waitForIdleSync();main {views(root()).filterIsInstance<ScrollView>().single {it.isShown}.fullScroll(View.FOCUS_UP)};shot("settings")
  main {val nameHeading=views(root()).filterIsInstance<TextView>().single {it.text.toString()==a.getString(R.string.duck_device_name)};check(nameHeading.lineCount==1){"Name object squeezed by value: ${nameHeading.lineCount} lines"};val texts=views(root()).filterIsInstance<TextView>().map {it.text.toString()};for(id in listOf(R.string.duck_thermal_note,R.string.duck_conversion_note,R.string.duck_access_note,R.string.duck_sender_settings_note,R.string.duck_brand_note))check(a.getString(id) !in texts){"Duplicate first-tier explanation:$id"}}
  main {val title=views(root()).filterIsInstance<TextView>().single {it.text.toString()==a.getString(R.string.duck_device_name)};val row=title.parent.parent as View;row.requestRectangleOnScreen(Rect(0,0,row.width,row.height),true)};shot("settings-device-value")
  main {views(root()).filterIsInstance<ScrollView>().single {it.isShown}.fullScroll(View.FOCUS_DOWN)};shot("settings-actions-tail")
  val d=DevicePanels(a);main {d.refresh()};Thread.sleep(500);main {editDialog=d.rename()};shot("name");main {check(views(root()).filterIsInstance<TextView>().none {it.text.toString()==a.getString(R.string.duck_name_intro)||it.text.toString()==a.getString(R.string.duck_code_tasks_unchanged)})};main {editDialog!!.dismiss()};Thread.sleep(250)
  main {sheet=a.showStorageControls(StorageSection.LOGS){}};Thread.sleep(500);shot("log-retention")
  main {val area=views(root()).single {it.tag=="receiver.select-field.log_days"};check(area.isClickable&&area.height>=a.dp(48));check(area.performClick())};Thread.sleep(180);shot("log-whole-row-popup");sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);Thread.sleep(180)
  File(output,"result-$suffix.json").writeText(JSONObject().put("emptyHistoryActualJNI",true).put("historyReadFailureActualFilesystem",true).put("loadedRecordsSyntheticOnly",true).put("firstTierNoRepeatedDescriptions",true).put("logWholeRowNativePopup",true).put("scope","No real Pixel, media, credentials or Google Photos operations").toString())
  return "PASS: BD24 telemetry/records grouping, no home cloud duplication; actual JNI empty/read failure, synthetic loaded rows; BD25 first-tier copy/name/whole log field native selector. $suffix"
 } finally {main {sheet?.takeIf {it.window?.decorView?.isAttachedToWindow==true}?.dismissImmediately();editDialog?.dismiss();a.finish()};ReceiverPreferences.setEnabled(targetContext,oldEnabled);DeviceProfiles.read(targetContext,oldName);prefs.edit().putInt("mode",previousMode).commit()}
}
