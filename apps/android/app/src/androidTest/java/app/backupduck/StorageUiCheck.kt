package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.Spinner
import android.widget.TextView
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.materialswitch.MaterialSwitch
import org.json.JSONObject
import java.io.File

/** Actual storage entry points, custom limits and consent; disposable validation data only. */
internal fun Instrumentation.checkStorageUI(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone")||android.os.Build.FINGERPRINT.contains("generic"))
    val language=args.getString("language")?:"en";val dark=args.getString("dark")=="true"
    targetContext.getSharedPreferences("appearance",0).edit().putInt("mode",if(dark)2 else 1).commit()
    ReceiverPreferences.setEnabled(targetContext,false)
    fun <T> main(action:()->T):T {var result:Result<T>?=null;runOnMainSync {result=runCatching(action)};return result!!.getOrThrow()}
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun root()=WindowInspector.getGlobalWindowViews().last {it.isShown&&it.hasWindowFocus()}
    fun settle() {waitForIdleSync();Thread.sleep(500)}
    main {AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(language))}
    val activity=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    val settingsRoot="${targetContext.filesDir}/receiver"
    fun config()=(NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",settingsRoot)) as JSONObject).getJSONObject("settings")
    fun save(value:JSONObject) {NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",settingsRoot).put("settings",value))}
    val previous=config()
    fun click(id:Int)=main {
        var v:View=views(root()).filterIsInstance<TextView>().first {it.text.toString()==activity.getString(id)}
        while(!v.isClickable)v=v.parent as View
        v.performClick();Unit
    }
    fun screenshot(name:String) {settle();val image=checkNotNull(uiAutomation.takeScreenshot());File(targetContext.cacheDir,"storage-$language-${if(dark)"dark" else "light"}-$name.png").outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)};image.recycle()}
    try {
        save(JSONObject(previous.toString()).put("receiver_budget_bytes",123456789L).put("min_free_bytes",456789L).put("receiver_relay",false))
        settle();main {activity.findViewById<BottomNavigationView>(R.id.main_navigation).selectedItemId=3};Thread.sleep(700)
        screenshot("top");click(R.string.duck_limit);Thread.sleep(700)
        check(main {views(root()).filterIsInstance<Spinner>().size==2});screenshot("limits")
        click(R.string.settings_save);Thread.sleep(800)
        check(config().getLong("receiver_budget_bytes")==123456789L&&config().getLong("min_free_bytes")==456789L) {"Custom quota changed without a selection"}
        click(R.string.duck_keep);settle();screenshot("retention")
        val retentionRoot=main {root()}
        val toggle=main {views(root()).filterIsInstance<MaterialSwitch>().single()}
        main {toggle.performClick()};settle()
        check(!config().getBoolean("receiver_relay"));check(main {!retentionRoot.isShown}) {"Scope sheet stacked on top of retention sheet"}
        screenshot("relay-consent");sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);settle()
        check(!config().getBoolean("receiver_relay"));check(main {retentionRoot.isShown}) {"Cancelling scope did not restore retention"}
        main {toggle.performClick()};settle();click(R.string.relay_include_history);click(R.string.settings_save);Thread.sleep(900)
        check(config().getBoolean("receiver_relay"));screenshot("relay-enabled")
        main {toggle.performClick()};Thread.sleep(700);check(!config().getBoolean("receiver_relay"))
        sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);settle();click(R.string.duck_storage_detail);Thread.sleep(800)
        check(main {views(root()).filterIsInstance<TextView>().any {it.text.toString()==activity.getString(R.string.storage_snapshot_note)}})
        screenshot("details")
        return "PASS: storage entry points, exact custom quotas, scope consent/cancel/restore, enable/disable persistence, real usage detail ($language, dark=$dark)"
    } finally {RelayMaintenance.cancelAutomatic();save(previous);main {activity.finish()}}
}
