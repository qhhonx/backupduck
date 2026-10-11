package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.*
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.materialswitch.MaterialSwitch
import java.io.File

/** Inspects empty/synthetic validation state; never presses reclaim or saves policy. */
internal fun Instrumentation.checkReceiverStorageFlow(args:Bundle):String {
    check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun <T> main(block:()->T):T {var r:Result<T>?=null;runOnMainSync {r=runCatching(block)};return r!!.getOrThrow()}
    fun root()=WindowInspector.getGlobalWindowViews().last {it.isShown&&it.hasWindowFocus()}
    fun awaitReady(test:()->Boolean) {repeat(80) {if(main {runCatching(test).getOrDefault(false)})return;Thread.sleep(100)};check(main {runCatching(test).getOrDefault(false)}){"Storage flow state did not appear"}}
    val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    val output=File(targetContext.cacheDir,"storage-flow-check").apply {mkdirs()};val suffix="${a.resources.configuration.screenWidthDp}-${args.getString("dark") ?: "false"}"
    fun text(id:Int)=views(root()).filterIsInstance<TextView>().filter {it.isShown&&it.text.toString()==a.getString(id)}
    fun click(id:Int) {awaitReady {text(id).isNotEmpty()};main {
        val t=text(id).first()
        val action=generateSequence(t as? View) {it.parent as? View}.first {it.isClickable}
        val scroll=generateSequence(action.parent as? View) {it.parent as? View}.filterIsInstance<ScrollView>().firstOrNull()
        scroll?.requestChildFocus(action,t);action.requestRectangleOnScreen(android.graphics.Rect(0,0,action.width,action.height),true)
        check(action.performClick())
    };waitForIdleSync()}
    fun shot(name:String) {waitForIdleSync();Thread.sleep(150);val b=checkNotNull(uiAutomation.takeScreenshot());File(output,"$name-$suffix.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
    fun closeSheet(){main {views(root()).filterIsInstance<ImageButton>().first {it.contentDescription.toString()==a.getString(R.string.receiver_close)}.performClick()};Thread.sleep(180)}
    try {
        main {a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=3}
        awaitReady {text(R.string.duck_storage_detail).isNotEmpty()}
        main {check(text(R.string.duck_cleanup_title).isEmpty())}
        click(R.string.duck_storage_detail)
        awaitReady {text(R.string.receiver_refinement_partial).isNotEmpty()}
        main {
            for(id in listOf(R.string.storage_limits,R.string.relay_check_history,R.string.gallery_receipts_export,R.string.storage_snapshot_note))check(text(id).isEmpty()){"Statistics contains unrelated action/text:$id"}
        }
        shot("pure-statistics");closeSheet()
        click(R.string.storage_flow_policy_entry)
        awaitReady {text(R.string.storage_flow_original_definition).isNotEmpty()}
        shot("retention-parent")
        fun expandScope(){main {
            val adjust=text(R.string.storage_flow_change_scope).firstOrNull()
            if(adjust!=null)generateSequence(adjust as? View) {it.parent as? View}.first {it.isClickable}.performClick()
            else views(root()).filterIsInstance<MaterialSwitch>().single().performClick()
        };awaitReady {views(root()).any {it.tag=="retention.scope-inline"&&it.isShown}}}
        expandScope();shot("scope-inline")
        click(R.string.device_cancel)
        main {check(views(root()).single {it.tag=="retention.scope-inline"}.visibility==View.GONE);check(text(R.string.storage_flow_original_definition).isNotEmpty())}
        expandScope();sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);Thread.sleep(180)
        main {check(views(root()).single {it.tag=="retention.scope-inline"}.visibility==View.GONE);check(text(R.string.storage_flow_original_definition).isNotEmpty())}
        click(R.string.relay_check_history)
        awaitReady {text(R.string.storage_flow_history_boundary).isNotEmpty()}
        shot("history-single-sheet-preview")
        click(R.string.storage_flow_close)
        awaitReady {text(R.string.storage_flow_original_definition).isNotEmpty()}
        shot("history-returned-to-parent")
        closeSheet()
        main {a.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=4}
        awaitReady {text(R.string.logs_export).isNotEmpty()}
        click(R.string.logs_export)
        awaitReady {text(R.string.duck_report_logs).isNotEmpty()}
        main {check(text(R.string.duck_report_logs).size==1);check(text(R.string.duck_report_gallery).isEmpty());check(text(R.string.duck_export_report_note).isEmpty())}
        shot("export-one-type")
        click(R.string.duck_choose_location)
        Thread.sleep(300);sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        awaitReady {text(R.string.duck_choose_location).isNotEmpty()&&text(R.string.duck_report_logs).isNotEmpty()}
        shot("export-cancel-return")
        return "PASS: pure storage statistics; retention inline scope cancel/back returns parent; historical inspection one sheet preview and close restores same parent; one-type export and system picker cancellation; no policy save/reclamation clicked. $suffix"
    } finally {main {a.finish()}}
}

/** Static final-version row evidence; no receiving, config change or export. */
internal fun Instrumentation.checkReceiverSettingsRevision():String {
    check(targetContext.packageName=="app.backupduck.validation"&&android.os.Build.MODEL.contains("sdk_gphone"))
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    val a=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("destination","settings")) as MainActivity
    val out=File(targetContext.cacheDir,"storage-flow-check").apply {mkdirs()}
    try {
        waitForIdleSync()
        runOnMainSync {
            val value=views(a.window.decorView).filterIsInstance<TextView>().single {it.tag=="duck.version"}
            value.requestRectangleOnScreen(android.graphics.Rect(0,0,value.width,value.height),true)
            val full=a.packageManager.getPackageInfo(a.packageName,0).versionName ?: ""
            val revision=Regex("""-ui([0-9]+(?:\.[0-9]+)*)""").find(full)?.groupValues?.get(1)
            check(revision==null||value.text.toString().endsWith("UI"+revision))
        }
        waitForIdleSync();Thread.sleep(100)
        runOnMainSync {
            val value=views(a.window.decorView).filterIsInstance<TextView>().single {it.tag=="duck.version"}
            if(a.resources.configuration.fontScale<=1.3f) {
                check(value.lineCount==1&&value.layout.getEllipsisCount(0)==0){"Normal version row hides UI revision: ${value.text}"}
            }
        }
        val b=checkNotNull(uiAutomation.takeScreenshot());File(out,"settings-version-${a.resources.configuration.screenWidthDp}.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()
        return "PASS: current release/UI revision remains visible in actual settings version row; full debug version available as metadata"
    } finally {runOnMainSync {a.finish()}}
}
